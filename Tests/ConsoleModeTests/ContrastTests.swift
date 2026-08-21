import AppKit
import SwiftUI
import Testing
@testable import ConsoleModeKit

/// WCAG 2.1 contrast, computed from the tokens themselves so a preset cannot
/// regress into unreadable text.
///
/// Body text is 13pt and captions 11pt — both below the 18pt "large text"
/// threshold, so every text token must clear AA at 4.5:1 rather than 3:1.
@MainActor
struct ContrastTests {
    static let minimumTextRatio = 4.5
    /// Meter fills and the severity dot are graphics, not text.
    static let minimumGraphicRatio = 3.0

    // MARK: - WCAG maths

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    static func relativeLuminance(_ color: Color) -> Double {
        let rgb = NSColor(color).usingColorSpace(.sRGB)!
        return 0.2126 * linear(Double(rgb.redComponent))
            + 0.7152 * linear(Double(rgb.greenComponent))
            + 0.0722 * linear(Double(rgb.blueComponent))
    }

    static func contrast(_ foreground: Color, on background: Color) -> Double {
        let a = relativeLuminance(foreground)
        let b = relativeLuminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The colour actually behind text: the surface plus any tint overlay.
    static func effectiveSurface(_ tokens: ThemeTokens) -> Color? {
        guard case .solid(let base) = tokens.surface else { return nil }
        guard tokens.surfaceOverlay != .clear else { return base }
        let overlay = NSColor(tokens.surfaceOverlay).usingColorSpace(.sRGB)!
        let bottom = NSColor(base).usingColorSpace(.sRGB)!
        let alpha = Double(overlay.alphaComponent)
        func blend(_ top: CGFloat, _ under: CGFloat) -> Double {
            Double(top) * alpha + Double(under) * (1 - alpha)
        }
        return Color(
            .sRGB,
            red: blend(overlay.redComponent, bottom.redComponent),
            green: blend(overlay.greenComponent, bottom.greenComponent),
            blue: blend(overlay.blueComponent, bottom.blueComponent),
            opacity: 1
        )
    }

    // MARK: - Sanity checks on the maths itself

    @Test func knownRatiosMatchTheSpec() {
        // Black on white is the documented maximum.
        let extreme = Self.contrast(Color(hex: 0x000000), on: Color(hex: 0xFFFFFF))
        #expect(abs(extreme - 21) < 0.05)
        // A colour against itself has no contrast.
        #expect(abs(Self.contrast(Color(hex: 0x777777), on: Color(hex: 0x777777)) - 1) < 0.001)
    }

    // MARK: - Token audit

    /// Every token that draws text, per preset.
    private func textTokens(_ tokens: ThemeTokens) -> [(String, Color)] {
        [
            ("textPrimary", tokens.textPrimary),
            ("textSecondary", tokens.textSecondary),
            ("textTertiary", tokens.textTertiary),
            ("accent", tokens.accent),
            // Severity colours render the percentage text, not just the meter.
            ("severityHealthy", tokens.severityHealthy),
            ("severityLow", tokens.severityLow),
            ("severityVeryLow", tokens.severityVeryLow),
            ("severityCritical", tokens.severityCritical),
        ]
    }

    @Test func everyTextTokenClearsAA() {
        for id in ThemeID.allCases {
            let tokens = id.tokens
            // The System preset defers to macOS semantic colours, which the OS
            // already guarantees and which have no fixed value to measure.
            guard let surface = Self.effectiveSurface(tokens) else { continue }

            for (name, color) in textTokens(tokens) {
                let ratio = Self.contrast(color, on: surface)
                #expect(
                    ratio >= Self.minimumTextRatio,
                    "\(id.rawValue).\(name) is \(String(format: "%.2f", ratio)):1, below AA 4.5:1"
                )
            }
        }
    }

    @Test func meterTrackIsVisibleAgainstItsSurface() {
        for id in ThemeID.allCases {
            let tokens = id.tokens
            guard let surface = Self.effectiveSurface(tokens) else { continue }
            // The track is a graphic and sits under the fill, so it only needs to
            // be discernible, not text-grade.
            let ratio = Self.contrast(tokens.meterTrack, on: surface)
            #expect(ratio >= 1.1, "\(id.rawValue) meter track is invisible at \(ratio):1")
        }
    }

    @Test func severityBandsAreDistinctValues() {
        // Luminance ratio is deliberately not used here: green and red can share
        // luminance while being obviously different hues, so that number says
        // nothing about whether the bands are tellable apart. What is worth
        // guarding is a preset accidentally reusing one colour for two bands.
        //
        // Severity is never carried by colour alone anyway — the row also prints
        // the percentage and lights a proportional number of meter cells — so
        // WCAG 1.4.1 is satisfied structurally rather than chromatically.
        for id in ThemeID.allCases {
            let tokens = id.tokens
            let bands: [Color] = [
                tokens.severityHealthy,
                tokens.severityLow,
                tokens.severityVeryLow,
                tokens.severityCritical,
            ]
            let luminances = bands.map { (Self.relativeLuminance($0) * 10_000).rounded() }
            #expect(Set(luminances).count == bands.count, "\(id.rawValue) reuses a colour across severity bands")
        }
    }

    @Test func borderIsVisibleWhereAPresetAsksForOne() {
        for id in ThemeID.allCases {
            let tokens = id.tokens
            guard tokens.borderWidth > 0, let surface = Self.effectiveSurface(tokens) else { continue }
            #expect(Self.contrast(tokens.borderColor, on: surface) >= 1.2, "\(id.rawValue) border is invisible")
        }
    }
}
