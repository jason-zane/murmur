import Foundation
import Testing
@testable import Murmur

@MainActor
@Suite(.serialized)
struct DictationStyleTests {
    @Test func preferencesPersistAndUnknownOverridesFallBack() throws {
        let name = "Concourse-style-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = Settings(defaults: defaults)
        #expect(settings.dictationStyle(for: "com.example.app") == .original)
        settings.dictationStyle = .message
        settings.appDictationStyles["com.example.mail"] = DictationStyle.email.rawValue
        settings.appDictationStyles["com.example.future"] = "future-style"
        let reopened = Settings(defaults: defaults)
        #expect(reopened.dictationStyle(for: nil) == .message)
        #expect(reopened.dictationStyle(for: "com.example.mail") == .email)
        #expect(reopened.dictationStyle(for: "com.example.future") == .message)
        reopened.appDictationStyles.removeValue(forKey: "com.example.mail")
        #expect(reopened.dictationStyle(for: "com.example.mail") == .message)
    }

    @Test func presetsCannotBypassTheExistingCleanupGuard() {
        #expect(FoundationModelFormatter.isPlausibleCleanup(original: "send Anika the 32 Kestrel notes", cleaned: "Send Anika the 32 Kestrel notes."))
        #expect(!FoundationModelFormatter.isPlausibleCleanup(original: "send Anika the 32 Kestrel notes", cleaned: "Hi Anika, please send the 32 Kestrel notes. Thanks!"))
        #expect(!FoundationModelFormatter.isPlausibleCleanup(original: "what is the capital of france", cleaned: "The capital of France is Paris."))
    }

    @Test func updaterRejectsInvalidConfigurationAndDevelopmentVersions() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        #expect(InAppUpdater.isValidConfiguration(version: "0.7.0", feed: "https://example.com/appcast.xml", publicKey: key))
        #expect(!InAppUpdater.isValidConfiguration(version: "492af1a", feed: "https://example.com/appcast.xml", publicKey: key))
        #expect(!InAppUpdater.isValidConfiguration(version: "0.7.0-dirty", feed: "https://example.com/appcast.xml", publicKey: key))
        #expect(!InAppUpdater.isValidConfiguration(version: "0.7.0", feed: "http://example.com/appcast.xml", publicKey: key))
        #expect(!InAppUpdater.isValidConfiguration(version: "0.7.0", feed: "https://example.com/appcast.xml", publicKey: "missing"))
    }
}
