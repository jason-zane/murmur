import MurmurDictionary
import AppKit
import SwiftUI

struct MainWindow: View {
    @Bindable var controller: DictationController
    let meetings: MeetingController
    let onToggleMeeting: () -> Void
    let onShowNotepad: () -> Void
    @State private var section: Section = .meetings
    @State private var selectedSession: String?
    @State private var error: String?
    @State private var settings = Settings.shared
    @State private var cloud = CloudAccount.shared
    @State private var sync = CloudSync.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Section: String, CaseIterable, Identifiable {
        case meetings, transcriptions, dictionary, connections
        var id: String { rawValue }
        var title: String {
            switch self {
            case .meetings: "Meetings"
            case .transcriptions: "Dictation"
            case .dictionary: "Dictionary"
            case .connections: "Connections"
            }
        }
        var icon: String {
            switch self {
            case .meetings: "text.book.closed"
            case .transcriptions: "waveform"
            case .dictionary: "character.book.closed"
            case .connections: "point.3.connected.trianglepath.dotted"
            }
        }
    }

    var body: some View {
        HStack(spacing: DS.Space.zero) {
            navigation
            Divider()
            Group {
                switch section {
                case .meetings:
                    LibraryView(controller: meetings, selection: $selectedSession,
                                onStartMeeting: onToggleMeeting, onOpenNotepad: onShowNotepad)
                case .transcriptions:
                    DictationWorkspace(controller: controller)
                case .dictionary:
                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                        WorkspaceHeading(title: "Dictionary", subtitle: "Names, phrases and the words you use every day.")
                        DictionaryPanel()
                    }.padding(DS.Space.xl)
                case .connections:
                    ConnectionsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(DS.Color.accent)
        .background(DS.Color.window)
        .frame(minWidth: DS.Layout.minWindowWidth, minHeight: DS.Layout.minWindowHeight)
        .transaction { if reduceMotion { $0.animation = nil } }
        .alert("Couldn't create note", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .murmurShowSession)) { note in
            section = .meetings
            selectedSession = note.object as? String
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurNewNote)) { _ in
            section = .meetings
            do { selectedSession = try meetings.store.createNote().id }
            catch { self.error = error.localizedDescription }
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurShowConnections)) { _ in section = .connections }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "waveform")
                    .font(DS.Font.symbol)
                    .foregroundStyle(DS.Color.accent)
                    .frame(width: DS.Layout.brandMark, height: DS.Layout.brandMark)
                    .background(DS.Color.accentSoft, in: .rect(cornerRadius: DS.Radius.md))
                Text("Voice Notes").font(DS.Font.brand).lineLimit(1)
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.top, DS.Space.lg)

            VStack(spacing: DS.Space.xs) {
                ForEach(Section.allCases) { item in
                    Button { section = item } label: {
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: item.icon).font(DS.Font.symbol).frame(width: DS.Layout.symbolColumn)
                            Text(item.title).font(DS.Font.bodyEmphasis)
                            Spacer(minLength: DS.Space.zero)
                        }
                        .foregroundStyle(section == item ? DS.Color.accent : DS.Color.textSecondary)
                        .padding(.horizontal, DS.Space.md)
                        .frame(height: DS.Layout.navRowHeight)
                        .background(section == item ? DS.Color.accentSoft : .clear, in: .rect(cornerRadius: DS.Radius.sm))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? [.isSelected] : [])
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                SettingsLink {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(cloud.isConnected ? "Signed in as" : "Not signed in")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                        Text(cloud.isConnected ? cloud.email : "Sign in to sync")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.accent)
                            .lineLimit(DS.Account.sidebarEmailLines).truncationMode(.middle)
                    }
                }.buttonStyle(.plain).help(cloud.isConnected ? cloud.email : "Account settings")
                Label(sync.status, systemImage: cloud.isConnected ? "icloud" : "laptopcomputer")
                    .font(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                Text("Hold " + settings.triggerSummary + " to dictate")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                Divider().padding(.vertical, DS.Space.xs)
                HStack {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape").font(DS.Font.callout)
                    }.buttonStyle(.plain).foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Readout("⌘,", color: DS.Color.textTertiary)
                }
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.bottom, DS.Space.md)
        }
        .padding(.horizontal, DS.Space.md)
        .frame(width: DS.Layout.navigationWidth)
        .background(.ultraThinMaterial)
    }
}

struct WorkspaceHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title).font(DS.Font.pageTitle).foregroundStyle(DS.Color.text)
            Text(subtitle).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
        }
    }
}

