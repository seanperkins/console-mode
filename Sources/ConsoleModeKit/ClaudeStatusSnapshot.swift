import Foundation

/// Mirrors the subset of Claude Code's documented `statusLine` JSON payload
/// (code.claude.com/docs/en/statusline) this app needs: account-wide rate
/// limits and Claude Code's own client-side cost estimate. Every other field
/// in the real payload (model, context window, cwd, session id, ...) is
/// irrelevant here and simply ignored by `Codable`.
///
/// Important: `cost.total_cost_usd` is explicitly documented as a
/// client-side estimate from a price table bundled in the Claude Code
/// client — not a billing figure. It is surfaced as an estimate, same
/// treatment as the `omp stats` catalog-priced rows.
struct ClaudeStatusSnapshot: Codable, Equatable, Sendable {
    var rateLimits: RateLimits?
    var cost: Cost?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
        case cost
    }

    struct RateLimits: Codable, Equatable, Sendable {
        var fiveHour: Window?
        var sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    /// `resets_at` is a Unix timestamp in seconds, per the documented schema
    /// (unlike `omp usage`'s milliseconds).
    struct Window: Codable, Equatable, Sendable {
        var usedPercentage: Double?
        var resetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }

    struct Cost: Codable, Equatable, Sendable {
        var totalCostUsd: Double?

        enum CodingKeys: String, CodingKey {
            case totalCostUsd = "total_cost_usd"
        }
    }
}

extension ClaudeStatusSnapshot {
    /// Reads the cache a `statusLine` wrapper script writes, discarding it if
    /// stale. Claude Code refreshes the payload on every turn while a session
    /// is active; a cache older than `maxAge` means no session has run
    /// recently, and showing it would read as current when it is not.
    static func loadCached(from url: URL, maxAge: TimeInterval = 3 * 3600, now: Date = Date()) -> ClaudeStatusSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              now.timeIntervalSince(modified) < maxAge,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(ClaudeStatusSnapshot.self, from: data)
    }

    /// Synthesizes an `anthropic` `UsageReport` from Claude Code's own
    /// statusline feed: 5h/7d rate-limit windows as ordinary percent
    /// `UsageLimit`s, plus (if reported) Claude's own cost estimate as a usd
    /// `UsageLimit`. Shaped exactly like `omp usage`'s own reports so it
    /// flows through the same rollup, severity, and threshold-alerting code
    /// — no separate bolt-on list, no duplicate Anthropic rows when `omp
    /// usage` also reports one.
    ///
    /// `cost.total_cost_usd` is scoped to Claude Code's *current session*
    /// (it resets on `/clear`) and this app's cache is last-writer-wins
    /// across concurrent sessions — it is neither total account spend nor a
    /// fixed time window, so the limit is labeled and detailed as such.
    func asAnthropicReport(fetchedAt: TimeInterval) -> UsageReport? {
        var limits: [UsageLimit] = []

        func addWindow(_ window: Window?, label: String, id: String) {
            guard let window, let usedPercentage = window.usedPercentage else { return }
            let usedFraction = (usedPercentage / 100).clampedFraction
            limits.append(
                UsageLimit(
                    id: id,
                    label: label,
                    window: window.resetsAt.map {
                        UsageWindow(id: id, label: label, durationMs: nil, resetsAt: $0 * 1000)
                    },
                    amount: UsageAmount(
                        used: usedPercentage,
                        limit: 100,
                        remaining: 100 * (1 - usedFraction),
                        usedFraction: usedFraction,
                        remainingFraction: 1 - usedFraction,
                        unit: "percent"
                    ),
                    status: usedFraction >= 1 ? "exhausted" : "ok"
                )
            )
        }

        addWindow(rateLimits?.fiveHour, label: "5 hours", id: "claude-code:5h")
        addWindow(rateLimits?.sevenDay, label: "7 days", id: "claude-code:7d")

        if let totalCostUsd = cost?.totalCostUsd, totalCostUsd > 0 {
            limits.append(
                UsageLimit(
                    id: "claude-code:cost-estimate",
                    label: "Est. cost (latest session)",
                    window: nil,
                    amount: UsageAmount(used: totalCostUsd, limit: nil, remaining: nil, usedFraction: nil, remainingFraction: nil, unit: "usd"),
                    status: "ok"
                )
            )
        }

        guard !limits.isEmpty else { return nil }
        return UsageReport(provider: "anthropic", fetchedAt: fetchedAt, limits: limits, metadata: nil)
    }
}
