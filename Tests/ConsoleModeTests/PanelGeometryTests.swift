import CoreGraphics
import Testing
@testable import ConsoleModeKit

/// With three limit lines the usage tab is the taller one, so it sets the baseline.
private let lines = 3
private let baseline = PanelGeometry.baselineHeight(lineCount: lines)

@Test func bothTabsShareTheRestingHeight() {
    // The whole point: switching tabs must not move the card or the input bar.
    for tab in ConsoleTab.allCases {
        let height = PanelGeometry.panelHeight(
            tab: tab,
            expanded: false,
            visibleRowCount: 1,
            lineCount: lines,
            screenVisibleHeight: 1_000
        )
        #expect(height == baseline)
    }
}

@Test func baselineTakesTheTallerTab() {
    // Eight limits, as the real payload reports: usage wins.
    #expect(PanelGeometry.baselineHeight(lineCount: 8) == PanelGeometry.usageHeight(lineCount: 8))
    // A single limit line is shorter than the notes chrome, so notes wins.
    #expect(PanelGeometry.baselineHeight(lineCount: 1) == PanelGeometry.contentHeight(visibleRowCount: 1))
}

@Test func rowCapacityFillsTheBaseline() {
    let capacity = PanelGeometry.notesRowCapacity(lineCount: lines)
    #expect(capacity >= 1)

    // The rows that fit must not overflow the shared height.
    let used = PanelGeometry.notesChrome + CGFloat(capacity) * PanelGeometry.rowHeight
    #expect(used <= baseline)
    // And one more row would overflow, so the space is actually being used.
    #expect(used + PanelGeometry.rowHeight > baseline)
}

@Test func collapsedNotesMatchesBaselineNotOneRow() {
    let height = PanelGeometry.panelHeight(
        tab: .notes,
        expanded: false,
        visibleRowCount: 1,
        lineCount: lines,
        screenVisibleHeight: 1_000
    )
    #expect(height == baseline)
    #expect(height > PanelGeometry.contentHeight(visibleRowCount: 1))
}

@Test func expandingNeverShrinksBelowBaseline() {
    let height = PanelGeometry.panelHeight(
        tab: .notes,
        expanded: true,
        visibleRowCount: 1,
        lineCount: lines,
        screenVisibleHeight: 1_000
    )
    #expect(height == baseline)
}

@Test func panelHeightClampsToHalfScreen() {
    let height = PanelGeometry.panelHeight(
        tab: .notes,
        expanded: true,
        visibleRowCount: 100,
        lineCount: lines,
        screenVisibleHeight: 1_000
    )
    #expect(height == 500)
}

@Test func usageHeightGrowsPerProvider() {
    let three = PanelGeometry.usageHeight(lineCount: 3)
    let four = PanelGeometry.usageHeight(lineCount: 4)
    #expect(four - three == PanelGeometry.usageRowHeight)

    // Empty still reserves one line for the empty-state row.
    #expect(PanelGeometry.usageHeight(lineCount: 0) == PanelGeometry.usageHeight(lineCount: 1))
}

@Test func usageTabIgnoresNoteExpansion() {
    let expanded = PanelGeometry.panelHeight(
        tab: .usage,
        expanded: true,
        visibleRowCount: 80,
        lineCount: lines,
        screenVisibleHeight: 1_000
    )
    #expect(expanded == baseline)
}


@Test func usageTabAlsoClampsToHalfScreen() {
    let height = PanelGeometry.panelHeight(
        tab: .usage,
        expanded: false,
        visibleRowCount: 1,
        lineCount: 200,
        screenVisibleHeight: 800
    )
    #expect(height == 400)
}

@Test func frameCentersHorizontallyAndStaysFlush() {
    let screen = ScreenMetrics(
        visibleOriginX: 100,
        visibleOriginY: 0,
        visibleWidth: 1_800,
        visibleHeight: 1_100
    )
    let frame = PanelGeometry.frame(
        screen: screen,
        tab: .notes,
        expanded: false,
        visibleRowCount: 1,
        lineCount: lines
    )
    #expect(frame.width == 640)
    #expect(frame.height == baseline)
    #expect(frame.origin.x == CGFloat(100 + (1_800 - 640) / 2))
    // Card top stays flush under the menu bar regardless of height.
    #expect(frame.origin.y == 1_100 - baseline)
}
