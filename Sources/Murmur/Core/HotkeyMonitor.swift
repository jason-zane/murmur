import AppKit
import Carbon.HIToolbox
import Foundation

/// Something you can hold to dictate: a modifier key, or a mouse button.
///
/// One flat enum rather than a nested `.modifier(_)` / `.mouse(_)` pair, because the value is
/// persisted by `rawValue` — a flat string keeps storage trivial and old values valid.
///
/// The set is every input that can physically be *held*: all eight modifier positions plus
/// the extra mouse buttons. Letter keys are excluded on purpose — held, they auto-repeat and
/// type into the focused app, which is exactly what a push-to-talk key must not do.
enum PushToTalkTrigger: String, CaseIterable, Sendable, Identifiable, Hashable {
    case leftControl, rightControl
    case leftOption, rightOption
    case leftCommand, rightCommand
    case leftShift, rightShift
    case fn
    case mouseMiddle, mouseButton4, mouseButton5, mouseButton6, mouseButton7, mouseButton8

    var id: String { rawValue }

    var isMouse: Bool { mouseButton != nil }

    /// Which physical mouse button, in `CGEvent`'s numbering. 0 and 1 are the normal left and
    /// right buttons and are deliberately unavailable — binding those makes the mouse unusable.
    var mouseButton: Int64? {
        switch self {
        case .mouseMiddle: 2
        case .mouseButton4: 3
        case .mouseButton5: 4
        case .mouseButton6: 5
        case .mouseButton7: 6
        case .mouseButton8: 7
        default: nil
        }
    }

    var keyCode: Int64? {
        switch self {
        case .leftControl: Int64(kVK_Control)         // 59
        case .rightControl: Int64(kVK_RightControl)   // 62
        case .leftOption: Int64(kVK_Option)           // 58
        case .rightOption: Int64(kVK_RightOption)     // 61
        case .leftCommand: Int64(kVK_Command)         // 55
        case .rightCommand: Int64(kVK_RightCommand)   // 54
        case .leftShift: Int64(kVK_Shift)             // 56
        case .rightShift: Int64(kVK_RightShift)       // 60
        case .fn: Int64(kVK_Function)                 // 63
        default: nil
        }
    }

    /// Device-*dependent* bit for this specific physical key.
    ///
    /// `CGEventFlags.maskAlternate` is the union mask — set whenever *either* Option key is
    /// down. Using it means holding Left ⌥ and tapping Right ⌥ makes the release invisible,
    /// because the union bit is still set by the other key. These raw values are IOKit's
    /// NX_DEVICE* masks, which carry the left/right distinction the public constants discard.
    var flag: CGEventFlags? {
        switch self {
        case .leftControl: CGEventFlags(rawValue: 0x00000001)   // NX_DEVICELCTLKEYMASK
        case .rightControl: CGEventFlags(rawValue: 0x00002000)  // NX_DEVICERCTLKEYMASK
        case .leftShift: CGEventFlags(rawValue: 0x00000002)     // NX_DEVICELSHIFTKEYMASK
        case .rightShift: CGEventFlags(rawValue: 0x00000004)    // NX_DEVICERSHIFTKEYMASK
        case .leftCommand: CGEventFlags(rawValue: 0x00000008)   // NX_DEVICELCMDKEYMASK
        case .rightCommand: CGEventFlags(rawValue: 0x00000010)  // NX_DEVICERCMDKEYMASK
        case .leftOption: CGEventFlags(rawValue: 0x00000020)    // NX_DEVICELALTKEYMASK
        case .rightOption: CGEventFlags(rawValue: 0x00000040)   // NX_DEVICERALTKEYMASK
        case .fn: .maskSecondaryFn                              // no left/right variant exists
        default: nil
        }
    }

    var displayName: String {
        switch self {
        case .leftControl: "Left ⌃"
        case .rightControl: "Right ⌃"
        case .leftOption: "Left ⌥"
        case .rightOption: "Right ⌥"
        case .leftCommand: "Left ⌘"
        case .rightCommand: "Right ⌘"
        case .leftShift: "Left ⇧"
        case .rightShift: "Right ⇧"
        case .fn: "fn"
        case .mouseMiddle: "Middle click"
        case .mouseButton4: "Mouse 4"
        case .mouseButton5: "Mouse 5"
        case .mouseButton6: "Mouse 6"
        case .mouseButton7: "Mouse 7"
        case .mouseButton8: "Mouse 8"
        }
    }

