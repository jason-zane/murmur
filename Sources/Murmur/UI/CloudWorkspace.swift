import AppKit
import SwiftUI
import WebKit

/// Booking and cloud connection forms use the same implementation on both platforms.
/// The isolated cookie store never receives the Mac's refresh token and is discarded
/// when the signed-in account changes. Only the configured origin can render in this view.
struct CloudWorkspace: View {
    let path: String
    @State private var account = CloudAccount.shared
    @State private var retry = UUID()
    @State private var error: String?
    var body: some View {
        VStack(spacing: DS.Space.zero) {
            if account.isConnected && !PreviewEnvironment.isActive {
                if let error {
                    InlineNotice(text: error, tone: .warning) {
                        ActionButton(title: "Try again", emphasis: .normal) { self.error = nil; retry = UUID() }
                    }.padding(DS.Space.xl)
                }
                SharedWorkspaceWebView(path: path, error: $error)
                    .id("\(account.credentials?.userID ?? "")-\(path)-\(retry)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(icon: "calendar.badge.clock", label: "Your meeting workspace", detail: "Sign in to manage booking links, availability and messages on Mac and web.") {
                    ActionButton(title: "Sign in to Voice Notes", emphasis: .prominent) { SettingsRouter.shared.open(.connections) }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SharedWorkspaceWebView: NSViewRepresentable {
    let path: String
    @Binding var error: String?
    func makeCoordinator() -> Coordinator { Coordinator(error: $error) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // Presentation only. No credentials are injected into the page.
        let css = "document.documentElement.classList.add('native-workspace');"
        configuration.userContentController.addUserScript(WKUserScript(source: css, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.origin = CloudAccount.shared.siteURL
        Task { @MainActor in
            do {
                let token = try await CloudAccount.shared.accessToken()
                var url = URLComponents(url: CloudAccount.shared.siteURL.appendingPathComponent("api/native/session"), resolvingAgainstBaseURL: false)!
                url.queryItems = [URLQueryItem(name: "page", value: path)]
                var request = URLRequest(url: url.url!)
                request.httpMethod = "POST"
                request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                view.load(request)
            } catch { self.error = error.localizedDescription }
        }
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var error: String?
        var origin: URL?
        init(error: Binding<String?>) { _error = error }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if url.scheme == origin?.scheme && url.host == origin?.host && url.port == origin?.port {
                if url.path.hasPrefix("/api/google/connect") {
                    NSWorkspace.shared.open(url)
                    return .cancel
                }
                return .allow
            }
            if ["https", "murmur", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            return .cancel
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { self.error = "Couldn’t open this workspace. Check your connection and try again." }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            self.error = "This workspace lost its connection. Try again."
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
                error = "This workspace needs attention. Check your sign-in and try again."
                return .cancel
            }
            return .allow
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, url.scheme == "https" { NSWorkspace.shared.open(url) }
            return nil
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
            let alert = NSAlert(); alert.messageText = "Voice Notes"; alert.informativeText = message
            alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
            guard let window = webView.window else { completionHandler(false); return }
            alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn) }
        }
    }
}
