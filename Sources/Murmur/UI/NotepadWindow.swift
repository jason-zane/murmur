import AppKit
import MurmurSessions
import SwiftUI

/// The meeting notepad: a real window, because you type into it.
///
/// This is the opposite of `HUDPanel` on purpose. The dictation HUD must *never* take key
/// status — if it did, the user's text field would lose focus and there'd be nothing to
/// inject into. The notepad must *always* be able to take it, because it is the text field.
/// They cannot share a class, and generalising one to serve both fails in a way that looks
/// like an injection bug rather than a window-class bug.
///
/// Floating, on every Space, and it survives being closed — closing hides it, the recording
/// carries on, and the menu bar brings it back.
@MainActor
final class NotepadWindow: NSWindow, NSWindowDelegate {
    private static let defaultSize = NSSize(width: DS.Layout.notepadWidth, height: DS.Layout.notepadHeight)

    init(controller: MeetingController, onRecord: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Notes"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        minSize = NSSize(width: DS.Layout.notepadMinWidth, height: DS.Layout.notepadMinHeight)
        delegate = self
        contentView = NSHostingView(rootView: NotepadView(controller: controller, onRecord: onRecord))
        setFrameAutosaveName("MurmurNotepad")
    }

    /// Shows the notepad. `activate` decides whether it takes focus: a manual start wants to
    /// type immediately; an auto-start during a call must not yank focus from the call.
    func present(activate: Bool) {
        if !isVisible, frameAutosaveName.isEmpty || !setFrameUsingName(frameAutosaveName) {
            positionDefault()
        }
        if activate {
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            orderFront(nil)
        }
    }

    func dismiss() {
        orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        orderOut(nil)
        return false
    }

    private func positionDefault() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - DS.Space.xl,
            y: visible.maxY - size.height - DS.Space.xxxl
        ))
    }
}

