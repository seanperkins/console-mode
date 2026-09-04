import AppKit
import Testing
@testable import ConsoleModeKit

/// Drives the real views offscreen and asserts the key bindings directly.
///
/// Bindings are tested through `ConsoleKeyBinding.action(for:)` rather than by
/// calling `panel.keyDown`. Calling the override proved only that its body ran; it
/// bypassed AppKit dispatch entirely, and in the live app a Control-modified key
/// never reaches the panel — the focused text field takes it first. The real path
/// is a local NSEvent monitor, and this is the decision that monitor makes.
@MainActor
struct PanelHarnessTests {

    private func makeShell() throws -> ConsoleShell {
        try SnapshotHarness.makeShell(
            for: .init(name: "keys", notes: ["alpha", "beta"]),
            usage: SnapshotHarness.usageFixture()
        )
    }

    // MARK: - Control bindings (primary: the summon chord already holds Control)

    @Test func controlOneAndTwoSelectTabs() {
        #expect(
            ConsoleKeyBinding.action(for: KeyDriver.event(characters: "1", keyCode: 18, flags: .control))
                == .selectTab(.notes)
        )
        #expect(
            ConsoleKeyBinding.action(for: KeyDriver.event(characters: "2", keyCode: 19, flags: .control))
                == .selectTab(.usage)
        )
    }

    @Test func commandOneAndTwoStillWork() {
        // Kept as an alias for habit, not as the documented binding.
        #expect(ConsoleKeyBinding.action(for: KeyDriver.command("1", keyCode: 18)) == .selectTab(.notes))
        #expect(ConsoleKeyBinding.action(for: KeyDriver.command("2", keyCode: 19)) == .selectTab(.usage))
    }

    @Test func controlTabCycles() {
        #expect(ConsoleKeyBinding.action(for: KeyDriver.controlTab()) == .cycleTab)
    }

    @Test func refreshBindsUnderBothModifiers() {
        #expect(ConsoleKeyBinding.action(for: KeyDriver.command("r", keyCode: 15)) == .refreshUsage)
        #expect(
            ConsoleKeyBinding.action(for: KeyDriver.event(characters: "r", keyCode: 15, flags: .control))
                == .refreshUsage
        )
    }

    @Test func escapeDismisses() {
        #expect(
            ConsoleKeyBinding.action(for: KeyDriver.event(characters: "\u{1b}", keyCode: 53, flags: []))
                == .dismiss
        )
    }

    // MARK: - Things that must not be claimed

    @Test func summonChordIsNotMistakenForATabSwitch() {
        // ⌃⇧` is the global hotkey; the extra Shift must disqualify it.
        let event = KeyDriver.event(characters: "`", keyCode: 50, flags: [.control, .shift])
        #expect(ConsoleKeyBinding.action(for: event) == nil)
    }

    @Test func plainDigitsReachTheTextField() {
        // Typing "2" into a note must never switch tabs.
        #expect(ConsoleKeyBinding.action(for: KeyDriver.event(characters: "2", keyCode: 19, flags: [])) == nil)
    }

    @Test func otherCommandKeysArePassedThrough() {
        for (character, keyCode) in [("v", UInt16(9)), ("c", 8), ("a", 0), ("z", 6), ("q", 12)] {
            #expect(
                ConsoleKeyBinding.action(for: KeyDriver.command(character, keyCode: keyCode)) == nil,
                "⌘\(character) must not be swallowed"
            )
        }
    }

    @Test func shiftedDigitsAreIgnored() {
        let event = KeyDriver.event(characters: "1", keyCode: 18, flags: [.control, .shift])
        #expect(ConsoleKeyBinding.action(for: event) == nil)
    }

    @Test func plainTabIsLeftToTheKeyViewLoop() {
        // Tab without Control still walks checkbox -> field -> chevron.
        #expect(ConsoleKeyBinding.action(for: KeyDriver.event(characters: "\t", keyCode: 48, flags: [])) == nil)
    }

    // MARK: - Shell behaviour behind those actions

    @Test func selectingTabsMovesTheShell() throws {
        let shell = try makeShell()
        #expect(shell.activeTab == .notes)

        shell.select(.usage)
        #expect(shell.activeTab == .usage)

        shell.cycleTab()
        #expect(shell.activeTab == .notes)
    }

    @Test func tabsAreUnavailableWhenUsageIsOff() throws {
        let shell = try makeShell()
        shell.setUsageEnabled(false)

        shell.select(.usage)
        #expect(shell.activeTab == .notes)
    }

    @Test func onDataChangeExpandsPrewarmedPanelWhenUsageLinesArrive() throws {
        let store = try NoteStore.inMemory()
        _ = try store.append("alpha")
        let model = NoteListModel(store: store)
        let usage = UsageMonitor(defaults: SnapshotHarness.scratchDefaults(), seeded: nil)
        let shell = ConsoleShell(notes: model, usage: usage)
        shell.usageEnabled = true
        shell.activeTab = .usage

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let metrics = ScreenLocator.metrics(for: screen)
        let panel = ConsolePanel(shell: shell)
        usage.onDataChange = {
            shell.syncCollapsedCapacity()
            panel.updateLayout(on: screen, animated: false)
        }

        panel.prewarm(on: screen)
        #expect(shell.usageLineCount == 1)
        let oneLineHeight = panel.frame.height
        let expectedOneLine = PanelGeometry.panelHeight(
            tab: .usage,
            expanded: false,
            visibleRowCount: shell.visibleRowCount,
            lineCount: 1,
            screenVisibleHeight: metrics.visibleHeight
        )
        #expect(oneLineHeight == expectedOneLine)

        let fixture = try #require(SnapshotHarness.usageFixture())
        let lineCount = fixture.allLines.count
        #expect(lineCount == 8)

        usage.simulateLoadedSnapshot(fixture)

        let loadedHeight = panel.frame.height
        let expectedLoaded = PanelGeometry.panelHeight(
            tab: .usage,
            expanded: false,
            visibleRowCount: shell.visibleRowCount,
            lineCount: lineCount,
            screenVisibleHeight: metrics.visibleHeight
        )
        #expect(loadedHeight > oneLineHeight)
        #expect(loadedHeight == expectedLoaded)
    }

    @Test func collapsedPanelKeepsHeightWhenSlashSuggestionsAppear() throws {
        let store = try NoteStore.inMemory()
        _ = try store.append("alpha")
        _ = try store.append("beta")
        let model = NoteListModel(store: store)
        let usage = UsageMonitor(defaults: SnapshotHarness.scratchDefaults(), seeded: nil)
        let shell = ConsoleShell(notes: model, usage: usage)
        shell.usageEnabled = true
        shell.activeTab = .notes

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let metrics = ScreenLocator.metrics(for: screen)
        let panel = ConsolePanel(shell: shell)
        panel.prewarm(on: screen)

        model.draft = ""
        panel.updateLayout(on: screen, animated: false)
        let withoutPalette = panel.frame.height

        model.draft = "/"
        panel.updateLayout(on: screen, animated: false)
        let withPalette = panel.frame.height

        let expected = PanelGeometry.panelHeight(
            tab: .notes,
            expanded: false,
            visibleRowCount: shell.visibleRowCount,
            lineCount: shell.usageLineCount,
            screenVisibleHeight: metrics.visibleHeight,
            noteDetailExtraHeight: shell.notesDetailExtraHeight
        )
        #expect(withoutPalette == expected)
        #expect(withPalette == expected)
        #expect(shell.notes.commandSuggestionExtraHeight > 0)
    }

    @Test func panelHeightMatchesAcrossTabs() throws {
        let shell = try makeShell()
        let notesHeight = SnapshotHarness.height(for: shell)
        shell.activeTab = .usage
        #expect(SnapshotHarness.height(for: shell) == notesHeight)
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
            .init(name: "notes-slash-suggestions-cyberpunk", theme: .cyberpunk, notes: notes, draft: "/"),
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
