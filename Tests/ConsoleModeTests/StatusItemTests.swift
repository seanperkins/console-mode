import AppKit
import Testing
@testable import ConsoleModeKit

@MainActor
struct StatusItemTests {

    /// The rule that was violated: AppKit documents a template image as a mask
    /// containing only black, which it fills with the menu bar colour. A
    /// `contentTintColor` on top of that is discarded and the raw black mask is
    /// drawn — which is exactly how the icon disappeared on a dark menu bar.
    @Test func templateAndColourAreMutuallyExclusive() {
        for severity in [UsageSeverity.healthy, .low, .veryLow, .critical, .exhausted] {
            let appearance = StatusItemAppearance.forSeverity(severity)
            let image = appearance.image()
            if appearance.tint == nil {
                #expect(image?.isTemplate == true, "\(severity) should be a template")
            } else {
                #expect(
                    image?.isTemplate == false,
                    "\(severity) carries a colour, so it must not be a template or the colour is discarded"
                )
            }
        }
    }

    @Test func healthyUsesTemplateSoItAdaptsPerDisplay() {
        let appearance = StatusItemAppearance.forSeverity(.healthy)
        // A template is filled by the system, which is the only way one icon can
        // be correct on a light and a dark display simultaneously.
        #expect(appearance.usesTemplate)
        #expect(appearance.tint == nil)
        #expect(appearance.symbolName == "note.text")
    }

    @Test func warningStatesCarryTheirOwnColour() {
        for severity in [UsageSeverity.low, .veryLow, .critical, .exhausted] {
            let appearance = StatusItemAppearance.forSeverity(severity)
            #expect(!appearance.usesTemplate, "\(severity) must not be a template")
            #expect(appearance.tint != nil)
        }
    }

    @Test func warningTintsAreSystemColoursNotThemeColours() {
        #expect(StatusItemAppearance.forSeverity(.low).tint == .systemYellow)
        #expect(StatusItemAppearance.forSeverity(.veryLow).tint == .systemOrange)
        #expect(StatusItemAppearance.forSeverity(.critical).tint == .systemRed)
        #expect(StatusItemAppearance.forSeverity(.exhausted).tint == .systemRed)
    }

    @Test func severityChangesTheSymbolNotJustTheColour() {
        // Survives a monochrome menu bar and colour-blind vision.
        #expect(StatusItemAppearance.forSeverity(.healthy).symbolName
            != StatusItemAppearance.forSeverity(.critical).symbolName)
    }

    @Test func colouredImageActuallyContainsItsColour() throws {
        // Guards the sourceAtop fill: a mistake there yields a black glyph, the
        // very symptom being fixed.
        let image = try #require(StatusItemAppearance.forSeverity(.critical).image())
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))

        var sawRed = false
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.5
                else { continue }
                if color.redComponent > 0.5, color.greenComponent < 0.5 {
                    sawRed = true
                }
            }
        }
        #expect(sawRed, "critical icon has no red pixels — the tint fill did not apply")
    }

    /// Previews the icons over both menu bar backdrops so the result can be seen
    /// rather than assumed. Template states are drawn the way the system fills
    /// them; coloured states are drawn verbatim, as the menu bar does.
    @Test func rendersIconOverBothAppearances() throws {
        let directory = "/tmp/console-mode-snapshots"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let cases: [UsageSeverity] = [.healthy, .low, .veryLow, .critical]
        let backdrops: [(String, NSColor, Bool)] = [
            ("dark", NSColor(white: 0.12, alpha: 1), true),
            ("light", NSColor(white: 0.95, alpha: 1), false),
        ]

        for (mode, backdrop, isDark) in backdrops {
            let size = NSSize(width: 22 * CGFloat(cases.count) + 8, height: 26)
            let canvas = NSImage(size: size)
            canvas.lockFocus()
            backdrop.setFill()
            NSRect(origin: .zero, size: size).fill()

            for (index, severity) in cases.enumerated() {
                let item = StatusItemAppearance.forSeverity(severity)
                guard let symbol = item.image() else { continue }
                let rect = NSRect(x: 4 + CGFloat(index) * 22, y: 5, width: 16, height: 16)

                if item.usesTemplate {
                    // Stand in for the system's fill of the mask.
                    let filled = NSImage(size: rect.size, flipped: false) { area in
                        symbol.draw(in: area)
                        (isDark ? NSColor.white : NSColor.black).set()
                        area.fill(using: .sourceAtop)
                        return true
                    }
                    filled.draw(in: rect)
                } else {
                    symbol.draw(in: rect)
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
