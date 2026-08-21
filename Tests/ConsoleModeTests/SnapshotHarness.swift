import AppKit
import SwiftUI
@testable import ConsoleModeKit

/// Headless renderer for the real console views.
///
/// Runs entirely offscreen: the hosting window is never ordered front, so this
/// needs neither Screen Recording nor Accessibility permission and never takes
/// over the display. It renders the production `ConsoleView(shell:)` including
/// the AppKit `ConsoleInputBar`, which `ImageRenderer` alone cannot draw.
@MainActor
enum SnapshotHarness {
    static let outputDirectory = "/tmp/console-mode-snapshots"

    struct Scenario {
        var name: String
        var tab: ConsoleTab = .notes
        var theme: ThemeID = .system
        var expanded: Bool = false
        var notes: [String] = []
        var seedUsage: Bool = true
        /// Loads the newest note into the input, capturing the editing state.
        var selectNewest: Bool = false
    }

    /// In-memory database, so the real notes file is never touched.
    static func makeShell(for scenario: Scenario, usage seeded: UsageSnapshot?) throws -> ConsoleShell {
        let store = try NoteStore.inMemory()
        for body in scenario.notes {
            _ = try store.append(body)
        }
        let model = NoteListModel(store: store)
        let monitor = UsageMonitor(
            defaults: scratchDefaults(),
            seeded: scenario.seedUsage ? seeded : nil
        )
        let shell = ConsoleShell(notes: model, usage: monitor)
        shell.themeID = scenario.theme
        shell.usageEnabled = true
        shell.activeTab = scenario.tab
        if scenario.expanded {
            model.expanded = true
        }
        shell.syncCollapsedCapacity()
        model.restartObservation()
        // Observation delivers on the main actor, so let it land before rendering.
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        if scenario.selectNewest {
            model.navigateToOlderNote()
        }
        return shell
    }

    /// A throwaway defaults domain so snapshots never read or write the real
    /// fired-threshold state.
    static func scratchDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "console-mode-snapshots")!
        suite.removePersistentDomain(forName: "console-mode-snapshots")
        return suite
    }

    /// The height the live panel would use, so snapshots match real geometry.
    static func height(for shell: ConsoleShell) -> CGFloat {
        PanelGeometry.panelHeight(
            tab: shell.activeTab,
            expanded: shell.notes.expanded,
            visibleRowCount: shell.visibleRowCount,
            providerCount: shell.usageLineCount,
            screenVisibleHeight: 1_200
        )
    }

    /// Renders through an offscreen window.
    ///
    /// `cacheDisplay` composites the real view tree. Glass is a backdrop effect
    /// that samples the desktop, so the System theme renders without its blur;
    /// the themed presets use solid surfaces and are exact.
    static func render(shell: ConsoleShell) -> Data? {
        let size = NSSize(width: PanelGeometry.cardWidth, height: height(for: shell))
        let hosting = NSHostingView(rootView: ConsoleView(shell: shell))
        hosting.frame = NSRect(origin: .zero, size: size)

        // Borderless and never ordered front: nothing reaches the screen.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.displayIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        // Let SwiftUI commit its first layout pass.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    @discardableResult
    static func write(scenario: Scenario, usage: UsageSnapshot?) throws -> String {
        let shell = try makeShell(for: scenario, usage: usage)
        guard let png = render(shell: shell) else {
            throw HarnessError.renderFailed(scenario.name)
        }
        try FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )
        let path = "\(outputDirectory)/\(scenario.name).png"
        try png.write(to: URL(fileURLWithPath: path))
        return path
    }

    enum HarnessError: Error, CustomStringConvertible {
        case renderFailed(String)

        var description: String {
            switch self {
            case .renderFailed(let name): return "render produced no bitmap for \(name)"
            }
        }
    }

    /// The captured `omp usage --json` payload bundled with the tests.
    static func usageFixture() -> UsageSnapshot? {
        guard let url = Bundle.module.url(forResource: "Fixtures/usage-sample", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? UsageClient.decode(data)
    }
}

// MARK: - Synthetic key events

/// Builds real `NSEvent`s and hands them straight to the panel. This exercises
/// the production key handlers without Accessibility permission, because it is
/// method dispatch rather than system-level event injection.
@MainActor
enum KeyDriver {
    static func command(_ character: String, keyCode: UInt16) -> NSEvent {
        event(characters: character, keyCode: keyCode, flags: .command)
    }

    static func controlTab() -> NSEvent {
        event(characters: "\t", keyCode: 48, flags: .control)
    }

    static func event(characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
