import AppKit
import Combine
import MurmurSessions
import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The main window. A `Window` rather than a `WindowGroup`: this app has one front
        // workspace. ⌘N creates a note rather than another copy of the window.
        Window("Voice Notes", id: "main") {
            MainWindow(controller: delegate.controller, meetings: delegate.meetings,
                       onToggleMeeting: delegate.toggleMeeting, onRecordCalendar: delegate.recordCalendarMeeting, onShowNotepad: delegate.showNotepad, onPreviewBar: delegate.previewDictationBar)
        }
        .defaultSize(width: DS.Layout.windowWidth, height: DS.Layout.windowHeight)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New note") { NotificationCenter.default.post(name: .murmurNewNote, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Record meeting") { delegate.toggleMeeting() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Find in notes") { NotificationCenter.default.post(name: .murmurFind, object: nil) }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }

        // Fully qualified: this app has its own `Settings` type, which otherwise shadows
        // SwiftUI's settings scene.
        SwiftUI.Settings {
            SettingsWindow(controller: delegate.controller, onPreviewBar: delegate.previewDictationBar)
        }
        .defaultSize(width: DS.Layout.settingsWidth, height: DS.Layout.settingsHeight)
        .windowResizability(.contentMinSize)

        // Secondary now: status and the hotkey while you're working in another app.
        MenuBarExtra {
            MenuContent(controller: delegate.controller, meetings: delegate.meetings,
                        detector: delegate.detector, delegate: delegate)
        } label: {
            StatusLabel(controller: delegate.controller, meetings: delegate.meetings)
        }

        // The benchmark lab. The scene has to exist unconditionally (SceneBuilder can't
        // type-check an `if` here), but nothing reaches it without the developer switch:
        // the Developer menu, the `murmur://show` host and the launch-time restore are gated.
        Window("Engine comparison", id: "comparison") {
            ComparisonWindow(controller: delegate.controller)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    let meetings = MeetingController()
    let detector = MeetingDetector()
    private var hud: HUDPanel?
    private var notepad: NotepadWindow?
    private var offerStrip: OfferStrip?
    private var onboarding: OnboardingWindow?
    private var stateObservation: NSObjectProtocol?

    func previewDictationBar() { hud?.preview() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A regular app now: dock icon, app menu, standard windows. The HUD is still a
        // non-activating panel, so dictating into another app never steals its focus — that
        // property belongs to the panel, not to the activation policy.
        NSApp.setActivationPolicy(.regular)

        hud = HUDPanel(controller: controller)
        notepad = NotepadWindow(controller: meetings) { [weak self] in self?.toggleMeeting() }
        offerStrip = OfferStrip(detector: detector) { [weak self] candidate in
            self?.startMeeting(from: candidate)
        }
        if PreviewEnvironment.isActive {
            if let action = PreviewEnvironment.launchAction {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    if action.hasPrefix("settings") {
                        NotificationCenter.default.post(name: .murmurOpenSettings, object: nil)
                    } else if action == "onboarding" {
                        showOnboarding()
                    } else if action.hasPrefix("session:") {
                        NotificationCenter.default.post(name: .murmurShowSession, object: String(action.dropFirst("session:".count)))
                    } else if action == "dictation" {
                        NotificationCenter.default.post(name: .murmurShowDictation, object: nil)
                    }
                }
            }
            return
        }
        wireMeetings()
        MeetingSchedule.shared.start()
        CloudSync.shared.start()
        UpdateCheck.shared.start()

        if !OnboardingWindow.isCompleted {
            showOnboarding()
        }

        Permissions.rememberTrusted()
        if !controller.activate() {
            Permissions.promptForAccessibility()
            // The tap can only be created once the user grants Accessibility, and there's
            // no notification for that — poll until it takes.
            retryActivation()
        }

        // Developer mode keeps an HTML dashboard beside the run log; otherwise this removes
        // one an earlier build may have left behind.
        RunLog.regenerate()

        // Parakeet's models take ~20s to load from disk, and that cost lands on whichever
        // dictation touches them first — so the first hold after every launch would stall
        // with the HUD showing nothing. Warm them in the background instead, but only when
        // they're actually going to be used and are already downloaded.
        let willUseParakeet = Settings.shared.compareMode || Settings.shared.engine == .parakeet
        if willUseParakeet, ParakeetModels.isDownloaded {
            Task.detached(priority: .utility) {
                _ = try? await ParakeetModels.shared.manager()
            }
        }

        // Every `make install` relaunches the app and drops its windows. Restoring the
        // window when it was open last time keeps it from vanishing on each rebuild.
        if Settings.shared.developerMode, UserDefaults.standard.bool(forKey: "comparisonWindowOpen") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                Self.showComparisonWindow()
            }
        }

        observeState()
        observeMeetingState()
        if Settings.shared.developerMode { Log.app.info("developer mode on") }
        Log.app.info("Murmur ready — hold \(Settings.shared.triggerSummary) to dictate")
    }

    // MARK: - Meetings

    private func wireMeetings() {
        detector.onDecision = { [weak self] decision in
            guard let self else { return }
            switch decision {
            case .autoStart(let candidate):
                self.startMeeting(from: candidate)
            case .offer(_, let quiet):
                if !quiet { self.offerStrip?.present() }
            }
        }
        detector.onCallEnded = { [weak self] in
            self?.meetings.stop()
        }
        detector.start()
    }

    /// From a detection — the candidate's app and calendar event name the session.
    func startMeeting(from candidate: MeetingCandidate) {
        guard meetings.state == .idle else { return }
        offerStrip?.dismiss()
        detector.dismissOffer()
        meetings.start(.init(
            title: candidate.calendarEvent?.title,
            app: candidate.label,
            bundleID: candidate.bundleID,
            calendarEvent: candidate.calendarEvent
        ))
        notepad?.present(activate: false)
    }

    /// From the Record button or menu — whatever the calendar knows, and nothing else.
    func toggleMeeting() {
        if meetings.state.isActive {
            meetings.stop()
        } else {
            guard meetings.state == .idle else { return }
            offerStrip?.dismiss()
            detector.dismissOffer()
            let event = MeetingSettings.shared.calendarEnabled ? CalendarService.shared.bestMatch() : nil
            let candidate = detector.candidate
            meetings.start(.init(
                title: event?.title,
                app: candidate?.label,
                bundleID: candidate?.bundleID,
                calendarEvent: event
            ))
            notepad?.present(activate: true)
        }
    }

    func showNotepad() {
        notepad?.present(activate: true)
    }

    func recordCalendarMeeting(_ event: CalendarEvent) {
        guard meetings.state == .idle else { return }
        offerStrip?.dismiss()
        detector.dismissOffer()
        meetings.start(.init(title: event.title, calendarEvent: event))
        notepad?.present(activate: true)
    }

    func showOnboarding() {
        if onboarding == nil { onboarding = OnboardingWindow() }
        onboarding?.present()
    }

    private func observeMeetingState() {
        withObservationTracking {
            _ = meetings.state
            _ = meetings.lastFinishedSessionID
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeMeetingState()
                if self.meetings.state == .finalising { self.detector.suppressCurrentCall() }
                self.detector.captureIsBusy = self.meetings.state != .idle
                self.detector.recordingBundleID = self.meetings.isRecording ? self.meetings.session?.bundleID : nil
                MeetingSchedule.shared.captureIsBusy = self.meetings.state != .idle
                switch self.meetings.state {
                case .recording:
                    break
                case .idle:
                    self.detector.recordingBundleID = nil
                    if let finished = self.meetings.lastFinishedSessionID, self.notepad?.isVisible == true {
                        // Leave the notepad up for a beat so "Saved" registers, then hand off
                        // to the Library with the new session selected.
                        try? await Task.sleep(for: .milliseconds(900))
                        guard self.meetings.state == .idle else { return }
                        self.notepad?.dismiss()
                        NotificationCenter.default.post(name: .murmurShowSession, object: finished)
                    }
                default:
                    break
                }
            }
        }
    }

    /// `murmur://toggle`, `murmur://meeting`, `murmur://notes` and friends. `clear` and
    /// `show` belong to the developer dashboard and do nothing without the switch.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "murmur" {
            switch url.host {
            case "clear" where Settings.shared.developerMode:
                RunLog.clear()
                RunStore.shared.reload()
            case "show" where Settings.shared.developerMode:
                Self.showComparisonWindow()
            case "toggle":
                // Scriptable equivalent of pressing the trigger. Useful for binding Murmur
                // to anything that can open a URL — Shortcuts, Stream Deck, Karabiner, a
                // mouse-button utility — and for exercising the start/stop path without a
                // physical key.
                controller.toggleRecording()
            case "meeting":
                toggleMeeting()
            case "notes":
                showNotepad()
            case "sessions":
                let id = url.lastPathComponent
                if SessionStore.isValidID(id), meetings.store.session(id: id) != nil {
                    NotificationCenter.default.post(name: .murmurShowSession, object: id)
                }
            case "dictation":
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .murmurShowDictation, object: nil)
            case "connections", "cloud":
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .murmurOpenSettings, object: "connections")
            case "setup":
                showOnboarding()
            case "paste":
                controller.pasteLastDictation()
            case "reset":
                controller.forceReset()
            case "settings":
                // The Settings scene can only be opened through SwiftUI's `openSettings`
                // action (the private selector is rejected with a runtime fault). That
                // action lives in a view's environment, so hand off to `StatusLabel`.
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .murmurOpenSettings, object: nil)
            default:
                break
            }
        }
    }

    /// Raises the comparison window without needing SwiftUI's `openWindow` environment
    /// value — usable from the app delegate and from a URL handler.
    static func showComparisonWindow() {
        RunStore.shared.reload()
        if let existing = NSApp.windows.first(where: { $0.title == "Engine comparison" }) {
            existing.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard meetings.state != .idle else { return .terminateNow }
        if meetings.state == .saveFailed { showNotepad(); return .terminateCancel }
        if meetings.state.isActive { meetings.stop() }
        Task { @MainActor in
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while meetings.state != .idle, meetings.state != .saveFailed, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if meetings.state != .idle { showNotepad() }
            sender.reply(toApplicationShouldTerminate: meetings.state == .idle)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        let isOpen = NSApp.windows.contains { $0.title == "Engine comparison" && $0.isVisible }
        UserDefaults.standard.set(isOpen, forKey: "comparisonWindowOpen")
        controller.deactivate()
        detector.stop()
        MeetingSchedule.shared.stop()
    }

    /// Shows and hides the HUD in step with the controller's state.
    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.state.isActive {
                    self.hud?.present()
                } else {
                    self.hud?.dismiss()
                }
                self.observeState()
            }
        }
    }

    private func retryActivation() {
        Task { @MainActor in
            while !Permissions.hasAccessibility {
                try? await Task.sleep(for: .seconds(1))
            }
            Permissions.rememberTrusted()
            controller.activate()
            Log.app.info("Accessibility granted — hotkey armed")
        }
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    let meetings: MeetingController
    let detector: MeetingDetector
    unowned let delegate: AppDelegate
    @State private var settings = Settings.shared
    @State private var updates = UpdateCheck.shared
    @Environment(\.openWindow) private var openWindow

    private var recordMeetingTitle: String {
        if let candidate = detector.candidate { return "Record \(candidate.callNoun)…" }
        return "Record meeting"
    }

    /// One switch for both sounds, the same as Settings ▸ General.
    private var sound: Binding<Bool> {
        Binding(
            get: { settings.soundEnabled },
            set: { settings.soundEnabled = $0; MeetingSettings.shared.soundEnabled = $0 }
        )
    }

    /// Short on purpose. Everything that is a setting lives in Settings; the menu holds the
    /// things you reach for from another app, plus three switches worth flipping without
    /// opening a window: sound, start at login and which engine transcribes.
    var body: some View {
        if meetings.state.isActive {
            Button("Stop recording  \(TimeFormat.clock(meetings.elapsed))") { delegate.toggleMeeting() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Show notes") { delegate.showNotepad() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        } else {
            Button(recordMeetingTitle) { delegate.toggleMeeting() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        Divider()

        Button("Paste last dictation") { controller.pasteLastDictation() }
        Text("Hold \(settings.triggerSummary) to dictate")

        Divider()

        Toggle("Sound", isOn: sound)
        Toggle("Start at login", isOn: $settings.launchAtLogin)
        Picker("Transcription", selection: $settings.engine) {
            ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                Text(choice == .parakeet && !ParakeetModels.isDownloaded
                     ? "Parakeet (not downloaded)" : choice.displayName)
                    .tag(choice)
            }
        }

        Divider()

        if !Permissions.hasAccessibility || !Permissions.hasMicrophone {
            Button("Permissions needed…") { delegate.showOnboarding() }
        }

        if let release = updates.available {
            Button("Update available · \(release.version)") { updates.open(release) }
        }

        Button("Open Voice Notes") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",", modifiers: .command)

        if settings.developerMode {
            Menu("Developer") {
                Toggle("Compare mode (both engines)", isOn: $settings.compareMode)
                Button("Engine comparison") {
                    RunStore.shared.reload()
                    openWindow(id: "comparison")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("d")
                if controller.state.isActive {
                    Button("Reset stuck dictation") { controller.forceReset() }
                }
            }
        }

        Button("Quit Voice Notes") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// The menu bar icon.
///
/// Also the one view that exists for the app's whole lifetime — no window need be open —
/// which makes it the right place to receive the URL handler's "open Settings" request and
/// forward it to `openSettings`, the only sanctioned way to open the Settings scene.
private struct StatusLabel: View {
    @Bindable var controller: DictationController
    let meetings: MeetingController
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if meetings.state.isActive {
                // The one state that must never be ambiguous: an app that can hear a meeting
                // owes the user an unmistakable sign that it is on.
                HStack(spacing: 4) {
                    Image(systemName: "record.circle.fill")
                    Text(TimeFormat.clock(meetings.elapsed))
                        .monospacedDigit()
                }
            } else {
                Image(systemName: controller.state.isActive ? "waveform.circle.fill" : "waveform")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurOpenSettings)) { _ in
            openSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurShowSession)) { _ in openWindow(id: "main") }
    }
}

extension Notification.Name {
    static let murmurOpenSettings = Notification.Name("com.jasonhunt.murmur.openSettings")
}
