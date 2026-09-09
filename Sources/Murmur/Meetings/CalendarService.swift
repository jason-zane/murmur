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

    /// How far the event start is from `date`, in seconds; negative means it started already.
    func offset(from date: Date) -> TimeInterval { start.timeIntervalSince(date) }
}

/// Reads the Mac's own calendars through EventKit.
///
/// Google Calendar, iCloud, Exchange — whatever is signed into System Settings ▸ Internet
/// Accounts is already syncing into Calendar.app, and EventKit reads that. No Google OAuth,
/// no browser login, no token that expires. One Calendars permission, and it's done.
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
        guard isAuthorized else { return [] }
        let predicate = store.predicateForEvents(
            withStart: date.addingTimeInterval(-max(before, 4 * 3600)),
            end: date.addingTimeInterval(after),
            calendars: nil
        )
        return store.events(matching: predicate)
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
    }

    /// The single event most likely to be the call happening now.
    ///
    /// Prefers events with attendees or a conference link — a solo "Focus" block is not a
    /// meeting — and, among those, the one whose start is nearest to now. An event that
    /// started more than fifteen minutes ago and has no link is assumed to be over.
    func bestMatch(at date: Date = Date()) -> CalendarEvent? {
        let candidates = events(around: date)
        let meetings = candidates.filter { $0.attendees.count >= 2 || $0.hasConference }
        return meetings.first ?? candidates.first { abs($0.offset(from: date)) <= 5 * 60 }
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
            .lowercased()
        let conference = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com",
                          "whereby.com", "around.co", "meet.jit.si", "facetime.apple.com"]
            .contains { haystack.contains($0) }
        return CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled event",
            start: event.startDate,
            end: event.endDate,
            attendees: attendees,
            hasConference: conference
        )
    }
}
