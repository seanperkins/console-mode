import AppKit
import Foundation
import GRDB
import Observation

@Observable
@MainActor
final class NoteListModel {
    var draft = ""
    var expanded = false
    private(set) var notes: [Note] = []
    private(set) var editingNoteID: Int64?
    private(set) var scrollTargetID: Int64?
    /// Unsaved new-note text stashed while walking the list with the arrow keys.
    private var pendingDraft = ""
    private(set) var isBackfilling = false
    private(set) var isAnalyzing = false
    var tagStatus: String?
    var analyzeStatus: String?
    /// Transient feedback shown as the input placeholder; cleared on the next keystroke.
    var statusMessage: String?
    /// Set by AppDelegate for commands the model cannot perform itself.
    var onAction: ((ConsoleAction) -> Void)?
    private(set) var filter: NoteFilter = .all
    private(set) var isReviewing = false

    private let store: NoteStore
    private var observation: AnyDatabaseCancellable?

    init(store: NoteStore) {
        self.store = store
        restartObservation()
    }


    /// How many rows the collapsed notes tab can show. Driven by the usage tab's
    /// height so both tabs are the same size at rest.
    var collapsedRowCapacity = 1 {
        didSet {
            guard collapsedRowCapacity != oldValue, !expanded else { return }
            restartObservation()
        }
    }

    var visibleRowCount: Int {
        max(notes.count, 1)
    }

    /// Rendered top-to-bottom: oldest at the top, newest last so it sits directly
    /// above the input. `notes` stays newest-first for arrow-key navigation.
    var displayNotes: [Note] {
        notes.reversed()
    }

    /// Newest note — the row nearest the input, and the one shown when collapsed.
    var newestNote: Note? {
        notes.first
    }

    var focusToken = 0

    /// Space above the input row available for the slash-command palette overlay.
    var commandSuggestionOverlayMaxHeight: CGFloat {
        PanelGeometry.commandSuggestionOverlayMaxHeight(
            visibleRowCount: visibleRowCount,
            noteDetailExtraHeight: selectedNoteDetailExtraHeight,
            hasFilterBanner: filterLabel != nil
        )
    }

    /// Height of the slash-command palette when visible. Overlays the note list; does not resize the panel.
    var commandSuggestionExtraHeight: CGFloat {
        PanelGeometry.commandSuggestionExtraHeight(
            suggestionCount: ConsoleInput.commandSuggestions(for: draft).count,
            maxHeight: commandSuggestionOverlayMaxHeight
        )
    }
    /// Extra list height while a note is selected and its detail strip is visible.
    var selectedNoteDetailExtraHeight: CGFloat {
        guard let note = editingNote else { return 0 }
        return NoteDetailLayout.detailHeight(for: note)
    }

    var isEditingExistingNote: Bool {
        editingNoteID != nil
    }

    var filterLabel: String? {
        if isReviewing { return "Review" }
        return filter.label
    }

    var emptyListMessage: String {
        if filter.isActive { return "No matches" }
        return "No notes yet"
    }

    /// Rows the current tab state wants loaded.
    private var observationLimit: Int {
        expanded ? 200 : max(1, collapsedRowCapacity)
    }

    /// Synchronous re-read. `ValueObservation` delivers asynchronously, so without
    /// this the card paints empty on first summon, and any read-after-write (the
    /// completion checkbox) would see a stale row.
    func refreshNotes() {
        if let fresh = try? store.fetchFiltered(filter, limit: observationLimit) {
            notes = fresh
        }
    }

    func restartObservation() {
        observation?.cancel()
        refreshNotes()
        observation = store.observeFiltered(filter, limit: observationLimit) { [weak self] notes in
            Task { @MainActor in
                self?.notes = notes
            }
        }
    }

    private func navigationList() throws -> [Note] {
        try store.fetchFiltered(filter, limit: 200)
    }

    func toggleExpanded() {
        expanded.toggle()
        restartObservation()
    }

