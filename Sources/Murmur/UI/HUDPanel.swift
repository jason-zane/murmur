import AppKit
import SwiftUI

/// The window the HUD capsule floats in.
///
/// The panel is a **fixed, transparent canvas** — deliberately wider and taller than the
/// pill it contains. The pill sizes itself to its content and centres inside, so it can grow
/// with the transcript and shrink again without the window ever resizing. Resizing an
/// `NSPanel` on every partial ASR result judders badly and fights the SwiftUI animation.
///
/// `canBecomeKey` is false and this is a `.nonactivatingPanel`: if the overlay ever took key
/// status, the user's text field would lose focus and there would be nothing left to inject
/// into. That is the load-bearing detail of the whole app.
@MainActor
final class HUDPanel: NSPanel {
    /// Canvas, not pill. Big enough for the widest the capsule is allowed to get.
    private static let canvas = NSSize(width: 460, height: 72)

    /// How far above the bottom of the screen the capsule sits. Clear of the Dock.
    private static let bottomInset: CGFloat = 72

    /// Must outlast the SwiftUI exit animation, or the window vanishes mid-fade.
    private static let exitDuration: Duration = .milliseconds(320)

    private var dismissTask: Task<Void, Never>?

    init(controller: DictationController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.canvas),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true

        isOpaque = false
        backgroundColor = .clear
        // The capsule draws its own shadow in SwiftUI; a window shadow would trace the
        // transparent canvas rectangle instead of the pill.
        hasShadow = false

        contentView = NSHostingView(rootView: HUDView(controller: controller))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Follows the screen the user is actually working on, not whichever screen the panel
    /// was last shown on — otherwise dictating on a second display puts the HUD elsewhere.
    func reposition() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else {
            Log.app.error("no screen available to position HUD")
            return
        }
        let visible = screen.visibleFrame
        setFrameOrigin(
            NSPoint(
                x: visible.midX - Self.canvas.width / 2,
                y: visible.minY + Self.bottomInset
            )
        )
    }

    func present() {
        dismissTask?.cancel()
        dismissTask = nil

        guard !isVisible else { return }
        reposition()
        // No alpha animation here — the capsule animates itself in SwiftUI, and animating
        // both produces a double fade.
        alphaValue = 1
        orderFrontRegardless()
    }

    func dismiss() {
        guard isVisible else { return }
        dismissTask?.cancel()
        // Hold the window open long enough for the capsule's exit spring to finish, then
        // order out. `MainActor.assumeIsolated` in a completion handler would assert rather
        // than check, and has taken the app down before — this stays on the main actor by
        // construction instead.
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.exitDuration)
            guard !Task.isCancelled else { return }
            self?.orderOut(nil)
        }
    }
}
