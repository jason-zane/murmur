import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The key you hold, the bar that appears, and the engine that listens.
struct DictationSettings: View {
    @Bindable var controller: DictationController
    var onPreviewBar: () -> Void
    @State private var settings = Settings.shared
    @State private var isCapturing = false
    @State private var captureNote: String?
    @State private var captureTimeout: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            pushToTalk
            dictationBar
            transcription
            writingStyle
            Card { DictationPractice(controller: controller) }
        }
        .onDisappear { cancelCapture() }
    }

    // MARK: - Push to talk

    private var pushToTalk: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Push to talk")
                Hint("Press Add key, then the key or mouse button you want to hold. "
                     + "Add as many as you like — whichever one you press owns that "
                     + "dictation, so another key can't cut it short.")

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: DS.Layout.chipColumn), spacing: DS.Space.sm)],
                    alignment: .leading,
                    spacing: DS.Space.sm
                ) {
                    ForEach(settings.triggers.sorted { $0.rawValue < $1.rawValue }) { trigger in
                        RemovableChip(
                            title: trigger.displayName,
                            canRemove: settings.triggers.count > 1
                        ) { remove(trigger) }
                    }
                }

                if isCapturing {
                    HStack(spacing: DS.Space.md) {
                        PulsingDot(color: DS.Color.accent)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("Press a key or mouse button…")
                                .font(DS.Font.bodyEmphasis)
                                .foregroundStyle(DS.Color.text)
                            Hint(captureNote
                                 ?? "Modifier keys (⌥ ⌘ ⌃ ⇧ fn) and extra mouse buttons "
                                  + "can be held to talk.")
                        }
                        Spacer()
                        ActionButton(title: "Cancel", emphasis: .normal) { cancelCapture() }
                    }
                    .padding(DS.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Color.accentSoft, in: .rect(cornerRadius: DS.Radius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .strokeBorder(DS.Color.accent.opacity(DS.Opacity.focusRing), lineWidth: DS.Stroke.hairline)
                    }
                } else {
                    ActionButton(title: "Add key", systemImage: "plus", emphasis: .normal) { startCapture() }
                }

                ForEach(settings.triggerCaveats, id: \.self) { caveat in
                    InlineNotice(text: caveat, tone: .warning)
                }

                Divider().padding(.vertical, DS.Space.xs)

                Text("Activation").font(DS.Font.body).foregroundStyle(DS.Color.text)
                Segmented(
                    options: ActivationMode.allCases.map { ($0, $0.displayName) },
                    selection: $settings.activation
                )
                Hint(settings.activation.detail)

                Divider().padding(.vertical, DS.Space.xs)

                ToggleRow(
                    title: "Paste last dictation shortcut",
                    hint: "Re-inserts your most recent dictation wherever the cursor is, in any app.",
                    isOn: $settings.pasteShortcutEnabled
                )
                .onChange(of: settings.pasteShortcutEnabled) { _, _ in controller.reloadPasteShortcut() }
                if settings.pasteShortcutEnabled {
                    PickerRow(
                        title: "Shortcut",
                        selection: $settings.pasteShortcut,
                        options: PasteShortcut.allCases.map { ($0, $0.displayName) }
                    )
                    .onChange(of: settings.pasteShortcut) { _, _ in controller.reloadPasteShortcut() }
                }
            }
        }
    }

    // MARK: - Dictation bar

    private var dictationBar: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack {
                    SectionLabel(text: "Dictation bar")
                    Spacer()
                    ActionButton(title: "Preview", systemImage: "eye", emphasis: .quiet, action: onPreviewBar)
                        .disabled(controller.state.isActive)
                }
                ToggleRow(
                    title: "Show live text",
                    hint: "Your words appear in the bar while you speak. With this off, the "
                        + "microphone meter and controls stay visible.",
                    isOn: $settings.showLiveDictationText
                )
                Divider().padding(.vertical, DS.Space.xs)
                Text("Screen edge").font(DS.Font.body).foregroundStyle(DS.Color.text)
                Segmented(options: HUDPosition.allCases.map { ($0, $0.displayName) },
                          selection: $settings.dictationBarPosition)
                Hint("Sits close to the edge, clear of the Dock and menu bar. "
                     + "Follows the screen you start dictating on.")
            }
        }
    }

    // MARK: - Transcription

    private var transcription: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Transcription")
                EngineRow(
                    selection: $settings.engine,
                    hint: settings.engine == .apple
                        ? "Apple's on-device transcriber. Streams text while you speak, "
                          + "and needs no download."
                        : "Parakeet on the Neural Engine. More accurate on English, but "
                          + "the text arrives when you release — no live text. Until it's "
                          + "downloaded, dictation uses Apple."
                )

                Divider().padding(.vertical, DS.Space.xs)

                ToggleRow(
                    title: "Clean up text",
                    hint: "Strips fillers, fixes spacing and punctuation. Dictionary corrections run either way.",
                    isOn: $settings.cleanupEnabled
                )
                if settings.cleanupEnabled {
                    ToggleRow(
                        title: "Smart cleanup",
                        hint: FoundationModelFormatter.unavailableReason
                            ?? "Apple Intelligence handles punctuation, paragraphing and spoken "
                             + "corrections like \"make that three, actually\". Falls back to the "
                             + "rule-based pass if it stalls.",
                        isOn: $settings.smartCleanup,
                        isEnabled: FoundationModelFormatter.isAvailable
                    )
                }

                Divider().padding(.vertical, DS.Space.xs)

                HStack(spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Label(AudioCapture.currentInputName ?? "No input device", systemImage: "mic")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.text)
                        Hint("Follows your system input device, picked up on the next dictation — "
                             + "unplugging a headset hands you back the built-in mic.")
                    }
                    Spacer()
                    ActionButton(title: "Change…", emphasis: .quiet) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    }
                }
            }
        }
    }

    // MARK: - Recording a key

    private var writingStyle: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Writing style")
                PickerRow(title: "Default", selection: $settings.dictationStyle,
                          options: DictationStyle.allCases.map { ($0, $0.title) })
                Hint(settings.dictationStyle.detail)
                Hint("Styles use Smart cleanup. Your wording, names and numbers stay the same. Without Apple Intelligence, the standard cleanup still works.")
                ForEach(settings.appDictationStyles.keys.sorted(), id: \.self) { bundleID in
                    HStack(spacing: DS.Space.sm) {
                        PickerRow(title: appName(bundleID), selection: Binding(
                            get: { settings.dictationStyle(for: bundleID) },
                            set: { settings.appDictationStyles[bundleID] = $0.rawValue }
                        ), options: DictationStyle.allCases.map { ($0, $0.title) })
                        ActionButton(title: "Use default", emphasis: .quiet) {
                            settings.appDictationStyles.removeValue(forKey: bundleID)
                        }
                        .accessibilityLabel("Use default style for \(appName(bundleID))")
                    }
                }
                ActionButton(title: "Add app…", systemImage: "plus", emphasis: .normal, action: addApp)
            }
        }
    }

    private func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
            .deletingPathExtension().lastPathComponent ?? bundleID
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app for dictation"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        settings.appDictationStyles[bundleID] = settings.dictationStyle.rawValue
    }

    private func startCapture() {
        captureNote = nil
        isCapturing = true
        controller.beginTriggerCapture { result in
            switch result {
            case .trigger(let trigger):
                var updated = settings.triggers
                updated.insert(trigger)
                settings.triggers = updated
                finishCapture()
                controller.reloadHotkey()
            case .unsupported(let reason):
                captureNote = reason
            }
        }
        // Don't leave the app swallowing input indefinitely if the user walks away.
        captureTimeout?.cancel()
        captureTimeout = Task { @MainActor in
            try? await Task.sleep(for: DS.Timing.captureTimeout)
            guard !Task.isCancelled else { return }
            cancelCapture()
        }
    }

    private func cancelCapture() {
        controller.cancelTriggerCapture()
        finishCapture()
    }

    private func finishCapture() {
        isCapturing = false
        captureNote = nil
        captureTimeout?.cancel()
        captureTimeout = nil
    }

    /// Never lets the last key be removed — with none armed the tap has nothing to watch
    /// and dictation silently stops working, with no visible cause.
    private func remove(_ trigger: PushToTalkTrigger) {
        guard settings.triggers.count > 1 else { return }
        var updated = settings.triggers
        updated.remove(trigger)
        settings.triggers = updated
        controller.reloadHotkey()
    }
}
