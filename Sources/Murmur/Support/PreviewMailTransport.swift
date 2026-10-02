import Foundation

/// Only the isolated debug preview can populate this transport. Production builds
/// receive no identity or data, and mailbox labels change only in memory; no network request is made.
@MainActor final class PreviewMailTransport: CloudSyncTransport {
    var userID: String? {
        PreviewEnvironment.isActive && PreviewEnvironment.launchAction == "mail" ? "synthetic-mail-preview" : nil
    }
    private var bin: Set<String> = [], archive: Set<String> = [], stars: Set<String> = [], read: Set<String> = []
    func request(_ path: String, method: String, body: Data?) async throws -> Data {
        guard userID != nil else { throw CloudHTTPError(status: 403, message: "This preview is unavailable.") }
        if method == "POST" {
            guard let body, let payload = try JSONSerialization.jsonObject(with: body) as? [String: String], let account = payload["account"], ["preview-personal", "preview-work"].contains(account), payload["id"] == "preview-thread" else { throw CloudHTTPError(status: 403, message: "Gmail saves and sends are disabled in this synthetic preview.") }
            switch payload["action"] {
            case "trash": bin.insert(account)
            case "restore": bin.remove(account); archive.remove(account)
            case "archive": archive.insert(account)
            case "star": stars.insert(account)
            case "unstar": stars.remove(account)
            case "read": read.insert(account)
            case "unread": read.remove(account)
            default: throw CloudHTTPError(status: 403, message: "This action is disabled in the synthetic preview.")
            }
            return Data("{}".utf8)
        }
        guard method == "GET" else { throw CloudHTTPError(status: 403, message: "This action is disabled in the synthetic preview.") }
        let result: [String: Any]
        if path == "api/mail" {
            result = ["accounts": [["id": "preview-personal", "email": "alex@example.invalid"], ["id": "preview-work", "email": "alex@northwind.invalid"]], "outbox": []]
        } else if path.contains("thread=") {
            let svg = Data("<svg xmlns='http://www.w3.org/2000/svg' width='480' height='80'><rect width='480' height='80' fill='#eef0fa'/><text x='20' y='46' fill='#4338ca' font-size='22'>Northwind · embedded image</text></svg>".utf8).base64EncodedString()
            let html = "<h2>Ready for the next chapter</h2><p>Thanks for reviewing the design. Here are the two images for our next conversation.</p><img src=\"data:image/svg+xml;base64,\(svg)\" alt=\"Northwind embedded image\"><p>Remote image</p><img data-concourse-image-src=\"https://placehold.co/480x120/png?text=Concourse+sample\" alt=\"Concourse remote sample\"><p>Both images should render when this message opens.</p>"
            result = ["messages": [["id": "preview-message", "thread_id": "preview-thread", "subject": "Design review and next steps", "from": "Priya Nair <priya@northwind.invalid>", "to": "Alex <alex@example.invalid>", "cc": "", "bcc": "", "date": "2026-10-02T00:00:00Z", "text": "Thanks for reviewing the design. Let's discuss the next steps.", "html": html, "source_html": html, "reply_to": "", "message_id": "<preview@northwind.invalid>", "in_reply_to": "", "references": "", "attachments": []]]]
        } else {
            let params = URLComponents(string: path)?.queryItems ?? []
            let account = params.first { $0.name == "account" }?.value ?? "preview-personal"
            let query = params.first { $0.name == "q" || $0.name == "query" }?.value ?? "in:inbox"
            let visible = query == "in:trash" ? bin.contains(account) : !bin.contains(account) && (query.contains("in:inbox") ? !archive.contains(account) : query == "is:starred" ? stars.contains(account) : true)
            let thread: [String: Any] = ["id": "preview-thread", "subject": "Design review and next steps", "from": "Priya Nair", "date": "2026-10-02T00:00:00Z", "snippet": "Two images and a few next steps for our next conversation.", "unread": !read.contains(account), "starred": stars.contains(account)]
            result = ["threads": visible ? [thread] : [], "next_page": NSNull()]
        }
        return try JSONSerialization.data(withJSONObject: result)
    }
}
