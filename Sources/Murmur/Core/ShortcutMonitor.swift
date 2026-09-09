import AppKit
import Carbon.HIToolbox
import Foundation

/// Watches for a single global key combination and fires a callback.
///
/// Separate from `HotkeyMonitor` on purpose. That one watches *modifier* transitions to open
/// and close the mic; this watches a complete `keyDown` chord and fires once. Sharing a tap
/// would mean one class doing two unrelated jobs with two different notions of "pressed",
/// and the paste shortcut can be switched off independently without disarming dictation.
///
/// Needs the same Accessibility permission as the dictation tap — it's the same mechanism.
@MainActor
final class ShortcutMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Modifiers we actually compare. Everything else — caps lock, numeric pad, and the `fn`
    /// bit that laptop keyboards set for function-row keys — is masked out, because requiring
    /// an exact match on the raw flags makes the shortcut fail on some keyboards for reasons
    /// the user cannot see.
    private static let relevant: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl,
    ]

    var shortcut: PasteShortcut = .commandShiftV
    var isEnabled = true
    var onTrigger: (() -> Void)?

    @discardableResult
    func start() -> Bool {
        stop()
        guard isEnabled else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("paste shortcut tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.hotkey.info("paste shortcut armed: \(self.shortcut.displayName, privacy: .public)")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    @discardableResult
    func reload() -> Bool { start() }

    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown, isEnabled else { return false }
        guard keyCode == Int64(kVK_ANSI_V) else { return false }
        guard flags.intersection(Self.relevant) == requiredFlags else { return false }

        onTrigger?()
        // Swallow it: the whole point is that this chord means "paste my last transcription"
        // rather than whatever the focused app would otherwise do with it.
        return true
    }

    private var requiredFlags: CGEventFlags { Self.flags(for: shortcut) }

    private static func flags(for shortcut: PasteShortcut) -> CGEventFlags {
        switch shortcut {
        case .commandShiftV: [.maskCommand, .maskShift]
        case .optionShiftV: [.maskAlternate, .maskShift]
        case .controlShiftV: [.maskControl, .maskShift]
        case .commandControlV: [.maskCommand, .maskControl]
        }
    }
}
