import Foundation

enum NoteExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case json

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        }
    }
}

enum NoteExportError: Error, Equatable {
    case empty
    case writeFailed(String)
}

/// Renders every note to a single portable file — the one-time-migration /
/// backup path this app otherwise has none of (SQLite-only, single machine).
/// Unlike `ObsidianExporter`, which appends one note at a time to a vault's
/// daily note as it's captured, this reads the whole store at once and
/// writes exactly one file.
enum NoteExporter {
    static func render(_ notes: [Note], as format: NoteExportFormat) throws -> Data {
        guard !notes.isEmpty else { throw NoteExportError.empty }
        switch format {
        case .markdown:
            return Data(markdown(notes).utf8)
        case .json:
            return try json(notes)
        }
    }

    static func write(_ notes: [Note], as format: NoteExportFormat, to url: URL) throws {
        let data = try render(notes, as: format)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw NoteExportError.writeFailed(error.localizedDescription)
        }
    }

    /// Oldest-first, one line per note, so the file reads top-to-bottom like
    /// a journal rather than newest-first like the live capture panel.
    static func markdown(_ notes: [Note]) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var lines = ["# Console Mode notes", "", "Exported \(stamp) · \(notes.count) note\(notes.count == 1 ? "" : "s")", ""]

        let clock = DateFormatter()
        clock.dateFormat = "yyyy-MM-dd HH:mm"

        for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
            let checkbox = note.isCompleted ? "- [x]" : "- [ ]"
            var meta = [clock.string(from: note.createdDate)]
            if let project = note.project, !project.isEmpty { meta.append("#\(project)") }
            lines.append("\(checkbox) \(note.body)  _(\(meta.joined(separator: " · ")))_")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Every field `Note` carries, keyed exactly as its `CodingKeys` name
    /// them (`created_at`, `action_summary`, ...) — a re-importable dump,
    /// not a display format.
    static func json(_ notes: [Note]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(notes.sorted { $0.createdAt < $1.createdAt })
    }
}
