import AppKit
import EventKit
import Foundation
import MurmurSessions

/// A calendar event reduced to what detection and the notepad need.
struct CalendarEvent: Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let attendees: [Attendee]
    /// True when the event carries a video link, in its URL, location or notes.
    let hasConference: Bool
    let conferenceURL: URL?
    /// Present when a guest booked this meeting through a Concourse booking link.
    var booking: CloudBooking? = nil
    var isAllDay = false
    var startDateOnly: String? = nil
    var endDateOnly: String? = nil
    static func localDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
    var displayStart: Date { isAllDay ? Self.localDate(startDateOnly) ?? start : start }
    var displayEnd: Date { isAllDay ? Self.localDate(endDateOnly) ?? end : end }
    var calendarName: String? = nil
    var calendarSourceID: String? = nil
    var legacyEventID: String? = nil
    var location: String? = nil
    var eventDescription: String? = nil
    var lastModified: Date? = nil
    var timeZone: String? = nil

    var scheduledMeeting: ScheduledMeeting? {
        conferenceURL.map { ScheduledMeeting(eventID: id, start: start, end: end, url: $0) }
    }
    var occurrenceID: String { id + "@" + String(Int(start.timeIntervalSince1970)) }

    /// How far the event start is from `date`, in seconds; negative means it started already.
    func offset(from date: Date) -> TimeInterval { start.timeIntervalSince(date) }
}

