import AppKit
import MurmurSessions
import SwiftUI

/// One meeting: the note, your bullets, and the transcript with speakers.
///
/// Your words at full strength; anything a model added recedes into tertiary. No highlight
/// fills, no "AI" badges — the contrast is the label, and it survives a paste into Obsidian.
struct SessionDetailView: View {
    @State var session: MeetingSession
    let store: SessionStore
    let onChanged: () -> Void
    let onDeleted: () -> Void

    @State private var segments: [TranscriptSegment] = []
    @State private var bullets: [NoteBullet] = []
    @State private var note: String = ""
    @State private var noteDraft: String = ""
    @State private var isEditingNote = false
    @State private var title = ""
    @State private var didCopy = false
    @State private var isConfirmingDelete = false
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                header
                noteSection
                if !bullets.isEmpty { bulletsSection }
                transcriptSection
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.Color.window)
        .onAppear(perform: load)
        .confirmationDialog("Delete “\(session.title)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                try? store.delete(id: session.id)
                onDeleted()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The transcript, your notes and every revision. This can't be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            TextField("Untitled meeting", text: $title)
                .textFieldStyle(.plain)
                .font(DS.Font.sessionTitle)
                .foregroundStyle(DS.Color.text)
                .onSubmit(saveTitle)

            HStack(spacing: DS.Space.sm) {
                Readout(dateText)
                Readout("·", color: DS.Color.textTertiary)
                Readout(TimeFormat.clock(session.duration))
                if let app = session.app {
                    Readout("·", color: DS.Color.textTertiary)
                    Readout(app)
                }
                Readout("·", color: DS.Color.textTertiary)
                Readout(session.engine)
                Spacer()
                ActionButton(title: didCopy ? "Copied" : "Copy as Markdown", systemImage: "doc.on.doc", emphasis: .normal) { copyMarkdown() }
                Menu {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.directory(for: session.id)])
                    }
                    Divider()
                    Button("Delete…", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(width: 26, height: 26)
                        .contentShape(.rect)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26)
            }

            if !session.attendees.isEmpty {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(session.attendees.map(\.name).joined(separator: ", "))
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                SectionLabel(text: "Note")
                if store.noteRevisionCount(for: session.id) > 0 {
                    Readout("v\(store.noteRevisionCount(for: session.id) + 1)", color: DS.Color.textTertiary)
                }
                Spacer()
                if isEditingNote {
                    ActionButton(title: "Cancel", emphasis: .quiet) { isEditingNote = false; noteDraft = note }
                    ActionButton(title: "Save", emphasis: .prominent) { saveNote() }
                } else {
                    ActionButton(title: note.isEmpty ? "Write" : "Edit", emphasis: .quiet) { noteDraft = note; isEditingNote = true }
                }
            }

            if isEditingNote {
                TextEditor(text: $noteDraft)
                    .font(DS.Font.body)
                    .scrollContentBackground(.hidden)
                    .padding(DS.Space.sm)
                    .frame(minHeight: 160)
                    .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.md))
                    .overlay { RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.accent.opacity(0.5), lineWidth: 1.5) }
            } else if note.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("No note yet.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textSecondary)
                    Hint("Ask Claude — “write up my \(session.title) call” — once Murmur is connected in Settings, or write one here.")
                }
                .padding(DS.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.md))
                .overlay { RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
            } else {
                Text(LocalizedStringKey(note))
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Bullets

    private var bulletsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            SectionLabel(text: "Your notes")
            VStack(alignment: .leading, spacing: DS.Space.xs + 1) {
                ForEach(bullets) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                        Text("•").foregroundStyle(DS.Color.textTertiary)
                        Text(bullet.text)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Readout(TimeFormat.clock(bullet.at), color: DS.Color.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                SectionLabel(text: "Transcript")
                Spacer()
                Readout("\(segments.count) segments", color: DS.Color.textTertiary)
            }
            if segments.isEmpty {
                Hint("Nothing was transcribed.")
            } else {
                LazyVStack(alignment: .leading, spacing: DS.Space.sm + 2) {
                    ForEach(segments) { segment in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                            Readout(TimeFormat.clock(segment.start), color: DS.Color.textTertiary)
                                .frame(width: 44, alignment: .trailing)
                            speakerChip(for: segment)
                            Text(segment.text)
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func speakerChip(for segment: TranscriptSegment) -> some View {
        let name = displayName(segment)
        return Button {
            renameText = segment.source == .you ? "" : (segment.speaker ?? "")
            renaming = name
        } label: {
            SpeakerChip(name: name, color: speakerColor(name))
        }
        .buttonStyle(.plain)
        .disabled(segment.source == .you)
        .popover(isPresented: Binding(get: { renaming == name && segment.id == firstSegment(named: name)?.id }, set: { if !$0 { renaming = nil } })) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                SectionLabel(text: "Who is this?")
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { rename(name, to: renameText) }
                HStack {
                    Spacer()
                    ActionButton(title: "Rename", emphasis: .prominent) { rename(name, to: renameText) }
                }
                Hint("Applies to every segment labelled “\(name)” in this meeting.")
            }
            .padding(DS.Space.lg)
        }
    }

    // MARK: - Speakers

    private var speakerOrder: [String] {
        var order: [String] = ["You"]
        for s in segments {
            let n = displayName(s)
            if !order.contains(n) { order.append(n) }
        }
        return order
    }

    private func speakerColor(_ name: String) -> Color {
        DS.Color.speaker(speakerOrder.firstIndex(of: name) ?? 1)
    }

    private func displayName(_ segment: TranscriptSegment) -> String {
        segment.source == .you ? "You" : (segment.speaker ?? "Speaker")
    }

    private func firstSegment(named name: String) -> TranscriptSegment? {
        segments.first { displayName($0) == name }
    }

    private func rename(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !trimmed.isEmpty, trimmed != old else { return }
        segments = segments.map { seg in
            guard seg.source == .call, displayName(seg) == old else { return seg }
            var copy = seg
            copy.speaker = trimmed
            return copy
        }
        try? store.replaceTranscript(segments, for: session.id)
        session.speakers = Array(Set(segments.compactMap(\.speaker))).sorted()
        try? store.save(session)
        onChanged()
    }

    // MARK: - Actions

    private func load() {
        title = session.title
        segments = store.transcript(for: session.id)
        bullets = store.bullets(for: session.id)
        note = store.note(for: session.id) ?? ""
        noteDraft = note
    }

    private func saveTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != session.title else { title = session.title; return }
        session.title = trimmed
        try? store.save(session)
        onChanged()
    }

    private func saveNote() {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? store.saveNote(text, for: session.id)
        note = text
        isEditingNote = false
        if let refreshed = store.session(id: session.id) { session = refreshed }
        onChanged()
    }

    private func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.markdown(for: session.id), forType: .string)
        didCopy = true
        Task { try? await Task.sleep(for: .seconds(1.4)); didCopy = false }
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM · HH:mm"
        return f.string(from: session.startedAt)
    }
}
