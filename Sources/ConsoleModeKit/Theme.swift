import AppKit
import SwiftUI

// MARK: - Token value types

/// How the card's backdrop is drawn. Glass samples the desktop behind the panel;
/// solid is required for high-contrast looks where translucency would wash out
/// neon accents.
enum SurfaceStyle: Equatable, Sendable {
    case glass
    case solid(Color)
}

/// Capsule reads as a normal macOS progress bar; segmented reads as a terminal
/// gauge. Both consume the same fraction.
enum MeterStyle: Equatable, Sendable {
    case capsule
    case segmented(count: Int)
}

enum LabelCasing: Equatable, Sendable {
    case asTyped
    case upper

    func apply(_ text: String) -> String {
        switch self {
        case .asTyped: return text
        case .upper: return text.uppercased()
        }
    }
}

/// Every visual decision the views are allowed to make. Views must read tokens
/// rather than naming colours or fonts directly, so a new preset restyles the
/// whole app without touching view code.
struct ThemeTokens: Equatable, Sendable {
    // Surface
    var surface: SurfaceStyle
    var surfaceOverlay: Color
    var borderColor: Color
    var borderWidth: CGFloat
    var glowColor: Color
    var glowRadius: CGFloat
    var cornerRadius: CGFloat
    var dividerColor: Color

    // Text
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    var accent: Color

    // Typography
    var fontDesign: Font.Design
    var labelCasing: LabelCasing
    var labelTracking: CGFloat

    // Controls
    var selectionFill: Color
    var meterTrack: Color
    var meterStyle: MeterStyle
    var promptGlyph: String?

    // Severity
    var severityHealthy: Color
    var severityLow: Color
    var severityVeryLow: Color
    var severityCritical: Color

    func color(for severity: UsageSeverity) -> Color {
        switch severity {
        case .healthy: return severityHealthy
        case .low: return severityLow
        case .veryLow: return severityVeryLow
        case .critical, .exhausted: return severityCritical
        }
    }

    func label(_ text: String) -> String { labelCasing.apply(text) }

    /// Body and caption derive from one design so presets cannot drift.
    var bodyFont: Font { .system(size: 13, design: fontDesign) }
    var captionFont: Font { .system(size: 11, design: fontDesign) }
    var tabFont: Font { .system(size: 11, weight: .semibold, design: fontDesign) }
    var meterFont: Font { .system(size: 12, design: .monospaced) }

    /// AppKit surfaces (the capture field, status item) need concrete NS types.
    var nsBodyFont: NSFont {
        switch fontDesign {
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        default:
            return NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
    }

    var nsTextPrimary: NSColor { NSColor(textPrimary) }
    var nsTextSecondary: NSColor { NSColor(textSecondary) }
    var nsAccent: NSColor { NSColor(accent) }
}

// MARK: - Presets

enum ThemeID: String, CaseIterable, Identifiable, Sendable {
    case system
    case cyberpunk
    case terminal
    case paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .cyberpunk: return "Cyberpunk"
        case .terminal: return "Terminal"
        case .paper: return "Paper"
        }
    }

    var summary: String {
        switch self {
        case .system: return "Native Liquid Glass and system colors."
        case .cyberpunk: return "Near-black glass, neon cyan and magenta, segmented meters."
        case .terminal: return "Green phosphor monospace on black."
        case .paper: return "Light, quiet, high legibility."
        }
    }

    var tokens: ThemeTokens { ThemeTokens.preset(self) }
}

extension Color {
    /// `0xRRGGBB` literal, so presets read as a palette rather than arithmetic.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension ThemeTokens {
    static func preset(_ id: ThemeID) -> ThemeTokens {
        switch id {
        case .system: return .system
        case .cyberpunk: return .cyberpunk
        case .terminal: return .terminal
        case .paper: return .paper
        }
    }

    /// The look the app shipped with, kept as a first-class preset so switching
    /// away from a themed look is lossless.
    static let system = ThemeTokens(
        surface: .glass,
        surfaceOverlay: .clear,
        borderColor: .clear,
        borderWidth: 0,
        glowColor: .clear,
        glowRadius: 0,
        cornerRadius: 16,
        dividerColor: Color.primary.opacity(0.35),
        textPrimary: .primary,
        textSecondary: .secondary,
        textTertiary: Color.primary.opacity(0.35),
        accent: .accentColor,
        fontDesign: .default,
        labelCasing: .asTyped,
        labelTracking: 0,
        selectionFill: Color.accentColor.opacity(0.14),
        meterTrack: Color.primary.opacity(0.10),
        meterStyle: .capsule,
        promptGlyph: nil,
        severityHealthy: .green,
        severityLow: .yellow,
        severityVeryLow: .orange,
        severityCritical: .red
    )

