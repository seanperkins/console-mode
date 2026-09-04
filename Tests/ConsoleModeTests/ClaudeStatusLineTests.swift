import Foundation
import Testing
@testable import ConsoleModeKit

// MARK: - ClaudeStatusSnapshot decoding

@Test func decodesDocumentedStatuslinePayload() throws {
    let json = """
    {"model":{"display_name":"Opus"},"cwd":"/tmp",
     "rate_limits":{"five_hour":{"used_percentage":14.0,"resets_at":1788462000},
                    "seven_day":{"used_percentage":33.0,"resets_at":1788930000}},
     "cost":{"total_cost_usd":1.23}}
    """
    let snapshot = try JSONDecoder().decode(ClaudeStatusSnapshot.self, from: Data(json.utf8))
    #expect(snapshot.rateLimits?.fiveHour?.usedPercentage == 14.0)
    #expect(snapshot.rateLimits?.sevenDay?.usedPercentage == 33.0)
    #expect(snapshot.cost?.totalCostUsd == 1.23)
}

@Test func decodingIgnoresEveryUndocumentedField() throws {
    // model/cwd/session_id/workspace/... are irrelevant here; absence of a
    // strict schema must not break decoding.
    let json = """
    {"model":{"display_name":"Opus"},"context_window":{"used_percentage":40},
     "session_id":"abc","transcript_path":"/tmp/x.jsonl","version":"2.1.0"}
    """
    let snapshot = try JSONDecoder().decode(ClaudeStatusSnapshot.self, from: Data(json.utf8))
    #expect(snapshot.rateLimits == nil)
    #expect(snapshot.cost == nil)
}

// MARK: - asAnthropicReport()

@Test func asAnthropicReportCoversBothWindowsAndCost() {
    let snapshot = ClaudeStatusSnapshot(
        rateLimits: .init(
            fiveHour: .init(usedPercentage: 14, resetsAt: 1_788_462_000),
            sevenDay: .init(usedPercentage: 33, resetsAt: 1_788_930_000)
        ),
        cost: .init(totalCostUsd: 1.23)
    )
    let report = try! #require(snapshot.asAnthropicReport(fetchedAt: 0))
    #expect(report.provider == "anthropic")
    #expect(report.limits.map(\.id) == ["claude-code:5h", "claude-code:7d", "claude-code:cost-estimate"])
    #expect(report.limits[0].remainingFraction == 0.86)
    #expect(report.limits[2].costUsed == 1.23)
    #expect(report.limits[2].costLimit == nil)
    #expect(report.limits[2].label == "Est. cost (latest session)")

    // Flows through the same rendering path as every other provider.
    let lines = ProviderUsage(report: report)
    #expect(lines.provider == "anthropic")
    #expect(lines.displayName == "Anthropic")
}

@Test func asAnthropicReportOmitsMissingWindowsAndZeroCost() {
    let snapshot = ClaudeStatusSnapshot(
        rateLimits: .init(fiveHour: .init(usedPercentage: nil, resetsAt: nil), sevenDay: nil),
        cost: .init(totalCostUsd: 0)
    )
    #expect(snapshot.asAnthropicReport(fetchedAt: 0) == nil)
}

// MARK: - UsageMonitor merge behavior

@MainActor
@Test func effectiveSnapshotReplacesOmpAnthropicReportWithFreshClaudeReading() {
    let ompSnapshot = UsageSnapshot(generatedAt: 0, reports: [
        UsageReport(provider: "anthropic", fetchedAt: 0, limits: [
            UsageLimit(id: "anthropic:7d", label: "7 days", window: nil,
                       amount: UsageAmount(used: 90, limit: 100, remaining: 10, usedFraction: 0.9, remainingFraction: 0.1, unit: "percent"),
                       status: "ok"),
        ], metadata: nil),
        UsageReport(provider: "cursor", fetchedAt: 0, limits: [
            UsageLimit(id: "cursor:api", label: "Monthly", window: nil,
                       amount: UsageAmount(used: 0, limit: 20, remaining: 20, usedFraction: 0, remainingFraction: 1, unit: "usd"),
                       status: "ok"),
        ], metadata: nil),
    ])
    let claudeStatus = ClaudeStatusSnapshot(
        rateLimits: .init(fiveHour: .init(usedPercentage: 14, resetsAt: nil), sevenDay: .init(usedPercentage: 33, resetsAt: nil)),
        cost: nil
    )
    let monitor = UsageMonitor(
        defaults: UserDefaults(suiteName: "monitor-claude-merge-test")!,
        seeded: ompSnapshot,
        seededClaudeStatus: claudeStatus
    )

    let effective = try! #require(monitor.effectiveSnapshot)
    let anthropicReports = effective.reports.filter { $0.provider == "anthropic" }
    #expect(anthropicReports.count == 1)
    #expect(anthropicReports[0].limits.map(\.id) == ["claude-code:5h", "claude-code:7d"])
    #expect(effective.reports.contains { $0.provider == "cursor" })

    // No duplicate Anthropic rows in the rendered lines or the rollup.
    #expect(monitor.lines.filter { $0.providerName == "Anthropic" }.count == 1)
    #expect(monitor.rollup.filter { $0.provider == "anthropic" }.count == 1)
}

