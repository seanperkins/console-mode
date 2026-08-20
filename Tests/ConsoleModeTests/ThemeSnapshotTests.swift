import AppKit
import SwiftUI
import Testing
@testable import ConsoleModeKit

/// Renders the real views offscreen so the token system can be inspected without
/// driving the panel (the hotkey cannot be synthesised in this environment).
/// Writes one PNG per theme to /tmp for visual review.
@MainActor
struct ThemeSnapshotTests {
    private func fixtureRollup() throws -> [ProviderUsage] {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/usage-sample", withExtension: "json"))
        return try UsageClient.decode(try Data(contentsOf: url)).providerRollup
    }

    @Test func rendersEveryThemeToPNG() throws {
        let rollup = try fixtureRollup()
        #expect(!rollup.isEmpty)

        for id in ThemeID.allCases {
            let tokens = id.tokens
            let card = VStack(spacing: 0) {
                // Tab strip stand-in plus the real usage rows.
                HStack(spacing: 6) {
                    ForEach(ConsoleTab.allCases) { tab in
                        Text(tokens.label(tab.title))
                            .font(tokens.tabFont)
                            .tracking(tokens.labelTracking)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background {
                                if tab == .usage {
                                    RoundedRectangle(cornerRadius: 4).fill(tokens.selectionFill)
                                }
                            }
                            .foregroundStyle(tab == .usage ? tokens.accent : tokens.textSecondary)
                    }
                    Spacer()
                }
                .frame(height: PanelGeometry.tabBarHeight)
                .padding(.horizontal, 10)

                Rectangle().fill(tokens.dividerColor).frame(height: 1)

                ForEach(rollup) { provider in
                    UsageRow(provider: provider)
                }
            }
            .frame(width: PanelGeometry.cardWidth)
            .padding(.vertical, PanelGeometry.verticalPadding)
            .background {
                let shape = RoundedRectangle(cornerRadius: tokens.cornerRadius, style: .continuous)
                ZStack {
                    switch tokens.surface {
                    case .glass:
                        shape.fill(Color(nsColor: .windowBackgroundColor))
                    case .solid(let color):
                        shape.fill(color)
                    }
                    if tokens.surfaceOverlay != .clear { shape.fill(tokens.surfaceOverlay) }
                    if tokens.borderWidth > 0 {
                        shape.strokeBorder(tokens.borderColor, lineWidth: tokens.borderWidth)
                    }
                }
            }
            .environment(\.theme, tokens)
            .font(tokens.bodyFont)
            .foregroundStyle(tokens.textPrimary)

            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            let image = try #require(renderer.nsImage, "renderer produced no image for \(id.rawValue)")
            #expect(image.size.width > 0)

            let data = try #require(image.tiffRepresentation)
            let png = try #require(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
            let path = "/tmp/console-mode-theme-\(id.rawValue).png"
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
