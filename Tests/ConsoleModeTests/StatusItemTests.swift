import AppKit
import Testing
@testable import ConsoleModeKit

@MainActor
struct StatusItemTests {

    @Test func healthyStateIsUntintedSoItFollowsTheMenuBar() {
        let appearance = StatusItemAppearance.forSeverity(.healthy)
        // A nil tint leaves the template image to the system, which is the only
        // way it renders correctly in both light and dark menu bars.
        #expect(appearance.tint == nil)
        #expect(appearance.symbolName == "note.text")
    }

    @Test func everySeverityProducesATemplateImage() {
        for severity in [UsageSeverity.healthy, .low, .veryLow, .critical, .exhausted] {
            let image = StatusItemAppearance.forSeverity(severity).image()
            // Without the template flag an SF Symbol draws flat black, which
            // disappears against a dark menu bar.
            #expect(image?.isTemplate == true, "\(severity) image is not a template")
        }
    }

    @Test func warningTintsAreSystemColoursNotThemeColours() {
        let tints = [
            StatusItemAppearance.forSeverity(.low).tint,
            StatusItemAppearance.forSeverity(.veryLow).tint,
            StatusItemAppearance.forSeverity(.critical).tint,
        ]
        #expect(tints == [.systemYellow, .systemOrange, .systemRed])

        // System colours resolve differently per appearance; a fixed theme colour
        // cannot, which is what made the icon vanish in dark mode.
        for tint in tints.compactMap({ $0 }) {
            let light = tint.usingColorSpace(.sRGB)
            #expect(light != nil)
        }
    }

    @Test func severityChangesTheSymbolNotJustTheColour() {
        // Colour alone would be unreadable for anyone who cannot distinguish it,
        // and invisible to anyone using a monochrome menu bar.
        #expect(StatusItemAppearance.forSeverity(.healthy).symbolName
            != StatusItemAppearance.forSeverity(.critical).symbolName)
    }

    /// Renders the icon over both menu bar appearances so the result can be seen
    /// rather than assumed.
    @Test func rendersIconOverBothAppearances() throws {
        let directory = "/tmp/console-mode-snapshots"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let cases: [(String, UsageSeverity)] = [
            ("healthy", .healthy), ("low", .low), ("verylow", .veryLow), ("critical", .critical),
        ]
        // Approximate menu bar backdrops in each appearance.
        let backdrops: [(String, NSColor, NSAppearance.Name)] = [
            ("dark", NSColor(white: 0.12, alpha: 1), .darkAqua),
            ("light", NSColor(white: 0.95, alpha: 1), .aqua),
        ]

        for (mode, backdrop, appearanceName) in backdrops {
            let appearance = try #require(NSAppearance(named: appearanceName))
            let size = NSSize(width: 22 * CGFloat(cases.count) + 8, height: 26)
            let canvas = NSImage(size: size)
            canvas.lockFocus()
            backdrop.setFill()
            NSRect(origin: .zero, size: size).fill()

            // Resolve template + system colours in the target appearance, exactly
            // as the menu bar would.
            appearance.performAsCurrentDrawingAppearance {
                for (index, entry) in cases.enumerated() {
                    let item = StatusItemAppearance.forSeverity(entry.1)
                    guard let symbol = item.image() else { continue }
                    let tint = item.tint ?? (appearanceName == .darkAqua ? NSColor.white : NSColor.black)
                    let rect = NSRect(x: 4 + CGFloat(index) * 22, y: 5, width: 16, height: 16)
                    let drawn = NSImage(size: rect.size)
                    drawn.lockFocus()
                    tint.set()
                    symbol.draw(in: NSRect(origin: .zero, size: rect.size))
                    NSRect(origin: .zero, size: rect.size).fill(using: .sourceAtop)
                    drawn.unlockFocus()
                    drawn.draw(in: rect)
                }
            }
            canvas.unlockFocus()

            let tiff = try #require(canvas.tiffRepresentation)
            let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "\(directory)/statusitem-\(mode).png"))
            #expect(png.count > 200)
        }
    }
}
