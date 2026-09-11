import AppKit
import MurmurSessions
import SwiftUI

/// What the detail column shows when no note is selected.
enum MainPage: Hashable { case home, calendar, notes, dictation, booking, connections, settings }

struct MainWindow: View {
    @Bindable var controller: DictationController
    let meetings: MeetingController
    let onToggleMeeting: () -> Void
    let onRecordCalendar: (CalendarEvent) -> Void
    let onShowNotepad: () -> Void
    let onPreviewBar: () -> Void
    @State private var page: MainPage = .home
    @State private var selectedSession: String?
    @State private var selectedMatch: SessionMatch?
    @State private var libraryVersion = 0
    @State private var error: String?
    @State private var settings = Settings.shared
    @State private var sync = CloudSync.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: DS.Layout.navigationWidth, ideal: DS.Layout.navigationWidth, max: DS.Layout.sidebarMinWidth
                )
        } detail: {
            GeometryReader { geometry in
                VStack(spacing: DS.Space.zero) {
                    if meetings.state != .idle {
                        RecordingStrip(controller: meetings, onShowNotes: onShowNotepad)
                    }
                    if let message = meetings.lastError {
                        InlineNotice(text: message, tone: .warning) {
                            if meetings.state == .saveFailed {
                                ActionButton(title: "Retry save", emphasis: .normal) { meetings.retrySave() }
                            }
                        }
                        .padding([.horizontal, .top], DS.Space.lg)
                    }
                    if page == .notes {
                        HSplitView {
                            NotesSidebar(controller: meetings, page: $page, selection: $selectedSession, match: $selectedMatch, reloadToken: libraryVersion)
                                .frame(minWidth: DS.Layout.sidebarMinWidth, idealWidth: DS.Layout.sidebarWidth, maxWidth: DS.Layout.sidebarMaxWidth)
                            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else { detail }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background(DS.Color.surface)
        }
        .toolbar { toolbar }
        .tint(DS.Color.accent)
        .frame(minWidth: DS.Layout.minWindowWidth, minHeight: DS.Layout.minWindowHeight)
        .transaction { if reduceMotion { $0.animation = nil } }
        .alert("Couldn't create note", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .murmurShowSession)) { note in
            page = .notes
            selectedSession = note.object as? String
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurFind)) { _ in page = .notes }
        .onReceive(NotificationCenter.default.publisher(for: .murmurShowPage)) { note in
            if let target = note.object as? MainPage { page = target; selectedSession = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurNewNote)) { _ in newNote() }
        .onReceive(NotificationCenter.default.publisher(for: .murmurShowDictation)) { _ in
            selectedSession = nil
            page = .dictation
        }
        .onChange(of: meetings.lastFinishedSessionID) { _, id in
            if let id { page = .notes; selectedSession = id }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { SettingsRouter.shared.open(.general) } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings  ⌘,")
            ActionButton(title: "New note", systemImage: "square.and.pencil", emphasis: .normal) { newNote() }
            if meetings.state.isActive {
                ActionButton(title: "Show notes", systemImage: "note.text", emphasis: .prominent, action: onShowNotepad)
            } else {
                ActionButton(title: "Record meeting", systemImage: "mic", emphasis: .prominent, action: onToggleMeeting)
                    .disabled(meetings.state != .idle)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: DS.Space.zero) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "waveform")
                    .font(DS.Font.symbol)
                    .foregroundStyle(DS.Color.accent)
                    .frame(width: DS.Layout.brandMark, height: DS.Layout.brandMark)
                    .background(DS.Color.accentSoft, in: .rect(cornerRadius: DS.Radius.md))
                Text("Voice Notes").font(DS.Font.brand).lineLimit(1)
                Spacer(minLength: DS.Space.zero)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.md)
            .padding(.bottom, DS.Space.sm)

            VStack(spacing: DS.Space.xxs) {
                navigation("Home", "house", .home)
                navigation("Calendar", "calendar", .calendar)
                navigation("Notes", "book.closed", .notes)
                navigation("Dictation", "waveform", .dictation)
                navigation("Booking links", "calendar.badge.clock", .booking)
                Spacer()
                navigation("Connections", "link", .connections)
                navigation("Settings", "gearshape", .settings)
            }.padding(DS.Space.md)

            Divider()
            footer
        }
    }

    private func navigation(_ title: String, _ icon: String, _ target: MainPage) -> some View {
        NavRow(title: title, systemImage: icon, isSelected: page == target) {
            page = target
            if target != .notes { selectedSession = nil }
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: DS.Space.sm) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if sync.state.isProblem, let label = sync.state.label {
                    Button { SettingsRouter.shared.open(.connections) } label: {
                        Label(label, systemImage: sync.state.symbol ?? "exclamationmark.circle")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.warning)
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings ▸ Connections")
                }
                if CloudAccount.shared.isConnected {
                    Text(CloudAccount.shared.email).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                }
                Text("Hold " + settings.triggerSummary + " to dictate")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            Spacer(minLength: DS.Space.zero)
            Button { SettingsRouter.shared.open(.general) } label: {
                Image(systemName: "gearshape")
                    .font(DS.Font.symbol)
                    .foregroundStyle(DS.Color.textSecondary)
                    .frame(width: DS.Layout.brandMark, height: DS.Layout.brandMark)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Settings  ⌘,")
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    @ViewBuilder private var detail: some View {
        if page == .notes, let id = selectedSession, let session = meetings.store.session(id: id) {
            SessionDetailView(
                session: session, store: meetings.store, initialMatch: selectedMatch,
                onChanged: { libraryVersion += 1 },
                onDeleted: { selectedSession = nil; libraryVersion += 1 }
            ).id(id)
        } else if page == .calendar {
            CalendarWorkspace(store: meetings.store, onRecord: onRecordCalendar, canRecord: meetings.state == .idle)
        } else if page == .booking {
            CloudWorkspace(path: "/scheduling")
        } else if page == .connections {
            ConnectionsWorkspace()
        } else if page == .settings {
            SettingsWindow(controller: controller, onPreviewBar: onPreviewBar)
        } else if page == .notes {
            EmptyState(icon: "note.text", label: "Notes", detail: "Choose a note, or start with a new one.") {
                ActionButton(title: "New note", emphasis: .prominent) { newNote() }
            }
        } else if page == .dictation {
            DictationList(controller: controller)
        } else {
            HomeView(store: meetings.store, onRecord: onToggleMeeting, onNewNote: newNote)
        }
    }

    private func newNote() {
        do {
            page = .notes
            selectedSession = try meetings.store.createNote().id
            libraryVersion += 1
        } catch { self.error = error.localizedDescription }
    }
}

private struct RecordingStrip: View {
    let controller: MeetingController
    let onShowNotes: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            if !controller.isRecording { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(controller.session?.title ?? "Preparing your meeting…").font(DS.Font.bodyEmphasis).lineLimit(1)
                if controller.isRecording {
                    CaptureStatus(controller: controller)
                } else {
                    Text(controller.state == .saveFailed ? "Save needs attention"
                         : controller.state == .starting ? "Preparing on-device transcription…" : "Saving your note…")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
            }
            Spacer()
            Readout(TimeFormat.clock(controller.elapsed), color: DS.Color.text)
            if controller.isRecording {
                ActionButton(title: "Stop", systemImage: "stop.fill", emphasis: .normal) { controller.stop() }
            }
        }
        .padding(DS.Space.md)
        .background(controller.isRecording ? DS.Color.recordSoft : DS.Color.hover, in: .rect(cornerRadius: DS.Radius.md))
        .padding([.horizontal, .top], DS.Space.lg)
    }
}

extension Notification.Name {
    static let murmurNewNote = Notification.Name("com.jasonhunt.murmur.newNote")
    static let murmurShowDictation = Notification.Name("com.jasonhunt.murmur.showDictation")
}
