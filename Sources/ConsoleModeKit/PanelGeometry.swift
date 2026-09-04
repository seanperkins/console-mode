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
    static let suggestionRowHeight: CGFloat = 22
    static let suggestionPadding: CGFloat = 6
    static let suggestionMaxVisibleRows = 8
    /// Filter chip above the note list when a filter or review queue is active.
    static let filterBannerHeight: CGFloat = 22

    static func commandSuggestionOverlayMaxHeight(
        visibleRowCount: Int,
        noteDetailExtraHeight: CGFloat = 0,
        hasFilterBanner: Bool = false
    ) -> CGFloat {
        let rows = CGFloat(max(visibleRowCount, 1))
        let banner = hasFilterBanner ? filterBannerHeight : 0
        return banner + rows * rowHeight + noteDetailExtraHeight + dividerHeight
    }

    static func commandSuggestionLayout(
        suggestionCount: Int,
        maxHeight: CGFloat
    ) -> (height: CGFloat, visibleRows: Int) {
        guard suggestionCount > 0, maxHeight > 0 else { return (0, 0) }
        let maxRowsByHeight = Int(floor((maxHeight - suggestionPadding) / suggestionRowHeight))
        let visibleRows = min(suggestionCount, suggestionMaxVisibleRows, max(0, maxRowsByHeight))
        guard visibleRows > 0 else { return (0, 0) }
        let height = CGFloat(visibleRows) * suggestionRowHeight + suggestionPadding
        return (height, visibleRows)
    }


    static func commandSuggestionExtraHeight(
        suggestionCount: Int,
        maxHeight: CGFloat = .greatestFiniteMagnitude
    ) -> CGFloat {
        commandSuggestionLayout(suggestionCount: suggestionCount, maxHeight: maxHeight).height
    }

    static func contentHeight(
        visibleRowCount: Int,
        noteDetailExtraHeight: CGFloat = 0
    ) -> CGFloat {
        let rows = max(visibleRowCount, 1)
        return tabBarHeight
            + verticalPadding * 2
            + CGFloat(rows) * rowHeight
            + noteDetailExtraHeight
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
        screenVisibleHeight: CGFloat,
        noteDetailExtraHeight: CGFloat = 0
    ) -> CGFloat {
        let baseline = baselineHeight(lineCount: lineCount)
        let notesHeight = contentHeight(
            visibleRowCount: visibleRowCount,
            noteDetailExtraHeight: noteDetailExtraHeight
        )
        let desired: CGFloat
        switch tab {
        case .notes:
            desired = max(notesHeight, baseline)
        case .usage:
            desired = max(baseline, usageHeight(lineCount: lineCount))
        }
        return min(desired, screenVisibleHeight / 2)
    }

    static func frame(
        screen: ScreenMetrics,
        tab: ConsoleTab,
        expanded: Bool,
        visibleRowCount: Int,
        lineCount: Int,
        noteDetailExtraHeight: CGFloat = 0
    ) -> CGRect {
        let height = panelHeight(
            tab: tab,
            expanded: expanded,
            visibleRowCount: visibleRowCount,
            lineCount: lineCount,
            screenVisibleHeight: screen.visibleHeight,
            noteDetailExtraHeight: noteDetailExtraHeight
        )
        let x = screen.visibleOriginX + (screen.visibleWidth - cardWidth) / 2
        let y = screen.visibleOriginY + screen.visibleHeight - topGapBelowMenuBar - height
        return CGRect(x: x, y: y, width: cardWidth, height: height)
    }
}
