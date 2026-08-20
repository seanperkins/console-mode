import Foundation
import GRDB
import Observation

@Observable
@MainActor
final class NoteListModel {
    var draft = ""
    var expanded = false
    private(set) var notes: [Note] = []

    private let store: NoteStore
    private var observation: AnyDatabaseCancellable?

    init(store: NoteStore) {
        self.store = store
        restartObservation()
    }

    var visibleRowCount: Int {
        max(notes.count, 1)
    }
    var focusToken = 0

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
            if try store.append(draft) != nil {
                draft = ""
            }
        } catch {
            NSLog("Failed to append note: \(error)")
        }
    }

    func requestInputFocus() {
        focusToken += 1
    }

    func toggleCompletion(for note: Note) {
        guard let id = note.id else { return }
        do {
            try store.setCompleted(id: id, completed: !note.isCompleted)
        } catch {
            NSLog("Failed to toggle completion: \(error)")
        }
    }
}
