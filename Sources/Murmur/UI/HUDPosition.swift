import AppKit
import SwiftUI

/// The capsule is anchored inside its fixed canvas as well as on the display. Otherwise
/// a short, text-free capsule would still sit hundreds of points away from a side edge.
enum HUDPosition: String, CaseIterable, Sendable {
    case top, bottom, left, right

    var displayName: String { rawValue.capitalized }

    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    var anchor: UnitPoint {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    var hiddenOffset: CGSize {
        switch self {
        case .top: CGSize(width: DS.Space.zero, height: -DS.HUD.hiddenOffset)
        case .bottom: CGSize(width: DS.Space.zero, height: DS.HUD.hiddenOffset)
        case .left: CGSize(width: -DS.HUD.hiddenOffset, height: DS.Space.zero)
        case .right: CGSize(width: DS.HUD.hiddenOffset, height: DS.Space.zero)
        }
    }

    /// Uses macOS's usable area so the bar stays clear of the menu bar and a visible Dock.
    func frame(in visible: NSRect) -> NSRect {
        let size = NSSize(width: min(DS.HUD.canvas.width, visible.width),
                          height: min(DS.HUD.canvas.height, visible.height))
        let centered = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        let origin: NSPoint
        switch self {
        case .top: origin = NSPoint(x: centered.x, y: visible.maxY - size.height)
        case .bottom: origin = NSPoint(x: centered.x, y: visible.minY)
        case .left: origin = NSPoint(x: visible.minX, y: centered.y)
        case .right: origin = NSPoint(x: visible.maxX - size.width, y: centered.y)
        }
        return NSRect(origin: origin, size: size)
    }
}
