import Foundation
import Testing
@testable import ConsoleModeKit

@Test func dailyNoteURLUsesVaultAndFolder() throws {
    let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let config = ObsidianConfig(isEnabled: true, vaultPath: vault.path, dailyFolder: "Daily")
    let calendar = Calendar.current
    var components = DateComponents()
    components.year = 2024
    components.month = 1
    components.day = 1
    let date = calendar.date(from: components)!

    let url = ObsidianExporter.dailyNoteURL(for: date, config: config, vaultURL: vault)
    #expect(url.lastPathComponent == "2024-01-01.md")
    #expect(url.path.contains("/Daily/"))
}

@Test func markdownLineIncludesProjectTag() {
    let note = Note(
        id: 1,
        body: "ship it",
        createdAt: 1_700_000_000,
        completedAt: nil,
        project: "console-mode"
    )
    let line = ObsidianExporter.markdownLine(for: note)
    #expect(line.contains("- [ ]"))
    #expect(line.contains("ship it"))
    #expect(line.contains("#console-mode"))
}

@Test func exportExpandsTildeVaultPath() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let rel = "ConsoleModeExportTest-\(UUID().uuidString)"
    let vaultDir = home.appendingPathComponent(rel)
    try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: vaultDir) }

    let config = ObsidianConfig(isEnabled: true, vaultPath: "~/\(rel)", dailyFolder: "")
    let note = Note(id: 1, body: "tilde path works", createdAt: Date().timeIntervalSince1970)

    try ObsidianExporter.export(note, config: config)
    let files = try FileManager.default.contentsOfDirectory(atPath: vaultDir.path)
    #expect(files.count == 1)
    let text = try String(contentsOf: vaultDir.appendingPathComponent(files[0]), encoding: .utf8)
    #expect(text.contains("tilde path works"))
}

@Test func exportAppendsToDailyNote() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let config = ObsidianConfig(isEnabled: true, vaultPath: dir.path, dailyFolder: "")
    let note = Note(id: 1, body: "first", createdAt: Date().timeIntervalSince1970)

    try ObsidianExporter.export(note, config: config)
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(files.count == 1)
    let text = try String(contentsOf: dir.appendingPathComponent(files[0]), encoding: .utf8)
    #expect(text.contains("first"))
}
