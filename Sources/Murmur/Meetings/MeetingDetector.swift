import AppKit
import ApplicationServices
import Foundation
import Observation

/// A process that looks like it is on a call, and everything known about it.
struct MeetingCandidate: Identifiable, Equatable, Sendable {
    let bundleID: String
    let pid: pid_t
    /// "Zoom", "Google Meet", or a process name for the unknown.
    let label: String
    /// "Zoom meeting", "Slack huddle" — what the offer calls it.
    let callNoun: String
    let isKnown: Bool
    let isBrowser: Bool
    let since: Date
    var calendarEvent: CalendarEvent?

    var id: String { "\(bundleID)#\(pid)" }

    func elapsed(at date: Date = Date()) -> TimeInterval { date.timeIntervalSince(since) }

    /// The single line the offer strip shows under the name: the evidence.
    func evidence(at date: Date = Date()) -> String {
        var parts = ["two-way audio \(Self.clock(elapsed(at: date)))"]
        if let event = calendarEvent {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            parts.append("calendar \(f.string(from: event.start))")
        }
        return parts.joined(separator: " · ")
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Decides when a call is happening and what to do about it.
///
/// Signals, in the order they are trusted: a process with both input *and* output running
/// (from `AudioProcessMonitor`), whether that process is a known meeting app, for browsers
/// whether a window title names a meeting service, and whether the calendar agrees. Then a
/// sustained-use delay before anything is shown, so a call you decline never becomes a
/// session, and a release timer afterwards, so the recording ends when the call does.
@MainActor
@Observable
final class MeetingDetector {
    enum Decision: Equatable {
        case autoStart(MeetingCandidate)
        case offer(MeetingCandidate, quiet: Bool)
    }

    /// The process currently under observation, if any — visible so the menu bar can show a
    /// quiet hint even before an offer.
    private(set) var candidate: MeetingCandidate?
    /// The offer currently showing, if any.
    private(set) var offered: MeetingCandidate?
    private(set) var isQuietOffer = false

    /// Set by the controller while a session records, so the detector can watch for the
    /// call ending rather than offering to record it again.
    var recordingBundleID: String?

    var onDecision: ((Decision) -> Void)?
    /// The recorded app has had no input for `autoStopAfter` seconds.
    var onCallEnded: (() -> Void)?

    private let monitor = AudioProcessMonitor()
    private var tick: Task<Void, Never>?
    /// Bundle IDs the user said "not now" to, cleared when that app's call ends.
    private var declined: Set<String> = []
    /// Bundle IDs already decided on for the current call, so one call yields one offer.
    private var decided: Set<String> = []
    private var releaseSince: Date?

    /// Unknown apps wait longer before a quiet offer. A known app's two-way audio is a call;
    /// an unknown app's might be a game.
    private static let unknownAppDelay: TimeInterval = 30

    func start() {
        guard tick == nil else { return }
        monitor.start()
        tick = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.evaluate()
            }
        }
        Log.app.info("meeting detector started")
    }

    func stop() {
        tick?.cancel()
        tick = nil
        monitor.stop()
        candidate = nil
        offered = nil
    }

    /// "Not now." Silence for this app until its current call ends.
    func decline() {
        guard let offered else { return }
        declined.insert(offered.bundleID)
        self.offered = nil
    }

    /// The offer was taken up (or the user pressed Record themselves).
    func dismissOffer() {
        offered = nil
    }

    // MARK: - Evaluation

