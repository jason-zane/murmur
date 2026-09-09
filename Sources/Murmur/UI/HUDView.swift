import SwiftUI

/// The floating capsule shown while dictating.
///
/// Design intent: as small as it can be and still tell you three things — that it heard you
/// start, that it is hearing you *now*, and what it got. Everything else is noise on top of
/// whatever you were actually looking at.
///
/// So it is a capsule roughly the size of a Touch Bar chip: a record dot, a live level
/// meter, and text only once there is text. It grows to fit the transcript and shrinks back,
/// which is why the panel behind it is a fixed transparent canvas and the pill sizes itself
/// inside — resizing the `NSPanel` on every partial result would judder.
struct HUDView: View {
    @Bindable var controller: DictationController

    /// The pill never gets wider than this, however long the utterance.
    private let maxTextWidth: CGFloat = 260

    var body: some View {
        HStack(spacing: DS.Space.sm + 2) {
            indicator

            LevelMeter(
                level: controller.level,
                isActive: controller.state == .listening,
                barCount: 5,
                barWidth: 2.5,
                spacing: 3,
                tint: isError ? DS.Color.record : DS.Color.accent
            )
            .frame(width: 32, height: 18)

            if let text = visibleText {
                Text(text)
                    .font(DS.Font.hud)
                    .foregroundStyle(isError ? DS.Color.record : DS.Color.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: maxTextWidth, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(.horizontal, DS.Space.lg - 2)
        .padding(.vertical, DS.Space.md - 1)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: DS.Stroke.hairline)
        }
        .elevation(DS.Shadow.floating)
        .scaleEffect(isPresented ? 1 : 0.9, anchor: .bottom)
        .opacity(isPresented ? 1 : 0)
        .offset(y: isPresented ? 0 : 10)
        .animation(DS.Motion.hud, value: isPresented)
        .animation(DS.Motion.spring, value: visibleText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A pulsing dot while capturing; a steady one once we've stopped listening and are
    /// waiting on the engine. The change is the only signal that the key release registered.
    @ViewBuilder
    private var indicator: some View {
        if controller.state == .listening {
            PulsingDot(color: DS.Color.record, size: 7)
        } else {
            StatusDot(
                color: isError ? DS.Color.record : DS.Color.accent,
                isLit: true,
                size: 7
            )
        }
    }

    private var isPresented: Bool { controller.state.isActive || isError }

    private var isError: Bool {
        if case .error = controller.state { return true }
        return false
    }

    /// Nil while simply listening in silence — that state is carried by the meter, and an
    /// "Listening…" label would only make the pill bigger for no information.
    private var visibleText: String? {
        switch controller.state {
        case .error(let message): message
        case .listening: controller.transcript.isEmpty ? nil : controller.transcript
        case .finishing: controller.transcript.isEmpty ? "Transcribing…" : controller.transcript
        case .starting, .idle: nil
        }
    }
}
