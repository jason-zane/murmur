import AppKit
import Foundation
import Observation

/// Release builds use Sparkle's signed updates. Unconfigured builds retain the
/// GitHub release-page fallback; development versions never check production.
@MainActor
@Observable
final class UpdateCheck {
    static let shared = UpdateCheck()

    struct Release: Equatable {
        let version: String
        let url: URL
    }

    static let repository = "jason-zane/murmur"

    private(set) var available: Release?
    private(set) var lastChecked: Date?
    private(set) var isChecking = false
    private(set) var lastError: String?
    var supportsInAppUpdates: Bool { InAppUpdater.shared.isEnabled }

    private var loop: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let lastCheckedKey = "updateCheck.lastChecked"
    private static let interval: TimeInterval = 24 * 60 * 60

    /// The version this binary reports, or nil for a build that isn't a release.
    static var currentVersion: String? {
        guard let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              semver(raw) != nil else { return nil }
        return raw
    }

    private init() {
        lastChecked = defaults.object(forKey: lastCheckedKey) as? Date
    }

    func start() {
        guard loop == nil, !PreviewEnvironment.isActive else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if let self, Settings.shared.checkForUpdates, !supportsInAppUpdates {
                    let due = lastChecked.map { Date().timeIntervalSince($0) >= Self.interval } ?? true
                    if due { await check() }
                }
                do { try await Task.sleep(for: .seconds(60 * 60)) } catch { return }
            }
        }
    }

    /// One request. A development build (no semver) never reports an update.
    func check() async {
        guard !isChecking, let current = Self.currentVersion else { return }
        if supportsInAppUpdates {
            lastError = nil
            isChecking = true
            do { if try !InAppUpdater.shared.check() { isChecking = false } }
            catch { isChecking = false; lastError = error.localizedDescription }
            return
        }
        isChecking = true
        defer { isChecking = false }
        lastError = nil
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // 404 means no release yet, which is not an error worth showing.
                lastChecked = Date()
                defaults.set(lastChecked, forKey: lastCheckedKey)
                return
            }
            let latest = try JSONDecoder().decode(Latest.self, from: data)
            let version = latest.tag_name.hasPrefix("v") ? String(latest.tag_name.dropFirst()) : latest.tag_name
            lastChecked = Date()
            defaults.set(lastChecked, forKey: lastCheckedKey)
            available = Self.isNewer(version, than: current) ? Release(version: version, url: latest.html_url) : nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func open(_ release: Release) {
        NSWorkspace.shared.open(release.url)
    }

    func finishedInAppCheck(error: (any Error)?) {
        isChecking = false
        lastChecked = Date()
        defaults.set(lastChecked, forKey: lastCheckedKey)
        // Sparkle displays failures and the no-update result in its own standard UI.
    }

    private struct Latest: Decodable {
        let tag_name: String
        let html_url: URL
    }

    /// "1.2.3" → [1, 2, 3]; anything else nil.
    static func semver(_ text: String) -> [Int]? {
        guard text.range(of: "^[0-9]+(?:\\.[0-9]+){0,2}$", options: .regularExpression) != nil else { return nil }
        let parts = text.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.map { $0! } + Array(repeating: 0, count: 3 - parts.count)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = semver(candidate), let b = semver(current) else { return false }
        return a.lexicographicallyPrecedes(b) == false && a != b
    }
}
