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