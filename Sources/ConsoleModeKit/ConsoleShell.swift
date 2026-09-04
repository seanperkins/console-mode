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
    /// Mirrored from settings, same pattern as `usageEnabled`.
    var terminalEnabled: Bool = TerminalSettings.current.isEnabled
    /// Flips true the first time the terminal tab is selected. Gates whether
    /// `ConsoleView` mounts `TerminalTabView` at all — a real PTY only spawns
    /// once this is true, never at panel construction, so an app where the
    /// terminal tab is never opened pays zero cost for the feature existing.
    /// Never resets to false: once a session exists, it stays mounted (and
    /// merely hidden) so tab switches never lose it.
    private(set) var hasActivatedTerminal = false

    /// Called once, the first time the terminal tab becomes active.
    func markTerminalActivated() {
        hasActivatedTerminal = true
    }

    init(notes: NoteListModel, usage: UsageMonitor) {
        self.notes = notes
        self.usage = usage
        syncCollapsedCapacity()
    }

    /// The usage tab sets the resting height, so the notes tab shows as many rows
    /// as that height allows.
    func syncCollapsedCapacity() {
        notes.collapsedRowCapacity = PanelGeometry.notesRowCapacity(lineCount: usageLineCount)
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
        switch tab {
        case .usage:
            // Opening the tab is an explicit request for current numbers.
            Task { await usage.refresh() }
        case .notes:
            notes.requestInputFocus()
        }
    }

    func cycleTab() {
        select(activeTab.next)
    }

    /// Rows the notes tab wants to show, used for panel height.
    var visibleRowCount: Int { notes.visibleRowCount }
    var notesDetailExtraHeight: CGFloat { notes.selectedNoteDetailExtraHeight }

    /// Rows the usage tab wants: one per limit across every provider, and at
    /// least one so the empty state fits.
    var usageLineCount: Int {
        max(usage.lines.count, 1)
    }
}
