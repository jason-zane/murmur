import SwiftUI
import AppKit

/// The design system for Voice Notes.
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
        static let conversationSurface = adaptive(light: 0xEFEDF7, dark: 0x302D40)
        static let conversationInk = adaptive(light: 0x4B435F, dark: 0xDEDAEB)
        static let conversationWave = adaptive(light: 0xB7AFD3, dark: 0x756999)

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
        static let zero: CGFloat = 0
        static let xxs: CGFloat = 2
        static let tight: CGFloat = 3
        static let compact: CGFloat = 6
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let page: CGFloat = 36
        static let xxxl: CGFloat = 48
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
        static let focus: CGFloat = 2
    }

    enum Layout {
        static let windowWidth: CGFloat = 1_180
        static let windowHeight: CGFloat = 780
        static let minWindowWidth: CGFloat = 1_040
        static let minWindowHeight: CGFloat = 620
        static let navigationWidth: CGFloat = 176
        static let libraryWidth: CGFloat = 282
        static let documentWidth: CGFloat = 760
        static let homeWidth: CGFloat = 640
        static let heroSymbol: CGFloat = 94
        static let heroTilt: Double = -10
        static let controlHeight: CGFloat = 32
        static let navRowHeight: CGFloat = 36
        static let symbolColumn: CGFloat = 20
        static let brandMark: CGFloat = 30
        static let emptySymbol: CGFloat = 40
        static let statusDot: CGFloat = 6
        static let transcriptTime: CGFloat = 48
        static let editorHeight: CGFloat = 360
        static let templatePicker: CGFloat = 120
        static let smallPicker: CGFloat = 90
        static let rulePicker: CGFloat = 240
        static let modelProgress: CGFloat = 260
        static let permissionDot: CGFloat = 7
        static let notepadWidth: CGFloat = 380
        static let notepadHeight: CGFloat = 440
        static let notepadMinWidth: CGFloat = 320
        static let notepadMinHeight: CGFloat = 300
        static let notepadTopInset: CGFloat = 28
        static let tabPicker: CGFloat = 224
        static let sheetWidth: CGFloat = 620
        static let sheetHeight: CGFloat = 480
        static let settingsWidth: CGFloat = 620
        static let settingsHeight: CGFloat = 760
        static let meterWidth: CGFloat = 100
        static let meterHeight: CGFloat = 20
        static let compactMeterWidth: CGFloat = 40
        static let strokeDash: [CGFloat] = [4, 4]
        static let proseLineSpacing: CGFloat = 5
    }

    enum Timing {
        static let feedback: Duration = .milliseconds(1_600)
        static let searchDebounce: Duration = .milliseconds(180)
        static let autosave: Duration = .milliseconds(800)
        static let refresh: Duration = .seconds(3)
    }

    enum Account {
        static let avatarSize: CGFloat = 44
        static let sidebarEmailLines = 1
    }

    enum HUD {
        static let canvas = NSSize(width: 500, height: 88)
        static let edgeInset: CGFloat = 8
        static let textWidth: CGFloat = 280
        static let spacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 11
        static let meterWidth: CGFloat = 32
        static let meterHeight: CGFloat = 18
        static let barCount = 5
        static let barWidth: CGFloat = 2.5
        static let barSpacing: CGFloat = 3
        static let dotSize: CGFloat = 7
        static let controlSize: CGFloat = 24
        static let lineLimit = 2
        static let borderOpacity = 0.08
        static let enterScale: CGFloat = 0.9
        static let textScale: CGFloat = 0.96
        static let hiddenOffset: CGFloat = 10
        static let visibleScale: CGFloat = 1
        static let hiddenOpacity = 0.0
        static let visibleOpacity = 1.0
        static let exitDuration: Duration = .milliseconds(320)
        static let previewDuration: Duration = .seconds(12)
    }

    // MARK: - Elevation

    enum Shadow {
        /// Cards resting on the window.
        static let soft = Spec(color: .black.opacity(0.06), radius: 3, y: 1)
        /// Controls and rows that lift on hover.
        static let lifted = Spec(color: .black.opacity(0.10), radius: 8, y: 3)
        /// Floating meeting prompts. The dictation bar deliberately has no shadow.
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

// MARK: - Meetings

/// Additions for meetings. Same rules: one accent, red means recording. Two amendments,
/// both documented here so they are decisions rather than exceptions:
///
/// - **Speaker colours are instrumentation**, like the level meter's amber and green — they
///   label who is talking and appear nowhere else. You are always the accent. Everyone else
///   cycles the remaining three, all kept well away from red.
/// - **Every number is a readout.** Durations, timestamps, counts and confidences are set in
///   tabular monospace, always. It is the one place the instrument idea survives, and it
///   survives as typography rather than chrome.
extension DS.Color {
    /// Index 0 is you. Others are assigned in order of first appearance.
    static let speaker: [SwiftUI.Color] = [
        accent,
        adaptive(light: 0x2F7D95, dark: 0x5FB3CC),
        adaptive(light: 0x7A5EA7, dark: 0xB294D6),
        adaptive(light: 0x5E7343, dark: 0x97B36C),
    ]

    static func speaker(_ index: Int) -> SwiftUI.Color {
        speaker[max(0, index) % speaker.count]
    }
}

extension DS.Font {
    /// Timestamps, durations, counts. Always paired with `.monospacedDigit()`.
    static let readout = SwiftUI.Font.system(size: 11, weight: .medium, design: .monospaced)
    static let readoutLarge = SwiftUI.Font.system(size: 22, weight: .medium, design: .monospaced)
    /// Session titles in the Library and the notepad.
    static let sessionTitle = SwiftUI.Font.system(size: 19, weight: .semibold)
    /// The notepad's bullets — a touch larger than body, because it's the thing you're doing.
    static let note = SwiftUI.Font.system(size: 14, weight: .regular)
}

extension DS.Space {
    /// Width of the labelled meter's label column, so the two bars align.
    static let meterLabel: CGFloat = 34
}

extension DS.Font {
    static let brand = SwiftUI.Font.system(size: 16, weight: .semibold, design: .rounded)
    static let pageTitle = SwiftUI.Font.system(size: 24, weight: .semibold)
    static let heroTitle = SwiftUI.Font.system(size: 36, weight: .medium)
    static let heroEmphasis = SwiftUI.Font.system(size: 38, weight: .regular, design: .serif).italic()
    static let heroSymbol = SwiftUI.Font.system(size: 82, weight: .ultraLight)
    static let documentTitle = SwiftUI.Font.system(size: 28, weight: .semibold)
    static let documentBody = SwiftUI.Font.system(size: 15, weight: .regular)
    static let documentHeading = SwiftUI.Font.system(size: 16, weight: .semibold)
    static let symbol = SwiftUI.Font.system(size: 14, weight: .medium)
    static let largeSymbol = SwiftUI.Font.system(size: 28, weight: .light)
    static let smallSymbol = SwiftUI.Font.system(size: 11, weight: .medium)
}
