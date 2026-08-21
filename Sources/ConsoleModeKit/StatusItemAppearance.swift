import AppKit

/// How the menu bar item should look for a given usage severity.
///
/// Deliberately independent of the panel theme. The menu bar follows the *system*
/// appearance, so panel tokens do not belong here: cyberpunk's palette is tuned
/// for a near-black card, and Paper's severity colours are dark enough to vanish
/// against a dark menu bar. System colours are appearance-adaptive by design.
struct StatusItemAppearance: Equatable {
    var symbolName: String
    /// `nil` means "leave the template image alone", which tracks the menu bar's
    /// own light/dark rendering.
    var tint: NSColor?

    static func forSeverity(_ severity: UsageSeverity) -> StatusItemAppearance {
        switch severity {
        case .healthy:
            // Untinted template: the system draws it correctly in both appearances.
            return StatusItemAppearance(symbolName: "note.text", tint: nil)
        case .low:
            return StatusItemAppearance(symbolName: "gauge.with.needle", tint: .systemYellow)
        case .veryLow:
            return StatusItemAppearance(symbolName: "gauge.with.needle", tint: .systemOrange)
        case .critical, .exhausted:
            return StatusItemAppearance(symbolName: "gauge.with.needle", tint: .systemRed)
        }
    }

    /// The symbol changes with severity as well as the colour, so the state is not
    /// conveyed by colour alone.
    func image() -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Console Mode")
        // Explicit rather than relying on the SF Symbol default, so the icon can
        // never render as flat black on a dark menu bar.
        image?.isTemplate = true
        return image
    }

    func apply(to button: NSStatusBarButton) {
        button.image = image()
        button.contentTintColor = tint
    }
}
