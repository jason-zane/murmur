import AppKit
import MurmurSessions
import SwiftUI

/// The notepad you keep open beside a call.
///
/// It opens as a **rail**: full height, down the right edge of the screen, narrow enough to
/// sit next to a video window without covering a face. A short floating box in the corner
/// made the notes feel like a receipt; a column makes them feel like a page you are writing
/// on while the call runs. It stays resizable and movable — the frame is autosaved, so
/// whatever the user drags it to is what they get next time.
@MainActor
final class NotepadWindow: NSWindow, NSWindowDelegate {
    init(controller: MeetingController, onRecord: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: DS.Notepad.width, height: DS.Notepad.minHeight)),
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
        minSize = NSSize(width: DS.Notepad.minWidth, height: DS.Notepad.minHeight)
        // Height is free; width is not. Past `maxWidth` the rail stops being a companion.
        maxSize = NSSize(width: DS.Notepad.maxWidth, height: .greatestFiniteMagnitude)
        // The backdrop is an `NSVisualEffectView` inside the content, so the window itself
        // must not paint over it.
        isOpaque = false
        backgroundColor = .clear
        delegate = self
        contentView = NSHostingView(rootView: NotepadView(controller: controller, onRecord: onRecord))
        // Deliberately not the old autosave name: saved frames from the floating-box
        // layout would restore a 380×440 window and hide the change.
        setFrameAutosaveName("MurmurNotesRail")
    }

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

    /// Full height of the working area, down the right edge — inside the visible frame, so
    /// it clears the menu bar and the Dock wherever the Dock happens to live.
    private func positionDefault() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let inset = DS.Notepad.edgeInset
        let width = min(DS.Notepad.width, max(DS.Notepad.minWidth, visible.width - inset * 2))
        let height = max(DS.Notepad.minHeight, visible.height - inset * 2)
        setFrame(
            NSRect(x: visible.maxX - width - inset, y: visible.maxY - height - inset,
                   width: width, height: height),
            display: false
        )
    }
}

struct NotepadView: View {
    enum Mode: Hashable { case notes, transcript }

