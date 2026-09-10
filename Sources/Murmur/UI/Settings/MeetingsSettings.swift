import AppKit
import MurmurSessions
import SwiftUI

/// When a meeting is recorded, what the calendar adds, the per-app exceptions, and how
/// the transcript becomes a note.
struct MeetingsSettings: View {
    @State private var settings = MeetingSettings.shared
    @State private var calendarGranted = CalendarService.shared.isAuthorized
    @State private var calendarDenied = CalendarService.shared.isDenied
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded
    @State private var audioGranted = SystemAudioCapture.isKnownGranted
    @State private var isAskingAudio = false
    private var hasCalendar: Bool { calendarGranted || CloudSync.shared.calendarConnected }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            meetings
            calendar
            rules
            transcription
        }
        .onAppear { refresh() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: DS.Timing.permissionPoll) } catch { return }
                refresh()
            }
        }
    }

    private func refresh() {
        calendarGranted = CalendarService.shared.isAuthorized
        calendarDenied = CalendarService.shared.isDenied
        parakeetOnDisk = ParakeetModels.isDownloaded
        audioGranted = SystemAudioCapture.isKnownGranted
    }

    // MARK: - Meetings

    private var meetings: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Meetings")
                ToggleRow(
                    title: "Detect calls automatically",
                    hint: "Voice Notes notices when an app has two-way audio — a mic in use and sound "
                        + "coming out — and offers to record. Music, Siri and voice memos never qualify.",
                    isOn: $settings.detectionEnabled
                )
                if settings.detectionEnabled {
                    ToggleRow(
                        title: "Start recording when I enter a known meeting",
                        hint: "Starts after a sustained call in Meet, Zoom, Teams and other recognised apps. "
                            + "A per-app rule below takes priority.",
                        isOn: $settings.autoRecordKnownCalls
                    )
                    Divider().padding(.vertical, DS.Space.xs)
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        HStack {
                            Text("Confirm a call after").font(DS.Font.body).foregroundStyle(DS.Color.text)
                            Spacer()
                            Readout("\(Int(settings.offerDelay)) s", color: DS.Color.textSecondary)
                        }
                        Slider(value: $settings.offerDelay, in: DS.Meetings.offerDelayRange, step: 1)
                            .controlSize(.small)
                        Hint("How long a call must be running before anything appears. "
                             + "A call you decline never becomes a note.")
                    }
                    Divider().padding(.vertical, DS.Space.xs)
                    PickerRow(
                        title: "End the recording after the call ends",
                        selection: $settings.autoStopAfter,
                        options: [(30.0, "30 s"), (60.0, "1 min"), (120.0, "2 min")]
                    )
                }
            }
        }
    }

    // MARK: - Calendar

    private var calendar: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Calendar")
                ToggleRow(
                    title: "Name meetings from my calendar",
                    hint: "Uses Google Calendar connected through Voice Notes, or the calendars on this Mac, "
                        + "to find meeting names, people and links. Nothing is written back.",
                    isOn: $settings.calendarEnabled
                )
                ToggleRow(
                    title: "Open scheduled meeting links automatically",
                    hint: "A minute before the start. Google Meet opens in Chrome. Recording starts only "
                        + "when the call is detected; skip a meeting from Up next.",
                    isOn: $settings.autoOpenMeetings,
                    isEnabled: settings.calendarEnabled
                )
                if settings.calendarEnabled {
                    Divider().padding(.vertical, DS.Space.xs)
                    PermissionRow(
                        title: "Calendars",
                        detail: CloudSync.shared.calendarConnected ? "Google Calendar is connected to Voice Notes."
                            : calendarGranted ? "Calendars on this Mac are available."
                            : calendarDenied ? "Mac access is off. Connect Google in Connections, or allow Calendar access."
                            : "Connect Google in Connections, or allow calendars on this Mac.",
                        isGranted: hasCalendar
                    ) {
                        if calendarDenied { CalendarService.openSettings() }
                        else { Task { calendarGranted = await CalendarService.shared.requestAccess(); calendarDenied = CalendarService.shared.isDenied } }
                    }
                    Divider().padding(.vertical, DS.Space.xs)
                    ToggleRow(
                        title: "Start without asking when the calendar agrees",
                        hint: "A matching calendar event can start recording even when automatic recording of "
                            + "known calls is off. Per-app rules still take priority.",
                        isOn: $settings.autoStartOnCalendarMatch
                    )
                }
            }
        }
    }

    // MARK: - Rules

    private var rules: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Per-app rules")
                AppRulesList()
                Hint("Browser calls are named from the window title — “Meet – …”, “Zoom Meeting” — "
                     + "using the Accessibility grant Voice Notes already has. Nothing else is read.")
            }
        }
    }

    // MARK: - Transcription & notes

    private var transcription: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Transcription & notes")
                EngineRow(selection: $settings.engine, hint: engineHint)
                if ModelKind.speakers.isDownloaded {
                    ToggleRow(
                        title: "Tell speakers apart on the call side",
                        hint: "Lines from the call are labelled Speaker 1, Speaker 2… as they arrive; "
                            + "rename them in the note afterwards. Your side is always You.",
                        isOn: $settings.speakerSeparation
                    )
                }

                Divider().padding(.vertical, DS.Space.xs)

                ToggleRow(
                    title: "Show the live transcript in the notes window",
                    hint: "Off by default: watching text arrive competes with the call. ⌘T toggles it any time.",
                    isOn: $settings.showLiveTranscript
                )
                ToggleRow(
                    title: "Summarise after each meeting",
                    hint: FoundationModelFormatter.unavailableReason
                        ?? "Uses Apple Intelligence on this Mac. Long meetings are read in parts; your "
                         + "transcript and personal notes are kept.",
                    isOn: $settings.autoSummarize
                )
                PickerRow(
                    title: "Default note template",
                    selection: $settings.defaultTemplate,
                    options: SummaryTemplate.allCases.map { ($0, $0.title) }
                )

                Divider().padding(.vertical, DS.Space.xs)

                PermissionRow(
                    title: "Audio recording",
                    detail: audioGranted
                        ? "Granted. The call side is heard during meetings."
                        : "Needed to hear the other side of a call. Without it, only your side is recorded.",
                    isGranted: audioGranted,
                    grantTitle: isAskingAudio ? "Asking…" : "Allow…"
                ) {
                    guard !isAskingAudio else { return }
                    isAskingAudio = true
                    Task {
                        audioGranted = await SystemAudioCapture.requestPermission()
                        isAskingAudio = false
                        if !audioGranted {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                        }
                    }
                }
                Hint("Audio is discarded once it's transcribed. Only text is kept — "
                     + "in ~/Library/Application Support/Murmur/sessions.")
            }
        }
    }

    private var engineHint: String {
        if settings.engine == .apple {
            return "Apple's on-device transcriber. Streams, needs no download, and keeps time — "
                + "every line knows when in the meeting it was said."
        }
        return parakeetOnDisk
            ? "Parakeet on the Neural Engine, in windows cut at pauses. More accurate on English; "
              + "text arrives a sentence or two behind."
            : "Parakeet isn't downloaded. Meetings use Apple until it is."
    }
}

