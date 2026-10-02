import Testing
@testable import Murmur

struct MailSenderPresentationTests {
    @Test func usesSuppliedNameAndRetainsUnknownAddressFallback() {
        #expect(mailSenderName("Priya Example <priya@example.invalid>") == "Priya Example")
        #expect(mailSenderName(#""Doe, Jane" <jane@example.invalid>"#) == "Doe, Jane")
        #expect(mailSenderName(#""Jane \"JJ\" Doe" <jane@example.invalid>"#) == #"Jane "JJ" Doe"#)
        #expect(mailSenderName("Zoë 李 <zoe@example.invalid>") == "Zoë 李")
        #expect(mailSenderName("sam@example.invalid") == "sam@example.invalid")
        #expect(mailSenderName(#""" <sam@example.invalid>"#) == "sam@example.invalid")
        #expect(mailSenderName("<sam@example.invalid>") == "sam@example.invalid")
        #expect(mailSenderName("") == "Unknown sender")
        #expect(mailAddresses(#""Doe, Jane" <jane@example.invalid>"#) == [#""Doe, Jane" <jane@example.invalid>"#])
    }
}
