import AppKit
import MurmurSessions
import SwiftUI

struct LibraryView: View {
    @Bindable var controller: MeetingController
    @Binding var selection: String?
    let onStartMeeting: () -> Void
    let onOpenNotepad: () -> Void
    @State private var sessions: [MeetingSession] = []
    @State private var query = ""
    @State private var matches: [String: SessionMatch] = [:]
    @State private var pinnedOnly = false
    @State private var searching = false
    @State private var searchID = UUID()
    @State private var error: String?
    @FocusState private var searchFocused: Bool
    private var store: SessionStore { controller.store }

    var body: some View {
        VStack(spacing: DS.Space.zero) {
            HStack(spacing: DS.Space.lg) {
                WorkspaceHeading(title: "Meetings", subtitle: "Listen closely. Leave with useful notes.")
                Spacer()
                ActionButton(title: "New note", systemImage: "square.and.pencil", emphasis: .normal) { newNote() }
                ActionButton(title: controller.state.isActive ? "Open notepad" : "Record meeting",
                             systemImage: controller.state.isActive ? "note.text" : "mic",
                             emphasis: .prominent) {
                    if controller.state.isActive { onOpenNotepad() }
                    else { onStartMeeting() }
                }
                .disabled(controller.state == .finalising || controller.state == .saveFailed)
            }
            .padding(DS.Space.xl)
            if controller.state != .idle { recordingBanner }
            if let message = error ?? controller.lastError {
                InlineNotice(icon: "exclamationmark.triangle", text: message) {
                    if controller.state == .saveFailed {
                        ActionButton(title: "Retry save", emphasis: .normal) { controller.retrySave() }
                    }
                }.padding([.horizontal, .bottom], DS.Space.lg)
            }
            Divider()
            HStack(spacing: DS.Space.zero) {
                sidebar.frame(width: DS.Layout.libraryWidth)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: controller.lastFinishedSessionID) { _, id in reload(); if let id { selection = id } }
        .onChange(of: controller.state) { _, _ in reload() }
        .onChange(of: selection) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .murmurNotesChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .murmurFind)) { _ in searchFocused = true }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: DS.Timing.refresh) } catch { return }
                reload()
                if !query.isEmpty { await search(debounce: false) }
            }
        }
        .task(id: query) { await search() }
    }

    private var sidebar: some View {
        VStack(spacing: DS.Space.zero) {
            VStack(spacing: DS.Space.md) {
                SearchField(text: $query, placeholder: "Search all notes")
                    .focused($searchFocused)
                HStack(spacing: DS.Space.sm) {
                    Button { selection = nil } label: { Label("Up next", systemImage: "calendar") }
                        .font(DS.Font.callout).buttonStyle(.plain).foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Button { pinnedOnly.toggle() } label: {
                        Image(systemName: pinnedOnly ? "pin.fill" : "pin")
                            .font(DS.Font.smallSymbol)
                            .foregroundStyle(pinnedOnly ? DS.Color.accent : DS.Color.textTertiary)
                    }.buttonStyle(.plain).help(pinnedOnly ? "Show all notes" : "Show pinned notes")
                    if searching { ProgressView().controlSize(.mini) }
                    else { Readout(String(filtered.count), color: DS.Color.textTertiary) }
                }
            }.padding(DS.Space.lg)
            if filtered.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text(query.isEmpty ? (pinnedOnly ? "No pinned notes" : "Your notes will live here")
                         : "No matching notes").font(DS.Font.bodyEmphasis)
                    Text(query.isEmpty ? "Record a meeting or start a note. Pin the ones you return to."
                         : "Search titles, people, your notes or something that was said.")
                        .font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                }.padding(DS.Space.lg).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List(selection: $selection) {
                    ForEach(groups, id: \.date) { group in
                        Section {
                            ForEach(group.sessions) { session in
                                LibrarySessionRow(session: session, match: matches[session.id])
                                    .tag(session.id)
                                    .listRowInsets(EdgeInsets(top: DS.Space.sm, leading: DS.Space.md,
                                                             bottom: DS.Space.sm, trailing: DS.Space.md))
                                    .contextMenu {
                                        Button(session.isPinned ? "Unpin note" : "Pin note") { togglePin(session) }
                                        Button("Copy as Markdown") { copy(store.markdown(for: session.id)) }
                                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.directory(for: session.id)]) }
                                    }
                            }
                        } header: {
                            Text(group.title).font(DS.Font.label).foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }.background(DS.Color.window)
    }

    @ViewBuilder private var detail: some View {
        if let id = selection, let session = sessions.first(where: { $0.id == id }) {
            SessionDetailView(session: session, store: store, initialMatch: matches[id], onChanged: reload, onDeleted: {
                selection = nil; reload()
            }).id(id)
        } else {
            MeetingHomeView(onRecord: onStartMeeting, onNewNote: newNote)
        }
    }

    private var recordingBanner: some View {
        HStack(spacing: DS.Space.md) {
            if controller.isRecording { RecordingDot(size: DS.Layout.statusDot) }
            else { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(controller.session?.title ?? "Preparing your meeting…").font(DS.Font.bodyEmphasis).lineLimit(1)
                Text(controller.isRecording ? "Recording on this Mac" : controller.state == .saveFailed ? "Save needs attention" : controller.state == .starting ? "Preparing on-device transcription…" : "Saving your conversation…")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer()
            Readout(TimeFormat.clock(controller.elapsed), color: DS.Color.text)
            if controller.isRecording {
                StreamMeters(you: controller.youLevel, call: controller.callLevel, callUnavailable: !controller.systemAudioActive)
                    .frame(width: DS.Layout.meterWidth)
                ActionButton(title: "Stop", systemImage: "stop.fill", emphasis: .normal) { controller.stop() }
            }
        }
        .padding(DS.Space.md)
        .background(controller.isRecording ? DS.Color.recordSoft : DS.Color.hover, in: .rect(cornerRadius: DS.Radius.md))
        .padding([.horizontal, .bottom], DS.Space.lg)
    }

    private var filtered: [MeetingSession] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions.filter { (!pinnedOnly || $0.isPinned) && (needle.isEmpty || matches[$0.id] != nil) }
    }
    private struct DayGroup { let date: Date; let title: String; let sessions: [MeetingSession] }
    private var groups: [DayGroup] {
        let calendar = Calendar.current
        return Dictionary(grouping: filtered, by: { calendar.startOfDay(for: $0.startedAt) })
            .sorted { $0.key > $1.key }.map { date, sessions in
                let title = calendar.isDateInToday(date) ? "Today" : calendar.isDateInYesterday(date) ? "Yesterday"
                    : date.formatted(.dateTime.day().month(.wide))
                return DayGroup(date: date, title: title, sessions: sessions)
            }
    }
    private func reload() {
        let latest = store.listSessions().filter { $0.id != controller.session?.id }
        if latest != sessions { sessions = latest }
    }
    private func search(debounce: Bool = true) async {
        let token = UUID(); searchID = token
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { matches = [:]; searching = false; return }
        searching = true
        if debounce { do { try await Task.sleep(for: DS.Timing.searchDebounce) } catch { return } }
        let store = store
        let result = await Task.detached(priority: .userInitiated) { store.findSessions(needle) }.value
        guard !Task.isCancelled, token == searchID, needle == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        matches = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        searching = false
    }
    private func newNote() {
        do { let note = try store.createNote(); query = ""; pinnedOnly = false; reload(); selection = note.id }
        catch { self.error = error.localizedDescription }
    }
    private func togglePin(_ session: MeetingSession) {
        do { try store.update(id: session.id) { $0.pinned = !session.isPinned }; reload() }
        catch { self.error = error.localizedDescription }
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

private struct LibrarySessionRow: View {
    let session: MeetingSession
    let match: SessionMatch?
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text(session.title).font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.text).lineLimit(2)
                Spacer(minLength: DS.Space.zero)
                if session.isPinned { Image(systemName: "pin.fill").font(DS.Font.smallSymbol).foregroundStyle(DS.Color.accent) }
            }
            if let match {
                Text(match.snippet).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(2)
            }
            HStack(spacing: DS.Space.sm) {
                Readout(session.startedAt.formatted(.dateTime.hour().minute()), color: DS.Color.textTertiary)
                if !session.isNoteOnly { Readout(TimeFormat.clock(session.duration), color: DS.Color.textTertiary) }
                Spacer(minLength: DS.Space.zero)
                Text(session.isNoteOnly ? "Note" : session.app ?? "Meeting").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
            }
        }.padding(.vertical, DS.Space.xs)
    }
}

extension Notification.Name {
    static let murmurShowSession = Notification.Name("com.jasonhunt.murmur.showSession")
    static let murmurFind = Notification.Name("com.jasonhunt.murmur.find")
}
