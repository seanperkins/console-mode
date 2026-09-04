import Foundation
import Observation

/// A limit that has just crossed a warning threshold.
struct UsageAlertItem: Equatable, Sendable, Identifiable {
    var limitID: String
    var providerName: String
    var windowLabel: String
    var remainingFraction: Double

    var id: String { limitID }
}

/// One transient notice, possibly covering several limits that crossed together.
struct UsageAlert: Equatable, Sendable {
    var threshold: Double
    var items: [UsageAlertItem]

    var headline: String {
        let percent = Int((threshold * 100).rounded())
        guard let first = items.first else { return "Usage below \(percent)%" }
        if items.count == 1 {
            return "\(first.providerName) \(first.windowLabel): \(UsageAlert.format(first.remainingFraction)) left"
        }
        let names = items.map(\.providerName).joined(separator: ", ")
        return "\(names): under \(percent)% left"
    }

    static func format(_ fraction: Double) -> String {
        let percent = fraction * 100
        if percent > 0, percent < 1 { return "<1%" }
        return "\(Int(percent.rounded()))%"
    }
}

@Observable
@MainActor
final class UsageMonitor {
    /// Warning thresholds in *remaining* fraction, deepest last.
    nonisolated static let thresholds: [Double] = [0.20, 0.10, 0.05]
    /// A limit must recover this far above a fired threshold before it can fire
    /// again, so a value hovering on the boundary cannot flap.
    nonisolated static let rearmMargin = 0.02

    private(set) var snapshot: UsageSnapshot?
    private(set) var statsSnapshot: StatsSnapshot?
    private(set) var claudeStatus: ClaudeStatusSnapshot?
    private(set) var deepSeekBalance: DeepSeekBalanceResponse?
    /// When `deepSeekBalance` was actually fetched — never `Date()` at read
    /// time, so a stale reading (kept on screen through a transient poll
    /// failure) is never relabeled as fresh.
    private(set) var deepSeekBalanceFetchedAt: Date?
    private(set) var deepSeekError: String?
    private(set) var openRouterBalance: OpenRouterBalanceResponse?
    /// See `deepSeekBalanceFetchedAt` — same staleness contract.
    private(set) var openRouterBalanceFetchedAt: Date?
    private(set) var openRouterError: String?
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    /// Set when a threshold is crossed; the panel shows it and then clears it.
    private(set) var activeAlert: UsageAlert?

    var onAlert: ((UsageAlert) -> Void)?
    /// Fired after every refresh attempt so the panel can resize to match the limit count.
    var onDataChange: (@MainActor () -> Void)?

    private var firedThresholds: [String: Double]
    private var pollTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let firedKey = "usage.firedThresholds"

    var rollup: [ProviderUsage] { effectiveSnapshot?.providerRollup ?? [] }

    /// Every limit, grouped by provider — one row each in the usage tab.
    var lines: [UsageLine] { (effectiveSnapshot?.allLines ?? []) + costLines }

    /// `snapshot` with any first-party reading substituted for `omp usage`'s
    /// own report for that provider — Claude Code's own statusline (more
    /// current than `omp usage`'s cache) and DeepSeek's real account balance
    /// (a billing figure `omp usage` never reports at all). Substitution
    /// (not addition) keeps rollup, severity, and threshold alerts from ever
    /// double-counting the same account under two different rows.
    var effectiveSnapshot: UsageSnapshot? {
        let now = Date().timeIntervalSince1970 * 1000
        var extra: [UsageReport] = []
        if let claudeReport = claudeStatus?.asAnthropicReport(fetchedAt: now) { extra.append(claudeReport) }
        if let deepSeekBalance, let deepSeekBalanceFetchedAt {
            let fetchedAtMs = deepSeekBalanceFetchedAt.timeIntervalSince1970 * 1000
            if let deepSeekReport = deepSeekBalance.asUsageReport(fetchedAt: fetchedAtMs) { extra.append(deepSeekReport) }
        }
        if let openRouterBalance, let openRouterBalanceFetchedAt {
            let fetchedAtMs = openRouterBalanceFetchedAt.timeIntervalSince1970 * 1000
            if let report = openRouterBalance.asUsageReport(fetchedAt: fetchedAtMs) { extra.append(report) }
        }

        guard var snap = snapshot else {
            guard !extra.isEmpty else { return nil }
            return UsageSnapshot(generatedAt: extra.map(\.fetchedAt).max() ?? now, reports: extra)
        }
        guard !extra.isEmpty else { return snap }
        let extraProviders = Set(extra.map(\.provider))
        snap.reports.removeAll { extraProviders.contains($0.provider) }
        snap.reports.append(contentsOf: extra)
        return snap
    }