/// Merges calendars on this Mac with Murmur's cached Google Calendar connection.
/// EventKit remains available offline and does not require a Murmur account.
@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()
    struct LocalSource: Identifiable { let id: String; let name: String; let account: String; let canWrite: Bool }
    var localSources: [LocalSource] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event).map { LocalSource(id: $0.calendarIdentifier, name: $0.title, account: $0.source.title, canWrite: $0.allowsContentModifications) }
    }
    func saveEvent(id: String?, originalStart: Date? = nil, expectedModified: Date? = nil, sourceID: String, title: String, start: Date, end: Date, allDay: Bool, location: String, description: String, repeatFrequency: String, timeZone: String = TimeZone.current.identifier, reminder: String = "keep") throws {
        guard isAuthorized, let calendar = store.calendar(withIdentifier: sourceID), calendar.allowsContentModifications else {
            throw CloudHTTPError(status: 403, message: "Choose a writable calendar on this Mac.")
        }
        let event: EKEvent
        if let id {
            let existing: EKEvent?
            if let originalStart {
                let predicate = store.predicateForEvents(withStart: originalStart.addingTimeInterval(-1), end: originalStart.addingTimeInterval(1), calendars: [calendar])
                existing = store.events(matching: predicate).first { $0.eventIdentifier == id && $0.startDate == originalStart }
            } else { existing = store.event(withIdentifier: id) }
            guard let existing, expectedModified == nil || existing.lastModifiedDate == expectedModified else { throw CloudHTTPError(status: 409, message: "This event changed or was removed. Open it again before editing.") }
            event = existing
        } else { event = EKEvent(eventStore: store) }
        event.calendar = calendar; event.title = title; event.startDate = start; event.endDate = end
        event.isAllDay = allDay
        event.timeZone = allDay ? nil : TimeZone(identifier: timeZone)
        if reminder == "none" { event.alarms = [] }
        else if let minutes = Int(reminder) { event.alarms = [EKAlarm(relativeOffset: -Double(minutes) * 60)] }
        event.location = location; event.notes = description
        if id == nil, let frequency: EKRecurrenceFrequency = ["Daily": .daily, "Weekly": .weekly, "Monthly": .monthly][repeatFrequency] {
            event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)]
        }
        try store.save(event, span: .thisEvent, commit: true)
    }
    func removeEvent(_ event: CalendarEvent) throws {
        guard isAuthorized, let sourceID = event.calendarSourceID, let calendar = store.calendar(withIdentifier: sourceID), calendar.allowsContentModifications else {
            throw CloudHTTPError(status: 403, message: "This calendar cannot be edited on this Mac.")
        }
        let predicate = store.predicateForEvents(withStart: event.start.addingTimeInterval(-1), end: event.start.addingTimeInterval(1), calendars: [calendar])
        guard let existing = store.events(matching: predicate).first(where: { $0.eventIdentifier == event.id && $0.startDate == event.start }), event.lastModified == nil || existing.lastModifiedDate == event.lastModified else {
            throw CloudHTTPError(status: 409, message: "This event changed or was removed. Open it again before removing it.")
        }
        try store.remove(existing, span: .thisEvent, commit: true)
    }
    private var hiddenSources: Set<String> { Set(UserDefaults.standard.stringArray(forKey: "calendar.hiddenSources") ?? []) }
    func isVisible(_ id: String) -> Bool { !hiddenSources.contains(id) }
    func setVisible(_ id: String, visible: Bool) {
        var hidden = hiddenSources
        if visible { hidden.remove(id) } else { hidden.insert(id) }
        UserDefaults.standard.set(Array(hidden), forKey: "calendar.hiddenSources")
    }

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var isDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted: true
        default: false
        }
    }

    /// Prompts if undetermined; otherwise reports the current state without a dialog.
    func requestAccess() async -> Bool {
        guard !isAuthorized else { return true }
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return false }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        NSWorkspace.shared.open(url)
    }

    /// Events overlapping a window around `date`. Declined, all-day and free-time blocks are
    /// left out — none of them is a meeting you'd be on a call for.
    func events(around date: Date, before: TimeInterval = 15 * 60, after: TimeInterval = 15 * 60) -> [CalendarEvent] {
        let cloud = CloudSync.shared.meetings.filter { $0.details?.meeting_suggestions != false && $0.details?.all_day != true && $0.details?.response != "declined" && $0.details?.availability != "transparent" && $0.ends_at > date.addingTimeInterval(-before) && $0.starts_at <= date.addingTimeInterval(after) }.map { event in
            let url = event.meeting_url.flatMap { MeetingLink.provider(for: $0) != nil ? $0 : nil }
            return CalendarEvent(id: event.calendarIdentity, title: event.title, start: event.starts_at, end: event.ends_at,
                attendees: event.attendees, hasConference: url != nil, conferenceURL: url, booking: event.booking)
        }
        guard isAuthorized else { return cloud.sorted { abs($0.offset(from: date)) < abs($1.offset(from: date)) } }
        let predicate = store.predicateForEvents(
            withStart: date.addingTimeInterval(-max(before, 4 * 3600)),
            end: date.addingTimeInterval(after),
            calendars: nil
        )
        let local = store.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay else { return false }
                if event.availability == .free { return false }
                if let status = event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus,
                   status == .declined { return false }
                // Still running, or starting within the window.
                return event.endDate > date.addingTimeInterval(-before) && event.startDate <= date.addingTimeInterval(after)
            }
            .map(Self.reduce)
            .sorted { abs($0.offset(from: date)) < abs($1.offset(from: date)) }
        let same = { (local: CalendarEvent, remote: CalendarEvent) in
            abs(local.start.timeIntervalSince(remote.start)) < 60 &&
                (local.conferenceURL == remote.conferenceURL && remote.conferenceURL != nil || local.title == remote.title)
        }
        // The Mac's copy of a booked meeting keeps the guest's booking details from the cloud copy.
        let merged = local.map { event -> CalendarEvent in
            guard let booked = cloud.first(where: { $0.booking != nil && same(event, $0) }) else { return event }
            return CalendarEvent(id: booked.id, title: event.title, start: event.start, end: event.end,
                attendees: event.attendees, hasConference: event.hasConference, conferenceURL: event.conferenceURL, booking: booked.booking)
        }
        let additional = cloud.filter { remote in !local.contains { same($0, remote) } }
        return (merged + additional).sorted { abs($0.offset(from: date)) < abs($1.offset(from: date)) }
    }

    /// Only when this Mac's calendars are busy — no titles, people or places — so booking
    /// links avoid events that exist only on this Mac. All-day events count only when marked busy.
    func busyTimes(from start: Date = Date(), days: Int = 60) -> [DateInterval] {
        guard isAuthorized else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: start.addingTimeInterval(Double(days) * 86_400), calendars: nil)
        let blocks = store.events(matching: predicate).filter { event in
            if event.availability == .free { return false }
            if event.isAllDay, event.availability != .busy, event.availability != .unavailable { return false }
            if let status = event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus,
               status == .declined { return false }
            return event.endDate > event.startDate
        }
        .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        .sorted { $0.start < $1.start }
        return Array(blocks.prefix(2_000))
    }

    /// The single event most likely to be the call happening now.
    ///
    /// Prefers events with attendees or a conference link — a solo "Focus" block is not a
    /// meeting — and, among those, the one whose start is nearest to now. An event that
    /// started more than fifteen minutes ago and has no link is assumed to be over.
    /// Faithful display of every visible event overlapping the requested period.
    /// Meeting detection keeps its own eligibility filters.
    func events(from start: Date, to end: Date, cloudEvents: [CloudMeeting]? = nil) -> [CalendarEvent] {
        if PreviewEnvironment.isActive { return PreviewEnvironment.sampleEvents(from: start, to: end) }
        let cloud = (cloudEvents ?? CloudSync.shared.meetings)
            .filter { $0.details?.show_in_calendar != false }
            .map { event -> CalendarEvent in
                let url = event.meeting_url.flatMap { MeetingLink.provider(for: $0) != nil ? $0 : nil }
                return CalendarEvent(id: event.calendarIdentity, title: event.title, start: event.starts_at, end: event.ends_at,
                    attendees: event.attendees, hasConference: url != nil, conferenceURL: url, booking: event.booking,
                    isAllDay: event.details?.all_day == true, startDateOnly: event.details?.start_date, endDateOnly: event.details?.end_date, calendarSourceID: event.connection_id.flatMap { account in event.calendar_id.map { account + "|" + $0 } },
                    legacyEventID: event.legacy_id_unique == true ? "google-" + event.id : nil, location: event.details?.location, eventDescription: event.details?.description, timeZone: event.details?.time_zone)
            }
            .filter { $0.displayEnd > start && $0.displayStart < end }
        guard isAuthorized else { return cloud.sorted { $0.start < $1.start } }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: store.calendars(for: .event).filter { isVisible($0.calendarIdentifier) })
        let local = store.events(matching: predicate)
            .map(Self.reduce)
        // Similar titles and times do not establish identity across independent sources.
        return (local + cloud).sorted { $0.start < $1.start }
    }

    func bestMatch(at date: Date = Date()) -> CalendarEvent? {
        let candidates = events(around: date)
        return candidates.first {
            ($0.attendees.count >= 2 || $0.hasConference) && $0.end > date && $0.start <= date.addingTimeInterval(5 * 60)
        }
    }

    private static func reduce(_ event: EKEvent) -> CalendarEvent {
        let attendees = (event.attendees ?? []).compactMap { participant -> Attendee? in
            guard let name = participant.name, !name.isEmpty else { return nil }
            let email = participant.url.absoluteString.hasPrefix("mailto:")
                ? String(participant.url.absoluteString.dropFirst("mailto:".count))
                : nil
            return Attendee(name: name, email: email)
        }
        let haystack = [event.url?.absoluteString, event.location, event.notes]
            .compactMap { $0 }
            .joined(separator: " ")
        let conferenceURL = MeetingLink.conferenceURL(in: haystack)
        return CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled event",
            start: event.startDate,
            end: event.endDate,
            attendees: attendees,
            hasConference: conferenceURL != nil,
            conferenceURL: conferenceURL,
            isAllDay: event.isAllDay, calendarName: event.calendar.title,
            calendarSourceID: event.calendar.calendarIdentifier, location: event.location, eventDescription: event.notes, lastModified: event.lastModifiedDate, timeZone: event.timeZone?.identifier
        )
    }
}