@MainActor
@Test func effectiveSnapshotKeepsOmpAnthropicReportWithoutFreshClaudeReading() {
    let ompSnapshot = UsageSnapshot(generatedAt: 0, reports: [
        UsageReport(provider: "anthropic", fetchedAt: 0, limits: [
            UsageLimit(id: "anthropic:7d", label: "7 days", window: nil,
                       amount: UsageAmount(used: 90, limit: 100, remaining: 10, usedFraction: 0.9, remainingFraction: 0.1, unit: "percent"),
                       status: "ok"),
        ], metadata: nil),
    ])
    let monitor = UsageMonitor(
        defaults: UserDefaults(suiteName: "monitor-claude-no-merge-test")!,
        seeded: ompSnapshot
    )
    let effective = try! #require(monitor.effectiveSnapshot)
    #expect(effective.reports.first { $0.provider == "anthropic" }?.limits.map(\.id) == ["anthropic:7d"])
}

// MARK: - loadCached freshness

@Test func loadCachedReturnsNilForMissingFile() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID()).json")
    #expect(ClaudeStatusSnapshot.loadCached(from: url) == nil)
}

@Test func loadCachedReturnsNilWhenStale() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("stale-\(UUID()).json")
    try Data("{\"cost\":{\"total_cost_usd\":1}}".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let now = Date()
    let snapshot = ClaudeStatusSnapshot.loadCached(from: url, maxAge: 60, now: now.addingTimeInterval(3600))
    #expect(snapshot == nil)
}

@Test func loadCachedReturnsSnapshotWhenFresh() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("fresh-\(UUID()).json")
    try Data("{\"cost\":{\"total_cost_usd\":1}}".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let snapshot = ClaudeStatusSnapshot.loadCached(from: url, maxAge: 3600, now: Date())
    #expect(snapshot?.cost?.totalCostUsd == 1)
}

// MARK: - ClaudeStatusLineInstaller

private func makeInstaller() -> ClaudeStatusLineInstaller {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cm-cship-test-\(UUID())")
    return ClaudeStatusLineInstaller(
        settingsURL: root.appendingPathComponent("settings.json"),
        supportDirectory: root.appendingPathComponent("Application Support")
    )
}

@Test func installFromEmptySettingsWritesCommandStatusLine() throws {
    let installer = makeInstaller()
    defer { try? FileManager.default.removeItem(at: installer.supportDirectory.deletingLastPathComponent()) }

    try installer.install()
    #expect(installer.isInstalled)

    let data = try Data(contentsOf: installer.settingsURL)
    let settings = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let statusLine = try #require(settings["statusLine"] as? [String: Any])
    let command = try #require(statusLine["command"] as? String)
    #expect(command.contains(installer.wrapperURL.path))
}

@Test func uninstallWithNoPriorStatusLineRemovesTheKeyEntirely() throws {
    let installer = makeInstaller()
    defer { try? FileManager.default.removeItem(at: installer.supportDirectory.deletingLastPathComponent()) }

    try installer.install()
    try installer.uninstall()
    #expect(!installer.isInstalled)

    let data = try Data(contentsOf: installer.settingsURL)
    let settings = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(settings["statusLine"] == nil)
}