    func commitDraft() {
        switch ConsoleInput.parse(draft) {
        case .empty:
            return
        case .command(let command, let argument):
            run(command, argument: argument)
        case .unknownCommand(let name):
            statusMessage = "Unknown command /\(name) — try /help"
        case .note(let body, let tags):
            save(body: body, tags: tags)
        }
    }

    /// A manual `#tag` wins over the model: it is an explicit instruction, so it is
    /// written immediately and the note is marked tagged to keep the tagger off it.
    private func save(body: String, tags: [String]) {
        do {
            if let editingNoteID {
                guard let updated = try store.updateBody(id: editingNoteID, rawBody: body) else { return }
                if let tag = tags.first {
                    try store.setProject(id: editingNoteID, project: tag, confidence: 1)
                } else {
                    scheduleTagging(noteID: editingNoteID, body: updated.body)
                }
                clearEditing()
            } else if let saved = try store.append(body), let id = saved.id {
                draft = ""
                pendingDraft = ""
                if let tag = tags.first {
                    try store.setProject(id: id, project: tag, confidence: 1)
                } else {
                    scheduleTagging(noteID: id, body: saved.body)
                }
                exportCapturedNote(saved)
            }
        } catch {
            NSLog("Failed to save note: \(error)")
            statusMessage = "Could not save that note."
        }
    }

    // MARK: - Commands

    private func run(_ command: SlashCommand, argument: String) {
        switch command {
        case .help:
            statusMessage = ConsoleInput.helpText
            draft = ""

        case .tag:
            guard let id = editingNoteID else {
                statusMessage = "Press ↑ to pick a note, then /tag it."
                draft = ""
                return
            }
            guard let slug = ProjectTagger.normalize(argument) else {
                statusMessage = "Usage: /tag project-name"
                draft = ""
                return
            }
            applyProject(slug, to: id, message: "Tagged \(slug).")

        case .untag:
            guard let id = editingNoteID else {
                statusMessage = "Press ↑ to pick a note first."
                draft = ""
                return
            }
            applyProject(nil, to: id, message: "Removed the project.")

        case .done:
            guard editingNote != nil else {
                statusMessage = "Press ↑ to pick a note first."
                draft = ""
                return
            }
            toggleCompletionForEditingNote()
            draft = ""
            if isReviewing {
                statusMessage = "Marked done."
                advanceReview()
            } else {
                statusMessage = isEditingNoteCompleted ? "Marked done." : "Marked not done."
                clearEditing()
            }

        case .find:
            guard !argument.isEmpty else {
                statusMessage = "Usage: /find search text"
                draft = ""
                return
            }
            applyFilter(.text(argument))

        case .project:
            guard let slug = ProjectTagger.normalize(argument) else {
                statusMessage = "Usage: /project name"
                draft = ""
                return
            }
            applyFilter(.project(slug))

        case .todo:
            applyFilter(.incomplete)

        case .all:
            stopReview()
            applyFilter(.all)

        case .review:
            startReview()

        case .next:
            guard isReviewing else {
                statusMessage = "Start with /review first."
                draft = ""
                return
            }
            draft = ""
            advanceReview(skipping: true)

        case .copy:
            copyEditingNote()

        case .remind:
            setReminder(from: argument)

        case .unremind:
            clearReminder()

        case .analyze:
            runAnalyze(argument: argument)

        case .actions:
            applyFilter(.actionable)

        case .unaction:
            clearActionReviewOnSelection()

        case .clear:
            draft = ""
            pendingDraft = ""
            clearEditing()

        case .delete:
            guard let id = editingNoteID else {
                statusMessage = "Press ↑ to pick a note first."
                draft = ""
                return
            }
            do {
                ReminderScheduler.cancel(noteID: id)
                try store.delete(id: id)
                clearEditing()
                statusMessage = "Deleted."
            } catch {
                NSLog("Failed to delete note: \(error)")
                statusMessage = "Could not delete that note."
            }

        case .expand:
            draft = ""
            guard !expanded else { return }
            toggleExpanded()

        case .collapse:
            draft = ""
            guard expanded else { return }
            toggleExpanded()

        case .settings:
            draft = ""
            onAction?(.openSettings)

        case .quit:
            onAction?(.quit)
        }
    }

