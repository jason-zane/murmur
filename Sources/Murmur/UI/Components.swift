import SwiftUI
import AppKit

// MARK: - Containers

/// A raised surface. The only container in the app — lists, forms and panels all sit on one.
struct Card<Content: View>: View {
    var padding: CGFloat = DS.Space.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline)
            }
            .elevation(DS.Shadow.soft)
    }
}

/// A small caps-ish heading above a group of controls.
///
/// Not tracked or uppercased — that reads as retro instrumentation. Weight and colour carry
/// the hierarchy instead, which is how macOS itself labels form sections.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.Font.label)
            .foregroundStyle(DS.Color.textSecondary)
    }
}

/// Explanatory text under a control. Always secondary, always wraps.
struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.Font.caption)
            .foregroundStyle(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Controls

/// A segmented control with a selection that slides between segments.
///
/// `matchedGeometryEffect` moves one pill rather than cross-fading two backgrounds, which is
/// what makes the movement read as a single object instead of a flicker.
struct Segmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = selection == option.value
                Button {
                    withAnimation(DS.Motion.quick) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(DS.Font.bodyEmphasis)
                        .foregroundStyle(isSelected ? DS.Color.text : DS.Color.textSecondary)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.sm - 1)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: DS.Radius.sm)
                                    .fill(DS.Color.surface)
                                    .elevation(DS.Shadow.soft)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(DS.Color.selection, in: .rect(cornerRadius: DS.Radius.md))
    }
}

/// Text button. `.prominent` fills with the accent; `.plain` is a quiet bordered control.
struct ActionButton: View {
    enum Emphasis { case prominent, normal, quiet }

    let title: String
    var systemImage: String?
    var emphasis: Emphasis = .normal
    var tint: Color = DS.Color.accent
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs + 2) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(DS.Font.bodyEmphasis)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm - 1)
            .background(background, in: .rect(cornerRadius: DS.Radius.sm))
            .overlay {
                if emphasis == .normal {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline)
                }
            }
            .contentShape(.rect)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.smooth, value: isHovering)
    }

    private var foreground: Color {
        switch emphasis {
        case .prominent: .white
        case .normal: DS.Color.text
        case .quiet: isHovering ? DS.Color.text : DS.Color.textSecondary
        }
    }

    private var background: Color {
        switch emphasis {
        case .prominent: isHovering ? tint.opacity(0.88) : tint
        case .normal: isHovering ? DS.Color.hover : .clear
        case .quiet: isHovering ? DS.Color.hover : .clear
        }
    }
}

/// The record control. Red only while armed — the one place the app uses that colour.
struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                ZStack {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 2).frame(width: 9, height: 9)
                    } else {
                        Circle().frame(width: 10, height: 10)
                    }
                }
                .foregroundStyle(isRecording ? .white : DS.Color.record)

                Text(isRecording ? "Stop" : "Record")
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(isRecording ? .white : DS.Color.text)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm + 1)
            .background {
                Capsule().fill(isRecording ? DS.Color.record : DS.Color.surface)
            }
            .overlay {
                Capsule().strokeBorder(
                    isRecording ? .clear : DS.Color.separator,
                    lineWidth: DS.Stroke.hairline
                )
            }
            .elevation(isHovering ? DS.Shadow.lifted : DS.Shadow.soft)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.quick, value: isRecording)
        .animation(DS.Motion.smooth, value: isHovering)
    }
}

/// A small state indicator. Replaces the panel lamp — same job, no bulb.
struct StatusDot: View {
    var color: Color = DS.Color.success
    var isLit: Bool = true
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(isLit ? color : DS.Color.textTertiary.opacity(0.35))
            .frame(width: size, height: size)
            .overlay {
                if isLit {
                    Circle().fill(color).blur(radius: size * 0.5).opacity(0.5)
                }
            }
            .animation(DS.Motion.smooth, value: isLit)
    }
}

/// A pulsing dot for the recording state, used in the HUD and the window header.
struct PulsingDot: View {
    var color: Color = DS.Color.record
    var size: CGFloat = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.55 + 0.45 * sin(t * 3.2)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .stroke(color, lineWidth: 1.5)
                        .scaleEffect(1 + 0.7 * pulse)
                        .opacity(0.55 * (1 - pulse))
                }
        }
    }
}

