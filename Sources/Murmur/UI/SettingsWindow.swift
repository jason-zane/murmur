import SwiftUI

struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    @State private var isCapturing = false
    @State private var captureNote: String?
    @State private var captureTimeout: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {

                Card {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SectionLabel(text: "Push to talk")
                        Hint("Press Add, then press the key or mouse button you want to hold. "
                             + "Map as many as you like — whichever one you press owns that "
                             + "dictation, so another trigger can't cut it short.")

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 140), spacing: DS.Space.sm)],
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
                                PulsingDot(color: DS.Color.accent, size: 8)
                                VStack(alignment: .leading, spacing: 2) {
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
                                    .strokeBorder(DS.Color.accent.opacity(0.5),
                                                  lineWidth: DS.Stroke.hairline)
                            }
                        } else {
                            ActionButton(title: "Add trigger", systemImage: "plus",
                                         emphasis: .normal) { startCapture() }
                        }

                        ForEach(settings.triggerCaveats, id: \.self) { caveat in
                            WarningNote(text: caveat)
                        }
                    }
                }
                .onDisappear { cancelCapture() }

                Card {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SectionLabel(text: "Activation")

                        Segmented(
                            options: ActivationMode.allCases.map { ($0, $0.displayName) },
                            selection: $settings.activation
                        )

                        Hint(settings.activation.detail)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SectionLabel(text: "Paste last transcription")

                        SettingToggle(
                            title: "Global shortcut",
                            isOn: $settings.pasteShortcutEnabled
                        )
                        .onChange(of: settings.pasteShortcutEnabled) { _, _ in
                            controller.reloadPasteShortcut()
                        }

                        if settings.pasteShortcutEnabled {
                            Segmented(
                                options: PasteShortcut.allCases.map { ($0, $0.displayName) },
                                selection: $settings.pasteShortcut
                            )
                            .onChange(of: settings.pasteShortcut) { _, _ in
                                controller.reloadPasteShortcut()
                            }
                        }

                        Hint("Re-inserts your most recent transcription wherever the cursor "
                             + "is, in any app.")
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SectionLabel(text: "Microphone")

                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: "mic")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Color.textSecondary)
                            Text(AudioCapture.currentInputName ?? "No input device")
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.text)
                            Spacer()
                            ActionButton(title: "Change…", emphasis: .quiet) {
                                NSWorkspace.shared.open(
                                    URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!
                                )
                            }
                        }

                        Hint("Murmur always follows your system input device, and picks up "
                             + "changes on the next dictation — so unplugging a headset "
                             + "hands you back the built-in mic.")
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SectionLabel(text: "Model")

                        Segmented(
                            options: SpeechEngineChoice.allCases.map {
                                ($0, $0 == .apple ? "Apple" : "Parakeet")
                            },
                            selection: $settings.engine
                        )

                        Hint(settings.engine == .apple
                             ? "Apple's on-device transcriber. Streams text while you speak, "
                               + "and needs no download."
                             : "Parakeet on the Neural Engine. More accurate on English, but "
                               + "resolves only on release — no live text. ~470 MB model, "
                               + "downloaded from the menu bar item.")
                    }
                }

                MeetingsSettingsCards()

                Card {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SectionLabel(text: "Cleanup")

                        SettingToggle(
                            title: "Clean up transcripts",
                            isOn: $settings.cleanupEnabled
                        )
                        Hint("Strips fillers, fixes spacing and punctuation. Dictionary "
                             + "corrections run either way.")

                        if settings.cleanupEnabled {
                            Divider().padding(.vertical, DS.Space.xs)

                            SettingToggle(
                                title: "Smart cleanup",
                                isOn: $settings.smartCleanup,
                                isEnabled: FoundationModelFormatter.isAvailable
                            )
                            Hint(FoundationModelFormatter.unavailableReason
                                 ?? "Apple's on-device model handles punctuation, paragraphing "
                                  + "and spoken corrections like \"make that three, actually\". "
                                  + "Falls back to the rule-based pass if it stalls.")
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SectionLabel(text: "General")

                        SettingToggle(
                            title: "Start Murmur at login",
                            isOn: $settings.launchAtLogin
                        )

                        if LoginItem.state == .requiresApproval {
                            HStack(spacing: DS.Space.sm) {
                                StatusDot(color: DS.Color.warning, isLit: true, size: 6)
                                Hint("Needs approval in System Settings ▸ General ▸ Login Items.")
                                Spacer()
                                ActionButton(title: "Open", emphasis: .quiet) {
                                    LoginItem.openLoginItemsSettings()
                                }
                            }
                        } else {
                            Hint("The push-to-talk trigger only works while Murmur is running.")
                        }

                        Divider().padding(.vertical, DS.Space.xs)

                        SettingToggle(title: "Sound on start and stop", isOn: $settings.soundEnabled)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SectionLabel(text: "Permissions")

                        PermissionRow(
                            title: "Accessibility",
                            detail: "Needed for the trigger, the paste shortcut, and inserting text.",
                            isGranted: Permissions.hasAccessibility,
                            action: Permissions.openAccessibilitySettings
                        )
                        PermissionRow(
                            title: "Microphone",
                            detail: "Needed to hear you.",
                            isGranted: Permissions.hasMicrophone,
                            action: Permissions.openMicrophoneSettings
                        )
                    }
                }
            }
            .padding(DS.Space.xl)
        }
        .background(DS.Color.window)
        .frame(width: 580, height: 760)
    }

    // MARK: - Recording a trigger

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
            try? await Task.sleep(for: .seconds(15))
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

    /// Never lets the last trigger be removed — with none armed the tap has nothing to watch
    /// and dictation silently stops working, with no visible cause.
    private func remove(_ trigger: PushToTalkTrigger) {
        guard settings.triggers.count > 1 else { return }
        var updated = settings.triggers
        updated.remove(trigger)
        settings.triggers = updated
        controller.reloadHotkey()
    }
}

private struct WarningNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(DS.Color.warning)
            Hint(text)
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.warning.opacity(0.10), in: .rect(cornerRadius: DS.Radius.sm))
    }
}

/// A toggle with the label on the left and the switch pushed to the trailing edge, which is
/// how macOS lays out settings — SwiftUI's default puts them adjacent.
private struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        HStack {
            Text(title)
                .font(DS.Font.body)
                .foregroundStyle(isEnabled ? DS.Color.text : DS.Color.textTertiary)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!isEnabled)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            StatusDot(
                color: isGranted ? DS.Color.success : DS.Color.warning,
                isLit: true,
                size: 7
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.text)
                Hint(detail)
            }
            Spacer()
            if isGranted {
                Chip(text: "Granted", tint: DS.Color.success, filled: true)
            } else {
                ActionButton(title: "Grant…", emphasis: .normal, action: action)
            }
        }
    }
}