    private func evaluate() {
        let settings = MeetingSettings.shared
        let now = Date()

        // While recording, the only question is whether the call has ended.
        if let recording = recordingBundleID {
            let stillLive = monitor.processes.contains { $0.bundleID == recording && $0.isRunningInput }
            if stillLive {
                releaseSince = nil
            } else {
                if releaseSince == nil { releaseSince = now }
                if let since = releaseSince, now.timeIntervalSince(since) >= settings.autoStopAfter {
                    releaseSince = nil
                    Log.app.info("call ended — \(recording, privacy: .public) released the mic \(Int(settings.autoStopAfter))s ago")
                    onCallEnded?()
                }
            }
            if offered != nil { offered = nil }
            candidate = nil
            return
        }
        releaseSince = nil

        guard settings.detectionEnabled else {
            candidate = nil
            offered = nil
            return
        }

        let twoWay = monitor.processes.filter {
            $0.isTwoWay && !MeetingAppRegistry.ignoredBundleIDs.contains($0.bundleID)
        }

        // Forget decisions and declines for apps whose calls have ended.
        let liveBundles = Set(twoWay.map(\.bundleID))
        decided = decided.intersection(liveBundles)
        declined = declined.intersection(liveBundles)

        guard let best = Self.pick(from: twoWay) else {
            candidate = nil
            offered = nil
            return
        }

        if candidate?.bundleID != best.bundleID || candidate?.pid != best.pid {
            candidate = best
            Log.app.info("call candidate: \(best.label, privacy: .public) (\(best.bundleID, privacy: .public))")
        }
        guard var current = candidate else { return }

        guard !decided.contains(current.bundleID), !declined.contains(current.bundleID) else { return }
        let rule = settings.rule(for: current.bundleID)
        guard rule != .never else { return }

        let delay = current.isKnown ? settings.offerDelay : Self.unknownAppDelay
        guard current.elapsed(at: now) >= delay else { return }

        if settings.calendarEnabled {
            current.calendarEvent = CalendarService.shared.bestMatch(at: now)
            candidate = current
        }

        decided.insert(current.bundleID)
        let strongEvidence = current.isKnown && current.calendarEvent != nil
        if rule == .auto || (settings.autoStartOnCalendarMatch && strongEvidence) {
            offered = nil
            onDecision?(.autoStart(current))
        } else {
            let quiet = !current.isKnown
            offered = current
            isQuietOffer = quiet
            onDecision?(.offer(current, quiet: quiet))
        }
    }

    /// Known native apps beat browsers with a meeting title, which beat other browsers, which
    /// beat everything else. Within a tier, the one that has been on a call longest wins.
    private static func pick(from processes: [AudioProcessInfo]) -> MeetingCandidate? {
        let now = Date()
        var scored: [(MeetingCandidate, Int)] = []
        for process in processes {
            let running = NSRunningApplication(processIdentifier: process.pid)
            let fallbackName = running?.localizedName ?? process.bundleID
            if let app = MeetingAppRegistry.app(for: process.bundleID) {
                switch app.kind {
                case .native:
                    scored.append((MeetingCandidate(
                        bundleID: process.bundleID, pid: process.pid, label: app.label, callNoun: app.callNoun,
                        isKnown: true, isBrowser: false, since: now
                    ), 3))
                case .browser:
                    let titles = BrowserTitleReader.windowTitles(pid: process.pid)
                    if let service = titles.lazy.compactMap({ MeetingAppRegistry.webService(matching: $0) }).first {
                        scored.append((MeetingCandidate(
                            bundleID: process.bundleID, pid: process.pid, label: service.label,
                            callNoun: "\(service.label) call", isKnown: true, isBrowser: true, since: now
                        ), 2))
                    } else {
                        scored.append((MeetingCandidate(
                            bundleID: process.bundleID, pid: process.pid, label: app.label,
                            callNoun: app.callNoun, isKnown: false, isBrowser: true, since: now
                        ), 1))
                    }
                }
            } else {
                scored.append((MeetingCandidate(
                    bundleID: process.bundleID, pid: process.pid, label: fallbackName,
                    callNoun: "call in \(fallbackName)", isKnown: false, isBrowser: false, since: now
                ), 0))
            }
        }
        return scored.max { $0.1 < $1.1 }?.0
    }
}

/// Reads window titles of another app through Accessibility — the grant Murmur already holds
/// for the hotkey. Titles only; nothing else is read and nothing is stored from them.
enum BrowserTitleReader {
    static func windowTitles(pid: pid_t) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        var titles: [String] = []

        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
           let focused, let title = title(of: unsafeDowncast(focused as AnyObject, to: AXUIElement.self)) {
            titles.append(title)
        }

        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
           let list = windows as? [AXUIElement] {
            for window in list.prefix(12) {
                if let title = title(of: window), !titles.contains(title) { titles.append(title) }
            }
        }
        return titles
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