@Test func installPreservesEveryOtherStatusLineKey() throws {
    let installer = makeInstaller()
    defer { try? FileManager.default.removeItem(at: installer.supportDirectory.deletingLastPathComponent()) }

    try FileManager.default.createDirectory(
        at: installer.settingsURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let original: [String: Any] = [
        "statusLine": [
            "type": "command",
            "command": "cship",
            "padding": 2,
            "refreshInterval": 5000,
            "hideVimModeIndicator": true,
        ] as [String: Any],
        "unrelatedTopLevelKey": "keep-me",
    ]
    try JSONSerialization.data(withJSONObject: original).write(to: installer.settingsURL)

    try installer.install()

    let installedData = try Data(contentsOf: installer.settingsURL)
    let installed = try #require(try JSONSerialization.jsonObject(with: installedData) as? [String: Any])
    let installedStatusLine = try #require(installed["statusLine"] as? [String: Any])
    #expect(installedStatusLine["padding"] as? Int == 2)
    #expect(installedStatusLine["refreshInterval"] as? Int == 5000)
    #expect(installedStatusLine["hideVimModeIndicator"] as? Bool == true)
    #expect((installedStatusLine["command"] as? String)?.contains(installer.wrapperURL.path) == true)
    #expect(installed["unrelatedTopLevelKey"] as? String == "keep-me")

    // The wrapper must forward to the original "cship" command so the
    // user's real statusline keeps working.
    let script = try String(contentsOf: installer.wrapperURL, encoding: .utf8)
    #expect(script.contains("| cship"))

    try installer.uninstall()
    let restoredData = try Data(contentsOf: installer.settingsURL)
    let restored = try #require(try JSONSerialization.jsonObject(with: restoredData) as? [String: Any])
    let restoredStatusLine = try #require(restored["statusLine"] as? [String: Any])
    #expect(restoredStatusLine["command"] as? String == "cship")
    #expect(restoredStatusLine["padding"] as? Int == 2)
    #expect(restoredStatusLine["refreshInterval"] as? Int == 5000)
    #expect(restoredStatusLine["hideVimModeIndicator"] as? Bool == true)
    #expect(restored["unrelatedTopLevelKey"] as? String == "keep-me")
}

/// Regression test: calling `install()` a second time must not save our own
/// wrapper command as "the previous command" — that would make the wrapper
/// forward to itself on every invocation.
@Test func installIsIdempotentAndNeverForwardsToItself() throws {
    let installer = makeInstaller()
    defer { try? FileManager.default.removeItem(at: installer.supportDirectory.deletingLastPathComponent()) }

    try FileManager.default.createDirectory(
        at: installer.settingsURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let original: [String: Any] = ["statusLine": ["type": "command", "command": "cship"] as [String: Any]]
    try JSONSerialization.data(withJSONObject: original).write(to: installer.settingsURL)

    try installer.install()
    #expect(installer.isInstalled)

    // Second install: same as the first from the user's perspective (e.g.
    // toggling the Settings switch off then on, or a second launch).
    try installer.install()
    try installer.install()

    let script = try String(contentsOf: installer.wrapperURL, encoding: .utf8)
    #expect(script.contains("| cship"))
    #expect(!script.contains(installer.wrapperURL.path))

    // Uninstall must still restore the real original, not a wrapper-wraps-
    // wrapper command a naive repeat install would have saved.
    try installer.uninstall()
    let data = try Data(contentsOf: installer.settingsURL)
    let restored = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let statusLine = try #require(restored["statusLine"] as? [String: Any])
    #expect(statusLine["command"] as? String == "cship")
}

@Test func uninstallNeverClobbersACommandChangedAfterInstall() throws {
    let installer = makeInstaller()
    defer { try? FileManager.default.removeItem(at: installer.supportDirectory.deletingLastPathComponent()) }

    try installer.install()

    // Simulate the user editing settings.json by hand after install, e.g.
    // switching to a different statusline tool entirely.
    var settings = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any]
    settings["statusLine"] = ["type": "command", "command": "some-other-tool"]
    try JSONSerialization.data(withJSONObject: settings).write(to: installer.settingsURL)

    try installer.uninstall()

    let data = try Data(contentsOf: installer.settingsURL)
    let restored = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let statusLine = try #require(restored["statusLine"] as? [String: Any])
    #expect(statusLine["command"] as? String == "some-other-tool")
}

/// End-to-end: a support directory path containing a space (as the real
/// "Application Support" path does) must still produce a `statusLine.command`
/// that actually executes — regression test for the unquoted-path bug.
@Test func installedCommandActuallyExecutesWithSpacesInThePath() throws {
    let installer = makeInstaller()
    defer { try? FileManager.default.removeItem(at: installer.supportDirectory.deletingLastPathComponent()) }
    #expect(installer.supportDirectory.path.contains(" "))

    try installer.install()

    let settingsData = try Data(contentsOf: installer.settingsURL)
    let settings = try #require(try JSONSerialization.jsonObject(with: settingsData) as? [String: Any])
    let statusLine = try #require(settings["statusLine"] as? [String: Any])
    let command = try #require(statusLine["command"] as? String)

    let payload = "{\"cost\":{\"total_cost_usd\":2.5}}"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    let stdin = Pipe()
    process.standardInput = stdin
    try process.run()
    stdin.fileHandleForWriting.write(Data(payload.utf8))
    stdin.fileHandleForWriting.closeFile()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
    let cached = try String(contentsOf: installer.cacheURL, encoding: .utf8)
    #expect(cached == payload)
}
