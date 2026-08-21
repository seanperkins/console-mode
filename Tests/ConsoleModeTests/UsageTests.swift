import Foundation
import Testing
@testable import ConsoleModeKit

// Payload shapes below mirror real `omp usage --json` output captured while
// building this feature, including Cursor's uncapped meter which omits
// `limit`, `remaining` and `remainingFraction`.

private func snapshot(_ limits: [(provider: String, id: String, remaining: Double?, used: Double?, status: String)]) -> UsageSnapshot {
    var byProvider: [String: [UsageLimit]] = [:]
    var order: [String] = []
    for entry in limits {
        if byProvider[entry.provider] == nil { order.append(entry.provider) }
        byProvider[entry.provider, default: []].append(
            UsageLimit(
                id: entry.id,
                label: entry.id,
                window: UsageWindow(id: "7d", label: "7 days", durationMs: 604_800_000, resetsAt: nil),
                amount: UsageAmount(
                    used: nil,
                    limit: nil,
                    remaining: nil,
                    usedFraction: entry.used,
                    remainingFraction: entry.remaining,
                    unit: "percent"
                ),
                status: entry.status
            )
        )
    }
    return UsageSnapshot(
        generatedAt: 1_787_261_100_882,
        reports: order.map { UsageReport(provider: $0, fetchedAt: 0, limits: byProvider[$0]!, metadata: nil) }
    )
}

// MARK: - Decoding

@Test func decodesRealUsagePayload() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/usage-sample", withExtension: "json"))
    let decoded = try UsageClient.decode(try Data(contentsOf: url))

    #expect(decoded.reports.count == 3)
    #expect(decoded.reports.map(\.provider).contains("cursor"))
    #expect(decoded.generatedAt > 0)
}

@Test func decodesLimitMissingCapFields() throws {
    // Cursor's uncapped meter: usedFraction only.
    let json = """
    {"generatedAt":1,"reports":[{"provider":"cursor","fetchedAt":1,"limits":[
      {"id":"cursor:usd:individual-auto","label":"Cursor Models",
       "window":{"id":"monthly","label":"Monthly","resetsAt":1787852720000},
       "amount":{"used":49.4,"usedFraction":0.494,"unit":"percent"},"status":"ok"}]}]}
    """
    let decoded = try UsageClient.decode(Data(json.utf8))
    let limit = try #require(decoded.reports.first?.limits.first)

    #expect(limit.amount.limit == nil)
    #expect(limit.amount.remainingFraction == nil)
    // Derived rather than dropped, so it still participates in threshold checks.
    #expect(limit.remainingFraction == 0.506)
    #expect(limit.window?.durationMs == nil)
}

@Test func exhaustedStatusReportsZeroRemaining() throws {
    let json = """
    {"generatedAt":1,"reports":[{"provider":"cursor","fetchedAt":1,"limits":[
      {"id":"cursor:usd:individual-api","label":"Other Models",
       "window":{"id":"monthly","label":"Monthly"},
       "amount":{"used":20,"limit":20,"remaining":0,"usedFraction":1,"remainingFraction":0,"unit":"usd"},
       "status":"exhausted"}]}]}
    """
    let limit = try #require(try UsageClient.decode(Data(json.utf8)).reports.first?.limits.first)
    #expect(limit.isExhausted)
    #expect(limit.remainingFraction == 0)
}

@Test func malformedOutputSurfacesAnError() {
    #expect(throws: UsageClientError.self) {
        try UsageClient.decode(Data("not json".utf8))
    }
}

// MARK: - Provider rollup

@Test func providerLineUsesTightestLimit() {
    let snap = snapshot([
        ("openai-codex", "codex:5h", 1.0, nil, "ok"),
        ("openai-codex", "codex:7d", 0.11, nil, "ok"),
        ("openai-codex", "codex:spark", 0.95, nil, "ok"),
    ])
    let provider = try! #require(snap.providerRollup.first)

    #expect(provider.displayName == "Codex")
    // The binding constraint, not the average or the first entry.
    #expect(provider.remainingFraction == 0.11)
    #expect(provider.limit?.id == "codex:7d")
    // 11% remaining sits in the <=20% band, not the <=10% one.
    #expect(provider.severity == .low)
    #expect(provider.allLimits.count == 3)
}

