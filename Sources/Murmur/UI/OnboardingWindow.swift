import AppKit
import AVFoundation
import SwiftUI

/// First run starts with the person's task. Calendar, Mail and Notes can be opened
/// immediately; dictation and meeting permissions remain an optional guided path.
///
/// TCC lies in one specific way this app has met before — the Accessibility toggle can read
/// as on while the app is untrusted, because the stored grant is keyed to a code signature
/// that no longer matches. So every row here reports what the system *actually* answers
/// right now, re-checked every second, and the wedged case gets the real fix.
@MainActor
final class OnboardingWindow: NSWindow {
    static var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarding.completed") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarding.completed") }
    }

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: DS.Layout.onboardingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Welcome to Concourse"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        contentView = NSHostingView(rootView: OnboardingView { [weak self] in
            Self.isCompleted = true
            UserDefaults.standard.set(true, forKey: "workspace.welcome.v2")
            self?.orderOut(nil)
        })
        center()
    }

    func present() {
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct OnboardingView: View {
    let onDone: () -> Void

    enum Page: Int, CaseIterable {
        case welcome, dictate, meetings, extras, done

        var title: String {
            switch self {
            case .welcome: "Welcome to your workspace"
            case .dictate: "Dictate anywhere"
            case .meetings: "Record meetings"
            case .extras: "Make it your workspace"
            case .done: "Ready for your day"
            }
        }

        var lead: String {
            switch self {
            case .welcome: "Sign in, connect your calendars and Gmail, and bring your day together."
            case .dictate: "Two permissions make dictation work. Each row shows what macOS reports right now."
            case .meetings: "Two more let Concourse hear a call and name it. Both are optional."
            case .extras: "Your calendars, Gmail and notes can live together. Connect apps whenever you’re ready."
            case .done: "Your workspace is ready. Dictation is always a held key away."
            }
        }
    }

    @State private var page: Page = .welcome
    @State private var accessibility = Permissions.hasAccessibility
    @State private var microphone = Permissions.hasMicrophone
    @State private var microphoneDenied = AVCaptureDevice.authorizationStatus(for: .audio) == .denied
    @State private var calendar = CalendarService.shared.isAuthorized
    @State private var calendarDenied = CalendarService.shared.isDenied
    @State private var audioCapture = SystemAudioCapture.isKnownGranted
    @State private var isAskingAudio = false
    @State private var didCopyReset = false
    @State private var claudeConfigured = ClaudeDesktopIntegration.isConfigured
    @State private var claudeMessage: String?
    @State private var settings = Settings.shared
    @State private var account = CloudAccount.shared

    private var essentialsGranted: Bool { accessibility && microphone }
    private var isInApplications: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }
    private var hasClaudeDesktop: Bool {
        FileManager.default.fileExists(atPath: ClaudeDesktopIntegration.configURL.deletingLastPathComponent().path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            if !isInApplications {
                InlineNotice(text: "Move Concourse to Applications first — start at login and the Claude connection point at the app's location.", tone: .warning) {
                    ActionButton(title: "Show in Finder", emphasis: .quiet) {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Readout("Step \(page.rawValue + 1) of \(Page.allCases.count)", color: DS.Color.textTertiary)
                Text(page.title)
                    .font(DS.Font.sessionTitle)
                    .foregroundStyle(DS.Color.text)
                Text(page.lead)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                switch page {
                case .welcome: welcome
                case .dictate: dictate
                case .meetings: meetings
                case .extras: extras
                case .done: done
                }
            }
            .transition(.opacity)

            Spacer(minLength: DS.Space.zero)

            HStack(spacing: DS.Space.sm) {
                if page != .welcome, page != .done {
                    ActionButton(title: "Back", emphasis: .quiet) { move(-1) }
                }
                Spacer()
                switch page {
                case .welcome:
                    ActionButton(title: "Use this Mac without an account", emphasis: .quiet) { move(1) }
                    ActionButton(title: account.isConnected ? "Connect my apps" : "Sign in and set up", emphasis: .prominent) {
                        if account.isConnected { finish(.connections) }
                        else { Task { await account.signIn(); if account.isConnected { finish(.connections) } } }
                    }.disabled(account.isSigningIn)
                case .dictate:
                    if !essentialsGranted { ActionButton(title: "Skip for now", emphasis: .quiet) { move(1) } }
                    ActionButton(title: "Continue", emphasis: .prominent) { move(1) }.disabled(!essentialsGranted)
                case .meetings, .extras:
                    ActionButton(title: "Continue", emphasis: .prominent) { move(1) }
                case .done:
                    ActionButton(title: "Open my workspace", emphasis: .prominent) { onDone(); NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.home) }
                }
            }
        }
        .padding(.top, DS.Space.xxl + DS.Space.xs)
        .padding([.horizontal, .bottom], DS.Space.xxl)
        .frame(width: DS.Layout.onboardingSize.width, height: DS.Layout.onboardingSize.height)
        .background(DS.Color.window)
        .animation(DS.Motion.quick, value: page)
        .task {
            while !Task.isCancelled {
                accessibility = Permissions.hasAccessibility
                Permissions.rememberTrusted()
                microphone = Permissions.hasMicrophone
                microphoneDenied = AVCaptureDevice.authorizationStatus(for: .audio) == .denied
                calendar = CalendarService.shared.isAuthorized
                calendarDenied = CalendarService.shared.isDenied
                audioCapture = SystemAudioCapture.isKnownGranted
                claudeConfigured = ClaudeDesktopIntegration.isConfigured
                try? await Task.sleep(for: DS.Timing.permissionPoll)
            }
        }
    }

    private func move(_ delta: Int) {
        if let next = Page(rawValue: page.rawValue + delta) { page = next }
    }

    // MARK: - Pages

    private func finish(_ target: MainPage) {
        onDone()
        NotificationCenter.default.post(name: .murmurShowPage, object: target)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Label("One account for your workspace", systemImage: "person.crop.circle").font(DS.Font.headline)
            Hint("Your Concourse account keeps your notes and Google connections together across Mac and web.")
            Label("Connect work and personal accounts", systemImage: "calendar").font(DS.Font.headline)
            Hint("Choose your Google calendars and Gmail inboxes next. Each connection asks for the access it needs.")
            Hint("Downloaded notes, calendars and mail remain available offline. Dictation and meeting capture run on this Mac.")
            if let message = account.message { InlineNotice(text: message, tone: .warning) }
        }
    }

    private var dictate: some View {
        VStack(spacing: DS.Space.md) {
            PermissionRow(
                title: "Accessibility",
                detail: "Sees the key you hold, inserts text where you're typing, and reads a browser window's title to tell a Meet call from a YouTube tab.",
                isGranted: accessibility,
                grantTitle: "Open System Settings"
            ) {
                Permissions.promptForAccessibility()
                Permissions.openAccessibilitySettings()
            }
            PermissionRow(
                title: "Microphone",
                detail: "Your side of every dictation and every call.",
                isGranted: microphone,
                grantTitle: microphoneDenied ? "Open System Settings" : "Allow"
            ) {
                if microphoneDenied { Permissions.openMicrophoneSettings() }
                else { Task { microphone = await Permissions.requestMicrophone() } }
            }
            if Permissions.wasEverTrusted, !accessibility {
                DisclosureGroup("Still not working?") {
                    wedgedHint.padding(.top, DS.Space.sm)
                }
                .font(DS.Font.callout)
            }
        }
    }

    private var meetings: some View {
        VStack(spacing: DS.Space.md) {
            PermissionRow(
                title: "Audio recording",
                detail: "Hears the other side of a call — the audio your Mac is playing — so both halves are transcribed. Separate from the microphone.",
                isGranted: audioCapture,
                grantTitle: isAskingAudio ? "Asking…" : "Allow"
            ) {
                guard !isAskingAudio else { return }
                isAskingAudio = true
                Task {
                    audioCapture = await SystemAudioCapture.requestPermission()
                    isAskingAudio = false
                }
            }
            PermissionRow(
                title: "Calendars",
                detail: "Names meetings after the event and lets you view and edit calendars on this Mac. Without it, notes are named by app and time.",
                isGranted: calendar,
                grantTitle: calendarDenied ? "Open System Settings" : "Allow"
            ) {
                if calendarDenied { CalendarService.openSettings() }
                else { Task { calendar = await CalendarService.shared.requestAccess() } }
            }
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "lock").font(DS.Font.smallSymbol).foregroundStyle(DS.Color.textSecondary)
                Hint("Audio is discarded once it's transcribed. Only text is kept, on this Mac.")
            }
        }
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Label("Calendar · work and personal accounts", systemImage: "calendar")
            Label("Mail · your Gmail inboxes together", systemImage: "envelope")
            Label("Notes · capture meetings and find decisions", systemImage: "book.closed")
            Hint("Calendar, Gmail and AI apps each have their own Connect action. Optional cloud features need a Concourse account; local notes and dictation don’t.")
            ActionButton(title: "Open Connected apps", emphasis: .normal) {
                onDone()
                NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.connections)
            }
            ToggleRow(title: "Start Concourse at login", hint: "Keep dictation and meeting detection ready.", isOn: $settings.launchAtLogin)
        }.font(DS.Font.body)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Hold \(settings.triggerSummary) anywhere to dictate.")
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.text)
            Hint("Concourse offers to record when a call starts in Meet, Zoom or Teams. "
                 + "Open Concourse for Today, Calendar, Mail and Notes. Connected apps brings your accounts together; Settings holds dictation and meeting preferences.")
        }
    }

    private var wedgedHint: some View {
        let command = "tccutil reset Accessibility " + (Bundle.main.bundleIdentifier ?? "com.jasonhunt.murmur")
        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            Hint("Accessibility was granted before, so the stored entry belongs to an older build. "
                 + "Don't toggle it — reset that one entry, then quit System Settings entirely and "
                 + "re-add Concourse:")
            HStack(spacing: DS.Space.sm) {
                Text(command)
                    .font(DS.Font.readout)
                    .foregroundStyle(DS.Color.text)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs)
                    .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.sm))
                    .overlay { RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline) }
                ActionButton(title: didCopyReset ? "Copied" : "Copy", emphasis: .quiet) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    didCopyReset = true
                    Task { try? await Task.sleep(for: DS.Timing.feedback); didCopyReset = false }
                }
            }
        }
    }
}