    /// Whether to swallow the event rather than pass it to the focused app.
    ///
    /// **Left-hand modifiers and both Shifts are never swallowed.** Consuming the
    /// `flagsChanged` would stop the app below ever seeing the modifier go down, which breaks
    /// ⌥+letter (é, ø, …), every ⌘/⌃ shortcut on that side, and capital letters. A bare
    /// modifier reaching the app does nothing on its own, so passing it through is free.
    ///
    /// `fn` is passed through for the same reason — swallowing it breaks fn+arrow, fn+delete
    /// and the emoji picker.
    ///
    /// Right-hand ⌃/⌥/⌘ and the extra mouse buttons *are* swallowed: they're dedicated to
    /// this app, and mouse 4/5 would otherwise fire browser back/forward on every dictation.
    var shouldConsumeEvent: Bool {
        switch self {
        case .rightControl, .rightOption, .rightCommand: true
        case .mouseMiddle, .mouseButton4, .mouseButton5, .mouseButton6, .mouseButton7, .mouseButton8: true
        case .leftControl, .leftOption, .leftCommand, .leftShift, .rightShift, .fn: false
        }
    }

    var caveat: String? {
        switch self {
        case .fn:
            "fn also triggers whatever \"Press fn key to\" is set to in System Settings ▸ Keyboard. Set that to \"Do Nothing\", or pick another trigger."
        case .leftShift, .rightShift:
            "Shift is passed through to the app you're typing in, so anything you type while holding it will be capitalised."
        case .leftOption, .leftCommand, .leftControl:
            "Left-hand modifiers are passed through so shortcuts keep working — but a long hold may repeat a key in some apps."
        case .mouseMiddle:
            "Middle click is used for paste in some apps and for opening links in a new tab."
        default:
            nil
        }
    }

    /// Resolve a physical input to a trigger, if it's one we can bind.
    static func modifier(keyCode: Int64) -> PushToTalkTrigger? {
        allCases.first { !$0.isMouse && $0.keyCode == keyCode }
    }

    static func mouse(button: Int64) -> PushToTalkTrigger? {
        allCases.first { $0.mouseButton == button }
    }
}

/// What the user pressed while Settings was waiting to record a trigger.
enum TriggerCapture {
    case trigger(PushToTalkTrigger)
    /// Something that can't be held to talk, with a reason the UI can show.
    case unsupported(String)
}

