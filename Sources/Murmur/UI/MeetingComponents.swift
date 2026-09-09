import SwiftUI

/// Two thin bars, You and Call. The signature of the meeting side of the app: it appears
/// wherever audio is live, because it is the proof-of-life the whole feature depends on. The
/// failure it prevents is discovering after forty minutes that system audio was never heard.
struct StreamMeters: View {
    let you: Float
    let call: Float
    var isActive: Bool = true
    var tint: Color = DS.Color.accent
    /// When the call stream isn't being captured, its bar is drawn hollow and labelled.
    var callUnavailable: Bool = false

    var body: some View {
        VStack(spacing: DS.Space.xs + 2) {
            MeterRow(label: "You", level: you, isActive: isActive, tint: tint, unavailable: false)
            MeterRow(label: "Call", level: call, isActive: isActive, tint: tint, unavailable: callUnavailable)
        }
    }

    private struct MeterRow: View {
        let label: String
        let level: Float
        let isActive: Bool
        let tint: Color
        let unavailable: Bool

        @State private var shown: CGFloat = 0

        var body: some View {
            HStack(spacing: DS.Space.sm) {
                Text(label.uppercased())
                    .font(DS.Font.readout)
                    .tracking(0.6)
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(width: DS.Space.meterLabel, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Color.selection)
                        if unavailable {
                            Capsule()
                                .strokeBorder(DS.Color.warning.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        } else {
                            Capsule()
                                .fill(tint)
                                .frame(width: max(4, geo.size.width * shown))
                        }
                    }
                }
                .frame(height: 4)
            }
            .onChange(of: level, initial: true) { _, new in
                // Fast attack, slow release — the way a real meter behaves.
                let target = CGFloat(isActive ? max(0, min(1, new)) : 0)
                withAnimation(target > shown ? DS.Motion.quick : .easeOut(duration: 0.35)) {
                    shown = target
                }
            }
            .onChange(of: isActive) { _, active in
                if !active { withAnimation(.easeOut(duration: 0.35)) { shown = 0 } }
            }
        }
    }
}

/// A number as a readout: tabular monospace, secondary colour, never wraps.
struct Readout: View {
    let text: String
    var font: Font = DS.Font.readout
    var color: Color = DS.Color.textSecondary

    init(_ text: String, font: Font = DS.Font.readout, color: Color = DS.Color.textSecondary) {
        self.text = text
        self.font = font
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .contentTransition(.numericText())
    }
}

/// A speaker's name as a chip in their colour. Optional confidence, when the name came from
/// a voiceprint match rather than from the user.
struct SpeakerChip: View {
    let name: String
    let color: Color
    var confidence: Double?

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Text(name)
            if let confidence {
                Text("\(Int((confidence * 100).rounded()))%")
                    .opacity(0.7)
            }
        }
        .font(DS.Font.readout)
        .foregroundStyle(.white)
        .padding(.horizontal, DS.Space.sm - 1)
        .padding(.vertical, 1.5)
        .background(color, in: .capsule)
    }
}

/// The solid red dot with a soft halo. The one thing in the app that is red.
struct RecordingDot: View {
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(DS.Color.record)
            .frame(width: size, height: size)
            .background {
                Circle().fill(DS.Color.recordSoft).frame(width: size * 2.2, height: size * 2.2)
            }
    }
}
