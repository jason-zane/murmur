import AppKit
import SwiftUI

/// The window the HUD capsule floats in.
///
/// The panel is a **fixed, transparent canvas** — deliberately wider and taller than the
/// pill it contains. The pill sizes itself to its content and anchors to an edge, so it can grow
/// with the transcript and shrink again without the window ever resizing. Resizing an
/// `NSPanel` on every partial ASR result judders badly and fights the SwiftUI animation.
///
/// `canBecomeKey` is false and this is a `.nonactivatingPanel`: if the overlay ever took key
/// status, the user's text field would lose focus and there would be nothing left to inject
/// into. That is the load-bearing detail of the whole app.
@MainActor
final class HUDPanel: NSPanel {
    /// Canvas, not pill. Big enough for the widest the capsule is allowed to get.
    private static let canvas = DS.HUD.canvas

    /// Must outlast the SwiftUI exit animation, or the window vanishes mid-fade.
    private static let exitDuration = DS.HUD.exitDuration

    private var dismissTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var isPreviewing = false
    private var currentScreen: NSScreen?
    private let controller: DictationController

    init(controller: DictationController) {
        self.controller = controller
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
        ignoresMouseEvents = false

        isOpaque = false
        backgroundColor = .clear
        // No window or SwiftUI shadow: only the capsule is visible, with no rectangular
        // backing around the transparent canvas.
        hasShadow = false

        let hosting = TransparentHUDHostingView(rootView: HUDView(controller: controller))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hosting
        observePosition()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Follows the screen the user is actually working on, not whichever screen the panel
    /// was last shown on — otherwise dictating on a second display puts the HUD elsewhere.
    func reposition(followPointer: Bool = false) {
        let previousScreen = followPointer ? nil : currentScreen.flatMap { previous in
            NSScreen.screens.first { $0 == previous }
        }
        guard let screen = previousScreen
                ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else {
            Log.app.error("no screen available to position HUD")
            return
        }
        currentScreen = screen
        setFrame(Settings.shared.dictationBarPosition.frame(in: screen.visibleFrame), display: true)
    }

    func present() {
        dismissTask?.cancel()
        dismissTask = nil
        previewTask?.cancel()
        previewTask = nil
        if isPreviewing {
            setPreview(false)
            reposition(followPointer: true)
        }

        guard !isVisible else { return }
        reposition(followPointer: true)
        // No alpha animation here — the capsule animates itself in SwiftUI, and animating
        // both produces a double fade.
        alphaValue = 1
        orderFrontRegardless()
    }

    func dismiss() {
        previewTask?.cancel()
        previewTask = nil
        if isPreviewing { setPreview(false) }
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

    /// A real overlay preview, with no microphone, engine or text insertion involved.
    func preview() {
        guard !controller.state.isActive else { return }
        dismissTask?.cancel()
        dismissTask = nil
        previewTask?.cancel()
        setPreview(true)
        reposition(followPointer: true)
        alphaValue = DS.HUD.visibleOpacity
        orderFrontRegardless()
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: DS.HUD.previewDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func setPreview(_ value: Bool) {
        isPreviewing = value
        (contentView as? TransparentHUDHostingView)?.rootView = HUDView(
            controller: controller, isPreview: value,
            onDismissPreview: { [weak self] in self?.dismiss() }
        )
    }

    private func observePosition() {
        withObservationTracking {
            _ = Settings.shared.dictationBarPosition
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.isVisible { self.reposition() }
                self.observePosition()
            }
        }
    }
}

private final class TransparentHUDHostingView: NSHostingView<HUDView> {
    override var isOpaque: Bool { false }
}
