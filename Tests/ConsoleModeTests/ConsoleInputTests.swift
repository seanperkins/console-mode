import Foundation
import Testing
@testable import ConsoleModeKit

// MARK: - Parsing

@Test func plainTextIsANote() {
    #expect(ConsoleInput.parse("buy oat milk") == .note(body: "buy oat milk", tags: []))
}

@Test func blankInputIsEmpty() {
    #expect(ConsoleInput.parse("") == .empty)
    #expect(ConsoleInput.parse("   \n\t ") == .empty)
}

@Test func hashTagsAreLiftedOutOfTheBody() {
    #expect(
        ConsoleInput.parse("fix the panel #console-mode")
            == .note(body: "fix the panel", tags: ["console-mode"])
    )
    #expect(
        ConsoleInput.parse("#console-mode fix the panel")
            == .note(body: "fix the panel", tags: ["console-mode"])
    )
    #expect(
        ConsoleInput.parse("scrape #event-calendar listings")
            == .note(body: "scrape listings", tags: ["event-calendar"])
    )
}

@Test func tagsAreNormalizedAndDeduplicated() {
    #expect(
        ConsoleInput.parse("note #Console_Mode #console-mode")
            == .note(body: "note", tags: ["console-mode"])
    )
}

@Test func multipleDistinctTagsArePreservedInOrder() {
    let parsed = ConsoleInput.parse("cross cutting #alpha #beta")
    #expect(parsed == .note(body: "cross cutting", tags: ["alpha", "beta"]))
}

/// A bare `#` or an unusable tag stays in the prose rather than vanishing.
@Test func unusableHashTokensStayInTheBody() {
    #expect(ConsoleInput.parse("issue # 42") == .note(body: "issue # 42", tags: []))
    #expect(ConsoleInput.parse("call it #---") == .note(body: "call it #---", tags: []))
}

/// `#` mid-word is not a tag, so URL fragments and CSS colours survive.
@Test func hashInsideAWordIsNotATag() {
    #expect(
        ConsoleInput.parse("read docs#install later")
            == .note(body: "read docs#install later", tags: [])
    )
    #expect(ConsoleInput.parse("use color ##fff") == .note(body: "use color ##fff", tags: []))
}

@Test func slashPrefixParsesCommands() {
    #expect(ConsoleInput.parse("/help") == .command(.help, argument: ""))
    #expect(ConsoleInput.parse("/tag console-mode") == .command(.tag, argument: "console-mode"))
    #expect(ConsoleInput.parse("  /expand  ") == .command(.expand, argument: ""))
}

@Test func commandNamesAreCaseInsensitiveAndAliased() {
    #expect(ConsoleInput.parse("/HELP") == .command(.help, argument: ""))
    #expect(ConsoleInput.parse("/?") == .command(.help, argument: ""))
    #expect(ConsoleInput.parse("/rm") == .command(.delete, argument: ""))
    #expect(ConsoleInput.parse("/q") == .command(.quit, argument: ""))
}

@Test func unknownCommandIsReportedNotSaved() {
    #expect(ConsoleInput.parse("/nope") == .unknownCommand("nope"))
    #expect(ConsoleInput.parse("/frobnicate now") == .unknownCommand("frobnicate"))
}

/// A slash mid-sentence is ordinary text, so dates and paths are safe.
@Test func slashInsideTextIsNotACommand() {
    #expect(ConsoleInput.parse("ship 9/12") == .note(body: "ship 9/12", tags: []))
    #expect(ConsoleInput.parse("see ~/sites/foo") == .note(body: "see ~/sites/foo", tags: []))
}

// MARK: - Command routing

@MainActor
struct ConsoleCommandTests {
    @Test func hashTagOnCaptureSetsProjectImmediately() throws {
        let store = try NoteStore.inMemory()
        let model = NoteListModel(store: store)

        model.draft = "fix the panel #console-mode"
        model.commitDraft()

        let saved = try store.fetchRecent(limit: 1).first!
        #expect(saved.body == "fix the panel")
        #expect(saved.project == "console-mode")
        // Marked tagged so the background tagger leaves the manual label alone.
        #expect(saved.isTagged)
        #expect(model.draft.isEmpty)
    }

