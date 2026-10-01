import AppKit
import SwiftUI

/// A timed, non-recording offer at the chosen dictation-bar edge.
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
    private let detector: MeetingDetector

    private var offerScreen: NSScreen?
    private var dismissTask: Task<Void, Never>?

    init(detector: MeetingDetector, onStart: @escaping (MeetingCandidate) -> Void) {
        self.detector = detector
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.canvas),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        // No window shadow either: it would trace the canvas, not the capsule.
        hasShadow = false

        let hosting = TransparentHostingView(rootView: OfferView(
            detector: detector,
            onStart: { [weak self] _ in
                guard let candidate = detector.acceptOffer() else { self?.dismiss(); return }
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
        offerScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        reposition()
        alphaValue = 1
        orderFrontRegardless()
        dismissTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                self.detector.expireOffer()
                guard self.detector.offered != nil else { self.dismiss(); return }
                self.reposition()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        orderOut(nil)
    }

    private func reposition() {
        guard let screen = offerScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        setFrame(Settings.shared.dictationBarPosition.frame(in: screen.visibleFrame, canvas: Self.canvas), display: true)
    }
}

struct OfferView: View {
    let detector: MeetingDetector
    let onStart: (MeetingCandidate) -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            if let candidate = detector.offered {
                HStack(spacing: DS.Space.md) {
                    mark
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Record meeting?")
                            .font(DS.Font.bodyEmphasis)
                            .foregroundStyle(DS.Color.text)
                        Text(headline(candidate))
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: DS.Space.sm)
                    ActionButton(title: "Not now", emphasis: .quiet, action: onDecline)
                    ActionButton(title: "Record", emphasis: .prominent) { onStart(candidate) }
                }
                TimelineView(.periodic(from: .now, by: DS.Offer.refreshInterval)) { context in
                    let remaining = max(0, (detector.offerDeadline ?? context.date).timeIntervalSince(context.date))
                    GeometryReader { geometry in
                        Capsule().fill(DS.Color.accentSoft)
                            .overlay(alignment: .leading) {
                                Capsule().fill(DS.Color.accent)
                                    .frame(width: geometry.size.width * min(1, remaining / MeetingDetector.offerDuration))
                            }
                    }
                    .frame(height: DS.Offer.progressHeight)
                    .accessibilityLabel("Offer closes without recording")
                    .accessibilityValue("\(Int(remaining.rounded(.up))) seconds remaining")
                }
            }
        }
        .padding(DS.Space.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Space.lg))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Space.lg)
                .strokeBorder(.primary.opacity(DS.Offer.borderOpacity), lineWidth: DS.Stroke.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Space.lg))
        .padding(DS.HUD.edgeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Settings.shared.dictationBarPosition.alignment)
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
