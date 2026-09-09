import Foundation

/// What to do when an app is found holding a two-way call.
enum MeetingAppRule: String, Codable, CaseIterable, Sendable {
    /// Start recording without asking.
    case auto
    /// Show the offer strip.
    case ask
    /// Never offer, never record, for this app.
    case never

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .ask: "Ask"
        case .never: "Never"
        }
    }
}

/// A known meeting app, by bundle identifier.
struct MeetingApp: Sendable, Hashable, Identifiable {
    enum Kind: Sendable { case native, browser }

    let bundleID: String
    let label: String
    let kind: Kind
    /// What an ad-hoc call in this app is called in the offer — "Slack huddle", "FaceTime
    /// call" — because "Meeting detected" for a huddle reads as the app not knowing.
    let callNoun: String

    var id: String { bundleID }
}

/// The apps detection can name. Anything else with two-way audio is still detected, just
/// offered quietly and labelled by its process name.
///
/// Browsers are listed so the front window's title can be read — that is how a Chrome tab
/// on meet.google.com is told apart from a YouTube tab that happened to be granted the mic.
enum MeetingAppRegistry {
    static let apps: [MeetingApp] = [
        MeetingApp(bundleID: "us.zoom.xos", label: "Zoom", kind: .native, callNoun: "Zoom meeting"),
        MeetingApp(bundleID: "com.microsoft.teams2", label: "Teams", kind: .native, callNoun: "Teams meeting"),
        MeetingApp(bundleID: "com.microsoft.teams", label: "Teams", kind: .native, callNoun: "Teams meeting"),
        MeetingApp(bundleID: "com.tinyspeck.slackmacgap", label: "Slack", kind: .native, callNoun: "Slack huddle"),
        MeetingApp(bundleID: "com.apple.FaceTime", label: "FaceTime", kind: .native, callNoun: "FaceTime call"),
        MeetingApp(bundleID: "net.whatsapp.WhatsApp", label: "WhatsApp", kind: .native, callNoun: "WhatsApp call"),
        MeetingApp(bundleID: "com.hnc.Discord", label: "Discord", kind: .native, callNoun: "Discord call"),
        MeetingApp(bundleID: "com.cisco.webexmeetingsapp", label: "Webex", kind: .native, callNoun: "Webex meeting"),
        MeetingApp(bundleID: "com.loom.desktop", label: "Loom", kind: .native, callNoun: "Loom recording"),
        MeetingApp(bundleID: "com.google.Chrome", label: "Chrome", kind: .browser, callNoun: "browser call"),
        MeetingApp(bundleID: "com.apple.Safari", label: "Safari", kind: .browser, callNoun: "browser call"),
        MeetingApp(bundleID: "company.thebrowser.Browser", label: "Arc", kind: .browser, callNoun: "browser call"),
        MeetingApp(bundleID: "com.brave.Browser", label: "Brave", kind: .browser, callNoun: "browser call"),
        MeetingApp(bundleID: "org.mozilla.firefox", label: "Firefox", kind: .browser, callNoun: "browser call"),
        MeetingApp(bundleID: "com.microsoft.edgemac", label: "Edge", kind: .browser, callNoun: "browser call"),
    ]

    private static let byBundle: [String: MeetingApp] = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0) })

    static func app(for bundleID: String) -> MeetingApp? { byBundle[bundleID] }

    /// Web meeting services, matched against a browser window title. Titles are the one
    /// thing every meeting page sets reliably: "Meet – abc-defg-hij", "Zoom Meeting",
    /// "Microsoft Teams". Matching is on the title, never the URL — no automation
    /// permission is needed to read a window title through Accessibility.
    struct WebService: Sendable {
        let label: String
        let titleNeedles: [String]
    }

    static let webServices: [WebService] = [
        WebService(label: "Google Meet", titleNeedles: ["Meet – ", "Meet - ", "Google Meet"]),
        WebService(label: "Zoom", titleNeedles: ["Zoom Meeting", "Zoom Webinar", "- Zoom"]),
        WebService(label: "Teams", titleNeedles: ["Microsoft Teams"]),
        WebService(label: "Webex", titleNeedles: ["Webex"]),
        WebService(label: "Whereby", titleNeedles: ["Whereby"]),
        WebService(label: "Around", titleNeedles: ["Around"]),
        WebService(label: "Jitsi", titleNeedles: ["Jitsi"]),
        WebService(label: "Discord", titleNeedles: ["Discord"]),
    ]

    static func webService(matching windowTitle: String) -> WebService? {
        webServices.first { service in
            service.titleNeedles.contains { windowTitle.localizedCaseInsensitiveContains($0) }
        }
    }

    /// The identifiers that should never be treated as a call even with two-way audio:
    /// ourselves, and system audio plumbing.
    static let ignoredBundleIDs: Set<String> = [
        "com.jasonhunt.murmur",
        "com.apple.audio.coreaudiod",
        "com.apple.controlcenter",
        "com.apple.Siri",
        "com.apple.assistantd",
        "com.apple.VoiceMemos",
        "com.apple.Music",
        "com.spotify.client",
    ]
}
