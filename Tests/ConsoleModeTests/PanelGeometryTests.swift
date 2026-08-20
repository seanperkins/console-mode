import CoreGraphics
import Testing
@testable import ConsoleModeKit

// The card now carries a tab strip on every tab, so the collapsed notes height is
// the old 89pt content plus `tabBarHeight`.
private let collapsed: CGFloat = 89 + PanelGeometry.tabBarHeight

@Test func collapsedHeightIncludesTabBar() {
    #expect(PanelGeometry.contentHeight(visibleRowCount: 1) == collapsed)
    #expect(PanelGeometry.collapsedHeight() == collapsed)
}

@Test func panelHeightClampsToHalfScreen() {
    let height = PanelGeometry.panelHeight(
        tab: .notes,
        expanded: true,
        visibleRowCount: 100,
        providerCount: 0,
        screenVisibleHeight: 1_000
    )
    #expect(height == 500)
}

@Test func collapsedHeightIgnoresRowCount() {
    let height = PanelGeometry.panelHeight(
        tab: .notes,
        expanded: false,
        visibleRowCount: 50,
        providerCount: 0,
        screenVisibleHeight: 1_000
    )
    #expect(height == collapsed)
}

@Test func usageHeightGrowsPerProvider() {
    let three = PanelGeometry.usageHeight(providerCount: 3)
    let four = PanelGeometry.usageHeight(providerCount: 4)
    #expect(four - three == PanelGeometry.usageRowHeight)

    // Empty still reserves one line for the empty-state row.
    #expect(PanelGeometry.usageHeight(providerCount: 0) == PanelGeometry.usageHeight(providerCount: 1))
}

@Test func usageTabIgnoresNoteExpansion() {
    let expanded = PanelGeometry.panelHeight(
        tab: .usage,
        expanded: true,
        visibleRowCount: 80,
        providerCount: 3,
        screenVisibleHeight: 1_000
    )
    let collapsedNotes = PanelGeometry.panelHeight(
        tab: .usage,
        expanded: false,
        visibleRowCount: 1,
        providerCount: 3,
        screenVisibleHeight: 1_000
    )
    #expect(expanded == collapsedNotes)
    #expect(expanded == PanelGeometry.usageHeight(providerCount: 3))
}

@Test func usageTabAlsoClampsToHalfScreen() {
    let height = PanelGeometry.panelHeight(
        tab: .usage,
        expanded: false,
        visibleRowCount: 1,
        providerCount: 200,
        screenVisibleHeight: 800
    )
    #expect(height == 400)
}

@Test func frameCentersHorizontally() {
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
        providerCount: 0
    )
    #expect(frame.width == 640)
    #expect(frame.height == collapsed)
    #expect(frame.origin.x == CGFloat(100 + (1_800 - 640) / 2))
    // Card top stays flush under the menu bar regardless of height.
    #expect(frame.origin.y == 1_100 - collapsed)
}
