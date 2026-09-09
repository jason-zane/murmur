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
        let cloud = CloudSync.shared.meetings.filter { $0.ends_at > date.addingTimeInterval(-before) && $0.starts_at <= date.addingTimeInterval(after) }.map { event in
            let url = event.meeting_url.flatMap { MeetingLink.provider(for: $0) != nil ? $0 : nil }
            return CalendarEvent(id: "google-" + event.id, title: event.title, start: event.starts_at, end: event.ends_at,
                attendees: event.attendees, hasConference: url != nil, conferenceURL: url)
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
        let additional = cloud.filter { remote in !local.contains { local in
            abs(local.start.timeIntervalSince(remote.start)) < 60 &&
                (local.conferenceURL == remote.conferenceURL && remote.conferenceURL != nil || local.title == remote.title)
        } }
        return (local + additional).sorted { abs($0.offset(from: date)) < abs($1.offset(from: date)) }
    }

    /// The single event most likely to be the call happening now.
    ///
    /// Prefers events with attendees or a conference link — a solo "Focus" block is not a
    /// meeting — and, among those, the one whose start is nearest to now. An event that
    /// started more than fifteen minutes ago and has no link is assumed to be over.
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
            conferenceURL: conferenceURL
        )
    }
}
