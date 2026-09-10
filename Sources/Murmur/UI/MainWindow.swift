import AppKit
import MurmurSessions
import SwiftUI

/// One sidebar, one detail. The sidebar lists notes or dictations; the detail shows the
/// selected one, or Home when nothing is selected. Everything that isn't a note — the
/// dictionary, connections, every setting — lives in Settings.
struct MainWindow: View {
    @Bindable var controller: DictationController
    let meetings: MeetingController
    let onToggleMeeting: () -> Void
    let onShowNotepad: () -> Void
    @State private var mode: Mode = .notes
    @State private var selectedSession: String?
    @State private var selectedMatch: SessionMatch?
    @State private var selectedRun: UUID?
    @State private var libraryVersion = 0
    @State private var error: String?
    @State private var settings = Settings.shared
    @State private var sync = CloudSync.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Mode: Hashable { case notes, dictation }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: DS.Layout.sidebarMinWidth, ideal: DS.Layout.sidebarWidth, max: DS.Layout.sidebarMaxWidth
                )
        } detail: {
            // Pinned to the column's size on purpose: a long note's scroll view otherwise
            // reports its content height as ideal, the column grows past the window, and
            // both columns render clipped top and bottom.
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
                    detail
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
            mode = .notes
            selectedSession = note.object as? String
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurNewNote)) { _ in newNote() }
        .onChange(of: meetings.lastFinishedSessionID) { _, id in
            if let id { mode = .notes; selectedSession = id }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            ActionButton(title: "New note", systemImage: "square.and.pencil", emphasis: .normal) { newNote() }
            if meetings.state.isActive {
                ActionButton(title: "Show notes", systemImage: "note.text", emphasis: .prominent, action: onShowNotepad)
            } else {
                ActionButton(title: "Record meeting", systemImage: "mic", emphasis: .prominent, action: onToggleMeeting)
                    .disabled(meetings.state != .idle)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: DS.Space.zero) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "waveform")
                        .font(DS.Font.symbol)
                        .foregroundStyle(DS.Color.accent)
                        .frame(width: DS.Layout.brandMark, height: DS.Layout.brandMark)
                        .background(DS.Color.accentSoft, in: .rect(cornerRadius: DS.Radius.md))
                    Text("Voice Notes").font(DS.Font.brand).lineLimit(1)
                }
                Segmented(
                    options: [(value: Mode.notes, title: "Notes"), (value: Mode.dictation, title: "Dictation")],
                    selection: $mode
                )
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.md)
            .padding(.bottom, DS.Space.sm)

            switch mode {
            case .notes:
                NotesSidebar(controller: meetings, selection: $selectedSession, match: $selectedMatch, reloadToken: libraryVersion)
            case .dictation:
                DictationSidebar(selection: $selectedRun)
            }

            Divider()
            footer
        }
    }

    /// The push-to-talk reminder, and the one sync line that needs you — nothing when
    /// everything is fine or there is no account.
    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if sync.state.isProblem, let label = sync.state.label {
                Button { SettingsRouter.shared.open(.connections) } label: {
                    Label(label, systemImage: sync.state.symbol ?? "exclamationmark.circle")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.warning)
                }
                .buttonStyle(.plain)
                .help("Open Settings ▸ Connections")
            }
            Text("Hold " + settings.triggerSummary + " to dictate")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        switch mode {
        case .notes:
            if let id = selectedSession, let session = meetings.store.session(id: id) {
                SessionDetailView(
                    session: session, store: meetings.store, initialMatch: selectedMatch,
                    onChanged: { libraryVersion += 1 },
                    onDeleted: { selectedSession = nil; libraryVersion += 1 }
                ).id(id)
            } else {
                HomeView(onRecord: onToggleMeeting, onNewNote: newNote)
            }
        case .dictation:
            if let id = selectedRun, let run = RunStore.shared.runs.first(where: { $0.id == id }) {
                DictationDetail(run: run) {
                    RunLog.delete(run)
                    selectedRun = nil
                }
            } else {
                DictationHome(controller: controller)
            }
        }
    }

    private func newNote() {
        mode = .notes
        do {
            selectedSession = try meetings.store.createNote().id
            libraryVersion += 1
        } catch { self.error = error.localizedDescription }
    }
}

/// While a meeting is being recorded (or saved): the title, proof that both sides are
/// heard, the clock, and Stop. Sits under the toolbar above whatever is selected.
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
}
