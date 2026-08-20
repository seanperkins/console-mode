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

    var windowLabel: String {
        window?.label ?? window?.id ?? label ?? "limit"
    }
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
