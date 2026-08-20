import CoreGraphics

enum PanelGeometry {
    static let cardWidth: CGFloat = 640
    static let topInset: CGFloat = 120
    static let rowHeight: CGFloat = 28
    static let inputHeight: CGFloat = 36
    static let verticalPadding: CGFloat = 12
    static let dividerHeight: CGFloat = 1
    static let cornerRadius: CGFloat = 16
    static let dropOffset: CGFloat = 24

    static func contentHeight(visibleRowCount: Int) -> CGFloat {
        let rows = max(visibleRowCount, 1)
        return verticalPadding * 2
            + CGFloat(rows) * rowHeight
            + dividerHeight
            + inputHeight
    }

    static func collapsedHeight() -> CGFloat {
        contentHeight(visibleRowCount: 1)
    }

    static func panelHeight(visibleRowCount: Int, screenVisibleHeight: CGFloat, expanded: Bool) -> CGFloat {
        guard expanded else { return collapsedHeight() }
        return min(contentHeight(visibleRowCount: visibleRowCount), screenVisibleHeight / 2)
    }

    static func frame(screen: ScreenMetrics, expanded: Bool, visibleRowCount: Int) -> CGRect {
        let height = panelHeight(
            visibleRowCount: visibleRowCount,
            screenVisibleHeight: screen.visibleHeight,
            expanded: expanded
        )
        let x = screen.visibleOriginX + (screen.visibleWidth - cardWidth) / 2
        let y = screen.visibleOriginY + screen.visibleHeight - topInset - height
        return CGRect(x: x, y: y, width: cardWidth, height: height)
    }
}
