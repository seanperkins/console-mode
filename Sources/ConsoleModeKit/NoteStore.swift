import Foundation
import GRDB

final class NoteStore: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    static func defaultDatabaseURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ConsoleMode/notes.sqlite", isDirectory: false)
    }

    static func openDefault() throws -> NoteStore {
        let url = defaultDatabaseURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }

        let queue = try DatabaseQueue(path: url.path, configuration: config)
        return try NoteStore(dbQueue: queue)
    }

    static func inMemory() throws -> NoteStore {
        let queue = try DatabaseQueue()
        return try NoteStore(dbQueue: queue)
    }

    @discardableResult
    func append(_ rawBody: String, at date: Date = Date()) throws -> Note? {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        return try dbQueue.write { db in
            var note = Note(id: nil, body: body, createdAt: date.timeIntervalSince1970, completedAt: nil)
            try note.insert(db)
            note.id = db.lastInsertedRowID
            return note
        }
    }

    @discardableResult
    func updateBody(id: Int64, rawBody: String) throws -> Note? {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE note SET body = ? WHERE id = ?",
                arguments: [body, id]
            )
        }

        return try dbQueue.read { db in
            try Note.fetchOne(db, key: id)
        }
    }

    func setCompleted(id: Int64, completed: Bool, at date: Date = Date()) throws {
        let completedAt: TimeInterval? = completed ? date.timeIntervalSince1970 : nil
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE note SET completed_at = ? WHERE id = ?",
                arguments: [completedAt, id]
            )
        }
    }

    func fetchNote(id: Int64) throws -> Note? {
        try dbQueue.read { db in
            try Note.fetchOne(db, key: id)
        }
    }

    func delete(id: Int64) throws {
        try dbQueue.write { db in
            _ = try Note.deleteOne(db, key: id)
        }
    }

    /// Wipe every note. Irreversible — callers must confirm first.
    @discardableResult
    func deleteAll() throws -> Int {
        try dbQueue.write { db in
            try Note.deleteAll(db)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in
            try Note.fetchCount(db)
        }
    }

    /// Every note, oldest first — full export (Markdown/JSON backup), not
    /// display. Unbounded on purpose: an export that silently truncates at
    /// some limit would be a corrupted backup, not a smaller one.
    func fetchAllForExport() throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .order(Column("created_at").asc, Column("id").asc)
                .fetchAll(db)
        }
    }

    /// Record the tagger's verdict. `project` nil means "ran, no label" — `tagged_at`
    /// still gets set so the note is not retried on every launch.
    func setProject(id: Int64, project: String?, confidence: Double?, at date: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE note SET project = ?, project_confidence = ?, tagged_at = ? WHERE id = ?",
                arguments: [project, confidence, date.timeIntervalSince1970, id]
            )
        }
    }

    /// Oldest-first so a backfill works through history in a predictable order.
    func fetchUntagged(limit: Int) throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .filter(Column("tagged_at") == nil)
                .order(Column("created_at").asc, Column("id").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Existing vocabulary, most-used first, so the tagger reuses labels instead of
    /// inventing near-duplicates.
    func knownProjects(limit: Int = 40) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT project FROM note
                WHERE project IS NOT NULL AND project <> ''
                GROUP BY project
                ORDER BY COUNT(*) DESC, MAX(created_at) DESC
                LIMIT ?
                """,
                arguments: [limit]
            )
        }
    }

    /// Newest first, with `id` breaking exact `created_at` ties so the display list
    /// and the arrow-key navigation list can never disagree.
    private static let newestFirst = [Column("created_at").desc, Column("id").desc]

    private static let textLikeEscape = "\\"

    /// Wraps a literal substring for `LIKE … ESCAPE '\'` so `%` and `_` in the query match themselves.
    private static func textLikePattern(for query: String) -> String {
        let escaped = query
            .replacingOccurrences(of: textLikeEscape, with: textLikeEscape + textLikeEscape)
            .replacingOccurrences(of: "%", with: textLikeEscape + "%")
            .replacingOccurrences(of: "_", with: textLikeEscape + "_")
        return "%\(escaped)%"
    }

    private static func filteredRequest(_ filter: NoteFilter) -> QueryInterfaceRequest<Note> {
        var request = Note.all()
        switch filter {
        case .all:
            break
        case .text(let query):
            request = request.filter(
                sql: "body LIKE ? ESCAPE '\(textLikeEscape)'",
                arguments: [textLikePattern(for: query)]
            )
        case .project(let slug):
            request = request.filter(Column("project") == slug)
        case .incomplete:
            request = request.filter(Column("completed_at") == nil)
        case .actionable:
            request = request
                .filter(Column("actionable") == true)
                .filter(Column("completed_at") == nil)
        }
        return request.order(Self.newestFirst)
    }

    func fetchRecent(limit: Int) throws -> [Note] {
        try fetchFiltered(.all, limit: limit)
    }

    func fetchFiltered(_ filter: NoteFilter, limit: Int) throws -> [Note] {
        try dbQueue.read { db in
            try Self.filteredRequest(filter).limit(limit).fetchAll(db)
        }
    }

    /// Oldest incomplete notes first — the review queue walks backlog in order.
    func fetchReviewQueue(limit: Int) throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .filter(Column("completed_at") == nil)
                .order(Column("created_at").asc, Column("id").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    @MainActor
    func observeRecent(limit: Int, onChange: @escaping @Sendable ([Note]) -> Void) -> AnyDatabaseCancellable {
        observeFiltered(.all, limit: limit, onChange: onChange)
    }

    @MainActor
    func observeFiltered(
        _ filter: NoteFilter,
        limit: Int,
        onChange: @escaping @Sendable ([Note]) -> Void
    ) -> AnyDatabaseCancellable {
        let observation = ValueObservation.tracking { db in
            try Self.filteredRequest(filter).limit(limit).fetchAll(db)
        }

        return observation.start(
            in: dbQueue,
            onError: { error in
                NSLog("NoteStore observation failed: \(error)")
            },
            onChange: onChange
        )
    }

    func setRemindAt(id: Int64, date: Date?) throws {
        try dbQueue.write { db in
            if let date {
                try db.execute(
                    sql: "UPDATE note SET remind_at = ? WHERE id = ?",
                    arguments: [date.timeIntervalSince1970, id]
                )
            } else {
                // Clearing the reminder also clears any recurrence — there is no
                // such thing as a recurring reminder with no next fire date.
                try db.execute(
                    sql: "UPDATE note SET remind_at = NULL, recurrence_rule = NULL WHERE id = ?",
                    arguments: [id]
                )
            }
        }
    }

    /// Persists a one-shot or recurring reminder schedule: `remind_at` always
    /// holds the next fire date; `recurrence_rule` is set only for recurring
    /// schedules and drives `ReminderScheduler`'s recurring notification triggers.
    func setReminderSchedule(id: Int64, schedule: ReminderSchedule) throws {
        let remindAt: TimeInterval
        let ruleJSON: String?
        switch schedule {
        case .once(let date):
            remindAt = date.timeIntervalSince1970
            ruleJSON = nil
        case .recurring(let rule, let firstFireDate):
            remindAt = firstFireDate.timeIntervalSince1970
            ruleJSON = String(decoding: try JSONEncoder().encode(rule), as: UTF8.self)
        }
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE note SET remind_at = ?, recurrence_rule = ? WHERE id = ?",
                arguments: [remindAt, ruleJSON, id]
            )
        }
    }

    /// Notes with a future or recurring reminder, soonest first. A recurring
    /// reminder is always "pending" even once its stored `remind_at` hint has
    /// passed — `ReminderScheduler` recomputes the next fire date from the rule.
    func fetchPendingReminders(limit: Int = 500) throws -> [Note] {
        let now = Date().timeIntervalSince1970
        return try dbQueue.read { db in
            try Note
                .filter(Column("remind_at") != nil)
                .filter(sql: "(remind_at > ? OR recurrence_rule IS NOT NULL)", arguments: [now])
                .filter(Column("completed_at") == nil)
                .order(Column("remind_at").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func setActionReview(
        id: Int64,
        actionable: Bool,
        summary: String?,
        detail: String?,
        at date: Date = Date()
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE note
                SET actionable = ?, action_summary = ?, action_detail = ?, action_reviewed_at = ?
                WHERE id = ?
                """,
                arguments: [actionable, summary, detail, date.timeIntervalSince1970, id]
            )
        }
    }

    func clearActionReview(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE note
                SET actionable = NULL, action_summary = NULL, action_detail = NULL, action_reviewed_at = NULL
                WHERE id = ?
                """,
                arguments: [id]
            )
        }
    }

    /// Incomplete notes the model has not classified yet, oldest first.
    func fetchUnreviewed(limit: Int) throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .filter(Column("completed_at") == nil)
                .filter(Column("action_reviewed_at") == nil)
                .order(Column("created_at").asc, Column("id").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func unreviewedCount() throws -> Int {
        try dbQueue.read { db in
            try Note
                .filter(Column("completed_at") == nil)
                .filter(Column("action_reviewed_at") == nil)
                .fetchCount(db)
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "note") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("body", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("completed_at", .double)
            }
            try db.execute(sql: "CREATE INDEX note_created_at_idx ON note(created_at DESC)")
        }
        migrator.registerMigration("v2_project_tags") { db in
            // `project` is the label; `tagged_at` records that the tagger ran at all,
            // so a note it declined to label is not retried forever.
            try db.alter(table: "note") { table in
                table.add(column: "project", .text)
                table.add(column: "project_confidence", .double)
                table.add(column: "tagged_at", .double)
            }
            try db.execute(sql: "CREATE INDEX note_project_idx ON note(project)")
        }
        migrator.registerMigration("v3_reminders") { db in
            try db.alter(table: "note") { table in
                table.add(column: "remind_at", .double)
            }
            try db.execute(sql: "CREATE INDEX note_remind_at_idx ON note(remind_at)")
        }
        migrator.registerMigration("v4_action_review") { db in
            try db.alter(table: "note") { table in
                table.add(column: "actionable", .boolean)
                table.add(column: "action_summary", .text)
                table.add(column: "action_detail", .text)
                table.add(column: "action_reviewed_at", .double)
            }
            try db.execute(sql: "CREATE INDEX note_actionable_idx ON note(actionable)")
        }
        migrator.registerMigration("v5_recurring_reminders") { db in
            try db.alter(table: "note") { table in
                table.add(column: "recurrence_rule", .text)
            }
        }
        return migrator
    }
}
