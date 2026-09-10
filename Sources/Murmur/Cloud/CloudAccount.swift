import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security

struct CloudConfiguration: Codable, Sendable {
    let ready: Bool
    let siteURL: URL
    let supabaseURL: URL
    let publishableKey: String
    let desktopClientID: String
    let mcpURL: URL
}

struct CloudCredentials: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String
    var configuration: CloudConfiguration
}

struct CloudHTTPError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

@MainActor @Observable
final class CloudAccount: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = CloudAccount()
    /// The hosted backend, stamped into Info.plist at build time (`make app SITE_URL=…`)
    /// so a self-hosted deployment needs no source change. Stored credentials carry the
    /// origin they were issued for; changing it means sign out, sign in.
    static let defaultSite: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "VoiceNotesSiteURL") as? String,
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.host != nil {
            return url
        }
        return URL(string: "https://murmur-rho-pied.vercel.app")!
    }()

    /// https everywhere, except a developer's own machine.
    static func isAcceptableOrigin(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        return url.scheme == "http" && (url.host == "localhost" || url.host == "127.0.0.1")
    }
    private(set) var credentials: CloudCredentials?
    private(set) var isSigningIn = false
    var message: String?
    private var authSession: ASWebAuthenticationSession?
    private var refreshing: Task<CloudCredentials, Error>?
    var isConnected: Bool { credentials != nil }
    var email: String { credentials?.email ?? "" }
    var siteURL: URL { credentials?.configuration.siteURL ?? Self.defaultSite }
    var mcpURL: URL { credentials?.configuration.mcpURL ?? Self.defaultSite.appendingPathComponent("mcp") }

    override init() {
        super.init()
        if !PreviewEnvironment.isActive { credentials = try? CloudKeychain.read() }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    func signIn() async {
        guard !isSigningIn, !PreviewEnvironment.isActive else { return }
        isSigningIn = true; message = nil
        defer { isSigningIn = false; authSession = nil }
        do {
            var configRequest = URLRequest(url: Self.defaultSite.appendingPathComponent("api/config"))
            configRequest.timeoutInterval = 20
            let configData = try await Self.send(configRequest)
            let configuration = try JSONDecoder().decode(CloudConfiguration.self, from: configData)
            guard configuration.ready, !configuration.desktopClientID.isEmpty,
                  Self.isAcceptableOrigin(configuration.siteURL), Self.isAcceptableOrigin(configuration.supabaseURL) else {
                throw CloudHTTPError(status: 503, message: "Voice Notes cloud is still being connected. Your local notes are ready to use.")
            }
            let verifier = try Self.randomString(), state = try Self.randomString()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
            var url = URLComponents(url: configuration.supabaseURL.appendingPathComponent("auth/v1/oauth/authorize"), resolvingAgainstBaseURL: false)!
            url.queryItems = [
                .init(name: "client_id", value: configuration.desktopClientID),
                .init(name: "redirect_uri", value: "murmur://oauth/callback"),
                .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email profile"),
                .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state),
            ]
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "murmur",
                    completionHandler: Self.authenticationCompletion(resuming: continuation))
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                authSession = session
                if !session.start() { continuation.resume(throwing: CloudHTTPError(status: 400, message: "The sign-in window could not open.")) }
            }
            let parameters = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard callback.host == "oauth", callback.path == "/callback",
                  parameters.first(where: { $0.name == "state" })?.value == state,
                  let code = parameters.first(where: { $0.name == "code" })?.value else {
                throw CloudHTTPError(status: 400, message: "This sign-in expired or was cancelled. Please try again.")
            }
            let token = try await Self.token(configuration, parameters: ["grant_type": "authorization_code", "code": code,
                "code_verifier": verifier, "redirect_uri": "murmur://oauth/callback"])
            var profileRequest = URLRequest(url: configuration.supabaseURL.appendingPathComponent("auth/v1/user"))
            profileRequest.setValue("Bearer " + token.access_token, forHTTPHeaderField: "Authorization")
            profileRequest.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
            let profile = try JSONDecoder().decode(Profile.self, from: await Self.send(profileRequest))
            let value = CloudCredentials(accessToken: token.access_token, refreshToken: token.refresh_token,
                expiresAt: Date().addingTimeInterval(token.expires_in), userID: profile.id, email: profile.email ?? "Your account", configuration: configuration)
            try CloudKeychain.save(value); credentials = value
            CloudSync.shared.start()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            message = "Sign-in cancelled. Your local notes are still here."
        } catch { message = error.localizedDescription }
    }

    /// AuthenticationServices calls back from an XPC queue. A closure created directly
    /// inside signIn inherits MainActor and Swift 6 traps before its body runs. Only
    /// resume the thread-safe continuation here; signIn resumes on MainActor itself.
    nonisolated static func authenticationCompletion(resuming continuation: CheckedContinuation<URL, any Error>)
        -> @Sendable (URL?, (any Error)?) -> Void {
        { callback, error in
            if let error { continuation.resume(throwing: error) }
            else if let callback { continuation.resume(returning: callback) }
            else { continuation.resume(throwing: CloudHTTPError(status: 400, message: "Sign-in did not return a connection.")) }
        }
    }

    func signOut() {
        refreshing?.cancel(); refreshing = nil
        CloudSync.shared.stop()
        do { try CloudKeychain.remove(); credentials = nil; message = "Signed out. Notes on this Mac are kept." }
        catch { message = error.localizedDescription }
    }

    func accessToken() async throws -> String {
        guard let value = credentials else { throw CloudHTTPError(status: 401, message: "Sign in to sync your notes.") }
        if value.expiresAt.timeIntervalSinceNow > 90 { return value.accessToken }
        if let refreshing { return try await refreshing.value.accessToken }
        let task = Task<CloudCredentials, Error> {
            let response = try await Self.token(value.configuration, parameters: ["grant_type": "refresh_token", "refresh_token": value.refreshToken])
            var updated = value
            updated.accessToken = response.access_token; updated.refreshToken = response.refresh_token
            updated.expiresAt = Date().addingTimeInterval(response.expires_in)
            try Task.checkCancellation()
            try CloudKeychain.save(updated)
            return updated
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            let updated = try await task.value
            guard credentials?.userID == updated.userID else { throw CancellationError() }
            credentials = updated; return updated.accessToken
        } catch { throw error }
    }

    private struct Profile: Decodable { let id: String; let email: String? }
    private struct Token: Decodable { let access_token: String; let refresh_token: String; let expires_in: TimeInterval }
    private static func token(_ configuration: CloudConfiguration, parameters: [String: String]) async throws -> Token {
        var request = URLRequest(url: configuration.supabaseURL.appendingPathComponent("auth/v1/oauth/token"))
        request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        var form = URLComponents()
        form.queryItems = (parameters.merging(["client_id": configuration.desktopClientID]) { a, _ in a }).map { .init(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return try JSONDecoder().decode(Token.self, from: await send(request))
    }
    static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let text = error?["message"] as? String ?? error?["error_description"] as? String ?? error?["error"] as? String
            throw CloudHTTPError(status: response.statusCode, message: text ?? "Voice Notes cloud returned \(response.statusCode). Try again shortly.")
        }
        return data
    }
    private static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw URLError(.unknown) }
        return Data(bytes).base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

@MainActor private enum CloudKeychain {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.jasonhunt.murmur.cloud", kSecAttrAccount as String: "account"]
    static func read() throws -> CloudCredentials? {
        var request = query; request[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return try JSONDecoder().decode(CloudCredentials.self, from: data)
    }
    static func save(_ value: CloudCredentials) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query; attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let created = SecItemAdd(attributes as CFDictionary, nil)
            guard created == errSecSuccess else { throw failure(created) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { throw failure(status) }
    }
    static func failure(_ status: OSStatus) -> CloudHTTPError {
        CloudHTTPError(status: Int(status), message: "The macOS Keychain could not save this connection. Unlock your Mac and try again.")
    }
}
