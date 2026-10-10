import AppKit
import Foundation
@preconcurrency import Sparkle

/// Sparkle verifies the update archive against the public key embedded in the signed app.
/// Development and preview builds cannot initialise the production updater.
@MainActor
final class InAppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = InAppUpdater()
    private var controller: SPUStandardUpdaterController?
    private var isBusy: @MainActor () -> Bool = { true }
    private var relaunchTask: Task<Void, Never>?
    var isEnabled: Bool { controller != nil }

    static func isValidConfiguration(version: String?, feed: String?, publicKey: String?) -> Bool {
        guard let version, UpdateCheck.semver(version) != nil,
              let feed, let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let publicKey, Data(base64Encoded: publicKey)?.count == 32 else { return false }
        return true
    }

    func start(isBusy: @escaping @MainActor () -> Bool) {
        #if !DEBUG
        guard controller == nil, !PreviewEnvironment.isActive,
              Bundle.main.bundleURL.pathExtension == "app",
              Self.isValidConfiguration(version: UpdateCheck.currentVersion,
                  feed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                  publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) else { return }
        self.isBusy = isBusy
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.sendsSystemProfile = false
        controller.updater.automaticallyDownloadsUpdates = false
        do {
            try controller.updater.start()
            controller.updater.automaticallyChecksForUpdates = Settings.shared.checkForUpdates
            self.controller = controller
        } catch { Log.app.error("Updater could not start: \(error.localizedDescription)") }
        #endif
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    @discardableResult
    func check() throws -> Bool {
        guard !isBusy() else { throw Self.busyError }
        guard let controller, controller.updater.canCheckForUpdates else { return false }
        controller.checkForUpdates(nil)
        return true
    }

    private static var busyError: NSError {
        NSError(domain: "com.jasonhunt.murmur.updater", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Finish dictation or stop the meeting before updating Concourse."])
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if isBusy() { throw Self.busyError }
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isBusy() else { return false }
        relaunchTask?.cancel()
        relaunchTask = Task { @MainActor in
            while isBusy() {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            installHandler()
        }
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        UpdateCheck.shared.finishedInAppCheck(error: error)
    }
}
