import AppKit
import SwiftUI

/// The "a call started — want notes?" prompt, shown as a pill near the top of the screen.
///
/// Like the HUD, this is a **transparent canvas larger than the pill inside it**, and
/// nothing in it casts a SwiftUI shadow. A shadow under a `.regularMaterial` background
/// cannot be masked to the capsule: the material is drawn by a backdrop layer with no alpha
/// for SwiftUI to shape a shadow from, so the shadow falls back to the layer's *bounds* and
/// paints a soft rectangle around the pill. Depth comes from the material and a hairline
/// border instead — the same trade the HUD makes.
@MainActor
final class OfferStrip: NSPanel {
    private static let canvas = DS.Offer.canvas
    private static let topInset = DS.Offer.topInset
    private static let autoDismiss = DS.Offer.autoDismiss

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
        // No window shadow either: it would trace the canvas, not the capsule.
        hasShadow = false

        let hosting = TransparentHostingView(rootView: OfferView(
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
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hosting
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
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
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
            if let candidate = detector.offered {
                mark
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
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
                ActionButton(title: "Take notes", emphasis: .prominent) { onStart(candidate) }
            }
        }
        .padding(.leading, DS.Space.md)
        .padding(.trailing, DS.Space.sm)
        .padding(.vertical, DS.Space.sm)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule().strokeBorder(.primary.opacity(DS.Offer.borderOpacity), lineWidth: DS.Stroke.hairline)
        }
        // Clip rather than shadow: everything the pill draws stays inside the capsule, so
        // there is no rectangle of anything left over the desktop.
        .clipShape(.capsule)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DS.Space.sm)
    }

    /// A soft accent disc rather than a lamp: at notification size a glowing dot reads as
    /// an artefact, and the waveform says what pressing Start would actually do.
    private var mark: some View {
        ZStack {
            Circle().fill(DS.Color.accentSoft)
            Image(systemName: "waveform")
                .font(DS.Font.symbol)
                .foregroundStyle(DS.Color.accent)
        }
        .frame(width: DS.Offer.markSize, height: DS.Offer.markSize)
    }

    private func headline(_ c: MeetingCandidate) -> String {
        if let event = c.calendarEvent { return "\(c.label) · \(event.title)" }
        return c.callNoun.prefix(1).uppercased() + c.callNoun.dropFirst()
    }
}
