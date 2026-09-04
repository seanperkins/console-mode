import Foundation

/// Mirrors DeepSeek's documented account balance payload
/// (`GET https://api.deepseek.com/user/balance`, api-docs.deepseek.com). This
/// is a real billing figure — the account's actual remaining prepaid
/// balance — unlike `omp stats`'s catalog-priced token estimate for the
/// same provider.
struct DeepSeekBalanceResponse: Codable, Equatable, Sendable {
    var isAvailable: Bool
    var balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    struct BalanceInfo: Codable, Equatable, Sendable {
        var currency: String
        var totalBalance: String
        var grantedBalance: String
        var toppedUpBalance: String

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }
}

extension DeepSeekBalanceResponse {
    /// Synthesizes a `deepseek` `UsageReport` carrying the account's real
    /// remaining balance — never mapped into `UsageAmount.used`/`limit`,
    /// since a balance is not spend against a known cap and this app's
    /// "$used" rendering path would misrepresent it. Shaped exactly like
    /// `omp usage`'s own reports so it flows through the same rollup and
    /// merge code as the Claude Code statusline reading.
    ///
    /// Accounts can carry balances in more than one currency (e.g. a legacy
    /// CNY balance alongside a USD one); the USD entry is preferred when
    /// present, otherwise the first reported currency is shown as-is — never
    /// relabeled as `$`.
    func asUsageReport(fetchedAt: TimeInterval) -> UsageReport? {
        let entry = balanceInfos.first { $0.currency.caseInsensitiveCompare("USD") == .orderedSame }
            ?? balanceInfos.first
        guard let entry, let total = Double(entry.totalBalance) else { return nil }

        let limit = UsageLimit(
            id: "deepseek:balance",
            label: "Account balance",
            window: nil,
            amount: UsageAmount(
                used: nil,
                limit: nil,
                remaining: total,
                usedFraction: nil,
                remainingFraction: nil,
                unit: entry.currency.lowercased()
            ),
            // No known cap to measure "remaining" against, so severity/fraction
            // stay unset (see `UsageLimit.remainingFraction`) — the only signal
            // this endpoint gives about running out is `is_available` itself.
            status: isAvailable ? "ok" : "exhausted"
        )
        return UsageReport(provider: "deepseek", fetchedAt: fetchedAt, limits: [limit], metadata: nil)
    }
}
