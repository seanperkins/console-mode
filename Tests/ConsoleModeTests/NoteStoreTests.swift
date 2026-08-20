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
