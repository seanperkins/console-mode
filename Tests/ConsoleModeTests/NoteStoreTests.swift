import Foundation
import GRDB
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

@Test func setReminderScheduleRoundTripsRecurrence() throws {
    let store = try NoteStore.inMemory()
    let note = try store.append("stretch")!
    let id = note.id!

    let rule = RecurrenceRule.weekdays(hour: 9, minute: 0)
    let firstFireDate = Date(timeIntervalSince1970: 1_700_042_400)
    try store.setReminderSchedule(id: id, schedule: .recurring(rule, firstFireDate: firstFireDate))

    let fetched = try store.fetchNote(id: id)!
    #expect(fetched.recurrenceRule == rule)
    #expect(fetched.remindAt == firstFireDate.timeIntervalSince1970)
}

@Test func setReminderScheduleOnceHasNoRecurrenceRule() throws {
    let store = try NoteStore.inMemory()
    let note = try store.append("one-shot")!
    let id = note.id!

    let date = Date(timeIntervalSince1970: 1_700_100_000)
    try store.setReminderSchedule(id: id, schedule: .once(date))

    let fetched = try store.fetchNote(id: id)!
    #expect(fetched.recurrenceRule == nil)
    #expect(fetched.remindAt == date.timeIntervalSince1970)
}

@Test func setRemindAtNilClearsRecurrenceRuleToo() throws {
    let store = try NoteStore.inMemory()
    let note = try store.append("daily standup")!
    let id = note.id!

    try store.setReminderSchedule(
        id: id,
        schedule: .recurring(.daily(hour: 9, minute: 0), firstFireDate: Date(timeIntervalSince1970: 1_700_042_400))
    )
    #expect(try store.fetchNote(id: id)?.recurrenceRule != nil)

    try store.setRemindAt(id: id, date: nil)

    let cleared = try store.fetchNote(id: id)!
    #expect(cleared.remindAt == nil)
    #expect(cleared.recurrenceRule == nil)
}

/// A recurring reminder stays "pending" for rescheduling even once its stored
/// `remind_at` hint has passed, since the recurrence itself never expires.
@Test func fetchPendingRemindersIncludesStaleRecurringNotes() throws {
    let store = try NoteStore.inMemory()
    let recurring = try store.append("water plants")!
    let staleOnce = try store.append("expired one-shot")!
    let freshOnce = try store.append("future one-shot")!

    let past = Date().addingTimeInterval(-3_600)
    let future = Date().addingTimeInterval(3_600)

    try store.setReminderSchedule(id: recurring.id!, schedule: .recurring(.daily(hour: 9, minute: 0), firstFireDate: past))
    try store.setReminderSchedule(id: staleOnce.id!, schedule: .once(past))
    try store.setReminderSchedule(id: freshOnce.id!, schedule: .once(future))

    let pending = try store.fetchPendingReminders().map(\.body)
    #expect(pending.contains("water plants"))
    #expect(pending.contains("future one-shot"))
    #expect(!pending.contains("expired one-shot"))
}

/// A note written before the `recurrence_rule` migration must still read back
/// cleanly — `recurrenceRule` decodes as nil rather than crashing.
@Test func noteWithoutRecurrenceColumnReadsBackAsNil() throws {
    let queue = try DatabaseQueue()

    // Replicates NoteStore's v1–v4 migrations exactly, stopping short of the
    // recurrence column so we can simulate a database created before it existed.
    var legacyMigrator = DatabaseMigrator()
    legacyMigrator.registerMigration("v1") { db in
        try db.create(table: "note") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("body", .text).notNull()
            table.column("created_at", .double).notNull()
            table.column("completed_at", .double)
        }
        try db.execute(sql: "CREATE INDEX note_created_at_idx ON note(created_at DESC)")
    }
    legacyMigrator.registerMigration("v2_project_tags") { db in
        try db.alter(table: "note") { table in
            table.add(column: "project", .text)
            table.add(column: "project_confidence", .double)
            table.add(column: "tagged_at", .double)
        }
        try db.execute(sql: "CREATE INDEX note_project_idx ON note(project)")
    }
    legacyMigrator.registerMigration("v3_reminders") { db in
        try db.alter(table: "note") { table in
            table.add(column: "remind_at", .double)
        }
        try db.execute(sql: "CREATE INDEX note_remind_at_idx ON note(remind_at)")
    }
    legacyMigrator.registerMigration("v4_action_review") { db in
        try db.alter(table: "note") { table in
            table.add(column: "actionable", .boolean)
            table.add(column: "action_summary", .text)
            table.add(column: "action_detail", .text)
            table.add(column: "action_reviewed_at", .double)
        }
        try db.execute(sql: "CREATE INDEX note_actionable_idx ON note(actionable)")
    }
    try legacyMigrator.migrate(queue)

    try queue.write { db in
        try db.execute(
            sql: "INSERT INTO note (body, created_at) VALUES (?, ?)",
            arguments: ["pre-migration note", 1_700_000_000.0]
        )
    }

    // NoteStore's own migrator only needs to add "v5_recurring_reminders" —
    // v1–v4 are already recorded as applied under the same migration names.
    let store = try NoteStore(dbQueue: queue)
    let notes = try store.fetchRecent(limit: 10)
    #expect(notes.count == 1)
    #expect(notes.first?.body == "pre-migration note")
    #expect(notes.first?.recurrenceRule == nil)
}