/// Only the apps with an explicit rule, plus a way to add one. Seventeen segmented controls
/// said "Default" sixteen times; this says it once.
struct AppRulesList: View {
    @State private var settings = MeetingSettings.shared

    /// Apps by label: Teams ships under two bundle identifiers and should read as one app.
    private var groups: [(label: String, ids: [String], kind: MeetingApp.Kind)] {
        var seen: [String: Int] = [:]
        var result: [(label: String, ids: [String], kind: MeetingApp.Kind)] = []
        for app in MeetingAppRegistry.apps {
            if let index = seen[app.label] {
                result[index].ids.append(app.bundleID)
            } else {
                seen[app.label] = result.count
                result.append((app.label, [app.bundleID], app.kind))
            }
        }
        return result
    }

    private func rule(for ids: [String]) -> MeetingAppRule? {
        ids.compactMap { settings.appRules[$0] }.first
    }

    private func set(_ rule: MeetingAppRule?, for ids: [String]) {
        for id in ids { settings.setRule(rule, for: id) }
    }

    var body: some View {
        let ruled = groups.filter { rule(for: $0.ids) != nil }
        let unruled = groups.filter { rule(for: $0.ids) == nil }
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if ruled.isEmpty {
                Hint("All apps follow the settings above.")
            }
            ForEach(ruled, id: \.label) { group in
                HStack(spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(group.label).font(DS.Font.body).foregroundStyle(DS.Color.text)
                        if group.kind == .browser { Hint("Browser") }
                    }
                    Spacer()
                    Menu(rule(for: group.ids)?.displayName ?? "") {
                        ForEach(MeetingAppRule.allCases, id: \.self) { option in
                            Button(option.displayName) { set(option, for: group.ids) }
                        }
                        Divider()
                        Button("Remove rule") { set(nil, for: group.ids) }
                    }
                    .fixedSize()
                }
            }
            if !unruled.isEmpty {
                Menu("Add rule…") {
                    ForEach(unruled, id: \.label) { group in
                        Menu(group.label) {
                            ForEach(MeetingAppRule.allCases, id: \.self) { option in
                                Button(option.displayName) { set(option, for: group.ids) }
                            }
                        }
                    }
                }
                .fixedSize()
                .padding(.top, DS.Space.xs)
            }
        }
    }
}