@Test func rollupSortsWorstFirst() {
    let snap = snapshot([
        ("anthropic", "a:7d", 0.81, nil, "ok"),
        ("cursor", "c:api", 0, nil, "exhausted"),
        ("openai-codex", "x:7d", 0.11, nil, "ok"),
    ])
    #expect(snap.providerRollup.map(\.displayName) == ["Cursor", "Codex", "Anthropic"])
}

@Test func providerWithNoNumbersReportsNoFraction() {
    let snap = snapshot([("anthropic", "a:7d", nil, nil, "ok")])
    let provider = try! #require(snap.providerRollup.first)
    #expect(provider.remainingFraction == nil)
    #expect(provider.severity == .healthy)
}

@Test func severityBandsMatchThresholds() {
    #expect(UsageSeverity.forRemaining(0.50) == .healthy)
    #expect(UsageSeverity.forRemaining(0.21) == .healthy)
    #expect(UsageSeverity.forRemaining(0.20) == .low)
    #expect(UsageSeverity.forRemaining(0.11) == .low)
    #expect(UsageSeverity.forRemaining(0.10) == .veryLow)
    #expect(UsageSeverity.forRemaining(0.06) == .veryLow)
    #expect(UsageSeverity.forRemaining(0.05) == .critical)
    #expect(UsageSeverity.forRemaining(0.01) == .critical)
    #expect(UsageSeverity.forRemaining(0) == .exhausted)
}

// MARK: - Threshold crossing

@Test func crossingTwentyPercentFiresOnce() {
    let snap = snapshot([("anthropic", "a:7d", 0.18, nil, "ok")])

    let first = UsageMonitor.evaluate(snapshot: snap, previouslyFired: [:])
    #expect(first.alerts.count == 1)
    #expect(first.alerts[0].threshold == 0.20)
    #expect(first.fired["a:7d"] == 0.20)

    // Same reading on the next poll must stay quiet.
    let second = UsageMonitor.evaluate(snapshot: snap, previouslyFired: first.fired)
    #expect(second.alerts.isEmpty)
    #expect(second.fired["a:7d"] == 0.20)
}

@Test func fallingDeeperFiresAgainAtTheDeeperThreshold() {
    let fired = ["a:7d": 0.20]
    let result = UsageMonitor.evaluate(
        snapshot: snapshot([("anthropic", "a:7d", 0.04, nil, "ok")]),
        previouslyFired: fired
    )
    // Skipping straight past 10% reports the deepest band reached, not both.
    #expect(result.alerts.count == 1)
    #expect(result.alerts[0].threshold == 0.05)
    #expect(result.fired["a:7d"] == 0.05)
}

@Test func recoveryRearmsOnlyBeyondTheMargin() {
    let fired = ["a:7d": 0.20]

    // Just above the line is still inside the anti-flap margin.
    let hovering = UsageMonitor.evaluate(
        snapshot: snapshot([("anthropic", "a:7d", 0.21, nil, "ok")]),
        previouslyFired: fired
    )
    #expect(hovering.fired["a:7d"] == 0.20)
    #expect(hovering.alerts.isEmpty)

    // Clear of the margin: the limit re-arms.
    let recovered = UsageMonitor.evaluate(
        snapshot: snapshot([("anthropic", "a:7d", 0.40, nil, "ok")]),
        previouslyFired: fired
    )
    #expect(recovered.fired["a:7d"] == nil)

    // And can therefore fire again on a later dip.
    let again = UsageMonitor.evaluate(
        snapshot: snapshot([("anthropic", "a:7d", 0.15, nil, "ok")]),
        previouslyFired: recovered.fired
    )
    #expect(again.alerts.count == 1)
}

@Test func limitsCrossingTogetherShareOneAlert() {
    let result = UsageMonitor.evaluate(
        snapshot: snapshot([
            ("anthropic", "a:7d", 0.08, nil, "ok"),
            ("openai-codex", "x:7d", 0.09, nil, "ok"),
        ]),
        previouslyFired: [:]
    )
    #expect(result.alerts.count == 1)
    #expect(result.alerts[0].items.count == 2)
    #expect(result.alerts[0].headline.contains("under 10%"))
}

@Test func healthyLimitsNeverAlert() {
    let result = UsageMonitor.evaluate(
        snapshot: snapshot([("anthropic", "a:7d", 0.81, nil, "ok")]),
        previouslyFired: [:]
    )
    #expect(result.alerts.isEmpty)
    #expect(result.fired.isEmpty)
}

