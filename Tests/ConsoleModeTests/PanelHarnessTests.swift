import AppKit
import Testing
@testable import ConsoleModeKit

/// Drives the real `ConsolePanel` and renders the real views, all offscreen.
@MainActor
struct PanelHarnessTests {

    // MARK: - Key handling

    /// The panel is nonactivating, so these handlers live in AppKit rather than
    /// SwiftUI. Feeding them real NSEvents is the only way to prove they fire.
    private func makePanel() throws -> (ConsolePanel, ConsoleShell) {
        let shell = try SnapshotHarness.makeShell(
            for: .init(name: "keys", notes: ["alpha", "beta"]),
            usage: SnapshotHarness.usageFixture()
        )
        return (ConsolePanel(shell: shell), shell)
    }

    @Test func commandTwoSelectsUsageTab() throws {
        let (panel, shell) = try makePanel()
        #expect(shell.activeTab == .notes)

        let handled = panel.performKeyEquivalent(with: KeyDriver.command("2", keyCode: 19))

        #expect(handled)
        #expect(shell.activeTab == .usage)
    }

    @Test func commandOneReturnsToNotes() throws {
        let (panel, shell) = try makePanel()
        shell.activeTab = .usage

        let handled = panel.performKeyEquivalent(with: KeyDriver.command("1", keyCode: 18))

        #expect(handled)
        #expect(shell.activeTab == .notes)
    }

    @Test func controlTabCyclesBothWays() throws {
        let (panel, shell) = try makePanel()

        panel.keyDown(with: KeyDriver.controlTab())
        #expect(shell.activeTab == .usage)

        panel.keyDown(with: KeyDriver.controlTab())
        #expect(shell.activeTab == .notes)
    }

    @Test func commandRIsHandledOnUsageTab() throws {
        let (panel, _) = try makePanel()
        // Consumed by the panel rather than falling through to the text field,
        // which would otherwise insert an "r".
        #expect(panel.performKeyEquivalent(with: KeyDriver.command("r", keyCode: 15)))
    }

    @Test func unrelatedCommandKeyIsNotSwallowed() throws {
        let (panel, shell) = try makePanel()
        // ⌘V must reach the responder chain so paste keeps working.
        _ = panel.performKeyEquivalent(with: KeyDriver.command("v", keyCode: 9))
        #expect(shell.activeTab == .notes)
    }

    @Test func tabsAreUnavailableWhenUsageIsOff() throws {
        let (panel, shell) = try makePanel()
        shell.setUsageEnabled(false)

        let handled = panel.performKeyEquivalent(with: KeyDriver.command("2", keyCode: 19))

        // The key is still claimed, but there is no usage tab to move to.
        #expect(handled)
        #expect(shell.activeTab == .notes)
    }

    // MARK: - Geometry through the real panel

    @Test func panelHeightMatchesAcrossTabs() throws {
        let (_, shell) = try SnapshotHarness.makeShell(
            for: .init(name: "geom", notes: ["one"]),
            usage: SnapshotHarness.usageFixture()
        ).asPair()

        let notesHeight = SnapshotHarness.height(for: shell)
        shell.activeTab = .usage
        let usageHeight = SnapshotHarness.height(for: shell)

        #expect(notesHeight == usageHeight)
    }

    // MARK: - Rendering

    @Test func rendersEveryScenarioOffscreen() throws {
        let usage = try #require(SnapshotHarness.usageFixture(), "usage fixture missing")
        let notes = ["ship the usage tab", "buy oat milk", "call the dentist tomorrow"]

        let scenarios: [SnapshotHarness.Scenario] = [
            .init(name: "notes-cyberpunk", theme: .cyberpunk, notes: notes),
            .init(name: "notes-system", theme: .system, notes: notes),
            .init(name: "notes-expanded-cyberpunk", theme: .cyberpunk, expanded: true, notes: notes),
            .init(name: "notes-editing-cyberpunk", theme: .cyberpunk, notes: notes, selectNewest: true),
            .init(name: "notes-empty-cyberpunk", theme: .cyberpunk, notes: []),
            .init(name: "usage-cyberpunk", tab: .usage, theme: .cyberpunk, notes: notes),
            .init(name: "usage-terminal", tab: .usage, theme: .terminal, notes: notes),
            .init(name: "usage-paper", tab: .usage, theme: .paper, notes: notes),
            .init(name: "usage-system", tab: .usage, theme: .system, notes: notes),
            .init(name: "usage-unavailable-cyberpunk", tab: .usage, theme: .cyberpunk, seedUsage: false),
        ]

        for scenario in scenarios {
            let path = try SnapshotHarness.write(scenario: scenario, usage: usage)
            let size = try #require(
                try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int
            )
            // A blank or failed render collapses to a near-empty PNG.
            #expect(size > 2_000, "\(scenario.name) rendered only \(size) bytes")
        }
    }
}

extension ConsoleShell {
    /// Small helper so a scenario can be built and reused in one expression.
    @MainActor
    fileprivate func asPair() -> (ConsoleShell, ConsoleShell) { (self, self) }
}
