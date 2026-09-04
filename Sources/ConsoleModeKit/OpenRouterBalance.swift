import Foundation

/// Mirrors OpenRouter's documented credits payload
/// (`GET https://openrouter.ai/api/v1/credits`, openrouter.ai/docs). A real
/// billing figure — total purchased credits minus total usage — unlike
/// `omp stats`'s catalog-priced token estimate for the same provider.
struct OpenRouterBalanceResponse: Codable, Equatable, Sendable {
    var data: Data

    struct Data: Codable, Equatable, Sendable {
        var totalCredits: Double
        var totalUsage: Double

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }

    /// The balance isn't a payload field — OpenRouter's own docs specify
    /// computing it client-side as `total_credits - total_usage`.
    var remaining: Double { data.totalCredits - data.totalUsage }
}

extension OpenRouterBalanceResponse {
    /// Synthesizes an `openrouter` `UsageReport` carrying the account's real
    /// remaining credit balance — same treatment as `DeepSeekBalanceResponse`:
    /// never mapped into `UsageAmount.used`/`limit`, since a remaining
    /// balance is not spend against a known cap. Always USD; OpenRouter
    /// credits have no other currency.
    func asUsageReport(fetchedAt: TimeInterval) -> UsageReport? {
        let limit = UsageLimit(
            id: "openrouter:balance",
            label: "Account balance",
            window: nil,
            amount: UsageAmount(
                used: nil,
                limit: nil,
                remaining: remaining,
                usedFraction: nil,
                remainingFraction: nil,
                unit: "usd"
            ),
            status: remaining > 0 ? "ok" : "exhausted"
        )
        return UsageReport(provider: "openrouter", fetchedAt: fetchedAt, limits: [limit], metadata: nil)
    }
}
