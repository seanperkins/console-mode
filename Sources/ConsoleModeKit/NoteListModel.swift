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
        do {
            if let editingNoteID {
                if try store.updateBody(id: editingNoteID, rawBody: draft) != nil {
                    clearEditing()
                }
            } else if try store.append(draft) != nil {
                draft = ""
                pendingDraft = ""
            }
        } catch {
            NSLog("Failed to save note: \(error)")
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
