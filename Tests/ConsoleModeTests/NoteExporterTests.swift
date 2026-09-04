import Foundation
import Testing
@testable import ConsoleModeKit

@Test func renderThrowsOnEmptyNotes() {
    #expect(throws: NoteExportError.self) {
        try NoteExporter.render([], as: .markdown)
    }
}

@Test func markdownOrdersOldestFirstAndIncludesProjectAndCompletion() {
    let notes = [
        Note(id: 2, body: "second", createdAt: 200, completedAt: nil, project: nil),
        Note(id: 1, body: "first", createdAt: 100, completedAt: 150, project: "kitchen"),
    ]
    let text = NoteExporter.markdown(notes)
    let firstIndex = try! #require(text.range(of: "- [x] first"))
    let secondIndex = try! #require(text.range(of: "- [ ] second"))
    #expect(firstIndex.lowerBound < secondIndex.lowerBound)
    #expect(text.contains("#kitchen"))
    #expect(text.contains("2 notes"))
}

@Test func jsonRoundTripsEveryField() throws {
    let notes = [
        Note(
            id: 1,
            body: "buy milk",
            createdAt: 100,
            completedAt: nil,
            project: "errands",
            projectConfidence: 0.9,
            taggedAt: 120,
            remindAt: 500,
            actionable: true,
            actionSummary: "Buy milk",
            actionDetail: "2% at the corner store",
            actionReviewedAt: 130
        )
    ]
    let data = try NoteExporter.render(notes, as: .json)
    let decoded = try JSONDecoder().decode([Note].self, from: data)
    #expect(decoded == notes)
}

@Test func jsonKeysUseDatabaseColumnNaming() throws {
    let notes = [Note(id: 1, body: "x", createdAt: 100, completedAt: nil)]
    let data = try NoteExporter.render(notes, as: .json)
    let text = String(decoding: data, as: UTF8.self)
    // Re-importability depends on matching `Note.CodingKeys`, not Swift's
    // camelCase property names.
    #expect(text.contains("\"created_at\""))
    #expect(!text.contains("\"createdAt\""))
}

@Test func writeToDiskRoundTripsThroughMarkdown() throws {
    let notes = [Note(id: 1, body: "hello", createdAt: 100, completedAt: nil)]
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).md")
    defer { try? FileManager.default.removeItem(at: url) }

    try NoteExporter.write(notes, as: .markdown, to: url)
    let written = try String(contentsOf: url, encoding: .utf8)
    #expect(written.contains("hello"))
}

@Test func exportFormatFileExtensionsMatchTheirFormat() {
    #expect(NoteExportFormat.markdown.fileExtension == "md")
    #expect(NoteExportFormat.json.fileExtension == "json")
}

@Test func fetchAllForExportReturnsEveryNoteOldestFirst() throws {
    let store = try NoteStore.inMemory()
    _ = try store.append("first", at: Date(timeIntervalSince1970: 100))
    _ = try store.append("second", at: Date(timeIntervalSince1970: 200))
    let notes = try store.fetchAllForExport()
    #expect(notes.map(\.body) == ["first", "second"])
}
