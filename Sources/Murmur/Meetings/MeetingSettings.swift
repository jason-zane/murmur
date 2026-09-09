import Foundation
import Observation

/// Everything meetings need that dictation doesn't. Its own object rather than more
/// properties on `Settings`, so the two halves of the app can change independently.
@MainActor
@Observable
final class MeetingSettings {
    static let shared = MeetingSettings()

    /// Master switch for detection. Off means the menu bar Record button is the only way in.
    var detectionEnabled: Bool { didSet { defaults.set(detectionEnabled, forKey: Keys.detectionEnabled) } }

    /// Read the Mac's calendar for meeting names and attendees. Needs the Calendars grant.
    var calendarEnabled: Bool { didSet { defaults.set(calendarEnabled, forKey: Keys.calendarEnabled) } }

    /// When a known app has a two-way call *and* the calendar agrees a meeting is on, start
    /// without asking. Off by default: trust is granted after detection has been right.
    var autoStartOnCalendarMatch: Bool { didSet { defaults.set(autoStartOnCalendarMatch, forKey: Keys.autoStart) } }

    /// How long two-way audio must persist before anything is offered. A ringing call you
    /// decline never becomes a session.
    var offerDelay: TimeInterval { didSet { defaults.set(offerDelay, forKey: Keys.offerDelay) } }

    /// How long after the app releases the mic a recording ends itself.
    var autoStopAfter: TimeInterval { didSet { defaults.set(autoStopAfter, forKey: Keys.autoStopAfter) } }

    /// Per-app overrides of the default rule, keyed by bundle identifier.
    var appRules: [String: MeetingAppRule] {
        didSet {
            if let data = try? JSONEncoder().encode(appRules) { defaults.set(data, forKey: Keys.appRules) }
        }
    }

    /// Which engine transcribes meetings. Apple streams and needs no download; Parakeet is
    /// more accurate on English but only if its models are on disk.
    var engine: SpeechEngineChoice { didSet { defaults.set(engine.rawValue, forKey: Keys.engine) } }

    /// Show the live transcript in the notepad. Off by default — it competes with the call.
    var showLiveTranscript: Bool { didSet { defaults.set(showLiveTranscript, forKey: Keys.showLiveTranscript) } }

    /// Play a sound when a meeting recording starts and stops.
    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) } }

    /// Rule for an app, falling back to the registry default: known meeting apps and
    /// browsers ask; anything unknown asks quietly (handled by the detector, not here).
    func rule(for bundleID: String) -> MeetingAppRule {
        appRules[bundleID] ?? .ask
    }

    func setRule(_ rule: MeetingAppRule, for bundleID: String) {
        var updated = appRules
        updated[bundleID] = rule
        appRules = updated
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let detectionEnabled = "meeting.detectionEnabled"
        static let calendarEnabled = "meeting.calendarEnabled"
        static let autoStart = "meeting.autoStartOnCalendarMatch"
        static let offerDelay = "meeting.offerDelay"
        static let autoStopAfter = "meeting.autoStopAfter"
        static let appRules = "meeting.appRules"
        static let engine = "meeting.engine"
        static let showLiveTranscript = "meeting.showLiveTranscript"
        static let soundEnabled = "meeting.soundEnabled"
    }

    private init() {
        detectionEnabled = defaults.object(forKey: Keys.detectionEnabled) as? Bool ?? true
        calendarEnabled = defaults.object(forKey: Keys.calendarEnabled) as? Bool ?? true
        autoStartOnCalendarMatch = defaults.object(forKey: Keys.autoStart) as? Bool ?? false
        offerDelay = defaults.object(forKey: Keys.offerDelay) as? Double ?? 8
        autoStopAfter = defaults.object(forKey: Keys.autoStopAfter) as? Double ?? 60
        if let data = defaults.data(forKey: Keys.appRules),
           let rules = try? JSONDecoder().decode([String: MeetingAppRule].self, from: data) {
            appRules = rules
        } else {
            appRules = [:]
        }
        engine = SpeechEngineChoice(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .apple
        showLiveTranscript = defaults.object(forKey: Keys.showLiveTranscript) as? Bool ?? false
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
    }
}
