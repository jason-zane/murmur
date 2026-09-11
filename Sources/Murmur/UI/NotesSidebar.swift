import AppKit
import MurmurSessions
import SwiftUI

/// The Notes half of the sidebar: search, the pin filter, and every note by day.
struct NotesSidebar: View {
    @Bindable var controller: MeetingController
    @Binding var page: MainPage
    @Binding var selection: String?
    /// The search hit for the selected note, so the detail can open at the right moment.
    @Binding var match: SessionMatch?
    /// Bumped by the window when a note changed somewhere it can't observe.
    let reloadToken: Int
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
            VStack(spacing: DS.Space.md) {
                SearchField(text: $query, placeholder: "Search all notes")
                    .focused($searchFocused)
                HStack(spacing: DS.Space.sm) {
                    Text("Notes").font(DS.Font.label).foregroundStyle(DS.Color.textTertiary)
                    Spacer()
                    Button { pinnedOnly.toggle() } label: {
                        Image(systemName: pinnedOnly ? "pin.fill" : "pin")
                            .font(DS.Font.smallSymbol)
                            .foregroundStyle(pinnedOnly ? DS.Color.accent : DS.Color.textTertiary)
                    }.buttonStyle(.plain).help(pinnedOnly ? "Show all notes" : "Show pinned notes")
                    if searching { ProgressView().controlSize(.mini) }
                    else { Readout(String(filtered.count), color: DS.Color.textTertiary) }
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm)
            if let error {
                InlineNotice(text: error, tone: .warning).padding(.horizontal, DS.Space.lg)
            }
            if filtered.isEmpty {
                EmptyState(
                    icon: query.isEmpty ? "note.text" : "magnifyingglass",
                    label: query.isEmpty ? (pinnedOnly ? "No pinned notes" : "Your notes will live here") : "No matching notes",
                    detail: query.isEmpty ? "Record a meeting or write a note. Pin the ones you return to."
                        : "Search titles, people, your notes or something that was said."
                )
            } else {
                List(selection: $selection) {
                    ForEach(groups, id: \.date) { group in
                        Section {
                            ForEach(group.sessions) { session in
                                NoteRow(session: session, match: matches[session.id])
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
        }
        .onAppear { reload(); searchFocused = true }
        .onChange(of: controller.state) { _, _ in reload() }
        .onChange(of: reloadToken) { _, _ in reload() }
        .onChange(of: selection) { _, id in match = id.flatMap { matches[$0] } }
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
    private func togglePin(_ session: MeetingSession) {
        do { try store.update(id: session.id) { $0.pinned = !session.isPinned }; reload() }
        catch { self.error = error.localizedDescription }
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

/// A sidebar destination that isn't a note: Home and the dictation list.
struct NavRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: systemImage).font(DS.Font.symbol).frame(width: DS.Layout.symbolColumn)
                Text(title).font(DS.Font.callout)
                Spacer(minLength: DS.Space.zero)
            }
            .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textSecondary)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.sm)
            .background(isSelected ? DS.Color.accentSoft : isHovering ? DS.Color.hover : .clear, in: .rect(cornerRadius: DS.Radius.md))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct NoteRow: View {
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
