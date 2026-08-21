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
    /// One limit per line in the usage tab. Tighter than a note row because the
    /// text is denser and every limit is on screen at once.
    static let usageRowHeight: CGFloat = 22
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

    /// One line per limit, so the height is a direct function of how many limits
    /// `omp usage` reports across every provider.
    static func usageHeight(lineCount: Int) -> CGFloat {
        let lines = max(lineCount, 1)
        return tabBarHeight
            + verticalPadding * 2
            + CGFloat(lines) * usageRowHeight
            + dividerHeight
            + usageFooterHeight
    }

    /// The height both tabs share at rest. Whichever tab needs more room sets the
    /// floor and the other matches it, so switching never moves the input bar.
    static func baselineHeight(lineCount: Int) -> CGFloat {
        max(contentHeight(visibleRowCount: 1), usageHeight(lineCount: lineCount))
    }

    /// Note rows that fit inside the shared baseline, so the notes tab spends the
    /// extra space on history instead of empty padding.
    static func notesRowCapacity(lineCount: Int) -> Int {
        let available = baselineHeight(lineCount: lineCount) - notesChrome
        return max(1, Int((available / rowHeight).rounded(.down)))
    }

    static func collapsedHeight(lineCount: Int = 0) -> CGFloat {
        baselineHeight(lineCount: lineCount)
    }

    static func panelHeight(
        tab: ConsoleTab,
        expanded: Bool,
        visibleRowCount: Int,
        lineCount: Int,
        screenVisibleHeight: CGFloat
    ) -> CGFloat {
        let baseline = baselineHeight(lineCount: lineCount)
        let desired: CGFloat
        switch tab {
        case .notes:
            // Expanding may grow past the baseline but never shrinks below it.
            desired = expanded
                ? max(contentHeight(visibleRowCount: visibleRowCount), baseline)
                : baseline
        case .usage:
            // Baseline, not raw usage height: with few limits the notes tab is the
            // taller one, and both must agree for the card to stay still.
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
        lineCount: Int
    ) -> CGRect {
        let height = panelHeight(
            tab: tab,
            expanded: expanded,
            visibleRowCount: visibleRowCount,
            lineCount: lineCount,
            screenVisibleHeight: screen.visibleHeight
        )
        let x = screen.visibleOriginX + (screen.visibleWidth - cardWidth) / 2
        let y = screen.visibleOriginY + screen.visibleHeight - topGapBelowMenuBar - height
        return CGRect(x: x, y: y, width: cardWidth, height: height)
    }
}