    @Test func tagCommandLabelsTheSelectedNote() throws {
        let store = try NoteStore.inMemory()
        let note = try store.append("some work")!
        let model = NoteListModel(store: store)

        model.navigateToOlderNote()
        model.draft = "/tag Event_Calendar"
        model.commitDraft()

        #expect(try store.fetchNote(id: note.id!)?.project == "event-calendar")
        #expect(model.draft.isEmpty)
        #expect(model.editingNoteID == nil)
    }

    @Test func untagCommandClearsTheProject() throws {
        let store = try NoteStore.inMemory()
        let note = try store.append("tagged work")!
        try store.setProject(id: note.id!, project: "console-mode", confidence: 1)
        let model = NoteListModel(store: store)

        model.navigateToOlderNote()
        model.draft = "/untag"
        model.commitDraft()

        #expect(try store.fetchNote(id: note.id!)?.project == nil)
    }

    @Test func deleteCommandRemovesTheSelectedNote() throws {
        let store = try NoteStore.inMemory()
        let note = try store.append("throwaway")!
        let model = NoteListModel(store: store)

        model.navigateToOlderNote()
        model.draft = "/delete"
        model.commitDraft()

        #expect(try store.fetchNote(id: note.id!) == nil)
    }

    @Test func doneCommandTogglesCompletion() throws {
        let store = try NoteStore.inMemory()
        let note = try store.append("finish this")!
        let model = NoteListModel(store: store)

        model.navigateToOlderNote()
        model.draft = "/done"
        model.commitDraft()

        #expect(try store.fetchNote(id: note.id!)?.isCompleted == true)
    }

    @Test func expandAndCollapseCommandsDriveTheList() throws {
        let store = try NoteStore.inMemory()
        let model = NoteListModel(store: store)
        #expect(!model.expanded)

        model.draft = "/expand"
        model.commitDraft()
        #expect(model.expanded)

        // Repeating it is a no-op rather than a toggle.
        model.draft = "/expand"
        model.commitDraft()
        #expect(model.expanded)

        model.draft = "/collapse"
        model.commitDraft()
        #expect(!model.expanded)
    }

    @Test func commandsNeedingASelectionExplainThemselves() throws {
        let store = try NoteStore.inMemory()
        _ = try store.append("untouched")
        let model = NoteListModel(store: store)

        model.draft = "/delete"
        model.commitDraft()

        #expect(model.statusMessage != nil)
        #expect(try store.fetchRecent(limit: 1).first?.body == "untouched")
    }

    @Test func unknownCommandDoesNotCreateANote() throws {
        let store = try NoteStore.inMemory()
        let model = NoteListModel(store: store)

        model.draft = "/frobnicate"
        model.commitDraft()

        #expect(try store.fetchRecent(limit: 10).isEmpty)
        #expect(model.statusMessage?.contains("/frobnicate") == true)
    }

    @Test func quitCommandRaisesAnAction() {
        let model = NoteListModel(store: try! NoteStore.inMemory())
        var received: [ConsoleAction] = []
        model.onAction = { received.append($0) }

        model.draft = "/quit"
        model.commitDraft()
        #expect(received == [.quit])

        model.draft = "/settings"
        model.commitDraft()
        #expect(received == [.quit, .openSettings])
    }

    @Test func clearCommandEmptiesDraftAndSelection() throws {
        let store = try NoteStore.inMemory()
        _ = try store.append("keep me")
        let model = NoteListModel(store: store)

        model.navigateToOlderNote()
        #expect(model.editingNoteID != nil)

        model.draft = "/clear"
        model.commitDraft()

        #expect(model.draft.isEmpty)
        #expect(model.editingNoteID == nil)
        #expect(try store.fetchRecent(limit: 1).first?.body == "keep me")
    }
}
