import MurmurDictionary
import AppKit
import SwiftUI

struct MainWindow: View {
    @Bindable var controller: DictationController

    @State private var section: Section = .transcriptions

    enum Section: String, CaseIterable, Identifiable {
        case transcriptions
        case dictionary

        var id: String { rawValue }
        var title: String { self == .transcriptions ? "Transcriptions" : "Dictionary" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(controller: controller)

            Divider()

            VStack(spacing: DS.Space.lg) {
                Segmented(
                    options: Section.allCases.map { ($0, $0.title) },
                    selection: $section
                )
                .frame(width: 280)
                .frame(maxWidth: .infinity, alignment: .center)

                Group {
                    switch section {
                    case .transcriptions: TranscriptionList()
                    case .dictionary: DictionaryPanel()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(DS.Space.xl)
        }
        .background(DS.Color.window)
        .frame(minWidth: 720, minHeight: 540)
    }
}

// MARK: - Header

private struct Header: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?

    private var isRecording: Bool { controller.state.isActive }

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            RecordButton(isRecording: isRecording) {
                controller.toggleRecording()
            }

            // Meter and counter occupy their space permanently so the header doesn't
            // reflow the moment recording starts.
            HStack(spacing: DS.Space.md) {
                LevelMeter(level: controller.level, isActive: isRecording, barCount: 7)
                    .frame(width: 46, height: 20)
                    .opacity(isRecording ? 1 : 0.25)

                Text(counterText)
                    .font(DS.Font.monoLarge)
                    .foregroundStyle(isRecording ? DS.Color.text : DS.Color.textTertiary)
                    .contentTransition(.numericText())
            }

            Spacer()

            HStack(spacing: DS.Space.sm) {
                StatusDot(
                    color: isRecording ? DS.Color.record : DS.Color.success,
                    isLit: true,
                    size: 6
                )
                Text(isRecording
                     ? "Listening"
                     : "Hold \(settings.triggerSummary) to dictate")
                    .font(DS.Font.callout)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .animation(DS.Motion.smooth, value: isRecording)

            // Only offered while something is in flight — it discards the utterance, so it
            // shouldn't be sitting there inviting a click the rest of the time.
            if isRecording {
                ActionButton(title: "Reset", emphasis: .quiet) {
                    controller.forceReset()
                }
                .help("Abandon this recording and return to idle")
            }

            // The app menu already carries Settings, but nothing in the window pointed at
            // it, so it was effectively undiscoverable.
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(DS.Space.sm - 2)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
        .animation(DS.Motion.quick, value: isRecording)
        .onChange(of: controller.state.isActive) { _, active in
            startedAt = active ? Date() : nil
            if !active { elapsed = 0 }
        }
        .task(id: startedAt) {
            guard let startedAt else { return }
            while !Task.isCancelled {
                elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private var counterText: String {
        let total = Int(elapsed)
        return String(format: "%01d:%02d", total / 60, total % 60)
    }
}

// MARK: - Transcriptions

private struct TranscriptionList: View {
    @State private var store = RunStore.shared
    @State private var query = ""
    @State private var isConfirmingClear = false

    private var runs: [DictationRun] {
        let all = store.runs.reversed().map { $0 }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.text.localizedStandardContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                SearchField(text: $query, placeholder: "Search transcriptions")

                Spacer()

                if !store.runs.isEmpty {
                    Text("\(store.runs.count)")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.textTertiary)
                    ActionButton(title: "Clear all", emphasis: .quiet) {
                        isConfirmingClear = true
                    }
                }
            }

            if runs.isEmpty {
                // Deliberately not inside a Card: an empty bordered box the size of the
                // window reads as a broken container rather than an empty list.
                EmptyState(
                    icon: store.runs.isEmpty ? "waveform" : "magnifyingglass",
                    label: store.runs.isEmpty ? "No transcriptions yet" : "No matches",
                    detail: store.runs.isEmpty
                        ? "Hold your push-to-talk key anywhere, or press Record."
                        : "Try a different search."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.sm) {
                        ForEach(runs) { run in
                            TranscriptionRow(run: run) {
                                withAnimation(DS.Motion.spring) { RunLog.delete(run) }
                            }
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .confirmationDialog(
            "Delete all \(store.runs.count) transcriptions?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { RunLog.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

private struct TranscriptionRow: View {
    let run: DictationRun
    let onDelete: () -> Void

    @State private var didCopy = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Chip(text: run.engine)
                Text(String(format: "%.2fs", run.processSeconds))
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.textTertiary)

                Spacer()

                Text(run.date, style: .time)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)

                HStack(spacing: DS.Space.xs) {
                    ActionButton(
                        title: didCopy ? "Copied" : "Copy",
                        emphasis: .quiet
                    ) { copy() }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Color.textTertiary)
                            .padding(DS.Space.xs)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this transcription")
                }
                .opacity(isHovering ? 1 : 0)
            }

            Text(run.text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let corrections = run.corrections, !corrections.isEmpty {
                CorrectionBadges(corrections: corrections)
            }
        }
        .padding(DS.Space.lg - 2)
        .background(
            isHovering ? DS.Color.hover : DS.Color.surface,
            in: .rect(cornerRadius: DS.Radius.lg)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline)
        }
        .onHover { isHovering = $0 }
        .animation(DS.Motion.smooth, value: isHovering)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(run.text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            didCopy = false
        }
    }
}

private struct CorrectionBadges: View {
    let corrections: [AppliedCorrection]

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(DS.Color.success)

            ForEach(corrections, id: \.self) { correction in
                HStack(spacing: DS.Space.xs) {
                    Text(correction.from)
                        .strikethrough()
                        .foregroundStyle(DS.Color.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(correction.to)
                        .foregroundStyle(DS.Color.text)
                    if correction.count > 1 {
                        Text("×\(correction.count)")
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .font(DS.Font.caption)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, 3)
                .background(DS.Color.success.opacity(0.10), in: .capsule)
            }
            Spacer()
        }
    }
}