    /// Rows for usage-priced providers `omp usage` never reports a quota for
    /// (DeepSeek, OpenRouter, Nous, ...), sourced from `omp stats`'s
    /// catalog-priced token cost. Appended after every real limit line.
    var costLines: [UsageLine] {
        guard let statsSnapshot else { return [] }
        return statsSnapshot.costEstimateLines(excluding: effectiveSnapshot?.trackedProviders ?? [])
    }

    /// Worst severity across every provider, for the menu bar indicator.
    var worstSeverity: UsageSeverity {
        rollup.map(\.severity).max() ?? .healthy
    }

    private let deepSeekCredentialStore: any DeepSeekCredentialStore
    private let openRouterCredentialStore: any OpenRouterCredentialStore

    init(
        defaults: UserDefaults = .standard,
        seeded: UsageSnapshot? = nil,
        seededStats: StatsSnapshot? = nil,
        seededClaudeStatus: ClaudeStatusSnapshot? = nil,
        seededDeepSeekBalance: DeepSeekBalanceResponse? = nil,
        seededOpenRouterBalance: OpenRouterBalanceResponse? = nil,
        deepSeekCredentialStore: any DeepSeekCredentialStore = KeychainDeepSeekCredentialStore(),
        openRouterCredentialStore: any OpenRouterCredentialStore = KeychainOpenRouterCredentialStore()
    ) {
        self.defaults = defaults
        self.deepSeekCredentialStore = deepSeekCredentialStore
        self.openRouterCredentialStore = openRouterCredentialStore
        firedThresholds = defaults.dictionary(forKey: Self.firedKey) as? [String: Double] ?? [:]
        if let seeded {
            // Deterministic input for the offscreen harness and tests: no process
            // launch, no network, no clock dependency.
            snapshot = seeded
            lastRefresh = Date(timeIntervalSince1970: 1_787_261_100)
        }
        statsSnapshot = seededStats
        claudeStatus = seededClaudeStatus
        if let seededDeepSeekBalance {
            deepSeekBalance = seededDeepSeekBalance
            deepSeekBalanceFetchedAt = Date(timeIntervalSince1970: 1_787_261_100)
        }
        if let seededOpenRouterBalance {
            openRouterBalance = seededOpenRouterBalance
            openRouterBalanceFetchedAt = Date(timeIntervalSince1970: 1_787_261_100)
        }
    }

    /// Test hook: applies a snapshot and fires `onDataChange` like `refresh()`'s defer.
    package func simulateLoadedSnapshot(
        _ snapshot: UsageSnapshot,
        stats: StatsSnapshot? = nil,
        claudeStatus: ClaudeStatusSnapshot? = nil,
        deepSeekBalance: DeepSeekBalanceResponse? = nil,
        openRouterBalance: OpenRouterBalanceResponse? = nil
    ) {
        self.snapshot = snapshot
        if let stats { statsSnapshot = stats }
        if let claudeStatus { self.claudeStatus = claudeStatus }
        if let deepSeekBalance {
            self.deepSeekBalance = deepSeekBalance
            deepSeekBalanceFetchedAt = Date(timeIntervalSince1970: 1_787_261_100)
        }
        if let openRouterBalance {
            self.openRouterBalance = openRouterBalance
            openRouterBalanceFetchedAt = Date(timeIntervalSince1970: 1_787_261_100)
        }
        lastError = nil
        lastRefresh = Date(timeIntervalSince1970: 1_787_261_100)
        onDataChange?()
    }

    /// Test hook: mirrors exactly what `refresh()` assigns when DeepSeek is
    /// disabled — unconditional clear, not a conditional skip like
    /// `simulateLoadedSnapshot`'s `deepSeekBalance` parameter.
    package func simulateDeepSeekDisabled() {
        deepSeekBalance = nil
        deepSeekBalanceFetchedAt = nil
        deepSeekError = nil
        onDataChange?()
    }