private struct DictationWorkspace: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @State private var store = RunStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            HStack {
                WorkspaceHeading(title: "Dictation", subtitle: "Speak naturally. Keep your words close.")
                Spacer()
                if controller.state.isActive {
                    LevelMeter(level: controller.level, isActive: controller.state == .listening)
                        .frame(width: DS.Layout.compactMeterWidth, height: DS.Layout.meterHeight)
                    ActionButton(title: controller.state == .listening ? "Stop" : "Cancel",
                                 systemImage: controller.state == .listening ? "stop.fill" : "xmark",
                                 emphasis: .prominent,
                                 tint: controller.state == .listening ? DS.Color.record : DS.Color.accent) { controller.toggleRecording() }
                }
            }
            if settings.compareMode {
                InlineNotice(icon: "rectangle.split.2x1", text: "Compare mode is on. Transcripts appear in Engine comparison and are not typed into other apps.") {
                    ActionButton(title: "Use dictation", emphasis: .normal) { settings.compareMode = false }
                }
            }
            if let message = controller.lastError {
                InlineNotice(icon: "exclamationmark.triangle", text: message) {
                    ActionButton(title: "Reset", emphasis: .quiet) { controller.forceReset() }
                }
            }
            HStack(spacing: DS.Space.xxl) {
                DictationStat(value: String(store.runs.count), label: "Dictations")
                DictationStat(value: String(store.runs.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count }), label: "Words captured")
                Spacer()
                VStack(alignment: .trailing, spacing: DS.Space.xs) {
                    Text("Hold " + settings.triggerSummary + " in any text field").font(DS.Font.bodyEmphasis)
                    Text("Release to insert. Your history stays here.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
            }
            .padding(DS.Space.lg)
            .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.md))
            TranscriptionList()
        }
        .padding(DS.Space.xl)
    }
}

private struct DictationStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Readout(value, font: DS.Font.readoutLarge, color: DS.Color.text)
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        }
    }
}

struct InlineNotice<Actions: View>: View {
    let icon: String
    let text: String
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.md) {
            Image(systemName: icon).foregroundStyle(DS.Color.accent).font(DS.Font.symbol)
            Text(text).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.sm)
            actions
        }
        .padding(DS.Space.md)
        .background(DS.Color.accentSoft, in: .rect(cornerRadius: DS.Radius.md))
    }
}

extension Notification.Name {
    static let murmurNewNote = Notification.Name("com.jasonhunt.murmur.newNote")
    static let murmurShowConnections = Notification.Name("com.jasonhunt.murmur.showConnections")
}

// MARK: - Transcriptions

struct TranscriptionList: View {
    @State private var store = RunStore.shared
    @State private var query = ""
    @State private var isConfirmingClear = false

    private var runs: [DictationRun] {
        let all = store.runs.reversed().map { $0 }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.text.localizedStandardContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                SearchField(text: $query, placeholder: "Search transcriptions")

                Spacer()

                if !store.runs.isEmpty {
                    Text("\(store.runs.count)")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.textTertiary)
                    ActionButton(title: "Clear all", emphasis: .quiet) {
                        isConfirmingClear = true
                    }
                }
            }

            if runs.isEmpty {
                // Deliberately not inside a Card: an empty bordered box the size of the
                // window reads as a broken container rather than an empty list.
                EmptyState(
                    icon: store.runs.isEmpty ? "waveform" : "magnifyingglass",
                    label: store.runs.isEmpty ? "No transcriptions yet" : "No matches",
                    detail: store.runs.isEmpty
                        ? "Hold your push-to-talk key anywhere, or press Record."
                        : "Try a different search."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.sm) {
                        ForEach(runs) { run in
                            TranscriptionRow(run: run) {
                                withAnimation(DS.Motion.spring) { RunLog.delete(run) }
                            }
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .confirmationDialog(
            "Delete all \(store.runs.count) transcriptions?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { RunLog.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

private struct TranscriptionRow: View {
    let run: DictationRun
    let onDelete: () -> Void

    @State private var didCopy = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Chip(text: run.engine)
                Text(String(format: "%.2fs", run.processSeconds))
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.textTertiary)

                Spacer()

                Text(run.date, style: .time)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)

                HStack(spacing: DS.Space.xs) {
                    ActionButton(
                        title: didCopy ? "Copied" : "Copy",
                        emphasis: .quiet
                    ) { copy() }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Color.textTertiary)
                            .padding(DS.Space.xs)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this transcription")
                }
                .opacity(isHovering ? 1 : 0)
            }

            Text(run.text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let corrections = run.corrections, !corrections.isEmpty {
                CorrectionBadges(corrections: corrections)
            }
        }
        .padding(DS.Space.lg - 2)
        .background(
            isHovering ? DS.Color.hover : DS.Color.surface,
            in: .rect(cornerRadius: DS.Radius.lg)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline)
        }
        .onHover { isHovering = $0 }
        .animation(DS.Motion.smooth, value: isHovering)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(run.text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            didCopy = false
        }
    }
}

private struct CorrectionBadges: View {
    let corrections: [AppliedCorrection]

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(DS.Color.success)

            ForEach(corrections, id: \.self) { correction in
                HStack(spacing: DS.Space.xs) {
                    Text(correction.from)
                        .strikethrough()
                        .foregroundStyle(DS.Color.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
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
                .padding(.vertical, 3)
                .background(DS.Color.success.opacity(0.10), in: .capsule)
            }
            Spacer()
        }
    }
}