    static let cyberpunk = ThemeTokens(
        // Solid near-black: neon on glass loses saturation against a bright desktop.
        surface: .solid(Color(hex: 0x070B12, opacity: 0.94)),
        surfaceOverlay: Color(hex: 0x00F0FF, opacity: 0.03),
        borderColor: Color(hex: 0x00F0FF, opacity: 0.55),
        borderWidth: 1,
        glowColor: Color(hex: 0x00F0FF, opacity: 0.45),
        glowRadius: 14,
        cornerRadius: 6,
        dividerColor: Color(hex: 0x00F0FF, opacity: 0.22),
        textPrimary: Color(hex: 0xE8FDFF),
        textSecondary: Color(hex: 0x6FD9E4),
        textTertiary: Color(hex: 0x3A6E78),
        accent: Color(hex: 0xFF2E97),
        fontDesign: .monospaced,
        labelCasing: .upper,
        labelTracking: 1.1,
        selectionFill: Color(hex: 0xFF2E97, opacity: 0.18),
        meterTrack: Color(hex: 0x00F0FF, opacity: 0.12),
        meterStyle: .segmented(count: 16),
        promptGlyph: "›",
        severityHealthy: Color(hex: 0x39FF14),
        severityLow: Color(hex: 0xFFD400),
        severityVeryLow: Color(hex: 0xFF8A00),
        severityCritical: Color(hex: 0xFF0044)
    )

    static let terminal = ThemeTokens(
        surface: .solid(Color(hex: 0x020402, opacity: 0.95)),
        surfaceOverlay: .clear,
        borderColor: Color(hex: 0x33FF66, opacity: 0.35),
        borderWidth: 1,
        glowColor: Color(hex: 0x33FF66, opacity: 0.28),
        glowRadius: 10,
        cornerRadius: 4,
        dividerColor: Color(hex: 0x33FF66, opacity: 0.20),
        textPrimary: Color(hex: 0xB6FFC4),
        textSecondary: Color(hex: 0x5FCE77),
        textTertiary: Color(hex: 0x2F6B3C),
        accent: Color(hex: 0x33FF66),
        fontDesign: .monospaced,
        labelCasing: .upper,
        labelTracking: 0.8,
        selectionFill: Color(hex: 0x33FF66, opacity: 0.16),
        meterTrack: Color(hex: 0x33FF66, opacity: 0.12),
        meterStyle: .segmented(count: 20),
        promptGlyph: "$",
        severityHealthy: Color(hex: 0x33FF66),
        severityLow: Color(hex: 0xE8FF3A),
        severityVeryLow: Color(hex: 0xFFA23A),
        severityCritical: Color(hex: 0xFF4D4D)
    )

    static let paper = ThemeTokens(
        surface: .solid(Color(hex: 0xFBFAF7, opacity: 0.97)),
        surfaceOverlay: .clear,
        borderColor: Color(hex: 0x1C1B19, opacity: 0.12),
        borderWidth: 1,
        glowColor: .clear,
        glowRadius: 0,
        cornerRadius: 12,
        dividerColor: Color(hex: 0x1C1B19, opacity: 0.12),
        textPrimary: Color(hex: 0x1C1B19),
        textSecondary: Color(hex: 0x5C574F),
        textTertiary: Color(hex: 0x9A948A),
        accent: Color(hex: 0x2E5BD8),
        fontDesign: .default,
        labelCasing: .asTyped,
        labelTracking: 0,
        selectionFill: Color(hex: 0x2E5BD8, opacity: 0.10),
        meterTrack: Color(hex: 0x1C1B19, opacity: 0.10),
        meterStyle: .capsule,
        promptGlyph: nil,
        severityHealthy: Color(hex: 0x1F7A3D),
        severityLow: Color(hex: 0xB07B00),
        severityVeryLow: Color(hex: 0xC2560F),
        severityCritical: Color(hex: 0xB3261E)
    )
}

// MARK: - Storage and environment

enum ThemeStore {
    private static let key = "theme.id"

    static var currentID: ThemeID {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let id = ThemeID(rawValue: raw)
            else { return .system }
            return id
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static var current: ThemeTokens { currentID.tokens }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeTokens.system
}

extension EnvironmentValues {
    var theme: ThemeTokens {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