// MARK: - Level

/// Live input level as a row of thin bars.
///
/// Replaces a needle VU meter. The needle's physics were the point of that design; here the
/// bars just track the signal, with a per-bar phase offset so the row reads as a waveform
/// rather than a graphic equaliser rising and falling in lockstep.
struct LevelMeter: View {
    let level: Float
    let isActive: Bool
    var barCount: Int = 5
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var tint: Color = DS.Color.accent

    /// Golden-ratio phases: evenly spread, never repeating in a visible cycle.
    private var phases: [Double] {
        (0..<barCount).map { (Double($0) * 0.618).truncatingRemainder(dividingBy: 1) }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        Capsule()
                            .fill(tint)
                            .frame(width: barWidth, height: height(index, t, geo.size.height))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func height(_ index: Int, _ time: TimeInterval, _ maxHeight: CGFloat) -> CGFloat {
        let floor = barWidth
        guard isActive else { return floor }
        let wave = sin(time * 7.0 + phases[index] * .pi * 2)
        let amplitude = CGFloat(max(0.05, min(1, level)))
        let scaled = amplitude * (0.5 + 0.5 * CGFloat(wave))
        return floor + max(0, scaled) * (maxHeight - floor)
    }
}

// MARK: - Fields and states

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Color.textTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .focused($isFocused)

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(DS.Color.selection.opacity(0.6), in: .rect(cornerRadius: DS.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(isFocused ? DS.Color.accent : .clear, lineWidth: 1.5)
        }
        .animation(DS.Motion.smooth, value: isFocused)
    }
}

/// A labelled text field, used in the dictionary editor.
struct LabelledField: View {
    let label: String
    @Binding var text: String
    let prompt: String

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
            SectionLabel(text: label)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .focused($isFocused)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm + 1)
                .background(DS.Color.selection.opacity(0.6), in: .rect(cornerRadius: DS.Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(isFocused ? DS.Color.accent : DS.Color.separator,
                                      lineWidth: isFocused ? 1.5 : DS.Stroke.hairline)
                }
                .animation(DS.Motion.smooth, value: isFocused)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let label: String
    let detail: String

    var body: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            VStack(spacing: DS.Space.xs) {
                Text(label)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textSecondary)
                Text(detail)
                    .font(DS.Font.callout)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.xxl)
    }
}

/// A small pill of metadata — engine name, timing, entry kind.
struct Chip: View {
    let text: String
    var tint: Color = DS.Color.textSecondary
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(DS.Font.label)
            .foregroundStyle(filled ? tint : DS.Color.textSecondary)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, 3)
            .background {
                if filled {
                    Capsule().fill(tint.opacity(0.14))
                } else {
                    Capsule().strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline)
                }
            }
    }
}

/// A chip that toggles on and off, for choosing several options at once.
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs + 2) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textTertiary)
                Text(title)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(isSelected ? DS.Color.text : DS.Color.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? DS.Color.accentSoft : (isHovering ? DS.Color.hover : .clear),
                in: .rect(cornerRadius: DS.Radius.sm)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .strokeBorder(
                        isSelected ? DS.Color.accent.opacity(0.5) : DS.Color.separator,
                        lineWidth: DS.Stroke.hairline
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.smooth, value: isSelected)
        .animation(DS.Motion.smooth, value: isHovering)
    }
}

/// A mapped trigger, with a remove control that appears on hover.
struct RemovableChip: View {
    let title: String
    var canRemove: Bool = true
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text(title)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.text)
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(DS.Space.xs)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!canRemove)
            .opacity(canRemove ? (isHovering ? 1 : 0.45) : 0.2)
            .help(canRemove ? "Remove" : "At least one trigger is required")
        }
        .padding(.leading, DS.Space.md)
        .padding(.trailing, DS.Space.xs + 2)
        .padding(.vertical, DS.Space.xs + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.accentSoft, in: .rect(cornerRadius: DS.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.accent.opacity(0.45), lineWidth: DS.Stroke.hairline)
        }
        .onHover { isHovering = $0 }
        .animation(DS.Motion.smooth, value: isHovering)
    }
}
