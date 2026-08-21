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
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    /// Set when a threshold is crossed; the panel shows it and then clears it.
    private(set) var activeAlert: UsageAlert?

    var onAlert: ((UsageAlert) -> Void)?

    private var firedThresholds: [String: Double]
    private var pollTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let firedKey = "usage.firedThresholds"

    var rollup: [ProviderUsage] { snapshot?.providerRollup ?? [] }

    /// Every limit, grouped by provider — one row each in the usage tab.
    var lines: [UsageLine] { snapshot?.allLines ?? [] }

    /// Worst severity across every provider, for the menu bar indicator.
    var worstSeverity: UsageSeverity {
        rollup.map(\.severity).max() ?? .healthy
    }

    init(defaults: UserDefaults = .standard, seeded: UsageSnapshot? = nil) {
        self.defaults = defaults
        firedThresholds = defaults.dictionary(forKey: Self.firedKey) as? [String: Double] ?? [:]
        if let seeded {
            // Deterministic input for the offscreen harness and tests: no process
            // launch, no network, no clock dependency.
            snapshot = seeded
            lastRefresh = Date(timeIntervalSince1970: 1_787_261_100)
        }
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
        defer { isRefreshing = false }

        let client = UsageClient(executableOverride: settings.ompPath)
        do {
            let fresh = try await client.fetch()
            snapshot = fresh
            lastError = nil
            lastRefresh = Date()
            evaluateThresholds(for: fresh)
        } catch {
            // Keep the last good snapshot on screen; a failed poll is not "no usage".
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
