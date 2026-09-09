import SwiftUI
import AppKit

/// The design system for Murmur.
///
/// Direction: quiet, modern, native. The app should look like it belongs on macOS in 2026 —
/// system materials, generous whitespace, one accent, depth from soft shadow and hairline
/// separators rather than bevels or ornament.
///
/// Every value a view needs lives here. Components never declare their own colours, sizes,
/// radii or durations; if something needs a number that isn't a token, add the token.
///
/// Three rules that keep it coherent:
/// - **One accent.** `accent` carries interaction. `record` is the *only* other saturated
///   colour, and it means recording and nothing else.
/// - **Semantic colours where macOS provides them.** `.primary`, `separatorColor` and the
///   material backgrounds adapt to appearance, accent tint and increased-contrast for free.
///   Hand-rolled hex is reserved for the two brand colours.
/// - **Motion is spring, not linear.** Interface elements have mass; nothing cuts.
enum DS {

    // MARK: - Colour

    enum Color {
        /// Interaction: selection, focus, the live waveform, primary actions.
        static let accent = adaptive(light: 0x4F46E5, dark: 0x8B8BF5)
        /// Accent at rest — chips, subtle fills, hover states on tinted controls.
        static let accentSoft = adaptive(light: 0x4F46E5, dark: 0x8B8BF5).opacity(0.12)

        /// Recording. Nothing else in the app is red.
        static let record = adaptive(light: 0xE5484D, dark: 0xFF6369)
        static let recordSoft = adaptive(light: 0xE5484D, dark: 0xFF6369).opacity(0.14)

        /// A correction fired, an entry is enabled — confirmation, not decoration.
        static let success = adaptive(light: 0x2A9D5C, dark: 0x4CC38A)
        /// A dictionary entry that looks likely to over-match.
        static let warning = adaptive(light: 0xB2801A, dark: 0xE0B44A)

        // Text
        static let text = SwiftUI.Color.primary
        static let textSecondary = SwiftUI.Color.secondary
        static let textTertiary = SwiftUI.Color.primary.opacity(0.4)

        // Surfaces
        static let window = SwiftUI.Color(nsColor: .windowBackgroundColor)
        static let surface = SwiftUI.Color(nsColor: .controlBackgroundColor)
        static let separator = SwiftUI.Color(nsColor: .separatorColor)

        /// Row and control states. Deliberately low-contrast — these should register as
        /// texture, not as a second selection colour.
        static let hover = SwiftUI.Color.primary.opacity(0.045)
        static let selection = SwiftUI.Color.primary.opacity(0.08)

        private static func adaptive(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
    }

    // MARK: - Type

    /// SF Pro throughout. Rounded is used only inside the HUD, where the capsule shape and
    /// small size want softer letterforms.
    enum Font {
        static let title = SwiftUI.Font.system(size: 19, weight: .semibold)
        static let headline = SwiftUI.Font.system(size: 14, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular)
        static let bodyEmphasis = SwiftUI.Font.system(size: 13, weight: .medium)
        static let callout = SwiftUI.Font.system(size: 12, weight: .regular)
        static let label = SwiftUI.Font.system(size: 11, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 11, weight: .regular)

        /// Timings and counters. Monospaced digits so numbers don't jitter as they tick.
        static let mono = SwiftUI.Font.system(size: 11, weight: .medium, design: .monospaced)
        static let monoLarge = SwiftUI.Font.system(size: 15, weight: .medium, design: .monospaced)

        static let hud = SwiftUI.Font.system(size: 12.5, weight: .medium, design: .rounded)
    }

    // MARK: - Metrics

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        /// Capsules resolve their own radius from height; this is just "very round".
        static let pill: CGFloat = 999
    }

    enum Stroke {
        static let hairline: CGFloat = 1
    }

    // MARK: - Elevation

    enum Shadow {
        /// Cards resting on the window.
        static let soft = Spec(color: .black.opacity(0.06), radius: 3, y: 1)
        /// Controls and rows that lift on hover.
        static let lifted = Spec(color: .black.opacity(0.10), radius: 8, y: 3)
        /// The HUD, floating over every other app.
        static let floating = Spec(color: .black.opacity(0.22), radius: 20, y: 8)

        struct Spec {
            let color: SwiftUI.Color
            let radius: CGFloat
            let y: CGFloat
        }
    }

    // MARK: - Motion

    enum Motion {
        /// The default for anything that changes size or position.
        static let spring = Animation.spring(response: 0.34, dampingFraction: 0.82)
        /// Snappier — presses, toggles, hover.
        static let quick = Animation.spring(response: 0.22, dampingFraction: 0.9)
        /// Opacity and colour, where a spring would look like a mistake.
        static let smooth = Animation.easeOut(duration: 0.16)
        /// The HUD arriving and leaving. Slightly looser, so it reads as physical.
        static let hud = Animation.spring(response: 0.30, dampingFraction: 0.75)
    }
}

// MARK: - Shadow application

extension View {
    func elevation(_ spec: DS.Shadow.Spec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: 0, y: spec.y)
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