/// Watches for a held trigger using a `CGEventTap`.
///
/// A tap is required rather than `NSEvent.addGlobalMonitor` because `fn` and left/right
/// modifier discrimination don't surface through the higher-level APIs. This needs
/// Accessibility permission; without it `CGEvent.tapCreate` returns nil.
///
/// Several triggers can be armed at once. Whichever one starts a hold owns it, and only that
/// one can end it — otherwise releasing an unrelated modifier mid-sentence would cut you off.
@MainActor
final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// The trigger currently held, if any.
    private var activeTrigger: PushToTalkTrigger?

    var triggers: Set<PushToTalkTrigger> = [.rightOption]
    var onPress: ((PushToTalkTrigger) -> Void)?
    var onRelease: ((PushToTalkTrigger) -> Void)?

    /// While set, the next held input is reported here instead of starting a dictation. This
    /// is how Settings records a trigger by having you press it. One-shot for a successful
    /// capture; an unsupported press reports and keeps listening.
    var captureHandler: ((TriggerCapture) -> Void)?

    /// - Returns: `false` if the tap couldn't be created — almost always missing Accessibility permission.
    @discardableResult
    func start() -> Bool {
        stop()

        guard !triggers.isEmpty else {
            Log.hotkey.error("no triggers configured — nothing to listen for")
            return false
        }

        // keyDown is included only so trigger capture can explain why a letter key was
        // rejected. Outside capture, key presses are passed through untouched.
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // CGEvent isn't Sendable, so pull out the plain values before crossing into
                // actor-isolated code. The tap was added to the main run loop, so this
                // callback genuinely does run on the main thread.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let button = event.getIntegerValueField(.mouseEventButtonNumber)
                let flags = event.flags
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, button: button, flags: flags)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let names = triggers.map(\.displayName).sorted().joined(separator: ", ")
        Log.hotkey.info("listening for \(names, privacy: .public)")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        activeTrigger = nil
    }

    /// Forget any in-flight press, so the next physical press reads as a press rather than
    /// being ignored as a repeat. Used when the controller force-resets a stuck session.
    func clearPressState() {
        activeTrigger = nil
    }

    // MARK: - Tap callback

    /// - Returns: `true` if the event should be swallowed rather than passed along.
    private func handle(
        type: CGEventType,
        keyCode: Int64,
        button: Int64,
        flags: CGEventFlags
    ) -> Bool {
        // The system disables a tap that runs too slowly or is interrupted; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        if let capture = captureHandler {
            return handleCapture(type: type, keyCode: keyCode, button: button, flags: flags, capture)
        }

        switch type {
        case .flagsChanged: return handleModifier(keyCode: keyCode, flags: flags)
        case .otherMouseDown: return handleMouse(button: button, isDown: true)
        case .otherMouseUp: return handleMouse(button: button, isDown: false)
        default: return false
        }
    }

    private func handleModifier(keyCode: Int64, flags: CGEventFlags) -> Bool {
        // A held modifier ends when its flag bit goes clear, on *any* flagsChanged event —
        // not only one carrying its own keycode.
        //
        // This is the fix for a hard-stuck recording. When a trigger we don't consume
        // (notably `fn`) opens a system panel, that panel takes the key-up and the matching
        // event never reaches this tap. Keying the release off the keycode therefore left the
        // hold active forever: the mic stayed open and no later press could start a new
        // dictation. Watching the flag bit means the next modifier event of any kind recovers.
        if let active = activeTrigger, !active.isMouse, let flag = active.flag {
            guard !flags.contains(flag) else { return false }
            activeTrigger = nil
            onRelease?(active)
            return keyCode == active.keyCode && active.shouldConsumeEvent
        }

        // Starting a hold requires an event from the trigger's own key, so pressing an
        // unrelated modifier can never begin a dictation.
        guard activeTrigger == nil else { return false }
        guard let match = triggers.first(where: { candidate in
            !candidate.isMouse
                && candidate.keyCode == keyCode
                && candidate.flag.map(flags.contains) == true
        }) else { return false }

        activeTrigger = match
        onPress?(match)
        return match.shouldConsumeEvent
    }

    private func handleMouse(button: Int64, isDown: Bool) -> Bool {
        if isDown {
            guard activeTrigger == nil else { return false }
            guard let match = triggers.first(where: { $0.mouseButton == button }) else {
                return false
            }
            activeTrigger = match
            onPress?(match)
            return match.shouldConsumeEvent
        }

        guard let active = activeTrigger, active.mouseButton == button else { return false }
        activeTrigger = nil
        onRelease?(active)
        return active.shouldConsumeEvent
    }

    // MARK: - Recording a trigger

    private func handleCapture(
        type: CGEventType,
        keyCode: Int64,
        button: Int64,
        flags: CGEventFlags,
        _ capture: (TriggerCapture) -> Void
    ) -> Bool {
        switch type {
        case .flagsChanged:
            if let trigger = PushToTalkTrigger.modifier(keyCode: keyCode) {
                // Only the press half. The release of the same key arrives as a second
                // flagsChanged with the bit clear; reporting that too would double-fire.
                guard trigger.flag.map(flags.contains) == true else { return false }
                captureHandler = nil
                capture(.trigger(trigger))
                return true
            }
            if keyCode == Int64(kVK_CapsLock) {
                capture(.unsupported("Caps Lock toggles rather than holds, so it can't be a push-to-talk key."))
                return true
            }
            return false

        case .otherMouseDown:
            if let trigger = PushToTalkTrigger.mouse(button: button) {
                captureHandler = nil
                capture(.trigger(trigger))
            } else {
                capture(.unsupported("That mouse button isn't one Voice Notes can bind."))
            }
            return true

        case .otherMouseUp:
            // Swallow the up half of a click we just captured, so the app underneath doesn't
            // see a stray button release.
            return PushToTalkTrigger.mouse(button: button) != nil

        case .keyDown:
            // Let the key type — swallowing it would look like a dead key — but explain.
            capture(.unsupported("Regular keys can't be held to talk: they'd repeat and type into whatever's focused. Use a modifier (⌥ ⌘ ⌃ ⇧ fn) or an extra mouse button."))
            return false

        default:
            return false
        }
    }
}
