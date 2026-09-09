import AppKit
import Foundation
import ServiceManagement

/// Start Murmur when you log in.
///
/// A dictation app that isn't running is a dictation app that doesn't work — the hotkey
/// lives in this process, so until it launches, holding the key does nothing. For anything
/// meant to replace a commercial tool this is table stakes, not a nicety.
///
/// `SMAppService.mainApp` registers the *bundle*, so there's no separate helper target and
/// nothing to keep in sync. Two things to know about it:
///
/// - **It registers the bundle at its current path.** Registering a copy in
///   `~/Library/Caches` (where `make app` stages) would pin the login item to a build
///   artifact. `make install` puts the running copy in `/Applications` for this reason.
/// - **`.requiresApproval` is not a failure.** macOS may route the request through
///   System Settings ▸ General ▸ Login Items, where the user flips it on. Surfacing that
///   as an error would be wrong; surfacing it as success would be a lie.
@MainActor
enum LoginItem {

    enum State {
        case enabled
        case disabled
        /// Registered, but the user has to approve it in System Settings ▸ Login Items.
        case requiresApproval
        /// The bundle isn't somewhere macOS will register — typically still in a build dir.
        case unavailable

        var isOn: Bool { self == .enabled || self == .requiresApproval }
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    /// - Returns: the resulting state, so the caller can tell "on" from "on, pending approval".
    @discardableResult
    static func set(_ enabled: Bool) -> State {
        do {
            if enabled {
                // Re-registering an already-registered app throws rather than no-opping.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        return state
    }

    /// System Settings ▸ General ▸ Login Items, for the `.requiresApproval` case.
    static func openLoginItemsSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}
