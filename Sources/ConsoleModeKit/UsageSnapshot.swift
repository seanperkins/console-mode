import Foundation

/// Mirrors `omp usage --json`. Every numeric field that the real payload has been
/// observed to omit is optional here: Cursor's uncapped meter has no `limit`,
/// `remaining` or `remainingFraction`, and its monthly window has no `durationMs`.
struct UsageSnapshot: Codable, Equatable, Sendable {
    var generatedAt: TimeInterval
    var reports: [UsageReport]

    var generatedDate: Date { Date(timeIntervalSince1970: generatedAt / 1000) }
}

struct UsageReport: Codable, Equatable, Sendable {
    var provider: String
    var fetchedAt: TimeInterval
    var limits: [UsageLimit]
    var metadata: UsageMetadata?
}

struct UsageMetadata: Codable, Equatable, Sendable {
    var planType: String?
    var email: String?
    var limitReached: Bool?
}

struct UsageWindow: Codable, Equatable, Sendable {
    var id: String
    var label: String?
    var durationMs: Double?
    var resetsAt: TimeInterval?

    var resetDate: Date? {
        resetsAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

struct UsageAmount: Codable, Equatable, Sendable {
    var used: Double?
    var limit: Double?
    var remaining: Double?
    var usedFraction: Double?
    var remainingFraction: Double?
    var unit: String?
}

struct UsageLimit: Codable, Equatable, Sendable {
    var id: String
    var label: String?
    var window: UsageWindow?
    var amount: UsageAmount
    var status: String?

    /// `exhausted` is reported independently of the numbers, so it wins outright.
    var isExhausted: Bool { status == "exhausted" }

    /// Cursor's uncapped meter reports `usedFraction` but no `remainingFraction`,
    /// so derive it rather than dropping the row from threshold checks.
    var remainingFraction: Double? {
        if isExhausted { return 0 }
        if let given = amount.remainingFraction { return given.clampedFraction }
        if let used = amount.usedFraction { return (1 - used).clampedFraction }
        return nil
    }

    /// The limit's own label wins: it carries the qualifier that distinguishes
    /// sibling meters sharing a window, like "7 days (Spark)" versus "7 days", or
    /// Cursor's "Cursor Models" and "Other Models" which are both "Monthly".
    var windowLabel: String {
        label ?? window?.label ?? window?.id ?? "limit"
    }

    /// Absolute figures for the tooltip, where the unit matters — Cursor bills in
    /// dollars while the others report percentages.
    var amountDetail: String? {
        guard let used = amount.used else { return nil }
        let unit = amount.unit ?? ""
        func number(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
        }
        let usedText = unit == "usd" ? "$\(number(used))" : "\(number(used))%"
        guard let cap = amount.limit else { return "\(usedText) used" }
        let capText = unit == "usd" ? "$\(number(cap))" : "\(number(cap))%"
        return "\(usedText) of \(capText) used"
    }

    /// Dollar figure for usage-based providers billed in real currency (Cursor's
    /// "Other Models" overage meter today, any future usd-unit meter tomorrow).
    /// `nil` for percent/request meters so the row falls back to the fraction text.
    var costUsed: Double? { amount.unit == "usd" ? amount.used : nil }

    /// The cap this meter spends against, when the provider sent one — shown
    /// alongside `costUsed` as "$used / $limit" so the row reads as spend,
    /// never as a remaining-budget figure that would hide an exhausted cap.
    var costLimit: Double? { amount.unit == "usd" ? amount.limit : nil }

    /// A real remaining balance with no known cap (DeepSeek's account
    /// balance today) — distinct from `costUsed`/`costLimit`, which always
    /// read as spend against a budget. Only set when the provider reported
    /// *just* a remaining figure (no `used`, no `limit`); a capped or
    /// spend-tracking usd meter already renders through `costUsed`.
    var costRemaining: UsageMoneyAmount? {
        guard amount.used == nil, amount.limit == nil,
              let remaining = amount.remaining,
              let unit = amount.unit, unit != "percent", unit != "requests"
        else { return nil }
        return UsageMoneyAmount(value: remaining, currencyCode: unit)
    }
}

/// A real dollar (or other currency) figure with no known cap to measure a
/// fraction against — shown as "$X.XX left", never framed as spend.
struct UsageMoneyAmount: Equatable, Sendable {
    var value: Double
    /// Lowercased currency code as the provider reported it (`"usd"`, `"cny"`, …).
    var currencyCode: String
}

extension Double {
    /// Guards against provider rounding drift like `1.0000000002`.
    var clampedFraction: Double { Swift.min(1, Swift.max(0, self)) }
}

// MARK: - Per-provider rollup

/// How close a limit is to running out. Ordered so `max()` finds the worst.
enum UsageSeverity: Int, Comparable, Sendable {
    case healthy = 0
    case low = 1        // <= 20% remaining
    case veryLow = 2    // <= 10%
    case critical = 3   // <= 5%
    case exhausted = 4  // 0% or status exhausted

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Thresholds are expressed in *remaining* fraction, matching how the app alerts.
    static func forRemaining(_ fraction: Double) -> UsageSeverity {
        if fraction <= 0 { return .exhausted }
        if fraction <= 0.05 { return .critical }
        if fraction <= 0.10 { return .veryLow }
        if fraction <= 0.20 { return .low }
        return .healthy
    }
}

/// One line in the usage tab: a provider reduced to its binding constraint.
struct ProviderUsage: Equatable, Sendable, Identifiable {
    var provider: String
    var displayName: String
    var limit: UsageLimit?
    var remainingFraction: Double?
    var severity: UsageSeverity
    /// Every limit for this provider, for the row tooltip.
    var allLimits: [UsageLimit]

    var id: String { provider }

    static func displayName(for provider: String) -> String {
        switch provider {
        case "openai-codex": return "Codex"
        case "anthropic": return "Anthropic"
        case "cursor": return "Cursor"
        default:
            return provider
                .split(separator: "-")
                .map(\.capitalized)
                .joined(separator: " ")
        }
    }

    /// The tightest limit is the one that will actually block work, so it is the
    /// number worth showing when a provider gets a single line.
    init(report: UsageReport) {
        provider = report.provider
        displayName = Self.displayName(for: report.provider)
        allLimits = report.limits

        let ranked = report.limits
            .compactMap { limit -> (UsageLimit, Double)? in
                guard let fraction = limit.remainingFraction else { return nil }
                return (limit, fraction)
            }
            .sorted { $0.1 < $1.1 }

        if let (tightest, fraction) = ranked.first {
            limit = tightest
            remainingFraction = fraction
            severity = .forRemaining(fraction)
        } else {
            // Authenticated but no numbers yet: report nothing rather than a fake 100%.
            limit = report.limits.first
            remainingFraction = nil
            severity = .healthy
        }
    }
}

extension UsageSnapshot {
    /// Providers in a stable, predictable order regardless of broker response order.
    var providerRollup: [ProviderUsage] {
        reports
            .map(ProviderUsage.init(report:))
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }
}

/// One rendered row in the usage tab: a single limit, with the provider name
/// carried only on the first row of each group so the column stays quiet.
struct UsageLine: Equatable, Sendable, Identifiable {
    var limitID: String
    /// `nil` on continuation rows — same provider as the row above.
    var providerName: String?
    var windowLabel: String
    var remainingFraction: Double?
    var severity: UsageSeverity
    var resetDate: Date?
    var isExhausted: Bool
    /// Absolute figures for the tooltip.
    var amountDetail: String?
    /// Dollar figure shown directly in the row for usd-billed meters, in place
    /// of the fraction text that would otherwise read as a meaningless percent.
    var costUsed: Double?
    var costLimit: Double?
    var costRemaining: UsageMoneyAmount?

    var id: String { limitID }
}

extension UsageSnapshot {
    /// Every limit, grouped by provider. Providers are ordered worst-first (the
    /// same order as `providerRollup`) and limits within a provider are ordered
    /// worst-first too, so the binding constraint leads each group.
    var allLines: [UsageLine] {
        providerRollup.flatMap { provider -> [UsageLine] in
            let sorted = provider.allLimits.sorted { lhs, rhs in
                switch (lhs.remainingFraction, rhs.remainingFraction) {
                case let (l?, r?): return l < r
                // Limits with no numbers sink to the bottom of their group.
                case (nil, _?): return false
                case (_?, nil): return true
                default: return lhs.id < rhs.id
                }
            }
            return sorted.enumerated().map { index, limit in
                UsageLine(
                    limitID: limit.id,
                    providerName: index == 0 ? provider.displayName : nil,
                    windowLabel: limit.windowLabel,
                    remainingFraction: limit.remainingFraction,
                    severity: limit.remainingFraction.map(UsageSeverity.forRemaining) ?? .healthy,
                    resetDate: limit.window?.resetDate,
                    isExhausted: limit.isExhausted,
                    amountDetail: limit.amountDetail,
                    costUsed: limit.costUsed,
                    costLimit: limit.costLimit,
                    costRemaining: limit.costRemaining
                )
            }
        }
    }
}

extension UsageSnapshot {
    /// Providers `omp usage` has any report for — a subscription quota, a
    /// real dollar meter, or both. Excluded from the stats-derived cost
    /// section so a provider never shows two different cost numbers: a flat
    /// subscription's catalog price is not what the user pays, and a real
    /// dollar meter (Cursor's overage pool) already has its own precise row.
    var trackedProviders: Set<String> {
        Set(reports.map(\.provider))
    }
}
