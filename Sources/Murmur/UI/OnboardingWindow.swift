import AppKit
import AVFoundation
import SwiftUI

/// First run, in four short pages: the two permissions dictation needs, the two a meeting
/// needs, a few extras, and the one thing to remember.
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
        title = "Welcome to Voice Notes"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        contentView = NSHostingView(rootView: OnboardingView { [weak self] in
            Self.isCompleted = true
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
        case dictate, meetings, extras, done

        var title: String {
            switch self {
            case .dictate: "Dictate anywhere"
            case .meetings: "Record meetings"
            case .extras: "A few extras"
            case .done: "That's it"
            }
        }

        var lead: String {
            switch self {
            case .dictate: "Two permissions make dictation work. Each row shows what macOS reports right now."
            case .meetings: "Two more let Voice Notes hear a call and name it. Both are optional."
            case .extras: "Everything here can be changed later in Settings."
            case .done: "Voice Notes lives in the menu bar."
            }
        }
    }

    @State private var page: Page = .dictate
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
                InlineNotice(text: "Move Voice Notes to Applications first — start at login and the Claude connection point at the app's location.", tone: .warning) {
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
                case .dictate: dictate
                case .meetings: meetings
                case .extras: extras
                case .done: done
                }
            }
            .transition(.opacity)

            Spacer(minLength: DS.Space.zero)

            HStack(spacing: DS.Space.sm) {
                if page != .dictate, page != .done {
                    ActionButton(title: "Back", emphasis: .quiet) { move(-1) }
                }
                Spacer()
                switch page {
                case .dictate:
                    if !essentialsGranted { ActionButton(title: "Skip for now", emphasis: .quiet) { move(1) } }
                    ActionButton(title: "Continue", emphasis: .prominent) { move(1) }.disabled(!essentialsGranted)
                case .meetings, .extras:
                    ActionButton(title: "Continue", emphasis: .prominent) { move(1) }
                case .done:
                    ActionButton(title: "Done", emphasis: .prominent, action: onDone)
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
                detail: "Names meetings after the event and knows who's in them. Read-only. Without it, notes are named by app and time.",
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
        VStack(spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                StatusDot(color: FoundationModelFormatter.isAvailable ? DS.Color.success : DS.Color.textTertiary, isLit: true, size: DS.Layout.permissionDot)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Apple Intelligence").font(DS.Font.body).foregroundStyle(DS.Color.text)
                    Hint(FoundationModelFormatter.unavailableReason ?? "Ready. Summaries and smart cleanup run on this Mac.")
                }
                Spacer()
                if FoundationModelFormatter.isAvailable {
                    Chip(text: "Ready", tint: DS.Color.success, filled: true)
                } else {
                    ActionButton(title: "Open System Settings", emphasis: .normal) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                    }
                }
            }
            ToggleRow(
                title: "Start Voice Notes at login",
                hint: "The push-to-talk key and call detection only work while it's running.",
                isOn: $settings.launchAtLogin
            )
            if hasClaudeDesktop {
                PermissionRow(
                    title: "Claude Desktop",
                    detail: claudeMessage ?? "Let Claude read your notes on this Mac. Nothing leaves the machine.",
                    isGranted: claudeConfigured,
                    grantTitle: "Connect"
                ) {
                    do {
                        try ClaudeDesktopIntegration.configure()
                        claudeConfigured = true
                        claudeMessage = "Connected. Quit and reopen Claude Desktop to load it."
                    } catch { claudeMessage = error.localizedDescription }
                }
            }
            HStack(spacing: DS.Space.md) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Voice Notes account").font(DS.Font.body).foregroundStyle(DS.Color.text)
                    Hint(account.isConnected ? "Signed in as " + account.email
                         : "Optional. Notes on the web, Google Calendar, and ChatGPT or Claude from anywhere.")
                }
                Spacer()
                if account.isConnected {
                    Chip(text: "Signed in", tint: DS.Color.success, filled: true)
                } else {
                    ActionButton(title: account.isSigningIn ? "Signing in…" : "Sign in", emphasis: .quiet) {
                        Task { await account.signIn() }
                    }.disabled(account.isSigningIn)
                }
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Hold \(settings.triggerSummary) anywhere to dictate.")
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.text)
            Hint("Voice Notes offers to record when a call starts in Meet, Zoom or Teams. "
                 + "Your notes, the dictionary and every setting are in the menu bar under Settings.")
        }
    }

    private var wedgedHint: some View {
        let command = "tccutil reset Accessibility " + (Bundle.main.bundleIdentifier ?? "com.jasonhunt.murmur")
        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            Hint("Accessibility was granted before, so the stored entry belongs to an older build. "
                 + "Don't toggle it — reset that one entry, then quit System Settings entirely and "
                 + "re-add Voice Notes:")
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
