import AppKit
import MurmurDictionary
import SwiftUI

// The Dictation half of the sidebar and its detail.

/// Every dictation, newest first, with search. One caption for the totals.
struct DictationSidebar: View {
    @Binding var selection: UUID?
    @State private var store = RunStore.shared
    @State private var query = ""
    @State private var isConfirmingClear = false

    private var runs: [DictationRun] {
        let all = store.runs.reversed().map { $0 }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.text.localizedStandardContains(trimmed) }
    }

    private var caption: String {
        let words = store.runs.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count }
        return "\(store.runs.count) dictations · \(words.formatted()) words"
    }

    var body: some View {
        VStack(spacing: DS.Space.zero) {
            VStack(spacing: DS.Space.md) {
                SearchField(text: $query, placeholder: "Search dictations")
                if !store.runs.isEmpty {
                    HStack(spacing: DS.Space.sm) {
                        Text(caption).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                        Spacer(minLength: DS.Space.zero)
                        ActionButton(title: "Clear all", emphasis: .quiet) { isConfirmingClear = true }
                    }
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm)

            if runs.isEmpty {
                EmptyState(
                    icon: store.runs.isEmpty ? "waveform" : "magnifyingglass",
                    label: store.runs.isEmpty ? "No dictations yet" : "No matches",
                    detail: store.runs.isEmpty
                        ? "Hold \(Settings.shared.triggerSummary) in any text field and speak."
                        : "Try a different search."
                )
            } else {
                List(selection: $selection) {
                    ForEach(runs) { run in
                        DictationRow(run: run)
                            .tag(run.id)
                            .listRowInsets(EdgeInsets(top: DS.Space.sm, leading: DS.Space.md,
                                                      bottom: DS.Space.sm, trailing: DS.Space.md))
                            .contextMenu {
                                Button("Copy") { copy(run.text) }
                                Button("Delete") { withAnimation(DS.Motion.spring) { RunLog.delete(run) } }
                            }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .confirmationDialog(
            "Delete all \(store.runs.count) dictations?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { RunLog.clear(); selection = nil }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct DictationRow: View {
    let run: DictationRun

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                Readout(run.date.formatted(.dateTime.hour().minute()), color: DS.Color.textTertiary)
                Text(run.date, format: .dateTime.day().month(.abbreviated))
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                Spacer(minLength: DS.Space.zero)
                // Benchmark facts, not history.
                if Settings.shared.developerMode { Chip(text: run.engine) }
            }
            Text(run.text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
                .lineLimit(3)
            if let corrections = run.corrections, !corrections.isEmpty {
                CorrectionBadges(corrections: corrections)
            }
        }
        .padding(.vertical, DS.Space.xs)
    }
}

/// One dictation in full, with copy and delete.
struct DictationDetail: View {
    let run: DictationRun
    let onDelete: () -> Void
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                HStack(spacing: DS.Space.md) {
                    Readout(run.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                    if Settings.shared.developerMode {
                        Chip(text: run.engine)
                        Readout(String(format: "%.2fs", run.processSeconds), color: DS.Color.textTertiary)
                    }
                    Spacer(minLength: DS.Space.zero)
                    ActionButton(title: copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", emphasis: .normal) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(run.text, forType: .string)
                        copied = true
                    }
                    ActionButton(title: "Delete", systemImage: "trash", emphasis: .quiet, action: onDelete)
                }
                Text(run.text)
                    .font(DS.Font.documentBody)
                    .foregroundStyle(DS.Color.text)
                    .lineSpacing(DS.Layout.proseLineSpacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let corrections = run.corrections, !corrections.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("Dictionary corrections").font(DS.Font.headline).foregroundStyle(DS.Color.textSecondary)
                        CorrectionBadges(corrections: corrections)
                    }
                }
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: DS.Layout.documentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: DS.Timing.feedback); copied = false } catch {}
        }
    }
}

/// The Dictation detail when nothing is selected: how to dictate, what is happening now.
struct DictationHome: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if let message = controller.lastError {
                    InlineNotice(text: message, tone: .warning) {
                        ActionButton(title: "Reset", emphasis: .quiet) { controller.forceReset() }
                    }
                }
                if settings.compareMode {
                    InlineNotice(icon: "rectangle.split.2x1", text: "Compare mode is on. Dictations go to Engine comparison and are not typed into other apps.") {
                        ActionButton(title: "Use dictation", emphasis: .normal) { settings.compareMode = false }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        HStack(spacing: DS.Space.md) {
                            Text("Hold " + settings.triggerSummary + " in any text field")
                                .font(DS.Font.headline).foregroundStyle(DS.Color.text)
                            Spacer(minLength: DS.Space.zero)
                            if controller.state.isActive {
                                LevelMeter(level: controller.level, isActive: controller.state == .listening)
                                    .frame(width: DS.Layout.compactMeterWidth, height: DS.Layout.meterHeight)
                                ActionButton(title: controller.state == .listening ? "Stop" : "Cancel",
                                             systemImage: controller.state == .listening ? "stop.fill" : "xmark",
                                             emphasis: .prominent,
                                             tint: controller.state == .listening ? DS.Color.record : DS.Color.accent) { controller.toggleRecording() }
                            }
                        }
                        Text("Release to insert. Everything you dictate is kept here, on this Mac.")
                            .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                        Hint("Change the key, the engine and cleanup in Settings ▸ Dictation. Names and jargon it keeps getting wrong go in Settings ▸ Dictionary.")
                    }
                }
            }
            .padding(DS.Space.page)
            .frame(maxWidth: DS.Layout.homeWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct CorrectionBadges: View {
    let corrections: [AppliedCorrection]

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(DS.Font.glyph)
                .foregroundStyle(DS.Color.success)

            ForEach(corrections, id: \.self) { correction in
                HStack(spacing: DS.Space.xs) {
                    Text(correction.from)
                        .strikethrough()
                        .foregroundStyle(DS.Color.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(DS.Font.glyphMicro)
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
                .padding(.vertical, DS.Space.tight)
                .background(DS.Color.successSoft, in: .capsule)
            }
            Spacer()
        }
    }
}
