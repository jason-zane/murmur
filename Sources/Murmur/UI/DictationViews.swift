import AppKit
import MurmurDictionary
import SwiftUI

/// Dictation history as one plain list: when, what was said, Copy. Nothing to open.
struct DictationList: View {
    @Bindable var controller: DictationController
    @State private var store = RunStore.shared
    @State private var settings = Settings.shared
    @State private var query = ""
    @State private var isConfirmingClear = false
    @State private var copiedID: UUID?

    private var runs: [DictationRun] {
        let all = store.runs.reversed().map { $0 }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.text.localizedStandardContains(trimmed) }
    }

    private struct DayGroup { let date: Date; let title: String; let runs: [DictationRun] }
    private var groups: [DayGroup] {
        let calendar = Calendar.current
        return Dictionary(grouping: runs, by: { calendar.startOfDay(for: $0.date) })
            .sorted { $0.key > $1.key }.map { date, runs in
                let title = calendar.isDateInToday(date) ? "Today" : calendar.isDateInYesterday(date) ? "Yesterday"
                    : date.formatted(.dateTime.weekday(.wide).day().month(.wide))
                return DayGroup(date: date, title: title, runs: runs)
            }
    }

    private var caption: String {
        let words = store.runs.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count }
        return "\(store.runs.count) dictations · \(words.formatted()) words"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                    Text("Dictation").font(DS.Font.title)
                    if !store.runs.isEmpty {
                        Text(caption).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).monospacedDigit()
                    }
                    Spacer(minLength: DS.Space.sm)
                    if !store.runs.isEmpty {
                        ActionButton(title: "Clear all", emphasis: .quiet) { isConfirmingClear = true }
                    }
                }
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
                if !store.runs.isEmpty {
                    SearchField(text: $query, placeholder: "Search dictations")
                        .frame(maxWidth: .infinity)
                }
                if runs.isEmpty {
                    EmptyState(
                        icon: store.runs.isEmpty ? "waveform" : "magnifyingglass",
                        label: store.runs.isEmpty ? "No dictations yet" : "No matches",
                        detail: store.runs.isEmpty
                            ? "Hold \(settings.triggerSummary) in any text field and speak. Everything you dictate is kept here, on this Mac."
                            : "Try a different search."
                    )
                    .frame(maxHeight: DS.Layout.editorHeight)
                } else {
                    ForEach(groups, id: \.date) { group in
                        VStack(alignment: .leading, spacing: DS.Space.zero) {
                            Text(group.title).font(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                                .padding(.bottom, DS.Space.sm)
                            ForEach(group.runs) { run in
                                DictationRow(run: run, copied: copiedID == run.id) {
                                    copy(run.text)
                                    copiedID = run.id
                                } onDelete: {
                                    withAnimation(DS.Motion.spring) { RunLog.delete(run) }
                                }
                                Divider()
                            }
                        }
                    }
                    Hint("Hold \(settings.triggerSummary) in any text field. Everything you dictate is kept here, on this Mac.")
                }
            }
            .padding(DS.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .confirmationDialog(
            "Delete all \(store.runs.count) dictations?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete all", role: .destructive) { RunLog.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .task(id: copiedID) {
            guard copiedID != nil else { return }
            do { try await Task.sleep(for: DS.Timing.feedback); copiedID = nil } catch {}
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct DictationRow: View {
    let run: DictationRun
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Readout(run.date.formatted(.dateTime.hour().minute()), color: DS.Color.textTertiary)
                .frame(width: DS.Layout.transcriptTime, alignment: .leading)
                .padding(.top, DS.Space.xxs)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(run.text)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.text)
                    .textSelection(.enabled)
                    .lineLimit(!expanded && run.text.count > DS.Layout.dictationExpansionThreshold ? DS.Layout.dictationPreviewLines : nil)
                    .fixedSize(horizontal: false, vertical: true)
                if run.text.count > DS.Layout.dictationExpansionThreshold {
                    ActionButton(title: expanded ? "Show less" : "Show full text", emphasis: .quiet) {
                        expanded.toggle()
                    }
                }
                if let corrections = run.corrections, !corrections.isEmpty {
                    CorrectionBadges(corrections: corrections)
                }
                if Settings.shared.developerMode {
                    HStack(spacing: DS.Space.sm) {
                        Chip(text: run.engine)
                        Readout(String(format: "%.2fs", run.processSeconds), color: DS.Color.textTertiary)
                    }
                }
            }
            Spacer(minLength: DS.Space.sm)
            HStack(spacing: DS.Space.xs) {
                ActionButton(title: copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", emphasis: .quiet, action: onCopy)
                Button(action: onDelete) {
                    Image(systemName: "trash").font(DS.Font.smallSymbol).foregroundStyle(DS.Color.textTertiary)
                        .frame(width: DS.Layout.symbolColumn, height: DS.Layout.symbolColumn)
                }
                .buttonStyle(.plain)
                .help("Delete this dictation")
                .accessibilityLabel("Delete this dictation")
            }
        }
        .padding(.vertical, DS.Space.md)
        .contentShape(.rect)
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Delete", action: onDelete)
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
