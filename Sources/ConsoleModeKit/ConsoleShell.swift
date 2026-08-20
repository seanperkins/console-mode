import Foundation
import Observation

/// Owns which tab is showing and the two tab models. The panel talks to this
/// rather than to `NoteListModel` directly, so the usage tab can drive height
/// and summoning on its own terms.
@Observable
@MainActor
final class ConsoleShell {
    var activeTab: ConsoleTab = .notes
    /// Held here so a Settings change restyles the live panel without a relaunch.
    var themeID: ThemeID = ThemeStore.currentID
    let notes: NoteListModel
    let usage: UsageMonitor

    var theme: ThemeTokens { themeID.tokens }

    func applyTheme(_ id: ThemeID) {
        ThemeStore.currentID = id
        themeID = id
    }

    /// Mirrored from settings so the tab strip redraws when it is toggled.
    var usageEnabled: Bool = UsageSettings.current.isEnabled

    init(notes: NoteListModel, usage: UsageMonitor) {
        self.notes = notes
        self.usage = usage
    }

    var tabs: [ConsoleTab] {
        usageEnabled ? ConsoleTab.allCases : [.notes]
    }

    /// Starts or stops polling to match the new setting, and leaves a tab that
    /// no longer exists.
    func setUsageEnabled(_ enabled: Bool) {
        usageEnabled = enabled
        if enabled {
            usage.start()
        } else {
            usage.stop()
            if activeTab == .usage { activeTab = .notes }
        }
    }

    func select(_ tab: ConsoleTab) {
        guard tabs.contains(tab), tab != activeTab else { return }
        activeTab = tab
        if tab == .usage {
            // Opening the tab is an explicit request for current numbers.
            Task { await usage.refresh() }
        }
    }

    func cycleTab() {
        select(activeTab.next)
    }

    /// Rows the notes tab wants to show, used for panel height.
    var visibleRowCount: Int { notes.visibleRowCount }

    /// Lines the usage tab wants to show; at least one so the empty state fits.
    var usageLineCount: Int {
        max(usage.rollup.count, 1)
    }
}
