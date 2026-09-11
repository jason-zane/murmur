import AppKit
import SwiftUI
import MurmurSessions

/// Meeting capture, calendar, speech models and per-app overrides.
struct MeetingsSettingsCards: View {
    @State private var settings = MeetingSettings.shared
    @State private var calendarGranted = CalendarService.shared.isAuthorized
    @State private var calendarDenied = CalendarService.shared.isDenied
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded
    @State private var audioGranted = SystemAudioCapture.isKnownGranted
    @State private var models = ModelLibrary.shared
    @State private var isAskingAudio = false
    private var hasCalendar: Bool { calendarGranted || CloudSync.shared.calendarConnected }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            detectionCard
            calendarCard
            rulesCard
            engineCard
            modelsCard
            audioCard
        }
        .onAppear {
            calendarGranted = CalendarService.shared.isAuthorized
            calendarDenied = CalendarService.shared.isDenied
            parakeetOnDisk = ParakeetModels.isDownloaded
            audioGranted = SystemAudioCapture.isKnownGranted
        }
    }

    // MARK: - Detection

    private var detectionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Meetings")

                SettingToggleRow(title: "Detect calls automatically", isOn: $settings.detectionEnabled)
                Hint("Voice Notes notices when an app has two-way audio — a mic in use and sound "
                     + "coming out — and offers to record. Music, Siri and voice memos never qualify.")

                if settings.detectionEnabled {
                    SettingToggleRow(title: "Start notes when I enter a known meeting", isOn: $settings.autoRecordKnownCalls)
                    Hint("Starts after a sustained call in Meet, Zoom, Teams and other recognized apps. An explicit per-app Ask or Never rule takes priority.")
                    Divider().padding(.vertical, DS.Space.xs)
                    offerDelayRow
                    Divider().padding(.vertical, DS.Space.xs)
                    autoStopRow
                }
            }
        }
    }

    private var offerDelayRow: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Text("Confirm a call after")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.text)
                Spacer()
                Readout("\(Int(settings.offerDelay)) s", color: DS.Color.textSecondary)
            }
            Slider(value: $settings.offerDelay, in: 3...60, step: 1)
                .controlSize(.small)
            Hint("How long a call must be running before anything appears. "
                 + "A call you decline never becomes a session.")
        }
    }

    private var autoStopRow: some View {
        HStack {
            Text("End the recording after the call ends")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
            Spacer()
            Picker("", selection: $settings.autoStopAfter) {
                Text("30 s").tag(30.0)
                Text("1 min").tag(60.0)
                Text("2 min").tag(120.0)
            }
            .labelsHidden()
            .frame(width: DS.Layout.smallPicker)
        }
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Calendar")

                SettingToggleRow(title: "Name meetings from my calendar", isOn: $settings.calendarEnabled)
                SettingToggleRow(title: "Open scheduled meeting links automatically", isOn: $settings.autoOpenMeetings)
                    .disabled(!settings.calendarEnabled)
                Hint("Opens supported meeting links a minute before the start. Google Meet opens in Chrome. Recording starts only when the call is detected. Skip a meeting from Up next.")
                Hint("Uses Google Calendar connected through Voice Notes, or calendars on this Mac, to find meeting names, people and links. Nothing is written back.")
                SettingToggleRow(title: "Keep booking links clear of events on this Mac", isOn: $settings.shareBusyTimes)
                Hint("For Voice Notes booking links. Shares only when you’re busy on this Mac, never titles, people or places, so guests can’t book over those times. Turn off to remove them.")

                if settings.calendarEnabled {
                    calendarPermissionRow
                    Divider().padding(.vertical, DS.Space.xs)
                    SettingToggleRow(title: "Start without asking when the calendar agrees",
                                     isOn: $settings.autoStartOnCalendarMatch)
                    Hint("Also allows a matching calendar event to start capture when automatic capture of known calls is off. Per-app rules still take priority.")
                }
            }
        }
    }

    private var calendarPermissionRow: some View {
        HStack(spacing: DS.Space.md) {
            StatusDot(color: hasCalendar ? DS.Color.success : DS.Color.warning, isLit: true, size: DS.Layout.permissionDot)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Calendars")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.text)
                Hint(CloudSync.shared.calendarConnected ? "Google Calendar is connected to Voice Notes." : calendarGranted ? "Calendars on this Mac are available." : calendarDenied ? "Mac access is off. Connect Google in Connections, or allow Calendar access here." : "Connect Google in Connections, or allow calendars on this Mac.")
            }
            Spacer()
            if hasCalendar {
                Chip(text: "Connected", tint: DS.Color.success, filled: true)
            } else if calendarDenied {
                ActionButton(title: "Open Settings…", emphasis: .normal) { CalendarService.openSettings() }
            } else {
                ActionButton(title: "Grant…", emphasis: .normal) {
                    Task {
                        calendarGranted = await CalendarService.shared.requestAccess()
                        calendarDenied = CalendarService.shared.isDenied
                    }
                }
            }
        }
    }

    // MARK: - Rules

    private var rulesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Per-app rules")
                Hint("Default follows the automatic capture settings above. Choose Ask, Auto or Never to override them for one app.")
                VStack(spacing: DS.Space.xs) {
                    ForEach(MeetingAppRegistry.apps.filter { $0.kind == .native }) { app in
                        AppRuleRow(app: app, settings: settings)
                    }
                    Divider().padding(.vertical, DS.Space.xs)
                    ForEach(MeetingAppRegistry.apps.filter { $0.kind == .browser }) { app in
                        AppRuleRow(app: app, settings: settings)
                    }
                }
                Hint("Browser calls are named from the window title — “Meet – …”, “Zoom Meeting” — "
                     + "using the Accessibility grant Voice Notes already has. Nothing else is read.")
            }
        }
    }

    // MARK: - Engine

    private var engineCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Meeting transcription")

                Segmented(
                    options: SpeechEngineChoice.allCases.map { ($0, $0 == .apple ? "Apple" : "Parakeet") },
                    selection: $settings.engine
                )
                Hint(engineHint)

                Divider().padding(.vertical, DS.Space.xs)

                SettingToggleRow(title: "Show the live transcript in the notepad", isOn: $settings.showLiveTranscript)
                Hint("Off by default: watching text arrive competes with the call. ⌘T toggles it any time.")
                SettingToggleRow(title: "Sound when a recording starts and stops", isOn: $settings.soundEnabled)
                Divider().padding(.vertical, DS.Space.xs)
                SettingToggleRow(title: "Summarize after each meeting", isOn: $settings.autoSummarize)
                Hint(FoundationModelFormatter.unavailableReason ?? "Uses Apple Intelligence on this Mac. Long meetings are read in parts; your transcript and personal notes are kept.")
                HStack {
                    Text("Default note template").font(DS.Font.body)
                    Spacer()
                    Picker("Template", selection: $settings.defaultTemplate) {
                        ForEach(SummaryTemplate.allCases) { template in Text(template.title).tag(template) }
                    }.labelsHidden().frame(width: DS.Layout.templatePicker)
                }
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
            : "Parakeet isn't downloaded. Meetings will use Apple until it is — download it from "
              + "the menu bar item."
    }

    // MARK: - Models

    private var modelsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "On-device models")
                Hint("Optional, and only ever fetched when you press Download. They live in "
                     + "~/Library/Application Support/FluidAudio and run on the Neural Engine.")
                ForEach(ModelKind.allCases) { kind in
                    Divider().padding(.vertical, DS.Space.xs)
                    ModelRow(kind: kind, library: models, onChanged: {
                        parakeetOnDisk = ParakeetModels.isDownloaded
                    })
                }
                if ModelKind.speakers.isDownloaded {
                    Divider().padding(.vertical, DS.Space.xs)
                    SettingToggleRow(title: "Tell speakers apart on the call side", isOn: $settings.speakerSeparation)
                    Hint("Lines from the call are labelled Speaker 1, Speaker 2… as they arrive; "
                         + "rename them in the meeting afterwards. Your side is always You.")
                }
            }
        }
    }

    // MARK: - Audio

    private var audioCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Audio recording")
                HStack(spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("System audio")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.text)
                        Hint(audioGranted
                             ? "Granted. The call side of the meter is live during meetings."
                             : "Needed to hear the other side of a call. If the call side of the "
                               + "meter stays hollow during a meeting, it was declined — turn it on here.")
                    }
                    Spacer()
                    if audioGranted {
                        Chip(text: "Granted", tint: DS.Color.success, filled: true)
                    } else {
                        ActionButton(title: isAskingAudio ? "Asking…" : "Allow…", emphasis: .prominent) {
                            guard !isAskingAudio else { return }
                            isAskingAudio = true
                            Task {
                                audioGranted = await SystemAudioCapture.requestPermission()
                                isAskingAudio = false
                            }
                        }
                        ActionButton(title: "Open Settings…", emphasis: .quiet) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                        }
                    }
                }
                Divider().padding(.vertical, DS.Space.xs)
                Hint("Audio is discarded once it's transcribed. Only text is kept — "
                     + "in ~/Library/Application Support/Murmur/sessions.")
            }
        }
    }


}

