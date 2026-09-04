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

@Test func usdMeterExposesCostFigures() throws {
    let json = """
    {"generatedAt":1,"reports":[{"provider":"cursor","fetchedAt":1,"limits":[
      {"id":"cursor:usd:individual-api","label":"Other Models",
       "window":{"id":"monthly","label":"Monthly"},
       "amount":{"used":6.5,"limit":20,"remaining":13.5,"usedFraction":0.325,"remainingFraction":0.675,"unit":"usd"},
       "status":"ok"}]}]}
    """
    let limit = try #require(try UsageClient.decode(Data(json.utf8)).reports.first?.limits.first)
    #expect(limit.costUsed == 6.5)
    #expect(limit.costLimit == 20)
}

@Test func uncappedUsdMeterHasNoCostLimit() throws {
    // No `limit` or `remaining` sent: derive nothing rather than a fake cap.
    let json = """
    {"generatedAt":1,"reports":[{"provider":"openrouter","fetchedAt":1,"limits":[
      {"id":"openrouter:usd:overage","label":"Overage",
       "window":{"id":"monthly","label":"Monthly"},
       "amount":{"used":4.2,"unit":"usd"},"status":"ok"}]}]}
    """
    let limit = try #require(try UsageClient.decode(Data(json.utf8)).reports.first?.limits.first)
    #expect(limit.costUsed == 4.2)
    #expect(limit.costLimit == nil)
}

@Test func percentMeterHasNoCostFigures() throws {
    // Cursor's included-quota meter is unit "percent", not "usd": it must not
    // masquerade as a dollar figure even though its id contains "usd".
    let json = """
    {"generatedAt":1,"reports":[{"provider":"cursor","fetchedAt":1,"limits":[
      {"id":"cursor:usd:individual-auto","label":"Cursor Models",
       "window":{"id":"monthly","label":"Monthly"},
       "amount":{"used":49.4,"usedFraction":0.494,"unit":"percent"},"status":"ok"}]}]}
    """
    let limit = try #require(try UsageClient.decode(Data(json.utf8)).reports.first?.limits.first)
    #expect(limit.costUsed == nil)
    #expect(limit.costLimit == nil)
}

@Test func allLinesCarryCostFiguresForUsdMeters() throws {
    let snap = UsageSnapshot(generatedAt: 1, reports: [
        UsageReport(provider: "cursor", fetchedAt: 1, limits: [
            UsageLimit(
                id: "cursor:usd:individual-api",
                label: "Other Models",
                window: nil,
                amount: UsageAmount(used: 6.5, limit: 20, remaining: 13.5, unit: "usd"),
                status: "ok"
            )
        ], metadata: nil)
    ])
    let line = try #require(snap.allLines.first)
    #expect(line.costUsed == 6.5)
    #expect(line.costLimit == 20)
}

@Test func balanceOnlyMeterExposesCostRemainingNotCostUsed() throws {
    let limit = UsageLimit(
        id: "deepseek:balance",
        label: "Account balance",
        window: nil,
        amount: UsageAmount(used: nil, limit: nil, remaining: 12.34, unit: "usd"),
        status: "ok"
    )
    #expect(limit.costUsed == nil)
    #expect(limit.costLimit == nil)
    #expect(limit.costRemaining == UsageMoneyAmount(value: 12.34, currencyCode: "usd"))
}

@Test func nonUsdBalanceKeepsItsCurrencyCode() throws {
    let limit = UsageLimit(
        id: "deepseek:balance",
        label: "Account balance",
        window: nil,
        amount: UsageAmount(used: nil, limit: nil, remaining: 110, unit: "cny"),
        status: "ok"
    )
    #expect(limit.costRemaining?.currencyCode == "cny")
}

@Test func decodesDeepSeekBalancePayloadPreferringUsd() throws {
    let json = """
    {"is_available":true,"balance_infos":[
      {"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"},
      {"currency":"USD","total_balance":"15.50","granted_balance":"1.00","topped_up_balance":"14.50"}
    ]}
    """
    let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: Data(json.utf8))
    let report = try #require(decoded.asUsageReport(fetchedAt: 1))
    #expect(report.provider == "deepseek")
    let limit = try #require(report.limits.first)
    #expect(limit.costRemaining == UsageMoneyAmount(value: 15.5, currencyCode: "usd"))
    #expect(limit.isExhausted == false)
}