struct NotepadView: View {
    @Bindable var controller: MeetingController
    let onRecord: () -> Void
    @State private var settings = MeetingSettings.shared
    @State private var title = ""
    @State private var showTranscript = false
    @FocusState private var focusedBullet: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if controller.state == .idle { idleHeader } else { header }
            if controller.state == .starting {
                Text("Preparing on-device transcription…").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            StreamMeters(
                you: controller.youLevel,
                call: controller.callLevel,
                isActive: controller.isRecording,
                callUnavailable: !controller.systemAudioActive
            )
            if let warning = controller.warning {
                Text(warning)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = controller.lastError {
                Text(error).font(DS.Font.callout).foregroundStyle(DS.Color.warning)
                if controller.state == .saveFailed {
                    ActionButton(title: "Retry save", emphasis: .prominent) { controller.retrySave() }
                }
            }
            Divider()
            if showTranscript { liveTranscript } else { bullets.disabled(!controller.isRecording) }
            footer
        }
        .padding(.top, DS.Layout.notepadTopInset)
        .padding([.horizontal, .bottom], DS.Space.lg)
        .frame(minWidth: DS.Layout.notepadMinWidth, minHeight: DS.Layout.notepadMinHeight)
        .background(DS.Color.window)
        .onAppear { syncTitle(); seedBullet() }
        .onChange(of: controller.session?.id) { _, _ in syncTitle(); seedBullet() }
        .onChange(of: settings.showLiveTranscript, initial: true) { _, on in showTranscript = on }
        .onKeyPress(.init("t"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            withAnimation(DS.Motion.quick) { showTranscript.toggle() }
            return .handled
        }
    }

    // MARK: - Pieces

    /// The notepad opened with nothing running: say so, and offer to start.
    private var idleHeader: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Not recording")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textSecondary)
                Readout("Waiting for a call, or press Record", color: DS.Color.textTertiary)
            }
            Spacer(minLength: DS.Space.zero)
            ActionButton(title: "Record", emphasis: .prominent, action: onRecord)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                TextField("Untitled meeting", text: $title)
                    .textFieldStyle(.plain)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.text)
                    .onSubmit { controller.rename(title) }
                    .onChange(of: title) { _, new in controller.rename(new) }
                HStack(spacing: DS.Space.sm) {
                    Readout(startedText)
                    Readout("·", color: DS.Color.textTertiary)
                    Readout(TimeFormat.clock(controller.elapsed), color: controller.isRecording ? DS.Color.text : DS.Color.textSecondary)
                    if let app = controller.session?.app {
                        Readout("·", color: DS.Color.textTertiary)
                        Readout(app)
                    }
                }
            }
            Spacer(minLength: DS.Space.zero)
            if controller.state == .finalising {
                ProgressView().controlSize(.small)
            } else if controller.isRecording {
                RecordingDot()
                    .padding(.top, DS.Space.xs)
            }
            ActionButton(title: controller.state == .finalising ? "Saving…" : controller.state == .starting ? "Cancel" : "Stop", emphasis: .normal) {
                controller.stop()
            }
            .disabled(!controller.state.isActive)
        }
    }

    private var bullets: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach($controller.bullets) { $bullet in
                    BulletRow(
                        bullet: $bullet,
                        focused: $focusedBullet,
                        onReturn: { insertBullet(after: bullet.id) },
                        onDeleteEmpty: { removeBullet(bullet.id) }
                    )
                }
            }
            .padding(.vertical, DS.Space.xs)
        }
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture {
            if let last = controller.bullets.last { focusedBullet = last.id }
        }
    }

    private var liveTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    ForEach(controller.liveSegments.suffix(40)) { segment in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                            Readout(TimeFormat.clock(segment.start), color: DS.Color.textTertiary)
                            Text(segment.text)
                                .font(DS.Font.callout)
                                .foregroundStyle(segment.source == .you ? DS.Color.text : DS.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .id(segment.id)
                    }
                    if !controller.livePartial.isEmpty {
                        Text(controller.livePartial)
                            .font(DS.Font.callout)
                            .foregroundStyle(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .id("partial")
                    }
                    if controller.liveSegments.isEmpty, controller.livePartial.isEmpty {
                        Hint("Listening. Text appears here as it's recognised.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.xs)
            }
            .onChange(of: controller.liveSegments.count) { _, _ in
                if let last = controller.liveSegments.last {
                    withAnimation(DS.Motion.smooth) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.sm) {
            Hint("Hold \(Settings.shared.triggerSummary) to dictate a note")
            Spacer()
            Button {
                withAnimation(DS.Motion.quick) { showTranscript.toggle() }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: showTranscript ? "list.bullet" : "text.alignleft")
                        .font(.system(size: 10, weight: .semibold))
                    Text(showTranscript ? "Notes" : "Transcript")
                        .font(DS.Font.label)
                    Text("⌘T").font(DS.Font.readout).foregroundStyle(DS.Color.textTertiary)
                }
                .foregroundStyle(DS.Color.textSecondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Readout("\(controller.liveSegments.count) seg", color: DS.Color.textTertiary)
        }
    }

    // MARK: - Bullets

    private func seedBullet() {
        guard controller.isRecording || controller.state == .starting, controller.bullets.isEmpty else { return }
        let first = controller.makeBullet()
        controller.bullets = [first]
        focusedBullet = first.id
    }

    private func insertBullet(after id: UUID) {
        guard let index = controller.bullets.firstIndex(where: { $0.id == id }) else { return }
        let new = controller.makeBullet()
        controller.bullets.insert(new, at: index + 1)
        focusedBullet = new.id
    }

    private func removeBullet(_ id: UUID) {
        guard controller.bullets.count > 1, let index = controller.bullets.firstIndex(where: { $0.id == id }) else { return }
        controller.bullets.remove(at: index)
        focusedBullet = controller.bullets[max(0, index - 1)].id
    }

    private func syncTitle() {
        title = controller.session?.title ?? ""
    }

    private var startedText: String {
        guard let start = controller.session?.startedAt else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: start)
    }
}

/// One bullet: a dot, the text, and its timestamp on hover. Return makes the next one;
/// Delete on an empty bullet removes it.
private struct BulletRow: View {
    @Binding var bullet: NoteBullet
    var focused: FocusState<UUID?>.Binding
    let onReturn: () -> Void
    let onDeleteEmpty: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            Text("•")
                .font(DS.Font.note)
                .foregroundStyle(DS.Color.textTertiary)
            TextField("", text: $bullet.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.Font.note)
                .foregroundStyle(DS.Color.text)
                .focused(focused, equals: bullet.id)
                .onSubmit(onReturn)
                .onKeyPress(.delete, phases: .down) { _ in
                    guard bullet.text.isEmpty else { return .ignored }
                    onDeleteEmpty()
                    return .handled
                }
            Readout(TimeFormat.clock(bullet.at), color: DS.Color.textTertiary)
                .opacity(isHovering || focused.wrappedValue == bullet.id ? 1 : 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, DS.Space.xs)
        .background(focused.wrappedValue == bullet.id ? DS.Color.hover : .clear, in: .rect(cornerRadius: DS.Radius.sm))
        .onHover { isHovering = $0 }
        .animation(DS.Motion.smooth, value: isHovering)
    }
}