    /// Test hook: same contract as `simulateDeepSeekDisabled`, for OpenRouter.
    package func simulateOpenRouterDisabled() {
        openRouterBalance = nil
        openRouterBalanceFetchedAt = nil
        openRouterError = nil
        onDataChange?()
    }

    // MARK: - Polling

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let minutes = UsageSettings.current.pollMinutes
                try? await Task.sleep(for: .seconds(max(1, minutes) * 60))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        let settings = UsageSettings.current
        isRefreshing = true
        defer {
            isRefreshing = false
            onDataChange?()
        }

        let usageClient = UsageClient(executableOverride: settings.ompPath)
        let statsClient = StatsClient(executableOverride: settings.ompPath)
        let deepSeekEnabled = DeepSeekSettings.current.isEnabled
        let deepSeekKey = deepSeekEnabled ? deepSeekCredentialStore.loadAPIKey() : nil
        let openRouterEnabled = OpenRouterSettings.current.isEnabled
        let openRouterKey = openRouterEnabled ? openRouterCredentialStore.loadAPIKey() : nil
        // Cost estimates and the real-balance providers are all nice-to-haves
        // on top of quota data — a failure or slow run there must never
        // block or blank the quota lines above.
        async let statsFetch: StatsSnapshot? = try? statsClient.fetch()
        async let deepSeekFetch: Swift.Result<DeepSeekBalanceResponse, Error>? = {
            guard let deepSeekKey, !deepSeekKey.isEmpty else { return nil }
            do {
                return .success(try await DeepSeekClient(apiKey: deepSeekKey).fetch())
            } catch {
                return .failure(error)
            }
        }()
        async let openRouterFetch: Swift.Result<OpenRouterBalanceResponse, Error>? = {
            guard let openRouterKey, !openRouterKey.isEmpty else { return nil }
            do {
                return .success(try await OpenRouterClient(apiKey: openRouterKey).fetch())
            } catch {
                return .failure(error)
            }
        }()

        do {
            let fresh = try await usageClient.fetch()
            snapshot = fresh
            lastError = nil
            lastRefresh = Date()
        } catch {
            // Keep the last good snapshot on screen; a failed poll is not "no usage".
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        if let stats = await statsFetch { statsSnapshot = stats }

        let resolvedDeepSeek = Self.resolveDeepSeekBalance(
            enabled: deepSeekEnabled,
            result: await deepSeekFetch,
            previousBalance: deepSeekBalance,
            previousFetchedAt: deepSeekBalanceFetchedAt,
            now: Date()
        )
        deepSeekBalance = resolvedDeepSeek.balance
        deepSeekBalanceFetchedAt = resolvedDeepSeek.fetchedAt
        deepSeekError = resolvedDeepSeek.error

        let resolvedOpenRouter = Self.resolveOpenRouterBalance(
            enabled: openRouterEnabled,
            result: await openRouterFetch,
            previousBalance: openRouterBalance,
            previousFetchedAt: openRouterBalanceFetchedAt,
            now: Date()
        )
        openRouterBalance = resolvedOpenRouter.balance
        openRouterBalanceFetchedAt = resolvedOpenRouter.fetchedAt
        openRouterError = resolvedOpenRouter.error

        let installer = ClaudeStatusLineInstaller.resolved(settingsPath: ClaudeStatusLineSettings.current.settingsPath)
        claudeStatus = ClaudeStatusSnapshot.loadCached(from: installer.cacheURL)

        // Alerts evaluate the merged view so a fresh Claude Code reading —
        // which may now be the only source for the anthropic row — can still
        // cross a threshold.
        if let effective = effectiveSnapshot {
            evaluateThresholds(for: effective)
        }
    }

