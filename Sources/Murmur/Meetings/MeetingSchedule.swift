import AppKit
import EventKit
import Foundation
import MurmurSessions
import Observation

/// Opening a calendar link never starts capture. Detection waits for audio from the call.
@MainActor
@Observable
final class MeetingSchedule {
    static let shared = MeetingSchedule()
    private(set) var events: [CalendarEvent] = []
    private(set) var calendarGranted = false
    private(set) var message: String?
    private(set) var handled: Set<String> = []
    var captureIsBusy = false
    private var tick: Task<Void, Never>?
    private var enabledSince = Date()
    private var wasEnabled = false
    private var ledger: [String: Double] = UserDefaults.standard.dictionary(forKey: "meeting.openedOccurrences") as? [String: Double] ?? [:]

    func start() {
        guard tick == nil else { return }
        enabledSince = Date()
        handled = Set(ledger.keys)
        refresh()
        tick = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.refresh()
            }
        }
    }
    func stop() { tick?.cancel(); tick = nil }
    func requestCalendar() async { _ = await CalendarService.shared.requestAccess(); refresh() }

    func refresh() {
        guard !PreviewEnvironment.isActive else { return }
        let now = Date(), settings = MeetingSettings.shared
        calendarGranted = CalendarService.shared.isAuthorized || CloudSync.shared.calendarConnected
        let enabled = settings.calendarEnabled && settings.autoOpenMeetings && calendarGranted
        if enabled && !wasEnabled { enabledSince = now }
        wasEnabled = enabled
        events = settings.calendarEnabled && calendarGranted
            ? CalendarService.shared.events(around: now, before: 0, after: 24 * 3_600)
                .filter { $0.end > now && ($0.hasConference || $0.attendees.count >= 2) }.sorted { $0.start < $1.start }
            : []
        guard enabled, !captureIsBusy else { return }
        let due = MeetingOpeningPolicy.due(events.compactMap(\.scheduledMeeting), now: now, enabledSince: enabledSince, handled: handled)
        guard due.count <= 1 else { message = "Two meetings start together. Choose which one to join below."; return }
        if let next = due.first, let event = events.first(where: { $0.occurrenceID == next.id }) { join(event) }
    }

    func skip(_ event: CalendarEvent) { markHandled(event); message = "Automatic opening skipped for “\(event.title)”." }
    func join(_ event: CalendarEvent) {
        guard let url = event.conferenceURL, MeetingLink.provider(for: url) != nil else {
            message = "This event has no supported meeting link. Open it in Calendar to join."; return
        }
        markHandled(event)
        message = nil
        if MeetingLink.provider(for: url) == "Google Meet",
           let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: config) { [weak self] _, error in
                if let error { Task { @MainActor in self?.message = "Couldn't open the meeting: \(error.localizedDescription)" } }
            }
        } else if !NSWorkspace.shared.open(url) { message = "Couldn't open the meeting link. Try Calendar." }
    }
    private func markHandled(_ event: CalendarEvent) {
        let now = Date().timeIntervalSince1970
        ledger = ledger.filter { $0.value > now - 7 * 86_400 }
        ledger[event.occurrenceID] = now
        handled = Set(ledger.keys)
        UserDefaults.standard.set(ledger, forKey: "meeting.openedOccurrences")
    }
}
