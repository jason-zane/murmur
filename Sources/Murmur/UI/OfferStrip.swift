import AppKit
import SwiftUI

/// "Recording? Start · Not now." A slim, non-activating strip that shows its evidence.
///
/// Same window discipline as the dictation HUD — it must not take focus from the call — but
/// unlike the HUD it accepts clicks. A non-activating panel can do both: the buttons work
/// and the app underneath stays frontmost.
@MainActor
final class OfferStrip: NSPanel {
    private static let canvas = NSSize(width: 520, height: 56)
    private static let topInset: CGFloat = 12
    private static let autoDismiss: Duration = .seconds(45)

    private var dismissTask: Task<Void, Never>?

    init(detector: MeetingDetector, onStart: @escaping (MeetingCandidate) -> Void) {
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
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        contentView = NSHostingView(rootView: OfferView(
            detector: detector,
            onStart: { [weak self] candidate in
                self?.dismiss()
                onStart(candidate)
            },
            onDecline: { [weak self] in
                detector.decline()
                self?.dismiss()
            }
        ))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present() {
        dismissTask?.cancel()
        reposition()
        alphaValue = 1
        orderFrontRegardless()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.autoDismiss)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        orderOut(nil)
    }

    private func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: visible.midX - Self.canvas.width / 2,
            y: visible.maxY - Self.canvas.height - Self.topInset
        ))
    }
}

struct OfferView: View {
    let detector: MeetingDetector
    let onStart: (MeetingCandidate) -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            StatusDot(color: DS.Color.accent, isLit: true, size: 8)

            if let candidate = detector.offered {
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline(candidate))
                        .font(DS.Font.bodyEmphasis)
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Readout(candidate.evidence(at: context.date), color: DS.Color.textTertiary)
                    }
                }
                Spacer(minLength: DS.Space.sm)
                ActionButton(title: "Not now", emphasis: .quiet, action: onDecline)
                ActionButton(title: "Start", emphasis: .prominent) { onStart(candidate) }
            }
        }
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.sm)
        .padding(.vertical, DS.Space.sm)
        .background(.regularMaterial, in: .capsule)
        .overlay { Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: DS.Stroke.hairline) }
        .elevation(DS.Shadow.floating)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DS.Space.sm)
    }

    private func headline(_ c: MeetingCandidate) -> String {
        if let event = c.calendarEvent { return "\(c.label) · \(event.title)" }
        return c.callNoun.prefix(1).uppercased() + c.callNoun.dropFirst()
    }
}