    /// Pure and actor-free so on/off and success/failure transitions can be
    /// tested without a process, the Keychain, or the network.
    ///
    /// Turning DeepSeek off must blank the reading immediately — leaving a
    /// merged report around after disable would show a number the user just
    /// asked to stop seeing. An auth failure (401/403) means the stored key
    /// is wrong or revoked, so a balance read under the old key is no longer
    /// trustworthy either. Any other failure (network blip, timeout) is
    /// transient: the last good reading stays on screen rather than
    /// blanking on every hiccup, same policy as `omp usage`'s `lastError`.
    nonisolated static func resolveDeepSeekBalance(
        enabled: Bool,
        result: Swift.Result<DeepSeekBalanceResponse, Error>?,
        previousBalance: DeepSeekBalanceResponse?,
        previousFetchedAt: Date?,
        now: Date
    ) -> (balance: DeepSeekBalanceResponse?, fetchedAt: Date?, error: String?) {
        guard enabled else { return (nil, nil, nil) }
        guard let result else {
            return (nil, nil, DeepSeekClientError.notConfigured.errorDescription)
        }
        switch result {
        case .success(let balance):
            return (balance, now, nil)
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if case DeepSeekClientError.exitFailure(let code, _) = error, code == 401 || code == 403 {
                return (nil, nil, message)
            }
            return (previousBalance, previousFetchedAt, message)
        }
    }

    /// Mirrors `resolveDeepSeekBalance` — same disable/auth-failure/transient-
    /// failure contract, for OpenRouter's credits endpoint.
    nonisolated static func resolveOpenRouterBalance(
        enabled: Bool,
        result: Swift.Result<OpenRouterBalanceResponse, Error>?,
        previousBalance: OpenRouterBalanceResponse?,
        previousFetchedAt: Date?,
        now: Date
    ) -> (balance: OpenRouterBalanceResponse?, fetchedAt: Date?, error: String?) {
        guard enabled else { return (nil, nil, nil) }
        guard let result else {
            return (nil, nil, OpenRouterClientError.notConfigured.errorDescription)
        }
        switch result {
        case .success(let balance):
            return (balance, now, nil)
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if case OpenRouterClientError.exitFailure(let code, _) = error, code == 401 || code == 403 {
                return (nil, nil, message)
            }
            return (previousBalance, previousFetchedAt, message)
        }
    }

    // MARK: - Thresholds

    private func evaluateThresholds(for snapshot: UsageSnapshot) {
        guard UsageSettings.current.alertsEnabled else { return }
        let result = Self.evaluate(snapshot: snapshot, previouslyFired: firedThresholds)
        firedThresholds = result.fired
        defaults.set(firedThresholds, forKey: Self.firedKey)

        // Deepest threshold first, so a 5% crossing is what the user actually sees.
        if let alert = result.alerts.min(by: { $0.threshold < $1.threshold }) {
            activeAlert = alert
            onAlert?(alert)
        }
    }

    func clearAlert() {
        activeAlert = nil
    }

    /// Pure and actor-free so the crossing rules can be tested without a process
    /// or a timer.
    nonisolated static func evaluate(
        snapshot: UsageSnapshot,
        previouslyFired: [String: Double]
    ) -> (alerts: [UsageAlert], fired: [String: Double]) {
        var fired = previouslyFired
        var newlyCrossed: [Double: [UsageAlertItem]] = [:]

        for report in snapshot.reports {
            let providerName = ProviderUsage.displayName(for: report.provider)
            for limit in report.limits {
                guard let remaining = limit.remainingFraction else { continue }
                let deepest = thresholds.filter { remaining <= $0 }.min()

                guard let deepest else {
                    // Recovered clear of every threshold: re-arm once past the margin.
                    if let previous = fired[limit.id], remaining > previous + rearmMargin {
                        fired.removeValue(forKey: limit.id)
                    }
                    continue
                }

                // Only fire when this is deeper than whatever already fired, so a
                // limit sitting at 11% does not re-alert on every poll.
                if let previous = fired[limit.id], deepest >= previous { continue }

                fired[limit.id] = deepest
                newlyCrossed[deepest, default: []].append(
                    UsageAlertItem(
                        limitID: limit.id,
                        providerName: providerName,
                        windowLabel: limit.windowLabel,
                        remainingFraction: remaining
                    )
                )
            }
        }

        let alerts = newlyCrossed
            .map { UsageAlert(threshold: $0.key, items: $0.value.sorted { $0.limitID < $1.limitID }) }
            .sorted { $0.threshold < $1.threshold }
        return (alerts, fired)
    }

    /// Used by Settings so the user can re-test alerting without waiting for a reset.
    func resetFiredThresholds() {
        firedThresholds = [:]
        defaults.removeObject(forKey: Self.firedKey)
        activeAlert = nil
    }
}
