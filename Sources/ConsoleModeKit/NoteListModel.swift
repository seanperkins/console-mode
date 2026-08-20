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
    var tagStatus: String?
    /// Transient feedback shown as the input placeholder; cleared on the next keystroke.
    var statusMessage: String?
    /// Set by AppDelegate for commands the model cannot perform itself.
    var onAction: ((ConsoleAction) -> Void)?

    private let store: NoteStore
    private var observation: AnyDatabaseCancellable?

    init(store: NoteStore) {
        self.store = store
        restartObservation()
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

    var isEditingExistingNote: Bool {
        editingNoteID != nil
    }

    func restartObservation() {
        observation?.cancel()
        let limit = expanded ? 200 : 1
        observation = store.observeRecent(limit: limit) { [weak self] notes in
            Task { @MainActor in
                self?.notes = notes
            }
        }
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
            statusMessage = isEditingNoteCompleted ? "Marked done." : "Marked not done."
            draft = ""
            clearEditing()

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
                let total = try store.fetchRecent(limit: 200).count
                if total > 1 {
                    expanded = true
                    restartObservation()
                }
            }

            let list = try store.fetchRecent(limit: 200)
            guard !list.isEmpty else { return }

            if let editingNoteID, let index = list.firstIndex(where: { $0.id == editingNoteID }) {
                let nextIndex = index + 1
                guard nextIndex < list.count else { return }
                beginEditing(list[nextIndex])
            } else {
                // Stash the unsaved line so walking back down restores it, like shell history.
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
            let list = try store.fetchRecent(limit: 200)
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
            try store.setCompleted(id: id, completed: !note.isCompleted)
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

    private func beginEditing(_ note: Note) {
        guard let id = note.id else { return }
        editingNoteID = id
        draft = note.body
        scrollTargetID = id
    }

    private func clearEditing() {
        editingNoteID = nil
        draft = pendingDraft
        pendingDraft = ""
        scrollTargetID = nil
    }
}
