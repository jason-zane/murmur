import SwiftUI
import WebKit

/// Provider HTML has already been sanitised on the server. The reader additionally
/// has no message scripts, app bridge or persistent cookies. Remote images require
/// an explicit choice scoped to this exact message body.
struct MailHTMLReader: View {
    let html: String
    @State private var allowedHTML: String?
    @State private var height = DS.Layout.mailHTMLHeight
    @State private var width = DS.Space.zero
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if html.contains(" data-concourse-image-src=\"") {
                Text(allowedHTML == html ? "Remote images allowed for this message." : "Remote images are blocked. Loading them may tell the sender you opened this message.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                ActionButton(title: allowedHTML == html ? "Block remote images" : "Load remote images", emphasis: .quiet) { allowedHTML = allowedHTML == html ? nil : html }
            }
            if html.contains(" data-concourse-unavailable-image=\"") {
                Text("Some embedded images are unavailable. You can still download the attachments below.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            MailHTMLWebView(html: MailHTMLDocument.make(html, allowRemoteImages: allowedHTML == html), width: width, height: $height)
                .frame(height: height)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }.frame(maxWidth: .infinity, alignment: .leading)
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
        let view = MailContentWebView(frame: .zero, configuration: configuration)
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
        (view as? MailContentWebView)?.canScrollVertically = false
        view.loadHTMLString(html, baseURL: nil)
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
            let expectedHTML = html, expectedWidth = width
            webView.evaluateJavaScript("document.body.scrollHeight", in: nil, in: .defaultClient) { [weak self] result in
                guard let self, self.html == expectedHTML, self.width == expectedWidth, case .success(let value) = result, let number = value as? NSNumber else { return }
                (webView as? MailContentWebView)?.canScrollVertically = CGFloat(number.doubleValue) > DS.Layout.mailHTMLMaximumHeight
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


/// With a fully measured message, SwiftUI's conversation ScrollView owns vertical
/// scrolling. WebKit otherwise consumes wheel events even when it has no scroll range.
@MainActor
private final class MailContentWebView: WKWebView {
    var canScrollVertically = false
    override func scrollWheel(with event: NSEvent) {
        if canScrollVertically || abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
}

enum MailHTMLDocument {
    /// Only server-sanitised HTML is accepted here; source_html is for forwarding only.
    static func make(_ html: String, allowRemoteImages: Bool = false) -> String {
        let body = allowRemoteImages ? html.replacingOccurrences(of: " data-concourse-image-src=\"", with: " src=\"") : html
        let images = allowRemoteImages ? "data: https:" : "data:"
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="referrer" content="no-referrer"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src \(images); base-uri 'none'; form-action 'none'">
        <style>:root{color-scheme:light}body{margin:0;padding:0;font:\(DS.Layout.mailReaderFontSize)px system-ui;line-height:\(DS.Layout.mailReaderLineHeight);color:CanvasText;background:Canvas;overflow-wrap:anywhere}img{max-width:100%;height:auto}table{max-width:100%}blockquote{border-left:solid thin GrayText}</style></head><body>
        \(body)
        </body></html>
        """
    }
}
