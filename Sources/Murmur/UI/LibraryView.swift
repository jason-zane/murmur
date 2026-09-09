import AppKit
import MurmurSessions
import SwiftUI

/// Every meeting, newest first, grouped by day. The main window's primary view.
struct LibraryView: View {
    @Bindable var controller: MeetingController
    let onStartMeeting: () -> Void

    @State private var sessions: [MeetingSession] = []
    @State private var selection: String?
    @State private var query = ""
    @State private var hitIDs: Set<String> = []

    private var store: SessionStore { controller.store }

    var body: some View {
        // A plain split, not NavigationSplitView: that one installs a window toolbar with a
        // sidebar toggle that cannot be removed from inside a tabbed content view.
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: reload)
        .onChange(of: controller.lastFinishedSessionID) { _, id in
            reload()
            if let id { selection = id }
        }
        .onChange(of: controller.state) { _, _ in reload() }
        .onChange(of: query) { _, _ in search() }
        .onReceive(NotificationCenter.default.publisher(for: .murmurShowSession)) { note in
            reload()
            if let id = note.object as? String { selection = id }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let session = sessions.first(where: { $0.id == id }) {
            SessionDetailView(session: session, store: store, onChanged: reload, onDeleted: {
                selection = nil
                reload()
            })
            .id(id)
        } else {
            EmptyState(
                icon: "waveform.and.mic",
                label: sessions.isEmpty ? "No meetings yet" : "Select a meeting",
                detail: sessions.isEmpty
                    ? "Murmur listens for calls in Zoom, Meet, Teams and the rest — or press Record."
                    : "Notes, your bullets and the transcript live here."
            )
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                SearchField(text: $query, placeholder: "Search meetings")
                Button(action: onStartMeeting) {
                    Image(systemName: controller.isRecording ? "stop.fill" : "record.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(controller.isRecording ? .white : DS.Color.record)
                        .frame(width: 28, height: 28)
                        .background(controller.isRecording ? DS.Color.record : DS.Color.surface, in: .circle)
                        .overlay { Circle().strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline) }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(controller.isRecording ? "Stop recording" : "Record a meeting now")
            }
            .padding(DS.Space.md)

            if controller.state.isActive, let live = controller.session {
                LiveRow(session: live, elapsed: controller.elapsed)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.bottom, DS.Space.xs)
            }

            List(selection: $selection) {
                ForEach(groups, id: \.title) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            SessionRow(session: session)
                                .tag(session.id)
                                .listRowInsets(EdgeInsets(top: 3, leading: DS.Space.sm, bottom: 3, trailing: DS.Space.sm))
                        }
                    } header: {
                        Text(group.title.uppercased())
                            .font(DS.Font.readout)
                            .tracking(0.8)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if filtered.isEmpty, !query.isEmpty {
                    EmptyState(icon: "magnifyingglass", label: "No matches", detail: "Titles, people, apps and what was said.")
                }
            }
        }
        .background(DS.Color.window)
    }

    // MARK: - Data

    private var filtered: [MeetingSession] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return sessions }
        return sessions.filter { s in
            hitIDs.contains(s.id)
                || s.title.lowercased().contains(needle)
                || (s.app ?? "").lowercased().contains(needle)
                || s.speakers.contains { $0.lowercased().contains(needle) }
                || s.attendees.contains { $0.name.lowercased().contains(needle) }
        }
    }

    private struct Group { let title: String; let sessions: [MeetingSession] }

    private var groups: [Group] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [MeetingSession]] = [:]
        for s in filtered {
            let key: String
            if calendar.isDateInToday(s.startedAt) { key = "Today" }
            else if calendar.isDateInYesterday(s.startedAt) { key = "Yesterday" }
            else {
                let f = DateFormatter()
                f.dateFormat = calendar.isDate(s.startedAt, equalTo: Date(), toGranularity: .year) ? "EEEE d MMMM" : "d MMMM yyyy"
                key = f.string(from: s.startedAt)
            }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(s)
        }
        return order.map { Group(title: $0, sessions: buckets[$0] ?? []) }
    }

    private func reload() {
        sessions = store.listSessions().filter { !$0.state.isInterrupted || $0.id != controller.session?.id }
    }

    private func search() {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { hitIDs = []; return }
        let store = self.store
        Task.detached(priority: .userInitiated) {
            let ids = Set(store.search(needle, limit: 200).map(\.sessionID))
            await MainActor.run { hitIDs = ids }
        }
    }
}

private struct SessionRow: View {
    let session: MeetingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                Text(session.title)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Chip(text: session.state == .noted ? "Noted" : "Raw",
                     tint: session.state == .noted ? DS.Color.success : DS.Color.textSecondary,
                     filled: session.state == .noted)
            }
            Readout(meta, color: DS.Color.textTertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private var meta: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        var parts = [f.string(from: session.startedAt), TimeFormat.clock(session.duration)]
        let people = session.speakers.isEmpty ? session.attendees.map(\.name) : session.speakers
        if !people.isEmpty { parts.append(people.prefix(3).joined(separator: ", ")) }
        if let app = session.app { parts.append(app) }
        return parts.joined(separator: " · ")
    }
}

private struct LiveRow: View {
    let session: MeetingSession
    let elapsed: TimeInterval

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            RecordingDot(size: 7)
            Text(session.title)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.text)
                .lineLimit(1)
            Spacer()
            Readout(TimeFormat.clock(elapsed), color: DS.Color.text)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(DS.Color.recordSoft, in: .rect(cornerRadius: DS.Radius.sm))
    }
}

extension Notification.Name {
    static let murmurShowSession = Notification.Name("com.jasonhunt.murmur.showSession")
}