    @Bindable var controller: MeetingController
    let onRecord: () -> Void
    @State private var settings = MeetingSettings.shared
    @State private var title = ""
    @State private var mode: Mode = .notes
    @FocusState private var focusedBullet: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            header
            if isActive {
                StreamMeters(
                    you: controller.youLevel,
                    call: controller.callLevel,
                    isActive: controller.isRecording,
                    callUnavailable: !controller.systemAudioActive
                )
                .padding(DS.Space.md)
                .background(DS.Color.hover, in: .rect(cornerRadius: DS.Radius.md))
            }
            notices
            if isActive {
                Segmented(
                    options: [(value: Mode.notes, title: "Notes"), (value: Mode.transcript, title: "Transcript")],
                    selection: $mode
                )
            }
            content
            footer
        }
        .padding(.top, DS.Notepad.topInset)
        .padding([.horizontal, .bottom], DS.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(backdrop)
        .onAppear { syncTitle(); seedBullet() }
        .onChange(of: controller.session?.id) { _, _ in syncTitle(); seedBullet() }
        .onChange(of: settings.showLiveTranscript, initial: true) { _, on in mode = on ? .transcript : .notes }
        .onKeyPress(.init("t"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            withAnimation(DS.Motion.quick) { mode = mode == .notes ? .transcript : .notes }
            return .handled
        }
    }

    /// Translucent, like every other panel that lives beside your work — plus a wash of red
    /// at the head of the rail while the microphone is open, so the state is legible from
    /// the corner of your eye without reading a word.
    private var backdrop: some View {
        ZStack(alignment: .top) {
            WindowBackdrop()
            LinearGradient(
                colors: [DS.Color.recordSoft, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: DS.Notepad.washHeight)
            .opacity(controller.isRecording ? DS.Notepad.washOpacity : 0)
            .animation(DS.Motion.spring, value: controller.isRecording)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                StatePill(state: controller.state)
                Spacer(minLength: DS.Space.sm)
                if isActive {
                    Readout(
                        TimeFormat.clock(controller.elapsed),
                        font: DS.Font.readoutLarge,
                        color: controller.isRecording ? DS.Color.text : DS.Color.textSecondary
                    )
                }
            }
            if isActive {
                TextField("Untitled meeting", text: $title)
                    .textFieldStyle(.plain)
                    .font(DS.Font.sessionTitle)
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(2)
                    .onSubmit { controller.rename(title) }
                    .onChange(of: title) { _, new in controller.rename(new) }
                HStack(spacing: DS.Space.sm) {
                    Readout(startedText)
                    if let app = controller.session?.app {
                        Readout("·", color: DS.Color.textTertiary)
                        Readout(app)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notices: some View {
        if controller.state == .starting {
            Hint("Preparing on-device transcription…")
        }
        if let warning = controller.warning {
            Notice(text: warning, tint: DS.Color.warning)
        }
        if let error = controller.lastError {
            Notice(text: error, tint: DS.Color.warning)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        if !isActive {
            EmptyState(
                icon: "note.text",
                label: "No meeting yet",
                detail: "Notes start on their own when a call begins — or press Record and take them now."
            )
        } else if mode == .transcript {
            liveTranscript
        } else {
            bullets
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
        .disabled(!controller.isRecording)
    }

    private var liveTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    ForEach(controller.liveSegments.suffix(40)) { segment in
                        TranscriptLine(segment: segment)
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

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Divider()
            HStack(spacing: DS.Space.sm) {
                if isActive {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Hint("Hold \(Settings.shared.triggerSummary) to dictate a note")
                        Readout("\(controller.liveSegments.count) lines · ⌘T", color: DS.Color.textTertiary)
                    }
                } else {
                    Hint("Everything stays on this Mac.")
                }
                Spacer(minLength: DS.Space.sm)
                primaryControl
            }
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        switch controller.state {
        case .idle:
            RecordButton(isRecording: false, action: onRecord)
        case .starting:
            ActionButton(title: "Cancel", emphasis: .normal) { controller.stop() }
        case .recording:
            RecordButton(isRecording: true) { controller.stop() }
        case .finalising:
            HStack(spacing: DS.Space.sm) {
                ProgressView().controlSize(.small)
                Readout("Saving…")
            }
        case .saveFailed:
            ActionButton(title: "Retry save", emphasis: .prominent) { controller.retrySave() }
        }
    }

    // MARK: - State

    private var isActive: Bool { controller.state != .idle }

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

// MARK: - Pieces

/// What the session is doing, in one glance-sized token.
private struct StatePill: View {
    let state: MeetingController.State

    var body: some View {
        HStack(spacing: DS.Space.compact) {
            if state == .recording {
                RecordingDot(size: DS.Notepad.dotSize)
            } else {
                StatusDot(color: tint, isLit: state != .idle, size: DS.Notepad.dotSize)
            }
            Text(label)
                .font(DS.Font.label)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .background(fill, in: .capsule)
        .animation(DS.Motion.smooth, value: state)
    }

    private var label: String {
        switch state {
        case .idle: "Not recording"
        case .starting: "Starting"
        case .recording: "Recording"
        case .finalising: "Saving"
        case .saveFailed: "Not saved"
        }
    }

    private var tint: Color {
        switch state {
        case .idle: DS.Color.textSecondary
        case .starting, .finalising: DS.Color.accent
        case .recording: DS.Color.record
        case .saveFailed: DS.Color.warning
        }
    }

    private var fill: Color {
        switch state {
        case .idle: DS.Color.selection
        case .starting, .finalising: DS.Color.accentSoft
        case .recording: DS.Color.recordSoft
        case .saveFailed: DS.Color.warningSoft
        }
    }
}

/// A warning or error that shouldn't read as body text.
private struct Notice: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.Font.smallSymbol)
                .foregroundStyle(tint)
            Text(text)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(DS.Notepad.noticeOpacity), in: .rect(cornerRadius: DS.Radius.sm))
    }
}

/// One finalised line of the live transcript. Narrow column, so the speaker and the clock
/// sit above the text rather than beside it.
private struct TranscriptLine: View {
    let segment: TranscriptSegment

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.sm) {
                Text(segment.speaker ?? (segment.source == .you ? "You" : "Call"))
                    .font(DS.Font.label)
                    .foregroundStyle(segment.source == .you ? DS.Color.accent : DS.Color.textSecondary)
                Readout(TimeFormat.clock(segment.start), color: DS.Color.textTertiary)
            }
            Text(segment.text)
                .font(DS.Font.callout)
                .foregroundStyle(DS.Color.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
        .padding(.vertical, DS.Space.tight)
        .padding(.horizontal, DS.Space.xs)
        .background(
            focused.wrappedValue == bullet.id ? DS.Color.selection : (isHovering ? DS.Color.hover : .clear),
            in: .rect(cornerRadius: DS.Radius.sm)
        )
        .onHover { isHovering = $0 }
        .animation(DS.Motion.smooth, value: isHovering)
    }
}

/// The window's translucent backing. `behindWindow` blending, so the rail picks up whatever
/// it is sitting on top of instead of reading as a grey slab.
private struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