@Test func deepSeekBalanceFallsBackToOnlyCurrencyWhenNoUsd() throws {
    let json = """
    {"is_available":false,"balance_infos":[
      {"currency":"CNY","total_balance":"0.00","granted_balance":"0.00","topped_up_balance":"0.00"}
    ]}
    """
    let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: Data(json.utf8))
    let report = try #require(decoded.asUsageReport(fetchedAt: 1))
    let limit = try #require(report.limits.first)
    #expect(limit.costRemaining == UsageMoneyAmount(value: 0, currencyCode: "cny"))
    // `is_available == false` is the only signal this endpoint gives about
    // running out — no known cap means no fraction, so it must surface as
    // exhausted status rather than silently reading as healthy.
    #expect(limit.isExhausted)
}

@MainActor
@Test func effectiveSnapshotMergesDeepSeekBalanceReplacingAnyOmpUsageEntry() {
    let ompSnapshot = UsageSnapshot(generatedAt: 0, reports: [
        UsageReport(provider: "cursor", fetchedAt: 0, limits: [
            UsageLimit(id: "cursor:api", label: "Monthly", window: nil,
                       amount: UsageAmount(used: 0, limit: 20, remaining: 20, usedFraction: 0, remainingFraction: 1, unit: "usd"),
                       status: "ok"),
        ], metadata: nil),
    ])
    let balance = DeepSeekBalanceResponse(
        isAvailable: true,
        balanceInfos: [.init(currency: "USD", totalBalance: "8.75", grantedBalance: "0", toppedUpBalance: "8.75")]
    )
    let monitor = UsageMonitor(
        defaults: UserDefaults(suiteName: "monitor-deepseek-merge-test")!,
        seeded: ompSnapshot,
        seededDeepSeekBalance: balance
    )

    let effective = try! #require(monitor.effectiveSnapshot)
    #expect(effective.reports.contains { $0.provider == "deepseek" })
    #expect(effective.reports.contains { $0.provider == "cursor" })
    #expect(effective.trackedProviders.contains("deepseek"))

    // Never doubles up as a stats-catalog estimate row once the real balance is in.
    let costLines = StatsSnapshot(byModel: [
        StatsModelEntry(model: "deepseek-chat", provider: "deepseek", totalCost: 3.0),
    ]).costEstimateLines(excluding: effective.trackedProviders)
    #expect(costLines.isEmpty)
}

// MARK: - DeepSeek balance resolution (pure, no network/Keychain)

private let deepSeekSample = DeepSeekBalanceResponse(
    isAvailable: true,
    balanceInfos: [.init(currency: "USD", totalBalance: "8.75", grantedBalance: "0", toppedUpBalance: "8.75")]
)

@Test func resolveDeepSeekBalanceDisabledAlwaysClearsRegardlessOfPreviousState() {
    let resolved = UsageMonitor.resolveDeepSeekBalance(
        enabled: false,
        result: .success(deepSeekSample),
        previousBalance: deepSeekSample,
        previousFetchedAt: Date(),
        now: Date()
    )
    #expect(resolved.balance == nil)
    #expect(resolved.fetchedAt == nil)
    #expect(resolved.error == nil)
}

@Test func resolveDeepSeekBalanceSuccessStampsTheRealFetchTime() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let resolved = UsageMonitor.resolveDeepSeekBalance(
        enabled: true,
        result: .success(deepSeekSample),
        previousBalance: nil,
        previousFetchedAt: nil,
        now: now
    )
    #expect(resolved.balance == deepSeekSample)
    #expect(resolved.fetchedAt == now)
    #expect(resolved.error == nil)
}

@Test func resolveDeepSeekBalanceAuthFailureClearsEvenAPreviousGoodReading() {
    let resolved = UsageMonitor.resolveDeepSeekBalance(
        enabled: true,
        result: .failure(DeepSeekClientError.exitFailure(code: 401, message: "invalid key")),
        previousBalance: deepSeekSample,
        previousFetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
        now: Date()
    )
    #expect(resolved.balance == nil)
    #expect(resolved.fetchedAt == nil)
    #expect(resolved.error != nil)
}

@Test func resolveDeepSeekBalanceTransientFailureKeepsTheLastGoodReading() {
    let staleTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let resolved = UsageMonitor.resolveDeepSeekBalance(
        enabled: true,
        result: .failure(DeepSeekClientError.requestFailed("timed out")),
        previousBalance: deepSeekSample,
        previousFetchedAt: staleTimestamp,
        now: Date()
    )
    #expect(resolved.balance == deepSeekSample)
    // The old fetch time is preserved, never relabeled as fresh.
    #expect(resolved.fetchedAt == staleTimestamp)
    #expect(resolved.error != nil)
}

@Test func resolveDeepSeekBalanceEnabledWithNoResultReportsNotConfigured() {
    let resolved = UsageMonitor.resolveDeepSeekBalance(
        enabled: true,
        result: nil,
        previousBalance: nil,
        previousFetchedAt: nil,
        now: Date()
    )
    #expect(resolved.balance == nil)
    #expect(resolved.error == DeepSeekClientError.notConfigured.errorDescription)
}

