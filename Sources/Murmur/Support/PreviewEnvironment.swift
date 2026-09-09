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
}