private struct AppRuleRow: View {
    let app: MeetingApp
    let settings: MeetingSettings

    var body: some View {
        HStack {
            Text(app.label)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
            Spacer()
            Picker("", selection: Binding(
                get: { settings.appRules[app.bundleID] },
                set: { settings.setRule($0, for: app.bundleID) }
            )) {
                Text("Default").tag(Optional<MeetingAppRule>.none)
                ForEach(MeetingAppRule.allCases, id: \.self) { rule in
                    Text(rule.displayName).tag(Optional(rule))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: DS.Layout.rulePicker)
        }
    }
}

private struct SettingToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct ModelRow: View {
    let kind: ModelKind
    let library: ModelLibrary
    let onChanged: () -> Void

    @State private var onDisk = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            StatusDot(color: onDisk ? DS.Color.success : DS.Color.textTertiary, isLit: true, size: DS.Layout.permissionDot)
                .padding(.top, DS.Space.compact)
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                HStack(spacing: DS.Space.sm) {
                    Text(kind.title)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.text)
                    Readout(kind.sizeHint, color: DS.Color.textTertiary)
                }
                Hint(kind.detail)
                if let progress = library.progress[kind] {
                    ProgressView(value: progress)
                        .controlSize(.small)
                        .tint(DS.Color.accent)
                        .frame(maxWidth: DS.Layout.modelProgress)
                        .padding(.top, DS.Space.xxs)
                }
                if let error = library.errors[kind] {
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if onDisk {
                Chip(text: "Installed", tint: DS.Color.success, filled: true)
            } else if library.isDownloading(kind) {
                ActionButton(title: "Downloading…", emphasis: .quiet) {}.disabled(true)
            } else {
                ActionButton(title: "Download", emphasis: .normal) { library.download(kind) }
            }
        }
        .onAppear { onDisk = kind.isDownloaded }
        .onChange(of: library.progress[kind]) { _, progress in
            if progress == nil {
                onDisk = kind.isDownloaded
                onChanged()
            }
        }
    }
}