    private func applyProject(_ slug: String?, to id: Int64, message: String) {
        do {
            try store.setProject(id: id, project: slug, confidence: 1)
            statusMessage = message
        } catch {
            NSLog("Failed to set project: \(error)")
            statusMessage = "Could not update the project."
        }
        draft = ""
        clearEditing()
    }

    // MARK: - Bulk actions

    var noteCount: Int {
        (try? store.count()) ?? 0
    }

    /// Irreversible. Settings confirms before calling this.
    @discardableResult
    func deleteAllNotes() -> Int {
        do {
            let removed = try store.deleteAll()
            // The selection and stashed draft both point at notes that no longer exist.
            clearEditing()
            pendingDraft = ""
            draft = ""
            statusMessage = "Deleted \(removed) note\(removed == 1 ? "" : "s")."
            return removed
        } catch {
            NSLog("Failed to delete all notes: \(error)")
            statusMessage = "Could not delete the notes."
            return 0
        }
    }

    /// Fetches everything for a Markdown/JSON backup. Settings drives the
    /// save panel and the actual file write via `NoteExporter`; this just
    /// hands back the data and a status line.
    func exportAllNotes() -> [Note] {
        do {
            let notes = try store.fetchAllForExport()
            if notes.isEmpty {
                statusMessage = "No notes to export."
            }
            return notes
        } catch {
            NSLog("Failed to fetch notes for export: \(error)")
            statusMessage = "Could not read notes to export."
            return []
        }
    }

    // MARK: - Project tagging

    /// Fire-and-forget so capture never waits on the model (~5s per call).
    private func scheduleTagging(noteID: Int64, body: String) {
        let config = TaggerSettings.current
        guard config.isEnabled else { return }

        let service = NoteTagService(store: store)
        Task.detached(priority: .utility) {
            await service.tag(noteID: noteID, body: body, config: config)
        }
    }

    /// Label notes the tagger has never seen. Surfaced from Settings.
    func backfillTags(limit: Int = 200) {
        guard !isBackfilling else { return }
        let config = TaggerSettings.current
        guard config.isEnabled else {
            tagStatus = "Tagging is turned off."
            return
        }

        isBackfilling = true
        tagStatus = "Tagging…"

        let service = NoteTagService(store: store)
        Task { [weak self] in
            let labelled = await service.backfill(limit: limit, config: config)
            let remaining = service.untaggedCount()
            self?.isBackfilling = false
            self?.tagStatus = remaining == 0
                ? "Tagged \(labelled) note\(labelled == 1 ? "" : "s")."
                : "Tagged \(labelled); \(remaining) still pending."
        }
    }

    func requestInputFocus() {
        focusToken += 1
    }

    func navigateToOlderNote() {
        do {
            if !expanded {
                let total = try navigationList().count
                if total > 1 {
                    expanded = true
                    restartObservation()
                }
            }

            let list = try navigationList()
            guard !list.isEmpty else { return }

            if let editingNoteID, let index = list.firstIndex(where: { $0.id == editingNoteID }) {
                let nextIndex = index + 1
                guard nextIndex < list.count else { return }
                beginEditing(list[nextIndex])
            } else {
                pendingDraft = draft
                beginEditing(list[0])
            }
        } catch {
            NSLog("Failed to navigate notes: \(error)")
        }
    }

    func navigateToNewerNote() {
        guard let editingNoteID else { return }

        do {
            let list = try navigationList()
            guard let index = list.firstIndex(where: { $0.id == editingNoteID }) else {
                clearEditing()
                return
            }

            if index > 0 {
                beginEditing(list[index - 1])
            } else {
                clearEditing()
            }
        } catch {
            NSLog("Failed to navigate notes: \(error)")
        }
    }

    func toggleCompletion(for note: Note) {
        guard let id = note.id else { return }
        do {
            let markingDone = !note.isCompleted
            try store.setCompleted(id: id, completed: markingDone)
            if markingDone, note.remindAt != nil {
                try store.setRemindAt(id: id, date: nil)
                ReminderScheduler.cancel(noteID: id)
            }
            refreshNotes()
        } catch {
            NSLog("Failed to toggle completion: \(error)")
        }
    }

