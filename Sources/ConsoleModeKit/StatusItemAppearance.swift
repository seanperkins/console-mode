import AppKit

/// How the menu bar item should look for a given usage severity.
///
/// Independent of the panel theme on purpose: the menu bar follows the system
/// appearance, and panel tokens are tuned for the card's surface. Paper's
/// severity colours would vanish against a dark menu bar.
///
/// The important rule is that **a template image and a colour are mutually
/// exclusive**. `isTemplate` marks the image as a mask — AppKit documents it as
/// containing only black, then fills it with the correct menu bar colour. Setting
/// `contentTintColor` on top of a template does not tint it; the mask wins and the
/// icon draws flat black. That combination was the bug.
///
/// So each state picks exactly one strategy:
/// - healthy: a template, which adapts to light/dark **per display** for free.
/// - warning: a non-template image carrying its own colour.
struct StatusItemAppearance: Equatable {
    var symbolName: String
    /// `nil` selects the template strategy.
    var tint: NSColor?

    static let pointSize: CGFloat = 16

    static func forSeverity(_ severity: UsageSeverity) -> StatusItemAppearance {
        switch severity {
        case .healthy:
            return StatusItemAppearance(symbolName: "note.text", tint: nil)
        case .low:
            return StatusItemAppearance(symbolName: "gauge.with.needle", tint: .systemYellow)
        case .veryLow:
            return StatusItemAppearance(symbolName: "gauge.with.needle", tint: .systemOrange)
        case .critical, .exhausted:
            return StatusItemAppearance(symbolName: "gauge.with.needle", tint: .systemRed)
        }
    }

    var usesTemplate: Bool { tint == nil }

    func image() -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Console Mode") else {
            return nil
        }

        guard let tint else {
            // Mask only. The system fills it correctly on every display, including
            // a light and a dark screen at the same time.
            base.isTemplate = true
            return base
        }

        // Colour is baked in, and the image must not be a template or the colour
        // is discarded.
        let size = NSSize(width: Self.pointSize, height: Self.pointSize)
        let coloured = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            tint.set()
            // Preserves the glyph's alpha, replaces its colour.
            rect.fill(using: .sourceAtop)
            return true
        }
        coloured.isTemplate = false
        return coloured
    }

    @MainActor
    func apply(to button: NSStatusBarButton) {
        button.image = image()
        // Always nil: a template must stay untinted, and a coloured image already
        // holds its colour.
        button.contentTintColor = nil
    }
}
