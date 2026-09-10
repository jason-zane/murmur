import AppKit
import SwiftUI

// Rows shared by the Settings tabs, onboarding and the home view.

/// A permission as macOS actually reports it, with the way to grant it.
struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    var grantTitle = "Grant…"
    let action: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            StatusDot(
                color: isGranted ? DS.Color.success : DS.Color.warning,
                isLit: true,
                size: DS.Layout.permissionDot
            )
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.text)
                Hint(detail)
            }
            Spacer()
            if isGranted {
                Chip(text: "Granted", tint: DS.Color.success, filled: true)
            } else {
                ActionButton(title: grantTitle, emphasis: .normal, action: action)
            }
        }
    }
}

/// One on-device model: what it is, whether it's on disk, and the download if it isn't.
struct ModelRow: View {
    let kind: ModelKind
    let library: ModelLibrary
    let onChanged: () -> Void

    @State private var onDisk = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            StatusDot(color: onDisk ? DS.Color.success : DS.Color.textTertiary, isLit: true, size: DS.Layout.permissionDot)
                .padding(.top, DS.Space.compact)
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                HStack(spacing: DS.Space.sm) {
                    Text(kind.title)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.text)
                    Readout(kind.sizeHint, color: DS.Color.textTertiary)
                }
                Hint(kind.detail)
                if let progress = library.progress[kind] {
                    ProgressView(value: progress)
                        .controlSize(.small)
                        .tint(DS.Color.accent)
                        .frame(maxWidth: DS.Layout.modelProgress)
                        .padding(.top, DS.Space.xxs)
                }
                if let error = library.errors[kind] {
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if onDisk {
                Chip(text: "Installed", tint: DS.Color.success, filled: true)
            } else if library.isDownloading(kind) {
                ActionButton(title: "Downloading…", emphasis: .quiet) {}.disabled(true)
            } else {
                ActionButton(title: "Download", emphasis: .normal) { library.download(kind) }
            }
        }
        .onAppear { onDisk = kind.isDownloaded }
        .onChange(of: library.progress[kind]) { _, progress in
            if progress == nil {
                onDisk = kind.isDownloaded
                onChanged()
            }
        }
    }
}

/// Apple or Parakeet. Parakeet's download sits inline, so choosing it never turns into a
/// hidden 470 MB fetch behind the next held key.
struct EngineRow: View {
    @Binding var selection: SpeechEngineChoice
    let hint: String
    @State private var library = ModelLibrary.shared
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Segmented(
                options: SpeechEngineChoice.allCases.map { ($0, $0.displayName) },
                selection: $selection
            )
            Hint(hint)
            if selection == .parakeet, !parakeetOnDisk {
                ModelRow(kind: .parakeet, library: library) {
                    parakeetOnDisk = ParakeetModels.isDownloaded
                }
            }
        }
        .onAppear { parakeetOnDisk = ParakeetModels.isDownloaded }
    }
}
