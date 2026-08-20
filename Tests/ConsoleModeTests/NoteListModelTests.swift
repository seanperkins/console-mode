import Foundation
import Testing
@testable import ConsoleModeKit

@MainActor
struct NoteListModelTests {
    @Test func upArrowLoadsNewestNoteIntoDraft() throws {
        let store = try NoteStore.inMemory()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try store.append("newest", at: base.addingTimeInterval(120))
        _ = try store.append("older", at: base)

        let model = NoteListModel(store: store)
        #expect(model.draft.isEmpty)
        #expect(model.editingNoteID == nil)

        model.navigateToOlderNote()

        #expect(model.draft == "newest")
        #expect(model.editingNoteID != nil)
    }

    @Test func upArrowWalksToOlderNotes() throws {
        let store = try NoteStore.inMemory()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try store.append("newest", at: base.addingTimeInterval(120))
        _ = try store.append("middle", at: base.addingTimeInterval(60))
        _ = try store.append("oldest", at: base)

        let model = NoteListModel(store: store)
        model.navigateToOlderNote()
        #expect(model.draft == "newest")

        model.navigateToOlderNote()
        #expect(model.draft == "middle")

        model.navigateToOlderNote()
        #expect(model.draft == "oldest")
    }

    @Test func downArrowReturnsToBlankDraft() throws {
        let store = try NoteStore.inMemory()
        _ = try store.append("only note")

        let model = NoteListModel(store: store)
        model.navigateToOlderNote()
        #expect(model.draft == "only note")

        model.navigateToNewerNote()
        #expect(model.draft.isEmpty)
        #expect(model.editingNoteID == nil)
    }

    @Test func arrowKeysPreserveUnsavedDraft() throws {
        let store = try NoteStore.inMemory()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try store.append("newest", at: base.addingTimeInterval(60))
        _ = try store.append("older", at: base)

        let model = NoteListModel(store: store)
        model.draft = "half-typed thought"

        model.navigateToOlderNote()
        #expect(model.draft == "newest")

        model.navigateToOlderNote()
        #expect(model.draft == "older")

        model.navigateToNewerNote()
        #expect(model.draft == "newest")

        // Walking back past the newest note restores the unsaved line.
        model.navigateToNewerNote()
        #expect(model.draft == "half-typed thought")
        #expect(model.editingNoteID == nil)
    }

    @Test func commitDraftUpdatesExistingNote() throws {
        let store = try NoteStore.inMemory()
        let note = try store.append("before")!
        let id = note.id!

        let model = NoteListModel(store: store)
        model.navigateToOlderNote()
        model.draft = "after"
        model.commitDraft()

        #expect(model.draft.isEmpty)
        #expect(model.editingNoteID == nil)

        let fetched = try store.fetchRecent(limit: 1).first!
        #expect(fetched.id == id)
        #expect(fetched.body == "after")
    }
}
