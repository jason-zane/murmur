import Testing
@testable import Murmur

@MainActor
struct MailHTMLDocumentTests {
    @Test func remoteImagesStayBlockedUntilExplicitlyAllowed() {
        let html = "<table width=\"600\"><tr><td><img data-concourse-image-src=\"https://cdn.example.invalid/image.png\" alt=\"Example\"></td></tr></table>"
        let blocked = MailHTMLDocument.make(html)
        #expect(blocked.contains("img-src data:;"))
        #expect(!blocked.contains(" src=\"https:"))
        let allowed = MailHTMLDocument.make(html, allowRemoteImages: true)
        #expect(allowed.contains("img-src data: https:;"))
        #expect(allowed.contains(" src=\"https://cdn.example.invalid/image.png\""))
        #expect(MailHTMLDocument.make(html) == blocked)
        #expect(allowed.contains("default-src 'none'"))
        #expect(allowed.contains("form-action 'none'"))
        #expect(allowed.contains("no-referrer"))
        #expect(allowed.contains("<table width=\"600\">"))
    }
}
