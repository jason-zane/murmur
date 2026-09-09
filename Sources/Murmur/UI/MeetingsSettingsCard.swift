import AppKit
import SwiftUI

/// Meetings settings: detection, calendar, engine, per-app rules, and the Claude Desktop
/// connection. Cards, like the rest of the settings window. Each card is its own property
/// so the type-checker sees six small views rather than one enormous one.
struct MeetingsSettingsCards: View {
    @State private var settings = MeetingSettings.shared
    @State private var calendarGranted = CalendarService.shared.isAuthorized
    @State private var calendarDenied = CalendarService.shared.isDenied
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded
    @State private var claudeConfigured = ClaudeDesktopIntegration.isConfigured
    @State private var claudeMessage: String?
    @State private var didCopySnippet = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            detectionCard
            calendarCard
            rulesCard
            engineCard
            claudeCard
            audioCard
        }
        .onAppear {
            calendarGranted = CalendarService.shared.isAuthorized
            calendarDenied = CalendarService.shared.isDenied
            parakeetOnDisk = ParakeetModels.isDownloaded
            claudeConfigured = ClaudeDesktopIntegration.isConfigured
        }
    }

    // MARK: - Detection

    private var detectionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Meetings")

                SettingToggleRow(title: "Detect calls automatically", isOn: $settings.detectionEnabled)
                Hint("Murmur notices when an app has two-way audio — a mic in use and sound "
                     + "coming out — and offers to record. Music, Siri and voice memos never qualify.")

                if settings.detectionEnabled {
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
                Text("Offer after")
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
            .frame(width: 90)
        }
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Calendar")

                SettingToggleRow(title: "Name meetings from my calendar", isOn: $settings.calendarEnabled)
                Hint("Reads the Mac's own Calendar — Google, iCloud, Exchange, whatever is signed "
                     + "in — for the event's name and who's in it. Nothing is written back.")

                if settings.calendarEnabled {
                    calendarPermissionRow
                    Divider().padding(.vertical, DS.Space.xs)
                    SettingToggleRow(title: "Start without asking when the calendar agrees",
                                     isOn: $settings.autoStartOnCalendarMatch)
                    Hint("When a known meeting app is on a call and an event is on right now, "
                         + "just start. Otherwise you're asked.")
                }
            }
        }
    }

    private var calendarPermissionRow: some View {
        HStack(spacing: DS.Space.md) {
            StatusDot(color: calendarGranted ? DS.Color.success : DS.Color.warning, isLit: true, size: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text("Calendars")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.text)
                Hint(calendarGranted ? "Granted." : calendarDenied ? "Turned off in System Settings." : "Not asked yet.")
            }
            Spacer()
            if calendarGranted {
                Chip(text: "Granted", tint: DS.Color.success, filled: true)
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
                Hint("Ask is the default. Promote an app to Auto once it's been right a few times.")
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
                     + "using the Accessibility grant Murmur already has. Nothing else is read.")
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

    // MARK: - Claude

    private var claudeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Claude")
                Hint("Claude Desktop can read your meetings through a local connector — a small "
                     + "program inside Murmur that Claude runs on this Mac. Nothing is uploaded; "
                     + "Claude asks it for a transcript the way it would read a file.")

                HStack(spacing: DS.Space.md) {
                    StatusDot(color: claudeConfigured ? DS.Color.success : DS.Color.textTertiary, isLit: true, size: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(claudeConfigured ? "Connected to Claude Desktop" : "Not connected")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.text)
                        Hint(claudeMessage ?? (claudeConfigured
                             ? "Restart Claude Desktop if it doesn't see Murmur yet."
                             : "Adds Murmur to Claude Desktop's connector list."))
                    }
                    Spacer()
                    if claudeConfigured {
                        Chip(text: "Connected", tint: DS.Color.success, filled: true)
                    } else {
                        ActionButton(title: "Connect…", emphasis: .prominent) { connectClaude() }
                    }
                }

                HStack(spacing: DS.Space.sm) {
                    ActionButton(title: didCopySnippet ? "Copied" : "Copy config", emphasis: .quiet) { copySnippet() }
                    Hint("For ChatGPT, Cursor or any other MCP client.")
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System audio")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.text)
                        Hint("macOS asks the first time a meeting starts. If the call side of the "
                             + "meter stays hollow, it was declined — turn it on here.")
                    }
                    Spacer()
                    ActionButton(title: "Open Settings…", emphasis: .normal) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                    }
                }
                Divider().padding(.vertical, DS.Space.xs)
                Hint("Audio is discarded once it's transcribed. Only text is kept — "
                     + "in ~/Library/Application Support/Murmur/sessions.")
            }
        }
    }

    // MARK: - Actions

    private func copySnippet() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ClaudeDesktopIntegration.snippet, forType: .string)
        didCopySnippet = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            didCopySnippet = false
        }
    }

    private func connectClaude() {
        let alert = NSAlert()
        alert.messageText = "Add Murmur to Claude Desktop?"
        alert.informativeText = "This edits Claude Desktop's connector list at\n\(ClaudeDesktopIntegration.configURL.path)\n\nExisting connectors are kept. Claude Desktop needs a restart afterwards."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try ClaudeDesktopIntegration.configure()
            claudeConfigured = true
            claudeMessage = "Added. Restart Claude Desktop to finish."
        } catch {
            claudeMessage = error.localizedDescription
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
                get: { settings.rule(for: app.bundleID) },
                set: { settings.setRule($0, for: app.bundleID) }
            )) {
                ForEach(MeetingAppRule.allCases, id: \.self) { rule in
                    Text(rule.displayName).tag(rule)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
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

/// Wires murmur-mcp into Claude Desktop's config, keeping whatever is already there.
enum ClaudeDesktopIntegration {
    static var configURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("claude_desktop_config.json")
    }

    /// The helper inside the running bundle. Stable as long as the app lives in /Applications.
    static var serverPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/murmur-mcp").path
    }

    static var isConfigured: Bool {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else { return false }
        return servers["murmur"] != nil
    }

    static var snippet: String {
        """
        {
          "mcpServers": {
            "murmur": {
              "command": "\(serverPath)"
            }
          }
        }
        """
    }

    static func configure() throws {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }
        var servers = json["mcpServers"] as? [String: Any] ?? [:]
        servers["murmur"] = ["command": serverPath]
        json["mcpServers"] = servers
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
    }
}
