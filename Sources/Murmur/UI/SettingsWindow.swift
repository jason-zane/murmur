import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case dictation = "Dictation"
    case meetings = "Meetings"
    case dictionary = "Dictionary"
    case connections = "Connections"

    var id: String { rawValue }
}

/// The one way to land on a particular Settings tab from elsewhere in the app. The scene
/// can only be opened through SwiftUI's `openSettings`, which lives in a view environment,
/// so the request is parked here and the menu bar label does the opening.
@MainActor
@Observable
final class SettingsRouter {
    static let shared = SettingsRouter()
    private(set) var requested: SettingsTab?

    func open(_ tab: SettingsTab) {
        requested = tab
        NotificationCenter.default.post(name: .murmurOpenSettings, object: nil)
    }

    func consume() -> SettingsTab? {
        defer { requested = nil }
        return requested
    }
}

/// Five tabs. Everything that isn't a note is here, and nothing is here twice.
struct SettingsWindow: View {
    @Bindable var controller: DictationController
    var onPreviewBar: () -> Void
    @State private var tab: SettingsTab = PreviewEnvironment.opensSettingsTab
        .flatMap { name in SettingsTab.allCases.first { $0.rawValue.lowercased() == name } } ?? .general
    @State private var router = SettingsRouter.shared

    var body: some View {
        VStack(spacing: DS.Space.zero) {
            Segmented(options: SettingsTab.allCases.map { ($0, $0.rawValue) }, selection: $tab)
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.xl)
                .padding(.bottom, DS.Space.lg)
            if tab == .dictionary {
                DictionaryPanel()
                    .padding([.horizontal, .bottom], DS.Space.xl)
            } else {
                ScrollView {
                    Group {
                        switch tab {
                        case .general: GeneralSettings()
                        case .dictation: DictationSettings(controller: controller, onPreviewBar: onPreviewBar)
                        case .meetings: MeetingsSettings()
                        case .connections: ConnectionsSettings()
                        case .dictionary: EmptyView()
                        }
                    }
                    .padding([.horizontal, .bottom], DS.Space.xl)
                }
            }
        }
        .background(DS.Color.window)
        .frame(minWidth: DS.Layout.settingsWidth, minHeight: DS.Layout.settingsMinHeight)
        .onAppear { if let requested = router.consume() { tab = requested } }
        .onChange(of: router.requested) { _, requested in if let requested { tab = router.consume() ?? requested } }
    }
}
