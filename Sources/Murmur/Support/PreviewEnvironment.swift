import Foundation

/// A debug build can preview an isolated notes directory without activating hotkeys,
/// reading calendars or starting meeting capture. Production launches never opt in.
enum PreviewEnvironment {
    static var root: URL? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["MURMUR_UI_TESTING"] == "1",
           let path = environment["MURMUR_SESSIONS_DIR"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        #endif
        return nil
    }
    static var isActive: Bool { root != nil }

    /// `MURMUR_PREVIEW_OPEN` names something to raise on launch, so a preview can be
    /// captured without driving the UI: `settings[:tab]`, `onboarding`, or `session:<id>`.
    static var launchAction: String? {
        #if DEBUG
        guard isActive else { return nil }
        return ProcessInfo.processInfo.environment["MURMUR_PREVIEW_OPEN"]
        #else
        return nil
        #endif
    }

    /// The Settings tab named by `launchAction`, lower-cased; "" for the default tab.
    static var opensSettingsTab: String? {
        guard let value = launchAction, value.hasPrefix("settings") else { return nil }
        return value.split(separator: ":").dropFirst().first.map(String.init) ?? ""
    }
}
