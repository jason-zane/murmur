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
                       onToggleMeeting: delegate.toggleMeeting, onShowNotepad: delegate.showNotepad)
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
            CommandGroup(after: .appInfo) {
                Button("Reveal Dictionary File") {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                }
            }
        }

        // Fully qualified: this app has its own `Settings` type, which otherwise shadows
        // SwiftUI's settings scene.
        SwiftUI.Settings {
            SettingsWindow(controller: delegate.controller, onPreviewBar: delegate.previewDictationBar)
        }

        // Secondary now: status and the hotkey while you're working in another app.
        MenuBarExtra {
            MenuContent(controller: delegate.controller, meetings: delegate.meetings,
                        detector: delegate.detector, delegate: delegate)
        } label: {
            StatusLabel(controller: delegate.controller, meetings: delegate.meetings)
        }

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
        if PreviewEnvironment.isActive { return }
        wireMeetings()
        MeetingSchedule.shared.start()
        CloudSync.shared.start()

        if !OnboardingWindow.isCompleted {
            showOnboarding()
        }

        if !controller.activate() {
            Permissions.promptForAccessibility()
            // The tap can only be created once the user grants Accessibility, and there's
            // no notification for that — poll until it takes.
            retryActivation()
        }

        // Write the dashboard up front so the menu item always opens something, even
        // before the first dictation.
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
        if UserDefaults.standard.bool(forKey: "comparisonWindowOpen") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                Self.showComparisonWindow()
            }
        }

        observeState()
        observeMeetingState()
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

    /// `murmur://clear` and `murmur://show`, used by the legacy HTML dashboard and
    /// as a scriptable way to raise the window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "murmur" {
            switch url.host {
            case "clear":
                RunLog.clear()
                RunStore.shared.reload()
            case "show":
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
            case "connections", "cloud":
                NotificationCenter.default.post(name: .murmurShowConnections, object: nil)
                NSApp.activate(ignoringOtherApps: true)
            case "setup":
                showOnboarding()
            case "paste":
                controller.pasteLastTranscription()
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

    private var recordMeetingTitle: String {
        if let candidate = detector.candidate { return "Record \(candidate.callNoun)…" }
        return "Record meeting"
    }
    @Environment(\.openWindow) private var openWindow
    @State private var isPreloadingParakeet = false
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded

    private var parakeetStatus: String {
        if isPreloadingParakeet { return "Loading Parakeet models…" }
        // Reflects what's actually on disk, not just what this menu instance has done.
        return parakeetOnDisk ? "Parakeet models installed ✓" : "Download Parakeet models…"
    }

    private func preloadParakeet() {
        guard !isPreloadingParakeet else { return }
        isPreloadingParakeet = true
        Task {
            do {
                _ = try await ParakeetModels.shared.manager()
                parakeetOnDisk = ParakeetModels.isDownloaded
            } catch {
                Log.speech.error("Parakeet preload failed: \(error.localizedDescription)")
            }
            isPreloadingParakeet = false
        }
    }

    var body: some View {
        if meetings.state.isActive {
            Button("Stop meeting  \(TimeFormat.clock(meetings.elapsed))") { delegate.toggleMeeting() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Show notes") { delegate.showNotepad() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        } else {
            Button(recordMeetingTitle) { delegate.toggleMeeting() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        Divider()

        Text("Hold \(settings.triggerSummary) to dictate")

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",", modifiers: .command)

        Button("Open Voice Notes") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        if controller.state.isActive {
            Button("Reset stuck recording") { controller.forceReset() }
        }

        Divider()

        Button("Paste last transcription") { controller.pasteLastTranscription() }

        Toggle("Compare mode (both engines)", isOn: $settings.compareMode)

        if !settings.compareMode {
            Picker("Engine", selection: $settings.engine) {
                ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
        }

        Toggle("Clean up text", isOn: $settings.cleanupEnabled)

        if settings.cleanupEnabled {
            Toggle("Smart cleanup (on-device AI)", isOn: $settings.smartCleanup)
                .disabled(!FoundationModelFormatter.isAvailable)
            if let reason = FoundationModelFormatter.unavailableReason {
                Text(reason).font(.caption)
            }
        }

        Toggle("Sound", isOn: $settings.soundEnabled)

        Toggle("Start at login", isOn: $settings.launchAtLogin)

        Divider()

        Button("Show comparison window") {
            RunStore.shared.reload()
            openWindow(id: "comparison")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("d")

        // Downloading ~470 MB on the first hold would look like a hang, so offer to do it
        // deliberately instead.
        if settings.engine == .parakeet {
            Button(parakeetStatus) { preloadParakeet() }
                .disabled(isPreloadingParakeet || parakeetOnDisk)
        }

        Button("Permissions & setup…") { delegate.showOnboarding() }

        if !Permissions.hasAccessibility {
            Button("Grant Accessibility…") { Permissions.openAccessibilitySettings() }
        }
        if !Permissions.hasMicrophone {
            Button("Grant Microphone…") { Permissions.openMicrophoneSettings() }
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
        .onReceive(NotificationCenter.default.publisher(for: .murmurShowConnections)) { _ in openWindow(id: "main") }
    }
}

extension Notification.Name {
    static let murmurOpenSettings = Notification.Name("com.jasonhunt.murmur.openSettings")
}
