import Foundation

/// Mirrors the subset of `omp stats --json` (`DashboardStats`) this app needs:
/// per-model cost, rolled up per provider. Every other field in the real
/// payload (token counts, latency, folders, time series, ...) is irrelevant
/// here and simply ignored by `Codable`.
///
/// Important: `totalCost` is **not** a billed charge. `omp stats` backfills it
/// from catalog list-token prices even for flat-fee subscription models
/// (Claude, Codex, Cursor's included pool), purely so every model has a
/// comparable number. Treating it as real spend for a subscription provider
/// would be wrong — see `costEstimateLines(excluding:)`, which drops any
/// provider `omp usage` already tracks.
struct StatsSnapshot: Codable, Equatable, Sendable {
    var byModel: [StatsModelEntry]
}

struct StatsModelEntry: Codable, Equatable, Sendable {
    var model: String
    var provider: String
    /// Catalog-priced estimate for the tokens this model burned in the active
    /// range. `omp stats --json` defaults to the trailing 24h.
    var totalCost: Double
}

extension StatsSnapshot {
    /// Estimated token cost summed per provider over the active range.
    var costByProvider: [String: Double] {
        Dictionary(grouping: byModel, by: \.provider)
            .mapValues { entries in entries.reduce(0) { $0 + $1.totalCost } }
    }

    /// One row per usage-priced provider with no real dollar quota meter of
    /// its own: `omp usage` reports nothing for it at all (DeepSeek,
    /// OpenRouter, Nous, ...), so there is no other number for it on screen.
    /// Providers `omp usage` already tracks are excluded even when they carry
    /// spend here — a flat-subscription provider's catalog price is not what
    /// the user pays, and a real dollar-metered provider (Cursor's overage
    /// pool) already gets its own precise row from that meter.
    func costEstimateLines(excluding trackedProviders: Set<String>) -> [UsageLine] {
        costByProvider
            .filter { provider, cost in cost > 0 && !trackedProviders.contains(provider) }
            .sorted { $0.value > $1.value }
            .map { provider, cost in
                UsageLine(
                    limitID: "cost-estimate:\(provider)",
                    providerName: ProviderUsage.displayName(for: provider),
                    windowLabel: "Est. cost (24h)",
                    remainingFraction: nil,
                    severity: .healthy,
                    resetDate: nil,
                    isExhausted: false,
                    amountDetail: "Catalog-priced token cost estimate, not a billed charge",
                    costUsed: cost,
                    costLimit: nil
                )
            }
    }
}
