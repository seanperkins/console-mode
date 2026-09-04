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
    /// Daily per-model spend buckets, used for the cost-estimate row's spend
    /// trend sparkline. Defaults to empty and tolerates a missing key so
    /// older captured fixtures (and anything that constructs a snapshot by
    /// hand in tests) keep working without it.
    var costSeries: [CostSeriesEntry]

    init(byModel: [StatsModelEntry], costSeries: [CostSeriesEntry] = []) {
        self.byModel = byModel
        self.costSeries = costSeries
    }

    private enum CodingKeys: String, CodingKey {
        case byModel, costSeries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        byModel = try container.decode([StatsModelEntry].self, forKey: .byModel)
        costSeries = try container.decodeIfPresent([CostSeriesEntry].self, forKey: .costSeries) ?? []
    }
}

/// One model's spend on one day, from `omp stats --json`'s `costSeries`.
/// Every other field in the real payload (input/output/cache cost
/// breakdown, request count, ...) is irrelevant here and ignored by `Codable`.
struct CostSeriesEntry: Codable, Equatable, Sendable {
    /// Unix milliseconds, day-aligned — matches `omp stats`'s own bucketing,
    /// so entries sharing this value are already grouped by day.
    var timestamp: Double
    var model: String
    var provider: String
    var cost: Double
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
                    amountDetail: costEstimateDetail(provider: provider),
                    costUsed: cost,
                    costLimit: nil
                )
            }
    }

    /// Top models by spend for one provider — the drill-down behind a
    /// cost-estimate row's tooltip, so "why is this number what it is" is
    /// one hover away instead of requiring `omp stats` on the command line.
    func topModels(for provider: String, limit: Int = 3) -> [(model: String, cost: Double)] {
        byModel
            .filter { $0.provider == provider }
            .sorted { $0.totalCost > $1.totalCost }
            .prefix(limit)
            .map { ($0.model, $0.totalCost) }
    }

    /// Daily total spend for a provider, chronological, from `costSeries`.
    /// Whatever range `omp stats --json` actively covers (default trailing
    /// 24h, more if the user configured a wider range) is however many
    /// buckets come back — this makes no assumption about the count.
    func dailyCostTrend(for provider: String) -> [Double] {
        let byDay = Dictionary(grouping: costSeries.filter { $0.provider == provider }, by: \.timestamp)
            .mapValues { entries in entries.reduce(0) { $0 + $1.cost } }
        return byDay.keys.sorted().map { byDay[$0] ?? 0 }
    }

    /// Compact 8-level Unicode sparkline, scaled to the series' own max so a
    /// provider trending toward exhaustion reads at a glance. Empty when
    /// there is nothing to compare (0 or 1 buckets, or every value is zero).
    static func sparkline(_ values: [Double]) -> String {
        guard values.count > 1, let peak = values.max(), peak > 0 else { return "" }
        let levels: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        return String(
            values.map { value in
                levels[min(levels.count - 1, Int((value / peak) * Double(levels.count - 1)))]
            }
        )
    }

    private func costEstimateDetail(provider: String) -> String {
        var parts = ["Catalog-priced token cost estimate, not a billed charge"]
        let models = topModels(for: provider)
        if !models.isEmpty {
            let modelsText = models
                .map { "\($0.model) ($\(String(format: "%.2f", $0.cost)))" }
                .joined(separator: ", ")
            parts.append("top: \(modelsText)")
        }
        let trend = Self.sparkline(dailyCostTrend(for: provider))
        if !trend.isEmpty {
            parts.append("trend \(trend)")
        }
        return parts.joined(separator: " · ")
    }
}
