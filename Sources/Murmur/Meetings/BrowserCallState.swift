import ApplicationServices
import Foundation

/// Audio devices stay open on Meet's preview screen. Only an in-call control proves
/// that the user has joined; a meeting title or matching calendar event does not.
enum BrowserCallState: Equatable, Sendable {
    case unknown, preview, active

    static func googleMeet(buttonLabels: [String]) -> Self {
        let labels = buttonLabels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if labels.contains(where: { $0 == "leave call" || $0.hasPrefix("leave call (") }) { return .active }
        if labels.contains(where: { ["join now", "ask to join", "rejoin", "cancel request"].contains($0) }) { return .preview }
        return .unknown
    }
}

/// Read only meeting-window button labels using the existing Accessibility grant.
/// Runs off the main actor, is bounded, and never stores browser page contents.
enum BrowserCallReader {
    static func googleMeet(pid: pid_t) -> BrowserCallState {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return .unknown }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(400))
        var labels: [String] = []
        var remaining = 1_000
        for window in windows.prefix(12) {
            guard let title = attribute(window, kAXTitleAttribute) as? String,
                  MeetingAppRegistry.webService(matching: title)?.label == "Google Meet" else { continue }
            var stack = [window]
            while let element = stack.popLast(), remaining > 0, ContinuousClock.now < deadline {
                remaining -= 1
                if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole {
                    for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
                        if let label = attribute(element, key) as? String { labels.append(label) }
                    }
                    if BrowserCallState.googleMeet(buttonLabels: labels) == .active { return .active }
                }
                if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                    stack.append(contentsOf: children.reversed())
                }
            }
        }
        return BrowserCallState.googleMeet(buttonLabels: labels)
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
}
