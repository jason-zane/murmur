import AppKit
import AVFoundation
import SwiftUI

/// First run: the permissions, each proven rather than claimed.
///
/// TCC lies in one specific way this app has met before — the Accessibility toggle can read
/// as on while the app is untrusted, because the stored grant is keyed to a code signature
/// that no longer matches. So every row here reports what the system *actually* answers
/// right now, re-checked every second, and the wedged case gets the real fix rather than a
/// switch that won't help.
@MainActor
final class OnboardingWindow: NSWindow {
    private static let size = NSSize(width: 540, height: 700)

    static var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarding.completed") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarding.completed") }
    }

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Welcome to Murmur"
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

    @State private var accessibility = Permissions.hasAccessibility
    @State private var microphone = Permissions.hasMicrophone
    @State private var microphoneDenied = AVCaptureDevice.authorizationStatus(for: .audio) == .denied
    @State private var calendar = CalendarService.shared.isAuthorized
    @State private var calendarDenied = CalendarService.shared.isDenied
    @State private var audioCapture = SystemAudioCapture.isKnownGranted
    @State private var isAskingAudio = false
    @State private var didCopyReset = false

    private var essentialsGranted: Bool { accessibility && microphone }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Murmur")
                    .font(DS.Font.sessionTitle)
                    .foregroundStyle(DS.Color.text)
                Text("Dictation and meeting notes, all on this Mac. Three permissions make it work; "
                     + "each one below shows what macOS actually reports right now.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: DS.Space.md) {
                PermissionStep(
                    number: 1,
                    title: "Accessibility",
                    detail: "Sees the key you hold to dictate, inserts text where you're typing, and reads a browser window's title to tell a Meet call from a YouTube tab.",
                    granted: accessibility,
                    denied: false,
                    grantTitle: "Open System Settings",
                    grant: {
                        Permissions.promptForAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                )
                if !accessibility {
                    wedgedHint
                }
                PermissionStep(
                    number: 2,
                    title: "Microphone",
                    detail: "Your side of every dictation and every call.",
                    granted: microphone,
                    denied: microphoneDenied,
                    grantTitle: microphoneDenied ? "Open System Settings" : "Allow",
                    grant: {
                        if microphoneDenied { Permissions.openMicrophoneSettings() }
                        else { Task { microphone = await Permissions.requestMicrophone() } }
                    }
                )
                PermissionStep(
                    number: 3,
                    title: "Audio recording",
                    detail: "Hears the other side of a call — the audio your Mac is playing — so both halves of a meeting are transcribed. Separate from the microphone.",
                    granted: audioCapture,
                    denied: false,
                    grantTitle: isAskingAudio ? "Asking…" : "Allow",
                    grant: {
                        guard !isAskingAudio else { return }
                        isAskingAudio = true
                        Task {
                            audioCapture = await SystemAudioCapture.requestPermission()
                            isAskingAudio = false
                        }
                    }
                )
                PermissionStep(
                    number: 4,
                    title: "Calendars",
                    detail: "Names meetings after the event and knows who's in them. Read-only, and optional — without it, sessions are named by app and time.",
                    granted: calendar,
                    denied: calendarDenied,
                    grantTitle: calendarDenied ? "Open System Settings" : "Allow",
                    grant: {
                        if calendarDenied { CalendarService.openSettings() }
                        else { Task { calendar = await CalendarService.shared.requestAccess() } }
                    }
                )
            }

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "lock")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.textSecondary)
                    Text("Audio is discarded once it's transcribed. Only text is kept, in ~/Library/Application Support/Murmur.")
                        .font(DS.Font.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Hint(essentialsGranted ? "Ready. Hold \(Settings.shared.triggerSummary) anywhere to dictate."
                     : "Accessibility and Microphone are required; Calendars can wait.")
                Spacer()
                ActionButton(title: essentialsGranted ? "Done" : "Skip for now", emphasis: essentialsGranted ? .prominent : .quiet, action: onDone)
            }
        }
        .padding(.top, DS.Space.xxl + 4)
        .padding([.horizontal, .bottom], DS.Space.xxl)
        .frame(width: 540, height: 700)
        .background(DS.Color.window)
        .task {
            while !Task.isCancelled {
                accessibility = Permissions.hasAccessibility
                microphone = Permissions.hasMicrophone
                microphoneDenied = AVCaptureDevice.authorizationStatus(for: .audio) == .denied
                calendar = CalendarService.shared.isAuthorized
                calendarDenied = CalendarService.shared.isDenied
                audioCapture = SystemAudioCapture.isKnownGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var wedgedHint: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Hint("If the Accessibility switch already shows Murmur as on but this row stays red, the "
                 + "stored grant belongs to an older build. Don't toggle it — reset that one entry, "
                 + "then quit System Settings entirely and re-add Murmur:")
            HStack(spacing: DS.Space.sm) {
                Text("tccutil reset Accessibility com.jasonhunt.murmur")
                    .font(DS.Font.readout)
                    .foregroundStyle(DS.Color.text)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs)
                    .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.sm))
                    .overlay { RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline) }
                ActionButton(title: didCopyReset ? "Copied" : "Copy", emphasis: .quiet) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("tccutil reset Accessibility com.jasonhunt.murmur", forType: .string)
                    didCopyReset = true
                    Task { try? await Task.sleep(for: .seconds(1.4)); didCopyReset = false }
                }
            }
        }
        .padding(.leading, DS.Space.xxl + DS.Space.sm)
    }
}

private struct PermissionStep: View {
    let number: Int
    let title: String
    let detail: String
    let granted: Bool
    let denied: Bool
    let grantTitle: String
    let grant: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            ZStack {
                Circle()
                    .fill(granted ? DS.Color.success : (denied ? DS.Color.warning : DS.Color.selection))
                    .frame(width: 26, height: 26)
                if granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(DS.Font.readout)
                        .foregroundStyle(denied ? .white : DS.Color.textSecondary)
                }
            }
            .animation(DS.Motion.quick, value: granted)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.text)
                Text(detail)
                    .font(DS.Font.callout)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.md)
            if granted {
                Chip(text: "Granted", tint: DS.Color.success, filled: true)
            } else {
                ActionButton(title: grantTitle, emphasis: .normal, action: grant)
            }
        }
        .padding(DS.Space.lg)
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.lg))
        .overlay { RoundedRectangle(cornerRadius: DS.Radius.lg).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline) }
    }
}
