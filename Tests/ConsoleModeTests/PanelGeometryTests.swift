import CoreGraphics
import Testing
@testable import ConsoleModeKit

@Test func collapsedHeightIs89() {
    #expect(PanelGeometry.contentHeight(visibleRowCount: 1) == 89)
    #expect(PanelGeometry.collapsedHeight() == 89)
}

@Test func panelHeightClampsToHalfScreen() {
    let height = PanelGeometry.panelHeight(
        visibleRowCount: 100,
        screenVisibleHeight: 1_000,
        expanded: true
    )
    #expect(height == 500)
}

@Test func collapsedHeightIgnoresRowCount() {
    let height = PanelGeometry.panelHeight(
        visibleRowCount: 50,
        screenVisibleHeight: 1_000,
        expanded: false
    )
    #expect(height == 89)
}

@Test func frameCentersHorizontally() {
    let screen = ScreenMetrics(
        visibleOriginX: 100,
        visibleOriginY: 0,
        visibleWidth: 1_800,
        visibleHeight: 1_100
    )
    let frame = PanelGeometry.frame(screen: screen, expanded: false, visibleRowCount: 1)
    #expect(frame.width == 640)
    #expect(frame.height == 89)
    #expect(frame.origin.x == CGFloat(100 + (1_800 - 640) / 2))
    #expect(frame.origin.y == CGFloat(1_100 - 120 - 89))
}
