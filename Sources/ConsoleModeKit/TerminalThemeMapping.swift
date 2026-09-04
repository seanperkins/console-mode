import AppKit
import GhosttyTerminal
import SwiftUI

/// Maps the app's own `ThemeTokens` onto `GhosttyTerminal`'s config surface,
/// so the terminal tab always reads as the same preset as Notes/Usage
/// instead of a foreign, differently-colored pane bolted onto the panel.
///
/// Kept out of `Theme.swift` so that file — read by every tab, including the
/// two that predate this dependency — never needs to import `GhosttyTerminal`.
extension ThemeTokens {
    /// A concrete fill for the terminal's background. `.glass` themes have no
    /// fixed color of their own (the real surface is a live blur), so this
    /// mirrors `CardBackground`'s own fallback for Reduce Transparency —
    /// the same approximation the app already uses when it cannot draw glass.
    private var terminalBackground: Color {
        switch surface {
        case .glass: return Color(nsColor: .windowBackgroundColor)
        case .solid(let color): return color
        }
    }

    /// `light`/`dark` variants let a fixed-palette preset (cyberpunk, terminal,
    /// paper) render identically in both — their colors are not
    /// appearance-dependent — while `.system`'s `.primary`/`.accentColor`
    /// resolve to their real per-appearance values instead of whichever
    /// happens to be current when this is called.
    func terminalTheme(scrollbackLimitMB: Int) -> GhosttyTerminal.TerminalTheme {
        GhosttyTerminal.TerminalTheme(
            light: terminalConfiguration(appearance: NSAppearance(named: .aqua)!, scrollbackLimitMB: scrollbackLimitMB),
            dark: terminalConfiguration(appearance: NSAppearance(named: .darkAqua)!, scrollbackLimitMB: scrollbackLimitMB)
        )
    }

    private func terminalConfiguration(appearance: NSAppearance, scrollbackLimitMB: Int) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withBackground(terminalBackground.hexString(appearance: appearance))
            builder.withForeground(textPrimary.hexString(appearance: appearance))
            builder.withCursorColor(accent.hexString(appearance: appearance))
            builder.withCursorStyle(.block)
            builder.withCursorStyleBlink(true)
            // Selection reads the theme's own selection tint at full strength —
            // `selectionFill`'s built-in opacity is meant to overlay flat SwiftUI
            // content, not survive being flattened to an opaque terminal color.
            builder.withSelectionBackground(accent.hexString(appearance: appearance))
            builder.withSelectionForeground(terminalBackground.hexString(appearance: appearance))
            // Our fixed card height is essentially never an exact multiple of
            // the cell grid — real Ghostty's own fix for this: without it,
            // every leftover pixel collects at the bottom edge instead of
            // being split across all four sides, which is what read as "not
            // sitting flush at the bottom."
            builder.withCustom("window-padding-balance", "true")
            // Bytes, not lines — Ghostty's own real unit. A session left
            // open for days stays bounded instead of growing without limit.
            builder.withCustom("scrollback-limit", "\(max(5, scrollbackLimitMB) * 1_000_000)")
        }
    }
}

private extension Color {
    /// Resolves to a concrete `#RRGGBB`, evaluated under `appearance` so a
    /// dynamic system color (`.primary`, `.accentColor`, ...) reflects that
    /// appearance's real value rather than whatever the process's current
    /// appearance happens to be when this runs.
    func hexString(appearance: NSAppearance) -> String {
        let nsColor = NSColor(self)
        var resolved = nsColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        }
        let r = Int((resolved.redComponent * 255).rounded())
        let g = Int((resolved.greenComponent * 255).rounded())
        let b = Int((resolved.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
