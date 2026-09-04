import Foundation

enum ObsidianExportError: Error, Equatable {
    case disabled
    case missingVault
    case writeFailed(String)
}

/// Appends captured notes to an Obsidian daily note file.
enum ObsidianExporter {
    static func export(_ note: Note, config: ObsidianConfig = ObsidianSettings.current) throws {
        guard config.isEnabled else { throw ObsidianExportError.disabled }
        let vault = config.vaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vault.isEmpty else { throw ObsidianExportError.missingVault }

        let fileURL = dailyNoteURL(for: note.createdDate, config: config, vaultURL: vaultURL(from: vault))
        let line = markdownLine(for: note)

        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            let header = "# \(note.createdDate.formatted(date: .abbreviated, time: .omitted))\n\n"
            try (header + line).write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Expands `~/…` so Settings paths like `~/Obsidian/MyVault` resolve to the home directory.
    static func vaultURL(from path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    static func dailyNoteURL(for date: Date, config: ObsidianConfig, vaultURL: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + ".md"

        var folder = config.dailyFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        while folder.hasPrefix("/") { folder.removeFirst() }
        while folder.hasSuffix("/") { folder.removeLast() }

        if folder.isEmpty {
            return vaultURL.appendingPathComponent(name)
        }
        return vaultURL.appendingPathComponent(folder).appendingPathComponent(name)
    }

    static func markdownLine(for note: Note) -> String {
        let time = note.createdDate.formatted(date: .omitted, time: .shortened)
        let box = note.isCompleted ? "x" : " "
        var line = "- [\(box)] \(time) \(note.body)"
        if let project = note.project, !project.isEmpty {
            line += " #\(project)"
        }
        return line + "\n"
    }
}
