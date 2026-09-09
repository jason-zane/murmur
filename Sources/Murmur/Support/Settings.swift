import Foundation
import Observation

enum SpeechEngineChoice: String, CaseIterable, Sendable {
    case apple
    case parakeet

    var displayName: String {
        switch self {
        case .apple: "Apple (streaming)"
        case .parakeet: "Parakeet (batch)"
        }
    }

    var showsLiveText: Bool { self == .apple }
}

/// How a trigger starts and stops a dictation.
enum ActivationMode: String, CaseIterable, Sendable {
    /// Hold to talk. Release ends it. A quick tap records almost nothing.
    case hold
    /// Tap to start, tap again to stop. Holding does nothing special.
    case toggle
    /// Hold to talk, *or* tap once to latch it on and tap again to stop.
    case hybrid

    var displayName: String {
        switch self {
        case .hold: "Hold"
        case .toggle: "Toggle"
        case .hybrid: "Both"
        }
    }

    var detail: String {
        switch self {
        case .hold:
            "Hold the trigger to dictate. Releasing it finishes."
        case .toggle:
            "Tap to start, tap again to stop. Holding behaves the same as tapping."
        case .hybrid:
            "Hold to dictate and release to finish — or tap once to keep it running "
            + "hands-free, then tap again to stop."
        }
    }
}

/// A global shortcut for re-inserting the last transcription wherever the cursor is.
enum PasteShortcut: String, CaseIterable, Sendable {
    case commandShiftV
    case optionShiftV
    case controlShiftV
    case commandControlV

    var displayName: String {
        switch self {
        case .commandShiftV: "⌘⇧V"
        case .optionShiftV: "⌥⇧V"
        case .controlShiftV: "⌃⇧V"
        case .commandControlV: "⌘⌃V"
        }
    }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    /// Every trigger that can start a dictation. More than one may be armed at once — a
    /// keyboard modifier and a mouse button, say — and whichever starts a hold owns it.
    var triggers: Set<PushToTalkTrigger> {
        didSet {
            // Never persist an empty set: with no trigger armed the hotkey tap has nothing
            // to listen for and the app silently stops responding.
            if triggers.isEmpty { triggers = oldValue.isEmpty ? [.rightOption] : oldValue }
            defaults.set(triggers.map(\.rawValue).sorted(), forKey: Keys.triggers)
        }
    }

    var activation: ActivationMode {
        didSet { defaults.set(activation.rawValue, forKey: Keys.activation) }
    }

    var pasteShortcutEnabled: Bool {
        didSet { defaults.set(pasteShortcutEnabled, forKey: Keys.pasteShortcutEnabled) }
    }

    var pasteShortcut: PasteShortcut {
        didSet { defaults.set(pasteShortcut.rawValue, forKey: Keys.pasteShortcut) }
    }

    var engine: SpeechEngineChoice {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    var compareMode: Bool {
        didSet { defaults.set(compareMode, forKey: Keys.compareMode) }
    }

    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }

    var smartCleanup: Bool {
        didSet { defaults.set(smartCleanup, forKey: Keys.smartCleanup) }
    }

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            let resulting = LoginItem.set(launchAtLogin)
            if resulting.isOn != launchAtLogin { launchAtLogin = resulting.isOn }
        }
    }

    /// Human-readable list of armed triggers, for the window header and menu.
    var triggerSummary: String {
        let names = triggers.map(\.displayName).sorted()
        switch names.count {
        case 0: return "no trigger"
        case 1: return names[0]
        case 2: return "\(names[0]) or \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " or " + names[names.count - 1]
        }
    }

    /// Caveats for whatever is currently armed, so the UI can warn without duplicating logic.
    var triggerCaveats: [String] {
        triggers.sorted { $0.rawValue < $1.rawValue }.compactMap(\.caveat)
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let triggers = "triggers"
        static let activation = "activation"
        static let pasteShortcut = "pasteShortcut"
        static let pasteShortcutEnabled = "pasteShortcutEnabled"
        static let cleanupEnabled = "cleanupEnabled"
        static let soundEnabled = "soundEnabled"
        static let engine = "engine"
        static let smartCleanup = "smartCleanup"
        static let compareMode = "compareMode"
        // Legacy single-key setting, read once to carry an existing choice forward.
        static let legacyPushToTalkKey = "pushToTalkKey"
    }

    private init() {
        // Resolved entirely in locals: stored properties can't be read back until every one
        // of them is initialized.
        var resolvedTriggers: Set<PushToTalkTrigger>
        if let stored = defaults.array(forKey: Keys.triggers) as? [String] {
            resolvedTriggers = Set(stored.compactMap(PushToTalkTrigger.init(rawValue:)))
        } else if let legacy = defaults.string(forKey: Keys.legacyPushToTalkKey),
                  let key = PushToTalkTrigger(rawValue: legacy) {
            // Carry forward the single key chosen under the old setting, except `fn` — that
            // default shipped briefly and is unusable unless "Press fn key to" is set to
            // "Do Nothing", which is not the stock configuration.
            resolvedTriggers = key == .fn ? [.rightOption] : [key]
        } else {
            resolvedTriggers = [.rightOption]
        }
        if resolvedTriggers.isEmpty { resolvedTriggers = [.rightOption] }
        triggers = resolvedTriggers

        // Hybrid by default: hold works as before, and a tap now latches instead of
        // producing a quarter-second of silence.
        activation = ActivationMode(rawValue: defaults.string(forKey: Keys.activation) ?? "")
            ?? .hybrid

        // ⌥⇧V rather than the more obvious ⌘⇧V: this shortcut is swallowed globally, and
        // ⌘⇧V is "Paste and Match Style" in most macOS apps — claiming it would quietly
        // remove plain-text paste everywhere. ⌥⇧V is unbound almost everywhere. ⌘⇧V is
        // still offered for anyone who doesn't use paste-and-match.
        pasteShortcut = PasteShortcut(rawValue: defaults.string(forKey: Keys.pasteShortcut) ?? "")
            ?? .optionShiftV
        pasteShortcutEnabled = defaults.object(forKey: Keys.pasteShortcutEnabled) as? Bool ?? true

        engine = SpeechEngineChoice(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .apple
        cleanupEnabled = defaults.object(forKey: Keys.cleanupEnabled) as? Bool ?? true
        // On by default: the LLM cleanup pass is what makes dictation feel like Wispr rather
        // than raw ASR. It degrades to RuleBasedFormatter where Foundation Models isn't
        // available, so defaulting it on is safe.
        smartCleanup = defaults.object(forKey: Keys.smartCleanup) as? Bool ?? true
        compareMode = defaults.object(forKey: Keys.compareMode) as? Bool ?? false
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        launchAtLogin = LoginItem.state.isOn
    }
}
