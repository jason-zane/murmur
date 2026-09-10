import AppKit
import SwiftUI

/// One line of proof that both sides of the call are being heard. The failure it prevents
/// is discovering after forty minutes that the call was never captured — so when something
/// is wrong the line says so, and when nothing is, it's a meter and nothing else.
struct CaptureStatus: View {
    let controller: MeetingController

    private enum Situation { case idle, notCaptured, callSilent, settling, fine }

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            RecordingDot(size: DS.Layout.statusDot)
            LevelMeter(
                level: max(controller.youLevel, controller.callLevel),
                isActive: controller.isRecording,
                tint: situation == .notCaptured ? DS.Color.warning : DS.Color.accent
            )
            .frame(width: DS.Layout.compactMeterWidth, height: DS.Layout.meterHeight)
            if let text {
                Text(text)
                    .font(DS.Font.caption)
                    .foregroundStyle(situation == .notCaptured ? DS.Color.warning : DS.Color.textTertiary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: DS.Space.zero)
            if situation == .notCaptured {
                ActionButton(title: "Fix", emphasis: .quiet) { fix() }
            }
        }
        .animation(DS.Motion.quick, value: text)
    }

    /// Reads `elapsed`, which ticks every second, so the timed states advance without a
    /// timer of their own.
    private var situation: Situation {
        guard controller.isRecording else { return .idle }
        if !controller.systemAudioActive { return .notCaptured }
        if let since = controller.callSilentSince,
           Date().timeIntervalSince(since) >= Self.seconds(DS.Timing.callSilence) {
            return .callSilent
        }
        return controller.elapsed < Self.seconds(DS.Timing.captureHint) ? .settling : .fine
    }

    private var text: String? {
        switch situation {
        case .notCaptured: "Call audio isn't being captured"
        case .callSilent: "No call audio yet"
        case .settling: "Hearing you and the call"
        case .idle, .fine: nil
        }
    }

    /// Ask for the Audio Recording grant; if it's still refused, open the pane it lives in.
    private func fix() {
        Task {
            if await SystemAudioCapture.requestPermission() { return }
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
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
    var size: CGFloat = DS.Layout.recordDot

    var body: some View {
        Circle()
            .fill(DS.Color.record)
            .frame(width: size, height: size)
            .background {
                Circle().fill(DS.Color.recordSoft).frame(width: size * DS.Layout.recordHalo, height: size * DS.Layout.recordHalo)
            }
    }
}

/// The line under a note: what just happened, who wrote it, whether it reached the cloud.
/// Says nothing at all when there is nothing to say.
struct NoteStatusLine: View {
    var transient: String?
    var source: String?
    var syncIssue: String?

    var body: some View {
        if transient != nil || source != nil || syncIssue != nil {
            HStack(spacing: DS.Space.md) {
                if let transient {
                    Text(transient).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                        .transition(.opacity)
                }
                if let syncIssue {
                    Label("This note hasn't synced yet", systemImage: "exclamationmark.circle")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.warning)
                        .help(syncIssue)
                }
                Spacer(minLength: DS.Space.zero)
                if let source {
                    Text(source).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.md)
            .animation(DS.Motion.quick, value: transient)
        }
    }
}
