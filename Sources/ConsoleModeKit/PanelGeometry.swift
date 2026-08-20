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

    /// Chrome around the note list: everything that is not a note row.
    static let notesChrome: CGFloat = tabBarHeight + verticalPadding * 2 + dividerHeight + inputHeight

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

    /// The height both tabs share at rest. The usage tab cannot shrink — it needs
    /// one line per provider — so it sets the floor, and the notes tab matches it.
    /// That keeps the input bar from jumping when switching tabs.
    static func baselineHeight(providerCount: Int) -> CGFloat {
        max(contentHeight(visibleRowCount: 1), usageHeight(providerCount: providerCount))
    }

    /// Note rows that fit inside the shared baseline, so the notes tab spends the
    /// extra space on history instead of empty padding.
    static func notesRowCapacity(providerCount: Int) -> Int {
        let available = baselineHeight(providerCount: providerCount) - notesChrome
        return max(1, Int((available / rowHeight).rounded(.down)))
    }

    static func collapsedHeight(providerCount: Int = 0) -> CGFloat {
        baselineHeight(providerCount: providerCount)
    }

    static func panelHeight(
        tab: ConsoleTab,
        expanded: Bool,
        visibleRowCount: Int,
        providerCount: Int,
        screenVisibleHeight: CGFloat
    ) -> CGFloat {
        let baseline = baselineHeight(providerCount: providerCount)
        let desired: CGFloat
        switch tab {
        case .notes:
            // Expanding may grow past the baseline but never shrinks below it.
            desired = expanded
                ? max(contentHeight(visibleRowCount: visibleRowCount), baseline)
                : baseline
        case .usage:
            // Baseline, not raw usage height: with few providers the notes tab is
            // the taller one, and both must agree for the card to stay still.
            desired = baseline
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
