import AppKit
import MurmurSessions
import SwiftUI
import UniformTypeIdentifiers

struct SessionDetailView: View {
    @State var session: MeetingSession
    let store: SessionStore
    var initialMatch: SessionMatch?
    let onChanged: () -> Void
    let onDeleted: () -> Void
    @State private var segments: [TranscriptSegment] = []
    @State private var bullets: [NoteBullet] = []
    @State private var note = ""
    @State private var draft = ""
    @State private var version = 0
    @State private var title = ""
    @State private var editing = false
    @State private var tab: DetailTab = .notes
    @State private var template = MeetingSettings.shared.defaultTemplate
    @State private var transcriptQuery = ""
    @State private var speakerFilter = "Everyone"
    @State private var scrollTarget: UUID?
    @State private var error: String?
    @State private var externalChange = false
    @State private var copied: String?
    @State private var confirmTrash = false
    @State private var showHistory = false
    @State private var revisionPreview: NoteRevision?
    @State private var renamingSpeaker: String?
    @State private var speakerName = ""
    @State private var summaries = MeetingSummaryService.shared
    @State private var sync = CloudSync.shared
    @FocusState private var titleFocused: Bool

    private enum DetailTab: String, CaseIterable { case notes = "Notes", transcript = "Transcript" }
    private var working: Bool { summaries.isWorking(session.id) }
    private var hasSource: Bool { !segments.isEmpty || !bullets.isEmpty }