@Test func limitWithoutNumbersIsSkipped() {
    let result = UsageMonitor.evaluate(
        snapshot: snapshot([("anthropic", "a:7d", nil, nil, "ok")]),
        previouslyFired: [:]
    )
    #expect(result.alerts.isEmpty)
}

@Test func exhaustedLimitAlertsAtDeepestBand() {
    let result = UsageMonitor.evaluate(
        snapshot: snapshot([("cursor", "c:api", 0, nil, "exhausted")]),
        previouslyFired: [:]
    )
    #expect(result.alerts.count == 1)
    #expect(result.alerts[0].threshold == 0.05)
}

@Test func liveFixtureFiresForCodexAndCursor() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/usage-sample", withExtension: "json"))
    let decoded = try UsageClient.decode(try Data(contentsOf: url))
    let result = UsageMonitor.evaluate(snapshot: decoded, previouslyFired: [:])

    // Real captured state: Codex 7-day at 11% and Cursor's API meter exhausted.
    let firedIDs = Set(result.fired.keys)
    #expect(firedIDs.contains("openai-codex:primary"))
    #expect(firedIDs.contains("cursor:usd:individual-api"))
    #expect(result.fired["openai-codex:primary"] == 0.20)
    #expect(result.fired["cursor:usd:individual-api"] == 0.05)
}

// MARK: - Formatting

@Test func percentFormattingRoundsAndFloors() {
    #expect(UsageAlert.format(0.11) == "11%")
    #expect(UsageAlert.format(0.005) == "<1%")
    #expect(UsageAlert.format(0) == "0%")
    #expect(UsageAlert.format(1) == "100%")
}

// MARK: - All-limits grouping

@Test func everyLimitGetsItsOwnLine() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/usage-sample", withExtension: "json"))
    let decoded = try UsageClient.decode(try Data(contentsOf: url))

    let lines = decoded.allLines
    let totalLimits = decoded.reports.reduce(0) { $0 + $1.limits.count }
    #expect(lines.count == totalLimits)
    #expect(lines.count == 8)
    // No limit is dropped or duplicated.
    #expect(Set(lines.map(\.limitID)).count == 8)
}

@Test func providerNameAppearsOncePerGroup() {
    let snap = snapshot([
        ("openai-codex", "x:7d", 0.11, nil, "ok"),
        ("openai-codex", "x:5h", 1.0, nil, "ok"),
        ("anthropic", "a:7d", 0.81, nil, "ok"),
    ])
    let lines = snap.allLines

    #expect(lines.count == 3)
    // First row of each group carries the label; continuations stay blank so the
    // column reads as one block per provider.
    #expect(lines.map(\.providerName) == ["Codex", nil, "Anthropic"])
}

@Test func limitsAreWorstFirstWithinAProvider() {
    let snap = snapshot([
        ("anthropic", "a:5h", 0.93, nil, "ok"),
        ("anthropic", "a:7d", 0.31, nil, "ok"),
        ("anthropic", "a:fable", 1.0, nil, "ok"),
    ])
    #expect(snap.allLines.map(\.limitID) == ["a:7d", "a:5h", "a:fable"])
}

@Test func groupsAreWorstProviderFirst() {
    let snap = snapshot([
        ("anthropic", "a:7d", 0.81, nil, "ok"),
        ("cursor", "c:api", 0, nil, "exhausted"),
        ("openai-codex", "x:7d", 0.11, nil, "ok"),
    ])
    #expect(snap.allLines.compactMap(\.providerName) == ["Cursor", "Codex", "Anthropic"])
}

@Test func limitsWithoutNumbersSinkWithinTheirGroup() {
    let snap = snapshot([
        ("cursor", "c:nodata", nil, nil, "ok"),
        ("cursor", "c:api", 0.4, nil, "ok"),
    ])
    let lines = snap.allLines
    #expect(lines.map(\.limitID) == ["c:api", "c:nodata"])
    #expect(lines.last?.remainingFraction == nil)
}

@Test func lineSeverityMatchesItsOwnLimit() {
    let snap = snapshot([
        ("openai-codex", "x:7d", 0.03, nil, "ok"),
        ("openai-codex", "x:5h", 0.90, nil, "ok"),
    ])
    let lines = snap.allLines
    // Each row is coloured by its own window, not by the provider's worst.
    #expect(lines[0].severity == .critical)
    #expect(lines[1].severity == .healthy)
}