    /// The note currently loaded into the input via the arrow keys, if any.
    /// Falls back to a direct fetch because `notes` holds only one row when collapsed.
    var editingNote: Note? {
        guard let editingNoteID else { return nil }
        if let loaded = notes.first(where: { $0.id == editingNoteID }) {
            return loaded
        }
        return try? store.fetchNote(id: editingNoteID)
    }

    var isEditingNoteCompleted: Bool {
        editingNote?.isCompleted ?? false
    }

    /// Toggle completion on the note in the input. No-op while composing a new note.
    func toggleCompletionForEditingNote() {
        guard let note = editingNote else { return }
        toggleCompletion(for: note)
    }

    func isNoteSelected(_ note: Note) -> Bool {
        guard let editingNoteID, let noteID = note.id else { return false }
        return editingNoteID == noteID
    }


    // MARK: - Filters and review

    private func applyFilter(_ filter: NoteFilter) {
        isReviewing = false
        self.filter = filter
        draft = ""
        pendingDraft = ""
        clearEditing()
        if filter.isActive, !expanded {
            expanded = true
        }
        restartObservation()
        statusMessage = filter.label ?? "Showing all notes."
    }

    private func startReview() {
        do {
            let queue = try store.fetchReviewQueue(limit: 200)
            guard let first = queue.first else {
                statusMessage = "Inbox clear."
                draft = ""
                return
            }
            isReviewing = true
            filter = .incomplete
            expanded = true
            restartObservation()
            beginEditing(first)
            statusMessage = "Reviewing \(queue.count) note\(queue.count == 1 ? "" : "s"). /next to skip."
        } catch {
            NSLog("Failed to start review: \(error)")
            statusMessage = "Could not start review."
            draft = ""
        }
    }

    private func stopReview() {
        isReviewing = false
    }

    private func advanceReview(skipping: Bool = false) {
        guard isReviewing else { return }
        do {
            let queue = try store.fetchReviewQueue(limit: 200)
            guard !queue.isEmpty else {
                stopReview()
                filter = .all
                restartObservation()
                clearEditing()
                statusMessage = "Inbox clear."
                return
            }

            if skipping, let currentID = editingNoteID,
               let index = queue.firstIndex(where: { $0.id == currentID }) {
                let nextIndex = index + 1
                if nextIndex < queue.count {
                    beginEditing(queue[nextIndex])
                    return
                }
                statusMessage = "End of queue."
                beginEditing(queue[0])
                return
            }

            beginEditing(queue[0])
        } catch {
            NSLog("Failed to advance review: \(error)")
            statusMessage = "Review stalled."
        }
    }

    private func copyEditingNote() {
        guard let note = editingNote else {
            statusMessage = "Press ↑ to pick a note first."
            draft = ""
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.body, forType: .string)
        statusMessage = "Copied."
        draft = ""
        if !isReviewing {
            clearEditing()
        }
    }



    // MARK: - Action review

