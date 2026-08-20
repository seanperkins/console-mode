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

    func fetchRecent(limit: Int) throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .order(Self.newestFirst)
                .limit(limit)
                .fetchAll(db)
        }
    }

    @MainActor
    func observeRecent(limit: Int, onChange: @escaping @Sendable ([Note]) -> Void) -> AnyDatabaseCancellable {
        let observation = ValueObservation.tracking { db in
            try Note
                .order(Self.newestFirst)
                .limit(limit)
                .fetchAll(db)
        }

        return observation.start(
            in: dbQueue,
            onError: { error in
                NSLog("NoteStore observation failed: \(error)")
            },
            onChange: onChange
        )
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
        return migrator
    }
}
