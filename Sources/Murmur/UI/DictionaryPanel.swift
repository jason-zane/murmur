import MurmurDictionary
import AppKit
import SwiftUI

struct DictionaryPanel: View {
    @State private var store = DictionaryStore.shared
    @State private var query = ""
    @State private var editing: DictionaryEntry?
    @State private var isAdding = false

    private var entries: [DictionaryEntry] { store.filtered(by: query) }

    var body: some View {
        VStack(spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                SearchField(text: $query, placeholder: "Search dictionary")

                Spacer()

                if !store.entries.isEmpty {
                    Text("\(store.entries.count)")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.textTertiary)
                }

                ActionButton(title: "Add", systemImage: "plus", emphasis: .prominent) {
                    isAdding = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            if entries.isEmpty {
                EmptyState(
                    icon: store.entries.isEmpty ? "character.book.closed" : "magnifyingglass",
                    label: store.entries.isEmpty ? "Dictionary is empty" : "No matches",
                    detail: store.entries.isEmpty
                        ? "Add names and jargon it keeps getting wrong."
                        : "Try a different search."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.xs + 2) {
                        ForEach(entries) { entry in
                            DictionaryRow(
                                entry: entry,
                                onEdit: { editing = entry },
                                onToggle: {
                                    var updated = entry
                                    updated.isEnabled.toggle()
                                    store.update(updated)
                                },
                                onDelete: { withAnimation(DS.Motion.spring) { store.delete(entry) } }
                            )
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
                .scrollContentBackground(.hidden)
            }

            HStack {
                Spacer()
                ActionButton(title: "Reveal dictionary.txt", emphasis: .quiet) {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                }
                .help(DictionaryStore.fileURL.path)
            }
        }
        .sheet(isPresented: $isAdding) {
            DictionaryEditor(entry: nil) { store.add($0) }
        }
        .sheet(item: $editing) { entry in
            DictionaryEditor(entry: entry) { store.update($0) }
        }
    }
}

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Space.md) {
            StatusDot(color: DS.Color.success, isLit: entry.isEnabled, size: 6)

            Chip(text: entry.kind == .correction ? "Fix" : "Term")
                .frame(width: 46, alignment: .leading)

            HStack(spacing: DS.Space.sm) {
                if entry.kind == .correction {
                    Text(entry.hear)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.Color.textTertiary)
                }

                Text(entry.write)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.text)
            }

            Spacer()

            HStack(spacing: DS.Space.xs) {
                ActionButton(title: "Edit", emphasis: .quiet, action: onEdit)
                ActionButton(title: entry.isEnabled ? "Disable" : "Enable",
                             emphasis: .quiet, action: onToggle)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.textTertiary)
                        .padding(DS.Space.xs)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .opacity(isHovering ? 1 : 0)
        }
        .opacity(entry.isEnabled ? 1 : 0.5)
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm + 2)
        .background(
            isHovering ? DS.Color.hover : DS.Color.surface,
            in: .rect(cornerRadius: DS.Radius.md)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline)
        }
        .onHover { isHovering = $0 }
        .animation(DS.Motion.smooth, value: isHovering)
    }
}

private struct DictionaryEditor: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: DictionaryEntry.Kind
    @State private var hear: String
    @State private var write: String

    init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _kind = State(initialValue: entry?.kind ?? .term)
        _hear = State(initialValue: entry?.hear ?? "")
        _write = State(initialValue: entry?.write ?? "")
    }

    private var draft: DictionaryEntry {
        DictionaryEntry(
            id: entry?.id ?? UUID(),
            kind: kind,
            write: write.trimmingCharacters(in: .whitespacesAndNewlines),
            hear: kind == .correction ? hear.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            isEnabled: entry?.isEnabled ?? true
        )
    }

    private var warnings: [DictionaryWarning] { DictionaryWarning.check(draft) }

    private var isValid: Bool {
        !draft.write.isEmpty && (kind == .term || !draft.hear.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text(entry == nil ? "New entry" : "Edit entry")
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.text)

            Segmented(
                options: [(DictionaryEntry.Kind.term, "Term"), (.correction, "Correction")],
                selection: $kind
            )

            VStack(alignment: .leading, spacing: DS.Space.md) {
                if kind == .correction {
                    LabelledField(label: "When you hear", text: $hear, prompt: "cloud code")
                }
                LabelledField(
                    label: kind == .correction ? "Write" : "Word or phrase",
                    text: $write,
                    prompt: kind == .correction ? "Claude Code" : "Anthropic"
                )
            }

            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: DS.Space.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.warning)
                    Text(warning.message)
                        .font(DS.Font.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.warning.opacity(0.10), in: .rect(cornerRadius: DS.Radius.sm))
            }

            HStack(spacing: DS.Space.sm) {
                Spacer()
                ActionButton(title: "Cancel", emphasis: .normal) { dismiss() }
                ActionButton(title: "Save", emphasis: .prominent) {
                    guard isValid else { return }
                    onSave(draft)
                    dismiss()
                }
                .disabled(!isValid)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 480)
        .background(DS.Color.window)
    }
}
