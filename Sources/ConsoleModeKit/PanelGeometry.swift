import CoreGraphics

enum PanelGeometry {
    static let cardWidth: CGFloat = 640
    /// Gap between the menu bar and the card top (visible frame maxY).
    static let topGapBelowMenuBar: CGFloat = 0
    static let rowHeight: CGFloat = 28
    static let inputHeight: CGFloat = 36
    static let verticalPadding: CGFloat = 12
    static let dividerHeight: CGFloat = 1
    static let cornerRadius: CGFloat = 16
    static let dropOffset: CGFloat = 24
    /// Compact tab strip above the content on every tab.
    static let tabBarHeight: CGFloat = 28
    /// One provider per line in the usage tab.
    static let usageRowHeight: CGFloat = 30
    /// Footer line carrying refresh time and errors.
    static let usageFooterHeight: CGFloat = 18

    static func contentHeight(visibleRowCount: Int) -> CGFloat {
        let rows = max(visibleRowCount, 1)
        return tabBarHeight
            + verticalPadding * 2
            + CGFloat(rows) * rowHeight
            + dividerHeight
            + inputHeight
    }

    static func collapsedHeight() -> CGFloat {
        contentHeight(visibleRowCount: 1)
    }

    /// One line per provider, so the height is a direct function of how many
    /// accounts `omp usage` reports.
    static func usageHeight(providerCount: Int) -> CGFloat {
        let lines = max(providerCount, 1)
        return tabBarHeight
            + verticalPadding * 2
            + CGFloat(lines) * usageRowHeight
            + dividerHeight
            + usageFooterHeight
    }

    static func panelHeight(
        tab: ConsoleTab,
        expanded: Bool,
        visibleRowCount: Int,
        providerCount: Int,
        screenVisibleHeight: CGFloat
    ) -> CGFloat {
        let desired: CGFloat
        switch tab {
        case .notes:
            desired = expanded ? contentHeight(visibleRowCount: visibleRowCount) : collapsedHeight()
        case .usage:
            desired = usageHeight(providerCount: providerCount)
        }
        // Never taller than half the screen, on either tab.
        return min(desired, screenVisibleHeight / 2)
    }

    static func frame(
        screen: ScreenMetrics,
        tab: ConsoleTab,
        expanded: Bool,
        visibleRowCount: Int,
        providerCount: Int
    ) -> CGRect {
        let height = panelHeight(
            tab: tab,
            expanded: expanded,
            visibleRowCount: visibleRowCount,
            providerCount: providerCount,
            screenVisibleHeight: screen.visibleHeight
        )
        let x = screen.visibleOriginX + (screen.visibleWidth - cardWidth) / 2
        let y = screen.visibleOriginY + screen.visibleHeight - topGapBelowMenuBar - height
        return CGRect(x: x, y: y, width: cardWidth, height: height)
    }
}
