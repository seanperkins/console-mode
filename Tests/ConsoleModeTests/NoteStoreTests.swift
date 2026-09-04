import Foundation
import Testing
@testable import ConsoleModeKit

@Test func appendTrimsWhitespace() throws {
    let store = try NoteStore.inMemory()
    let note = try store.append("  hello  ")
    #expect(note?.body == "hello")
}

@Test func appendRejectsEmpty() throws {
    let store = try NoteStore.inMemory()
    #expect(try store.append("") == nil)
    #expect(try store.append("   \n\t  ") == nil)
}

@Test func fetchOrdersNewestFirst() throws {
    let store = try NoteStore.inMemory()
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    _ = try store.append("first", at: base)
    _ = try store.append("second", at: base.addingTimeInterval(60))
    _ = try store.append("third", at: base.addingTimeInterval(120))

    let notes = try store.fetchRecent(limit: 10)
    #expect(notes.map(\.body) == ["third", "second", "first"])
}

@Test func completionRoundTrip() throws {
    let store = try NoteStore.inMemory()
    let note = try store.append("task")!
    let id = note.id!

    try store.setCompleted(id: id, completed: true, at: Date(timeIntervalSince1970: 1_700_000_100))
    var fetched = try store.fetchRecent(limit: 1).first!
    #expect(fetched.isCompleted)
    #expect(fetched.completedAt == 1_700_000_100)

    try store.setCompleted(id: id, completed: false)
    fetched = try store.fetchRecent(limit: 1).first!
    #expect(!fetched.isCompleted)
    #expect(fetched.completedAt == nil)
}


@Test func updateBodyTrimsWhitespace() throws {
    let store = try NoteStore.inMemory()
    let note = try store.append("original")!
    let id = note.id!

    let updated = try store.updateBody(id: id, rawBody: "  revised  ")
    #expect(updated?.body == "revised")

    let fetched = try store.fetchRecent(limit: 1).first!
    #expect(fetched.body == "revised")
}

@Test func updateBodyRejectsEmpty() throws {
    let store = try NoteStore.inMemory()
    let note = try store.append("keep me")!
    let id = note.id!
    #expect(try store.updateBody(id: id, rawBody: "") == nil)
    #expect(try store.updateBody(id: id, rawBody: "   ") == nil)

    let fetched = try store.fetchRecent(limit: 1).first!
    #expect(fetched.body == "keep me")
}

@Test func setProjectMarksNoteTagged() throws {
    let store = try NoteStore.inMemory()
    let note = try store.append("wire up the tagger")!
    let id = note.id!

    #expect(try store.fetchNote(id: id)?.isTagged == false)

    try store.setProject(id: id, project: "console-mode", confidence: 0.95)

    let tagged = try store.fetchNote(id: id)!
    #expect(tagged.project == "console-mode")
    #expect(tagged.projectConfidence == 0.95)
    #expect(tagged.isTagged)
}

/// A declined label still counts as tagged, so backfill does not retry forever.
@Test func declinedTagStillMarksAttempt() throws {
    let store = try NoteStore.inMemory()
    let note = try store.append("My freee bird yeah")!
    let id = note.id!

    try store.setProject(id: id, project: nil, confidence: 0.1)

    let tagged = try store.fetchNote(id: id)!
    #expect(tagged.project == nil)
    #expect(tagged.isTagged)
    #expect(try store.fetchUntagged(limit: 10).isEmpty)
}

@Test func fetchUntaggedIsOldestFirst() throws {
    let store = try NoteStore.inMemory()
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    _ = try store.append("newest", at: base.addingTimeInterval(120))
    let oldest = try store.append("oldest", at: base)!
    _ = try store.append("middle", at: base.addingTimeInterval(60))

    #expect(try store.fetchUntagged(limit: 10).map(\.body) == ["oldest", "middle", "newest"])

    try store.setProject(id: oldest.id!, project: "x", confidence: 0.9)
    #expect(try store.fetchUntagged(limit: 10).map(\.body) == ["middle", "newest"])
}

@Test func knownProjectsRanksByUsage() throws {
    let store = try NoteStore.inMemory()
    let a = try store.append("one")!
    let b = try store.append("two")!
    let c = try store.append("three")!
    let d = try store.append("four")!

    try store.setProject(id: a.id!, project: "rare-thing", confidence: 0.9)
    try store.setProject(id: b.id!, project: "console-mode", confidence: 0.9)
    try store.setProject(id: c.id!, project: "console-mode", confidence: 0.9)
    try store.setProject(id: d.id!, project: nil, confidence: 0.1)

    // Most-used first, and unlabelled notes contribute nothing.
    #expect(try store.knownProjects() == ["console-mode", "rare-thing"])
}

@Test func deleteAllRemovesEveryNote() throws {
    let store = try NoteStore.inMemory()
    _ = try store.append("one")
    _ = try store.append("two")
    _ = try store.append("three")
    #expect(try store.count() == 3)

    #expect(try store.deleteAll() == 3)

    #expect(try store.count() == 0)
    #expect(try store.fetchRecent(limit: 10).isEmpty)
}

@Test func deleteAllOnEmptyStoreIsHarmless() throws {
    let store = try NoteStore.inMemory()
    #expect(try store.deleteAll() == 0)
    #expect(try store.count() == 0)
}
@Test func fetchFilteredFindsSubstring() throws {
    let store = try NoteStore.inMemory()
    _ = try store.append("buy oat milk")
    _ = try store.append("fix the API")
    _ = try store.append("ship Oat Milk recipe")

    let hits = try store.fetchFiltered(.text("oat"), limit: 10)
    #expect(hits.map(\.body).sorted() == ["buy oat milk", "ship Oat Milk recipe"].sorted())
}

@Test func fetchFilteredMatchesLiteralPercentAndUnderscore() throws {
    let store = try NoteStore.inMemory()
    _ = try store.append("discount is 100% off")
    _ = try store.append("foo_bar is not a wildcard")
    _ = try store.append("totally unrelated")

    let percentHits = try store.fetchFiltered(.text("100%"), limit: 10)
    #expect(percentHits.map(\.body) == ["discount is 100% off"])

    let underscoreHits = try store.fetchFiltered(.text("foo_bar"), limit: 10)
    #expect(underscoreHits.map(\.body) == ["foo_bar is not a wildcard"])
}

@Test func fetchFilteredByProject() throws {
    let store = try NoteStore.inMemory()
    let a = try store.append("one")!
    let b = try store.append("two")!
    try store.setProject(id: a.id!, project: "console-mode", confidence: 1)
    try store.setProject(id: b.id!, project: "other", confidence: 1)

    let hits = try store.fetchFiltered(.project("console-mode"), limit: 10)
    #expect(hits.map(\.body) == ["one"])
}

@Test func fetchFilteredIncomplete() throws {
    let store = try NoteStore.inMemory()
    let open = try store.append("still open")!
    let done = try store.append("finished")!
    try store.setCompleted(id: done.id!, completed: true)

    let hits = try store.fetchFiltered(.incomplete, limit: 10)
    #expect(hits.map(\.body) == ["still open"])
}

@Test func reviewQueueIsOldestIncompleteFirst() throws {
    let store = try NoteStore.inMemory()
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    _ = try store.append("newest", at: base.addingTimeInterval(120))
    _ = try store.append("oldest", at: base)
    let done = try store.append("done", at: base.addingTimeInterval(60))!
    try store.setCompleted(id: done.id!, completed: true)

    #expect(try store.fetchReviewQueue(limit: 10).map(\.body) == ["oldest", "newest"])
}


