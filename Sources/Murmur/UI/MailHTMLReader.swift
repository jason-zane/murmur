import SwiftUI
import WebKit

/// Provider HTML has already been sanitised on the server. The reader additionally
/// has no scripts, app bridge, persistent cookies or permission to load remote resources.
struct MailHTMLReader: View {
    let html: String
    @State private var height = DS.Layout.mailHTMLHeight
    @State private var width = DS.Space.zero
    var body: some View {
        MailHTMLWebView(html: html, width: width, height: $height)
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
private struct MailHTMLWebView: NSViewRepresentable {
    let html: String
    let width: CGFloat
    @Binding var height: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.height = $height
        guard context.coordinator.html != html else {
            if context.coordinator.width != width { context.coordinator.width = width; context.coordinator.measure(view) }
            return
        }
        context.coordinator.html = html; context.coordinator.width = width
        let document = """
        <!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <style>:root{color-scheme:light dark}body{margin:0;padding:0;font:\(DS.Layout.mailReaderFontSize)px system-ui;line-height:\(DS.Layout.mailReaderLineHeight);color:CanvasText;background:Canvas;overflow-wrap:anywhere}table{max-width:100%}blockquote{border-left:solid thin GrayText}</style>
        \(html)
        """
        view.loadHTMLString(document, baseURL: nil)
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var html: String?
        var width = DS.Space.zero
        var height: Binding<CGFloat>
        init(height: Binding<CGFloat>) { self.height = height }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { measure(webView) }
        func measure(_ webView: WKWebView) {
            // Only our fixed layout measurement runs in an isolated client world.
            // Message scripts remain disabled; there is no message-to-app bridge.
            webView.evaluateJavaScript("document.body.scrollHeight", in: nil, in: .defaultClient) { [weak self] result in
                guard let self, case .success(let value) = result, let number = value as? NSNumber else { return }
                let measured = min(DS.Layout.mailHTMLMaximumHeight, max(DS.Layout.mailHTMLMinimumHeight, CGFloat(number.doubleValue)))
                if self.height.wrappedValue != measured { self.height.wrappedValue = measured }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            return nil
        }
    }
}
