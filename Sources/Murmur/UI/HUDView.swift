import SwiftUI

/// The floating capsule shown while dictating.
///
/// Design intent: as small as it can be and still tell you three things — that it heard you
/// start, that it is hearing you *now*, and optionally what it got. Everything else is noise on top of
/// whatever you were actually looking at.
///
/// So it is a capsule roughly the size of a Touch Bar chip: a record dot, a live level
/// meter, and text only once there is text. It grows to fit the transcript and shrinks back,
/// which is why the panel behind it is a fixed transparent canvas and the pill sizes itself
/// inside — resizing the `NSPanel` on every partial result would judder.
struct HUDView: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    var isPreview = false
    var onDismissPreview: () -> Void = {}

    /// The pill never gets wider than this, however long the utterance.
    private let maxTextWidth = DS.HUD.textWidth

    var body: some View {
        HStack(spacing: DS.HUD.spacing) {
            indicator

            LevelMeter(
                level: controller.level,
                isActive: controller.state == .listening,
                barCount: DS.HUD.barCount,
                barWidth: DS.HUD.barWidth,
                spacing: DS.HUD.barSpacing,
                tint: isError ? DS.Color.warning : DS.Color.accent
            )
            .frame(width: DS.HUD.meterWidth, height: DS.HUD.meterHeight)

            if let text = visibleText {
                Text(text)
                    .font(DS.Font.hud)
                    .foregroundStyle(isError ? DS.Color.warning : DS.Color.text)
                    .lineLimit(DS.HUD.lineLimit)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxTextWidth, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.opacity.combined(with: .scale(scale: DS.HUD.textScale, anchor: .leading)))
            }
            if controller.state.isActive || isPreview {
                Button {
                    if isPreview { onDismissPreview() }
                    else { controller.stopButtonRecording() }
                } label: {
                    Image(systemName: !isPreview && controller.state == .listening ? "stop.fill" : "xmark")
                        .font(DS.Font.callout)
                        .frame(width: DS.HUD.controlSize, height: DS.HUD.controlSize)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(controlLabel)
                .help(controlLabel)
            }
        }
        .padding(.horizontal, DS.HUD.horizontalPadding)
        .padding(.vertical, DS.HUD.verticalPadding)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule().strokeBorder(.primary.opacity(DS.HUD.borderOpacity), lineWidth: DS.Stroke.hairline)
        }
        .clipShape(.capsule)
        .scaleEffect(isPresented ? DS.HUD.visibleScale : DS.HUD.enterScale,
                     anchor: settings.dictationBarPosition.anchor)
        .opacity(isPresented ? DS.HUD.visibleOpacity : DS.HUD.hiddenOpacity)
        .offset(isPresented ? .zero : settings.dictationBarPosition.hiddenOffset)
        .animation(DS.Motion.hud, value: isPresented)
        .animation(DS.Motion.spring, value: visibleText)
        .padding(DS.HUD.edgeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: settings.dictationBarPosition.alignment)
    }

    /// A pulsing dot while capturing; a steady one once we've stopped listening and are
    /// waiting on the engine. The change is the only signal that the key release registered.
    @ViewBuilder
    private var indicator: some View {
        if controller.state == .listening {
            PulsingDot(color: DS.Color.record, size: DS.HUD.dotSize)
        } else {
            StatusDot(
                color: isError ? DS.Color.warning : DS.Color.accent,
                isLit: true,
                size: DS.HUD.dotSize
            )
        }
    }

    private var isPresented: Bool { isPreview || controller.state.isActive || isError }

    private var controlLabel: String {
        if isPreview { return "Dismiss bar preview" }
        return controller.state == .listening ? "Finish dictation" : "Cancel dictation"
    }

    private var isError: Bool {
        if case .error = controller.state { return true }
        return false
    }

    /// Nil while simply listening in silence — that state is carried by the meter, and an
    /// "Listening…" label would only make the pill bigger for no information.
    private var visibleText: String? {
        if isPreview { return settings.showLiveDictationText ? "Your words appear here" : nil }
        switch controller.state {
        case .error(let message): return message
        case .listening:
            return settings.showLiveDictationText && !controller.transcript.isEmpty ? controller.transcript : nil
        case .finishing:
            return settings.showLiveDictationText && !controller.transcript.isEmpty ? controller.transcript : "Transcribing…"
        case .starting: return "Preparing microphone…"
        case .idle: return nil
        }
    }
}