    private func runAnalyze(argument: String) {
        guard !isAnalyzing else { return }
        let config = ActionReviewSettings.current
        guard config.isEnabled else {
            statusMessage = "Action review is turned off in Settings."
            draft = ""
            return
        }

        let notes: [Note]
        if argument.isEmpty, let selected = editingNote {
            notes = [selected]
        } else {
            let limit = Int(argument.trimmingCharacters(in: .whitespacesAndNewlines)) ?? config.batchSize
            let capped = max(1, min(limit, 50))
            do {
                notes = try store.fetchUnreviewed(limit: capped)
            } catch {
                statusMessage = "Could not load notes to review."
                draft = ""
                return
            }
        }

        guard !notes.isEmpty else {
            statusMessage = "Nothing to analyze."
            draft = ""
            return
        }

        isAnalyzing = true
        analyzeStatus = "Analyzing \(notes.count) note\(notes.count == 1 ? "" : "s")…"
        statusMessage = analyzeStatus
        draft = ""

        let service = NoteActionService(store: store)
        Task { [weak self] in
            do {
                let reviewed = try await service.reviewNotes(notes, config: config)
                let remaining = service.unreviewedCount()
                self?.isAnalyzing = false
                self?.analyzeStatus = remaining == 0
                    ? "Reviewed \(reviewed) note\(reviewed == 1 ? "" : "s")."
                    : "Reviewed \(reviewed); \(remaining) still pending."
                self?.statusMessage = self?.analyzeStatus
            } catch {
                self?.isAnalyzing = false
                self?.analyzeStatus = nil
                self?.statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func backfillActionReview(limit: Int? = nil) {
        runAnalyze(argument: limit.map(String.init) ?? "")
    }

    private func clearActionReviewOnSelection() {
        guard let id = editingNoteID else {
            statusMessage = "Press ↑ to pick a note first."
            draft = ""
            return
        }
        do {
            try store.clearActionReview(id: id)
            statusMessage = "Cleared action review."
        } catch {
            statusMessage = "Could not clear action review."
        }
        draft = ""
        clearEditing()
    }
    // MARK: - Reminders and export

    private func setReminder(from argument: String) {
        guard !argument.isEmpty else {
            statusMessage = "Usage: /remind tomorrow 9am (or every weekday 9am)"
            draft = ""
            return
        }

        let split = ReminderParser.splitArgument(argument)
        guard case .success(let schedule) = ReminderParser.parseSchedule(split.when) else {
            statusMessage = "Could not parse \(split.when)."
            draft = ""
            return
        }

        if let id = editingNoteID {
            applyReminderSchedule(to: id, schedule: schedule)
            draft = ""
            clearEditing()
            return
        }

        if let body = split.body, !body.isEmpty {
            do {
                guard let saved = try store.append(body), let id = saved.id else { return }
                applyReminderSchedule(to: id, schedule: schedule)
                draft = ""
                exportCapturedNote(saved)
            } catch {
                statusMessage = "Could not save that note."
                draft = ""
            }
            return
        }

        statusMessage = "Press ↑ to pick a note, or /remind tomorrow 9am buy milk"
        draft = ""
    }

    private func clearReminder() {
        guard let id = editingNoteID else {
            statusMessage = "Press ↑ to pick a note first."
            draft = ""
            return
        }
        do {
            try store.setRemindAt(id: id, date: nil)
            ReminderScheduler.cancel(noteID: id)
            refreshNotes()
            statusMessage = "Reminder cleared."
        } catch {
            statusMessage = "Could not clear the reminder."
        }
        draft = ""
        clearEditing()
    }

    private func applyReminderSchedule(to id: Int64, schedule: ReminderSchedule) {
        do {
            try store.setReminderSchedule(id: id, schedule: schedule)
            ReminderScheduler.cancel(noteID: id)
            refreshNotes()
            if let note = try store.fetchNote(id: id) {
                Task { await ReminderScheduler.schedule(note: note) }
            }
            switch schedule {
            case .once(let date):
                statusMessage = "Reminder set for \(ReminderParser.format(date))."
            case .recurring(let rule, _):
                statusMessage = "Reminder set for \(ReminderParser.describeRecurrence(rule))."
            }
        } catch {
            statusMessage = "Could not set that reminder."
        }
    }

    private func exportCapturedNote(_ note: Note) {
        do {
            try ObsidianExporter.export(note)
        } catch ObsidianExportError.disabled, ObsidianExportError.missingVault {
            return
        } catch {
            NSLog("Obsidian export failed: \(error)")
        }
    }

    private func beginEditing(_ note: Note) {
        guard let id = note.id else { return }
        editingNoteID = id
        draft = note.body
        scrollTargetID = id
        if note.isActionable {
            var message = note.actionSummary ?? "Actionable"
            if let detail = note.actionDetail, !detail.isEmpty {
                message += " — \(detail)"
            }
            statusMessage = message
        } else if note.isActionReviewed {
            statusMessage = "Reference note (not actionable)."
        }
    }

    private func clearEditing() {
        editingNoteID = nil
        draft = pendingDraft
        pendingDraft = ""
        scrollTargetID = nil
    }
}