@MainActor
@Test func disablingDeepSeekAfterASeededBalanceClearsTheMergedRow() {
    let monitor = UsageMonitor(
        defaults: UserDefaults(suiteName: "monitor-deepseek-disable-test")!,
        seeded: snapshot([("cursor", "c:api", 0.5, nil, "ok")]),
        seededDeepSeekBalance: deepSeekSample
    )
    #expect(monitor.effectiveSnapshot?.reports.contains { $0.provider == "deepseek" } == true)

    monitor.simulateDeepSeekDisabled()

    #expect(monitor.deepSeekBalance == nil)
    #expect(monitor.deepSeekBalanceFetchedAt == nil)
    #expect(monitor.effectiveSnapshot?.reports.contains { $0.provider == "deepseek" } == false)
    // The other provider's row is untouched by the clear.
    #expect(monitor.effectiveSnapshot?.reports.contains { $0.provider == "cursor" } == true)
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

// MARK: - Stats-derived cost estimates

@Test func trackedProvidersIncludeEveryReportedProviderRegardlessOfUnit() {
    let snap = snapshot([
        ("anthropic", "a:7d", 0.5, nil, "ok"),
        ("cursor", "c:api", 0.5, nil, "ok"),
    ])
    #expect(snap.trackedProviders == ["anthropic", "cursor"])
}

@Test func costEstimateLinesSkipProvidersOmpUsageAlreadyTracks() {
    // Anthropic is a flat subscription (percent-only quota); Cursor already
    // has its own real dollar meter. Neither should get a second, estimated
    // cost number. DeepSeek has no `omp usage` report at all, so it is the
    // only usage-priced candidate left.
    let stats = StatsSnapshot(byModel: [
        StatsModelEntry(model: "claude-opus", provider: "anthropic", totalCost: 12.0),
        StatsModelEntry(model: "composer", provider: "cursor", totalCost: 3.0),
        StatsModelEntry(model: "deepseek-v3", provider: "deepseek", totalCost: 0.79),
    ])
    let lines = stats.costEstimateLines(excluding: ["anthropic", "cursor"])
    #expect(lines.map(\.limitID) == ["cost-estimate:deepseek"])
    #expect(lines.first?.providerName == "Deepseek")
    #expect(lines.first?.windowLabel == "Est. cost (24h)")
    #expect(lines.first?.costUsed == 0.79)
    #expect(lines.first?.costLimit == nil)
    #expect(lines.first?.remainingFraction == nil)
}

@Test func costEstimateLinesSumMultipleModelsPerProvider() {
    let stats = StatsSnapshot(byModel: [
        StatsModelEntry(model: "model-a", provider: "openrouter", totalCost: 1.5),
        StatsModelEntry(model: "model-b", provider: "openrouter", totalCost: 2.25),
    ])
    let lines = stats.costEstimateLines(excluding: [])
    #expect(lines.first?.costUsed == 3.75)
}

@Test func costEstimateLinesDropZeroCostProviders() {
    let stats = StatsSnapshot(byModel: [
        StatsModelEntry(model: "model-a", provider: "nous", totalCost: 0)
    ])
    #expect(stats.costEstimateLines(excluding: []).isEmpty)
}

@MainActor
@Test func monitorLinesAppendCostEstimatesAfterQuotaLines() {
    let monitor = UsageMonitor(
        defaults: UserDefaults(suiteName: "monitor-cost-lines-test")!,
        seeded: snapshot([("anthropic", "a:7d", 0.5, nil, "ok")]),
        seededStats: StatsSnapshot(byModel: [
            StatsModelEntry(model: "claude-opus", provider: "anthropic", totalCost: 12.0),
            StatsModelEntry(model: "deepseek-v3", provider: "deepseek", totalCost: 0.79),
        ])
    )
    #expect(monitor.lines.map(\.limitID) == ["a:7d", "cost-estimate:deepseek"])
}

@Test func statsClientDecodeSkipsTheSyncProgressPreamble() throws {
    // `omp stats --json` writes "Synced N entries..." to stdout before the
    // JSON payload; decoding must not choke on it.
    let output = "Synced 41 new entries from 4 files (24085 total)\n\n{\"byModel\":[{\"model\":\"m\",\"provider\":\"p\",\"totalCost\":1.5}]}"
    let decoded = try StatsClient.decode(Data(output.utf8))
    #expect(decoded.byModel.count == 1)
    #expect(decoded.byModel.first?.totalCost == 1.5)
}

@Test func statsClientDecodeRejectsOutputWithNoJsonObject() {
    #expect(throws: StatsClientError.self) {
        try StatsClient.decode(Data("Synced 0 new entries from 0 files (0 total)\n".utf8))
    }
}
