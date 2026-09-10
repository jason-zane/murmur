import AppKit
import MurmurSessions
import SwiftUI

/// Start at login, sounds, the on-device models both engines use, every permission, and
/// which version this is.
struct GeneralSettings: View {
    @State private var settings = Settings.shared
    @State private var meetingSettings = MeetingSettings.shared
    @State private var models = ModelLibrary.shared
    @State private var updates = UpdateCheck.shared
    @State private var accessibility = Permissions.hasAccessibility
    @State private var microphone = Permissions.hasMicrophone
    @State private var audioCapture = SystemAudioCapture.isKnownGranted
    @State private var calendar = CalendarService.shared.isAuthorized
    @State private var calendarDenied = CalendarService.shared.isDenied

    /// One switch for both sounds. They were two settings for no reason a user would care about.
    private var sounds: Binding<Bool> {
        Binding(
            get: { settings.soundEnabled },
            set: { settings.soundEnabled = $0; meetingSettings.soundEnabled = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Card {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    SectionLabel(text: "General")
                    ToggleRow(
                        title: "Start Voice Notes at login",
                        hint: "The push-to-talk key and call detection only work while Voice Notes is running.",
                        isOn: $settings.launchAtLogin
                    )
                    if LoginItem.state == .requiresApproval {
                        InlineNotice(text: "Needs approval in System Settings ▸ General ▸ Login Items.", tone: .warning) {
                            ActionButton(title: "Open", emphasis: .quiet) { LoginItem.openLoginItemsSettings() }
                        }
                    }
                    Divider().padding(.vertical, DS.Space.xs)
                    ToggleRow(
                        title: "Sounds",
                        hint: "A short tone when a dictation or a recording starts and stops.",
                        isOn: sounds
                    )
                }
            }

            Card {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    SectionLabel(text: "On-device models")
                    Hint("Optional, and only ever fetched when you press Download. They live in "
                         + "~/Library/Application Support/FluidAudio and run on the Neural Engine.")
                    ForEach(ModelKind.allCases) { kind in
                        Divider().padding(.vertical, DS.Space.xs)
                        ModelRow(kind: kind, library: models, onChanged: {})
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    SectionLabel(text: "Permissions")
                    PermissionRow(
                        title: "Accessibility",
                        detail: "Sees the key you hold and inserts text where you're typing.",
                        isGranted: accessibility,
                        action: Permissions.openAccessibilitySettings
                    )
                    PermissionRow(
                        title: "Microphone",
                        detail: "Your side of every dictation and every call.",
                        isGranted: microphone
                    ) {
                        Task {
                            microphone = await Permissions.requestMicrophone()
                            if !microphone { Permissions.openMicrophoneSettings() }
                        }
                    }
                    PermissionRow(
                        title: "Audio recording",
                        detail: "The other side of a call — the audio your Mac is playing.",
                        isGranted: audioCapture
                    ) {
                        Task {
                            audioCapture = await SystemAudioCapture.requestPermission()
                            if !audioCapture {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                            }
                        }
                    }
                    PermissionRow(
                        title: "Calendars",
                        detail: "Names meetings after the event and knows who's in them. Read-only.",
                        isGranted: calendar
                    ) {
                        if calendarDenied { CalendarService.openSettings() }
                        else { Task { calendar = await CalendarService.shared.requestAccess() } }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    SectionLabel(text: "About")
                    HStack(spacing: DS.Space.md) {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("Voice Notes " + Self.version).font(DS.Font.body).foregroundStyle(DS.Color.text)
                            Hint(updates.lastChecked.map { "Checked for updates " + $0.formatted(.relative(presentation: .named)) + "." }
                                 ?? "Not checked for updates yet.")
                        }
                        Spacer()
                        ActionButton(title: updates.isChecking ? "Checking…" : "Check now", emphasis: .quiet) {
                            Task { await updates.check() }
                        }
                        .disabled(updates.isChecking || UpdateCheck.currentVersion == nil)
                    }
                    if let release = updates.available {
                        InlineNotice(icon: "arrow.down.circle", text: "Update available · \(release.version)") {
                            ActionButton(title: "Download", emphasis: .prominent) { updates.open(release) }
                        }
                    } else if let error = updates.lastError {
                        Hint(error)
                    }
                    ToggleRow(
                        title: "Check for updates automatically",
                        hint: "Once a day, from the project's GitHub releases. Nothing about you is sent.",
                        isOn: $settings.checkForUpdates
                    )
                    Divider().padding(.vertical, DS.Space.xs)
                    HStack(spacing: DS.Space.md) {
                        Hint("Your notes are ordinary files in ~/Library/Application Support/Murmur.")
                        Spacer()
                        ActionButton(title: "Notes folder", systemImage: "folder", emphasis: .quiet) {
                            NSWorkspace.shared.open(SessionStore.defaultRoot)
                        }
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                accessibility = Permissions.hasAccessibility
                microphone = Permissions.hasMicrophone
                audioCapture = SystemAudioCapture.isKnownGranted
                calendar = CalendarService.shared.isAuthorized
                calendarDenied = CalendarService.shared.isDenied
                do { try await Task.sleep(for: DS.Timing.permissionPoll) } catch { return }
            }
        }
    }

    /// "0.5.0 (123)" from the bundle, stamped at build time.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}
