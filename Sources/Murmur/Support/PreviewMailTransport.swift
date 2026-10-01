import Foundation

/// Only the isolated debug preview can populate this transport. Production builds
/// receive no identity or data, and all mutations fail before any network request.
@MainActor final class PreviewMailTransport: CloudSyncTransport {
    var userID: String? {
        PreviewEnvironment.isActive && PreviewEnvironment.launchAction == "mail" ? "synthetic-mail-preview" : nil
    }
    func request(_ path: String, method: String, body: Data?) async throws -> Data {
        guard userID != nil, method == "GET" else { throw CloudHTTPError(status: 403, message: "Account actions are disabled in this synthetic preview.") }
        let result: [String: Any]
        if path == "api/mail" {
            result = ["accounts": [["id": "preview-personal", "email": "alex@example.invalid"], ["id": "preview-work", "email": "alex@northwind.invalid"]], "outbox": []]
        } else if path.contains("thread=") {
            let svg = Data("<svg xmlns='http://www.w3.org/2000/svg' width='480' height='80'><rect width='480' height='80' fill='#eef0fa'/><text x='20' y='46' fill='#4338ca' font-size='22'>Northwind · embedded image</text></svg>".utf8).base64EncodedString()
            let html = "<h2>Ready for the next chapter</h2><p>Thanks for reviewing the design. Here are the two images for our next conversation.</p><img src=\"data:image/svg+xml;base64,\(svg)\" alt=\"Northwind embedded image\"><p>Remote image</p><img data-concourse-image-src=\"https://placehold.co/480x120/png?text=Concourse+sample\" alt=\"Concourse remote sample\"><p>Both images should render when this message opens.</p>"
            result = ["messages": [["id": "preview-message", "thread_id": "preview-thread", "subject": "Design review and next steps", "from": "Priya Nair <priya@northwind.invalid>", "to": "Alex <alex@example.invalid>", "cc": "", "bcc": "", "date": "2026-10-02T00:00:00Z", "text": "Thanks for reviewing the design. Let's discuss the next steps.", "html": html, "source_html": html, "reply_to": "", "message_id": "<preview@northwind.invalid>", "in_reply_to": "", "references": "", "attachments": []]]]
        } else {
            result = ["threads": [["id": "preview-thread", "subject": "Design review and next steps", "from": "Priya Nair", "date": "2026-10-02T00:00:00Z", "snippet": "Two images and a few next steps for our next conversation.", "unread": true, "starred": false]], "next_page": NSNull()]
        }
        return try JSONSerialization.data(withJSONObject: result)
    }
}