    var body: some View {
        VStack(spacing: DS.Space.zero) {
            header
            notice.padding([.horizontal, .bottom], DS.Space.xl)
            HStack(spacing: DS.Space.md) {
                Segmented(options: DetailTab.allCases.map { ($0, $0.rawValue) }, selection: $tab)
                    .fixedSize()
                Spacer()
                if tab == .notes {
                    if hasSource { summariseMenu }
                    ActionButton(title: editing ? "Done" : "Edit", systemImage: editing ? "checkmark" : "square.and.pencil", emphasis: .quiet) {
                        if editing { if saveDraft() { editing = false } }
                        else { draft = note; editing = true }
                    }
                } else { Readout("\(segments.count) segments", color: DS.Color.textTertiary) }
            }
            .padding(.horizontal, DS.Space.xl).padding(.bottom, DS.Space.lg)
            Divider()
            if tab == .notes { notesBody } else { transcriptBody }
            Divider()
            footer
        }
        .background(DS.Color.surface)
        .onAppear {
            load()
            if let time = initialMatch?.timestamp { jump(to: time) }
        }
        .onDisappear { saveTitle(); if editing { _ = saveDraft() } }
        .task(id: draft) {
            guard editing, draft != note else { return }
            do { try store.saveEditingDraft(draft, baseVersion: version, for: session.id) }
            catch { self.error = error.localizedDescription; return }
            guard !externalChange else { return }
            do { try await Task.sleep(for: DS.Timing.autosave) } catch { return }
            _ = saveDraft()
        }
        .task(id: title) {
            guard !title.isEmpty, title != session.title else { return }
            do { try await Task.sleep(for: DS.Timing.autosave) } catch { return }
            saveTitle()
        }
        .task(id: copied) {
            guard copied != nil else { return }
            do { try await Task.sleep(for: DS.Timing.feedback); copied = nil } catch {}
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: DS.Timing.refresh) } catch { return }
                refreshExternal()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurNotesChanged)) { event in
            if event.object as? String == session.id { refreshExternal(refreshSource: true) }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "murmur-time", let seconds = Double(url.host ?? "") else { return .systemAction }
            jump(to: seconds); return .handled
        })
        .confirmationDialog("Move “\(session.title)” to Trash?", isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { trash() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This note and its history can be recovered from the Mac's Trash.") }
        .sheet(isPresented: $showHistory) { historySheet }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .top, spacing: DS.Space.sm) {
                TextField("Untitled note", text: $title, axis: .vertical)
                    .textFieldStyle(.plain).font(DS.Font.documentTitle).foregroundStyle(DS.Color.text)
                    .focused($titleFocused).onSubmit(saveTitle)
                Button { pin() } label: { Image(systemName: session.isPinned ? "pin.fill" : "pin").font(DS.Font.symbol) }
                    .buttonStyle(.plain).foregroundStyle(session.isPinned ? DS.Color.accent : DS.Color.textSecondary)
                    .help(session.isPinned ? "Unpin note" : "Pin note")
                    .padding(.top, DS.Space.sm)
                Menu {
                    Button("Copy notes") { copy(note.isEmpty ? bullets.map(\.text).joined(separator: "\n") : note, label: "notes") }
                    Button("Copy full meeting as Markdown") { copy(store.markdown(for: session.id), label: "meeting") }
                    Button("Copy for AI") { copyForAI() }
                    Divider()
                    Button("Export Markdown…") { export() }
                    Button("Note history…") { revisionPreview = nil; showHistory = true }
                        .disabled(store.noteRevisionCount(for: session.id) == 0)
                    Button("Reveal files in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.directory(for: session.id)]) }
                    Divider()
                    Button("Move to Trash…") { confirmTrash = true }
                } label: { Image(systemName: "ellipsis").font(DS.Font.symbol) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: DS.Layout.symbolColumn)
                .help("Copy, export and note options")
                .padding(.top, DS.Space.sm)
            }
            Text(metadata)
                .font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let booking = session.booking {
                DisclosureGroup("Booking details · \(booking.eventType)") {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text(booking.guestName).font(DS.Font.label)
                        if let email = booking.guestEmail { Text(email).foregroundStyle(DS.Color.textSecondary) }
                        ForEach(booking.answers, id: \.question) { answer in
                            Text(answer.question).font(DS.Font.label)
                            Text(answer.answer).textSelection(.enabled)
                        }
                        Text("Provided by the guest before the meeting.").foregroundStyle(DS.Color.textSecondary)
                    }.font(DS.Font.caption).frame(maxWidth: .infinity, alignment: .leading)
                }.font(DS.Font.callout)
            }
        }
        .padding(DS.Space.xl)
    }

    /// Date · duration · app · who was there. One line; it wraps if the room was full.
    private var metadata: String {
        var parts = [session.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())]
        if !session.isNoteOnly { parts.append(TimeFormat.clock(session.duration)) }
        if let app = session.app { parts.append(app) }
        if !session.attendees.isEmpty { parts.append(session.attendees.map(\.name).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// The template is the menu; the button is the action. Replaces a picker and a button
    /// that together said the same thing twice.
    private var summariseMenu: some View {
        Menu {
            ForEach(SummaryTemplate.allCases) { option in
                Button(option.title) { template = option; summarise() }
            }
        } label: {
            Label(note.isEmpty ? "Summarise" : "Refresh summary", systemImage: "sparkles")
        } primaryAction: {
            summarise()
        }
        .fixedSize()
        .disabled(working || !FoundationModelFormatter.isAvailable || externalChange)
        .help(FoundationModelFormatter.unavailableReason ?? "Uses the \(template.title) template. Choose another from the menu.")
    }

    private func summarise() {
        if editing, !saveDraft() { return }
        editing = false
        summaries.generate(id: session.id, template: template, store: store)
    }

    /// One notice at a time, most important first: a change you might lose, then an error,
    /// then progress.
    @ViewBuilder private var notice: some View {
        if externalChange {
            InlineNotice(icon: "arrow.triangle.2.circlepath", text: "The saved note changed in another app. Your draft is kept here.") {
                ActionButton(title: "Copy draft", emphasis: .quiet) { copy(draft, label: "draft") }
                ActionButton(title: "Keep my draft", emphasis: .normal) {
                    version = store.noteVersion(for: session.id); externalChange = false; _ = saveDraft()
                }
                ActionButton(title: "Use saved", emphasis: .quiet) {
                    do { try store.clearEditingDraft(for: session.id, matching: draft); loadNote(); externalChange = false; error = nil }
                    catch { self.error = error.localizedDescription }
                }
            }
        } else if let message = error ?? summaries.errors[session.id] {
            InlineNotice(icon: "info.circle", text: message) {
                if let generated = summaries.drafts[session.id] {
                    ActionButton(title: "Review draft", emphasis: .normal) { draft = generated; editing = true }
                }
            }
        } else if let progress = summaries.progress[session.id] {
            InlineNotice(icon: "sparkles", text: progress) {
                ActionButton(title: "Cancel", emphasis: .quiet) { summaries.cancel(session.id) }
            }
        }
    }

    private var notesBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                if editing {
                    ZStack(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("Write down what matters…").font(DS.Font.documentBody)
                                .foregroundStyle(DS.Color.textTertiary).padding(.top, DS.Space.sm).padding(.leading, DS.Space.xs)
                        }
                        TextEditor(text: $draft).font(DS.Font.documentBody)
                            .scrollContentBackground(.hidden).frame(minHeight: DS.Layout.editorHeight)
                            .accessibilityLabel("Meeting notes editor")
                    }
                } else if note.isEmpty {
                    EmptyState(
                        icon: "square.and.pencil",
                        label: hasSource ? "Turn the meeting into a useful note." : session.isNoteOnly ? "A blank page, ready for you." : "No speech was captured.",
                        detail: hasSource ? (summaries.unavailableReason ?? "Make a summary on this Mac, with key points, decisions and next steps.")
                            : session.isNoteOnly ? "Capture a thought, prepare an agenda or write something you want to keep."
                            : "You can still write a note here. Next time, check that the notes window says it's hearing you and the call."
                    ) {
                        ActionButton(title: "Write a note", systemImage: "square.and.pencil", emphasis: .normal) { draft = note; editing = true }
                    }
                    .frame(maxHeight: DS.Layout.editorHeight)
                } else {
                    MarkdownNoteView(text: note, onToggleTask: toggleTask, onTimestamp: jump)
                }
                if !bullets.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        Divider()
                        Text("Your notes during the meeting").font(DS.Font.headline).foregroundStyle(DS.Color.textSecondary)
                        ForEach(bullets) { bullet in
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                                Text("•").foregroundStyle(DS.Color.textTertiary)
                                Text(bullet.text).font(DS.Font.documentBody).textSelection(.enabled)
                                Spacer(minLength: DS.Space.zero)
                                Button { jump(to: bullet.at) } label: { Readout(TimeFormat.clock(bullet.at), color: DS.Color.accent) }
                                    .buttonStyle(.plain).help("Show this moment in the transcript")
                            }
                        }
                    }
                }
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: DS.Layout.documentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transcriptBody: some View {
        VStack(spacing: DS.Space.zero) {
            HStack(spacing: DS.Space.md) {
                SearchField(text: $transcriptQuery, placeholder: "Find in transcript")
                Picker("Speaker", selection: $speakerFilter) {
                    Text("Everyone").tag("Everyone")
                    ForEach(speakers, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().fixedSize()
            }.padding(DS.Space.lg)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Space.xl) {
                        if filteredSegments.isEmpty {
                            Text(segments.isEmpty ? "No speech was captured in this note." : "No matching lines. Try another word or speaker.")
                                .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                        }
                        ForEach(filteredSegments) { segment in
                            VStack(alignment: .leading, spacing: DS.Space.sm) {
                                HStack(spacing: DS.Space.sm) {
                                    Button { speakerName = displayName(segment); renamingSpeaker = speakerName } label: {
                                        SpeakerChip(name: displayName(segment), color: speakerColor(segment))
                                    }
                                    .buttonStyle(.plain).disabled(segment.source == .you)
                                    .popover(isPresented: Binding(get: { renamingSpeaker == displayName(segment) && firstSegment(named: displayName(segment)) == segment.id }, set: { if !$0 { renamingSpeaker = nil } })) {
                                        VStack(alignment: .leading, spacing: DS.Space.md) {
                                            Text("Name this speaker").font(DS.Font.headline)
                                            TextField("Name", text: $speakerName).textFieldStyle(.roundedBorder)
                                            ActionButton(title: "Save name", emphasis: .prominent) { renameSpeaker(displayName(segment), to: speakerName) }
                                        }.padding(DS.Space.lg).frame(width: DS.Layout.popoverWidth)
                                    }
                                    Readout(TimeFormat.clock(segment.start), color: DS.Color.textTertiary)
                                }
                                Text(segment.text).font(DS.Font.documentBody).foregroundStyle(DS.Color.text)
                                    .lineSpacing(DS.Layout.proseLineSpacing).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(DS.Space.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(scrollTarget == segment.id ? DS.Color.accentSoft : .clear, in: .rect(cornerRadius: DS.Radius.md))
                            .id(segment.id)
                        }
                    }
                    .padding(DS.Space.lg)
                }
                .onAppear { if let scrollTarget { proxy.scrollTo(scrollTarget, anchor: .top) } }
                .onChange(of: scrollTarget) { _, id in if let id { proxy.scrollTo(id, anchor: .top) } }
            }
        }
    }

    private var footer: some View {
        NoteStatusLine(
            transient: copied != nil ? "Copied" : (editing && draft != note ? "Unsaved changes" : nil),
            source: session.noteSource,
            syncIssue: sync.issue(for: session.id)?.message
        )
    }

    private var historySheet: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack {
                Text("Note history").font(DS.Font.pageTitle)
                Spacer()
                ActionButton(title: "Done", emphasis: .quiet) { showHistory = false }
            }
            if let revision = revisionPreview {
                HStack {
                    ActionButton(title: "All versions", systemImage: "chevron.left", emphasis: .quiet) { revisionPreview = nil }
                    Spacer()
                    ActionButton(title: "Restore this version", emphasis: .prominent) { restore(revision) }
                }
                ScrollView { MarkdownNoteView(text: revision.text) }
            } else {
                Text("Restoring an earlier note keeps the current one as a revision.")
                    .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                List(store.noteRevisions(for: session.id)) { revision in
                    Button { revisionPreview = revision } label: {
                        VStack(alignment: .leading, spacing: DS.Space.sm) {
                            Readout("Version \(revision.number)")
                            Text(revision.text).font(DS.Font.body).lineLimit(2)
                        }.padding(.vertical, DS.Space.sm)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(DS.Space.xl).frame(width: DS.Layout.sheetWidth, height: DS.Layout.sheetHeight)
    }

    private var filteredSegments: [TranscriptSegment] {
        let query = transcriptQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return segments.filter { (speakerFilter == "Everyone" || displayName($0) == speakerFilter) && (query.isEmpty || $0.text.localizedStandardContains(query)) }
    }
    private var speakers: [String] { var names: [String] = []; for s in segments { let name = displayName(s); if !names.contains(name) { names.append(name) } }; return names }
    private func displayName(_ s: TranscriptSegment) -> String { s.source == .you ? "You" : s.speaker ?? "Call" }
    private func speakerColor(_ s: TranscriptSegment) -> Color { s.source == .you ? DS.Color.speaker(0) : DS.Color.speaker((speakers.filter { $0 != "You" }.firstIndex(of: displayName(s)) ?? 0) + 1) }
    private func firstSegment(named name: String) -> UUID? { filteredSegments.first { displayName($0) == name }?.id }
    private func load() {
        title = session.title
        segments = store.transcript(for: session.id); bullets = store.bullets(for: session.id)
        template = SummaryTemplate(rawValue: session.summaryTemplate ?? "") ?? MeetingSettings.shared.defaultTemplate
        loadNote()
        editing = session.isNoteOnly && note.isEmpty
        if let recovered = store.editingDraft(for: session.id), recovered.text != note {
            draft = recovered.text; editing = true
            externalChange = recovered.baseVersion != version
            version = recovered.baseVersion
        }
    }
    private func loadNote() {
        note = store.note(for: session.id) ?? ""; draft = note; version = store.noteVersion(for: session.id)
        if let current = store.session(id: session.id) { session = current }
    }
    private func refreshExternal(refreshSource: Bool = false) {
        if let current = store.session(id: session.id), current != session {
            if !titleFocused, title == session.title { title = current.title }
            session = current
        }
        if refreshSource {
            segments = store.transcript(for: session.id)
            bullets = store.bullets(for: session.id)
        }
        let saved = store.note(for: session.id) ?? ""
        if saved != note {
            if editing && draft != note { externalChange = true }
            else { loadNote(); onChanged() }
        }
    }
    private func saveTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != session.title else { return }
        do { session = try store.update(id: session.id) { $0.title = trimmed }; onChanged() }
        catch { self.error = error.localizedDescription }
    }
    @discardableResult private func saveDraft() -> Bool {
        guard draft != note else { return true }
        do {
            try store.saveEditingDraft(draft, baseVersion: version, for: session.id)
            guard !externalChange else { return false }
            try store.saveNote(draft, for: session.id, expectedVersion: version, source: "Edited by you", template: template)
            try store.clearEditingDraft(for: session.id, matching: draft)
            note = draft; version = store.noteVersion(for: session.id); error = nil
            if let updated = store.session(id: session.id) { session = updated }
            onChanged(); return true
        } catch {
            if case SessionStoreError.noteConflict = error { externalChange = true }
            self.error = error.localizedDescription; return false
        }
    }
    private func toggleTask(_ line: Int) {
        var lines = note.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return }
        if lines[line].contains("- [ ] ") { lines[line] = lines[line].replacingOccurrences(of: "- [ ] ", with: "- [x] ", range: lines[line].range(of: "- [ ] ")) }
        else if let range = lines[line].range(of: "- [x] ", options: .caseInsensitive) { lines[line].replaceSubrange(range, with: "- [ ] ") }
        draft = lines.joined(separator: "\n"); _ = saveDraft()
    }
    private func pin() {
        let pinned = !session.isPinned
        do { session = try store.update(id: session.id) { $0.pinned = pinned }; onChanged() }
        catch { self.error = error.localizedDescription }
    }
    private func jump(to time: TimeInterval) {
        transcriptQuery = ""; speakerFilter = "Everyone"
        scrollTarget = segments.first { $0.end >= time }?.id ?? segments.last?.id
        tab = .transcript
    }
    private func renameSpeaker(_ old: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let updated = segments.map { s -> TranscriptSegment in
            guard s.source == .call, displayName(s) == old else { return s }
            var changed = s; changed.speaker = trimmed; return changed
        }
        do {
            try store.replaceTranscript(updated, for: session.id)
            session = try store.update(id: session.id) { $0.speakers = Array(Set(updated.compactMap(\.speaker))).sorted() }
            segments = updated; renamingSpeaker = nil; speakerFilter = "Everyone"; onChanged()
        } catch { self.error = error.localizedDescription }
    }
    private func restore(_ revision: NoteRevision) {
        do {
            try store.saveNote(revision.text, for: session.id, expectedVersion: version, source: "Restored by you")
            loadNote(); editing = false; externalChange = false; showHistory = false; onChanged()
        } catch { self.error = error.localizedDescription; showHistory = false }
    }
    private func copyForAI() {
        copy(MeetingNotes.prompt(session: session, bullets: bullets, segments: segments, template: template)
             + (note.isEmpty ? "" : "\n\nCurrent note (for reference):\n" + note), label: "ai")
    }
    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); copied = label
    }
    private func export() {
        if editing, !saveDraft() { return }
        saveTitle()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = session.title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try store.markdown(for: session.id).write(to: url, atomically: true, encoding: .utf8) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func trash() {
        summaries.cancel(session.id)
        NSWorkspace.shared.recycle([store.directory(for: session.id)]) { _, error in
            Task { @MainActor in
                if let error { self.error = error.localizedDescription } else { onDeleted() }
            }
        }
    }
}
