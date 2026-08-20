import SwiftUI
import Testing
@testable import ConsoleModeKit

@Test func everyThemeIDResolvesToTokens() {
    // A preset added to the enum without a token set would trap here.
    for id in ThemeID.allCases {
        let tokens = id.tokens
        #expect(tokens.cornerRadius >= 0)
        #expect(!id.title.isEmpty)
        #expect(!id.summary.isEmpty)
    }
}

@Test func severityMappingCoversEveryCase() {
    let tokens = ThemeTokens.cyberpunk
    #expect(tokens.color(for: .healthy) == tokens.severityHealthy)
    #expect(tokens.color(for: .low) == tokens.severityLow)
    #expect(tokens.color(for: .veryLow) == tokens.severityVeryLow)
    // Exhausted deliberately shares the critical colour rather than adding a token.
    #expect(tokens.color(for: .critical) == tokens.severityCritical)
    #expect(tokens.color(for: .exhausted) == tokens.severityCritical)
}

@Test func casingTokenDrivesLabels() {
    #expect(ThemeTokens.cyberpunk.label("Notes") == "NOTES")
    #expect(ThemeTokens.terminal.label("Usage") == "USAGE")
    #expect(ThemeTokens.system.label("Notes") == "Notes")
    #expect(ThemeTokens.paper.label("Notes") == "Notes")
}

@Test func monospacePresetsUseMonospacedAppKitFont() {
    // The capture field is AppKit, so the bridge must honour the design token.
    #expect(ThemeTokens.cyberpunk.nsBodyFont.fontName != ThemeTokens.system.nsBodyFont.fontName)
    #expect(ThemeTokens.terminal.fontDesign == .monospaced)
    #expect(ThemeTokens.system.fontDesign == .default)
}

@Test func meterStyleVariesByPreset() {
    #expect(ThemeTokens.system.meterStyle == .capsule)
    #expect(ThemeTokens.paper.meterStyle == .capsule)
    if case .segmented(let count) = ThemeTokens.cyberpunk.meterStyle {
        #expect(count > 0)
    } else {
        Issue.record("cyberpunk should use a segmented meter")
    }
}

@Test func glassPresetIsOnlyTheSystemOne() {
    #expect(ThemeTokens.system.surface == .glass)
    // Neon on glass desaturates, so the themed presets pick solid surfaces.
    for tokens in [ThemeTokens.cyberpunk, .terminal, .paper] {
        #expect(tokens.surface != .glass)
    }
}

@Test func hexInitializerMapsChannels() {
    #expect(Color(hex: 0xFF0000) == Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1))
    #expect(Color(hex: 0x00FF00) == Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1))
    #expect(Color(hex: 0x0000FF) == Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
}

@Test func unknownStoredThemeFallsBackToSystem() {
    let defaults = UserDefaults.standard
    let key = "theme.id"
    let original = defaults.string(forKey: key)
    defer {
        if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    defaults.set("does-not-exist", forKey: key)
    #expect(ThemeStore.currentID == .system)
}

@Test func themeRoundTripsThroughStorage() {
    let defaults = UserDefaults.standard
    let key = "theme.id"
    let original = defaults.string(forKey: key)
    defer {
        if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    ThemeStore.currentID = .cyberpunk
    #expect(ThemeStore.currentID == .cyberpunk)
    #expect(ThemeStore.current.meterStyle == ThemeTokens.cyberpunk.meterStyle)
}

@Test func tabCyclingWrapsInOrder() {
    #expect(ConsoleTab.notes.next == .usage)
    #expect(ConsoleTab.usage.next == .notes)
    #expect(ConsoleTab.notes.commandDigit == "1")
    #expect(ConsoleTab.usage.commandDigit == "2")
}
