import AppKit
import SwiftUI

/// One limit per line. The provider name appears only on the first line of each
/// group, so the eye reads a block per provider without the name repeating.
struct UsageRow: View {
    @Environment(\.theme) private var theme
    let line: UsageLine

    private var tint: Color { theme.color(for: line.severity) }

    var body: some View {
        HStack(spacing: 8) {
            Text(line.providerName.map(theme.label) ?? "")
                .font(theme.captionFont)
                .tracking(theme.labelTracking)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .frame(width: 88, alignment: .leading)

            Text(line.windowLabel)
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                // Wide enough for the longest real label, "Claude 7 Day (Fable)".
                .frame(width: 168, alignment: .leading)

            meter
                .frame(width: 118)

            Text(remainingText)
                .font(theme.meterFont)
                .foregroundStyle(line.remainingFraction == nil ? theme.textTertiary : tint)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                // "left" stays on every row: the meter fills with what is *spent*,
                // so a bare number would be ambiguous.
                .frame(width: 84, alignment: .trailing)

            Spacer(minLength: 0)

            Text(resetText)
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
        }
        .frame(height: PanelGeometry.usageRowHeight)
        .padding(.horizontal, 12)
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Fills with the *used* portion, so a full bar reads as "spent".
    @ViewBuilder
    private var meter: some View {
        let used = line.remainingFraction.map { 1 - $0 }
        switch theme.meterStyle {
        case .capsule:
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.meterTrack)
                    // Nothing spent must draw nothing: a minimum-width sliver
                    // would read as usage on an untouched limit.
                    if let used, used > 0 {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(2, geometry.size.width * used))
                    }
                }
            }
            .frame(height: 5)

        case .segmented(let count):
            // The count of lit cells is readable without reading the number.
            let lit = used.map { Int(($0 * Double(count)).rounded(.up)) } ?? 0
            HStack(spacing: 1.5) {
                ForEach(0..<count, id: \.self) { index in
                    Rectangle()
                        .fill(index < lit ? tint : theme.meterTrack)
                        .frame(height: 8)
                }
            }
            .shadow(color: tint.opacity(theme.glowRadius > 0 ? 0.6 : 0), radius: 2)
        }
    }

    private var remainingText: String {
        if let cost = costText { return cost }
        guard let fraction = line.remainingFraction else { return "—" }
        return UsageAlert.format(fraction) + " left"
    }

    /// Dollar figure for usage-based meters — shown instead of a percent, since
    /// a raw fraction of an uncapped budget would be meaningless.
    ///
    /// Two distinct shapes: `costUsed` always shows what was *spent* (a
    /// "remaining" figure alone would hide an exhausted cap behind "$0
    /// left"). `costRemaining` is the opposite case — a real account
    /// balance with no known cap to measure spend against (DeepSeek) — so
    /// showing what is left is the only figure that means anything.
    private var costText: String? {
        if let used = line.costUsed {
            func money(_ value: Double) -> String {
                value == value.rounded() ? "$\(Int(value))" : String(format: "$%.2f", value)
            }
            if let limit = line.costLimit { return "\(money(used)) / \(money(limit))" }
            return money(used) + " used"
        }
        if let remaining = line.costRemaining {
            return UsageRow.money(remaining) + " left"
        }
        return nil
    }

    /// Never prefixes a non-USD balance with `$` — DeepSeek accounts can
    /// carry a CNY balance, and mislabeling it as dollars would be wrong by
    /// roughly 7x.
    private static func money(_ amount: UsageMoneyAmount) -> String {
        let number = amount.value == amount.value.rounded()
            ? "\(Int(amount.value))"
            : String(format: "%.2f", amount.value)
        return amount.currencyCode == "usd" ? "$\(number)" : "\(number) \(amount.currencyCode.uppercased())"
    }

    private var resetText: String {
        guard let reset = line.resetDate else {
            return line.isExhausted ? "exhausted" : ""
        }
        let seconds = reset.timeIntervalSinceNow
        // A window whose reset has already passed says nothing useful.
        guard seconds > 0 else { return "" }
        return "in " + UsageRow.relative(reset)
    }

    private var tooltip: String {
        var parts: [String] = [line.windowLabel]
        if let detail = line.amountDetail { parts.append(detail) }
        if let reset = line.resetDate, reset.timeIntervalSinceNow > 0 {
            parts.append("resets in " + UsageRow.relative(reset))
        }
        if line.isExhausted { parts.append("exhausted") }
        return parts.joined(separator: " · ")
    }

    /// Short relative form: the exact minute rarely matters, the day does.
    static func relative(_ date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "now" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds < 3600 ? [.minute] : (seconds < 86_400 ? [.hour] : [.day])
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        return (formatter.string(from: seconds) ?? "")
    }

    private var accessibilityText: String {
        let remaining = costText ?? line.remainingFraction.map { UsageAlert.format($0) + " remaining" } ?? "no data"
        let provider = line.providerName ?? ""
        return "\(provider) \(line.windowLabel), \(remaining)"
    }
}

struct UsageView: View {
    @Environment(\.theme) private var theme
    @Bindable var monitor: UsageMonitor

    var body: some View {
        GeometryReader { geometry in
            let footerBlock = PanelGeometry.dividerHeight + PanelGeometry.usageFooterHeight
            VStack(spacing: 0) {
                if monitor.lines.isEmpty {
                    emptyRow
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(monitor.lines) { line in
                                UsageRow(line: line)
                            }
                        }
                    }
                    .frame(height: max(PanelGeometry.usageRowHeight, geometry.size.height - footerBlock))
                }

                Rectangle()
                    .fill(theme.dividerColor)
                    .frame(height: PanelGeometry.dividerHeight)

                footer
            }
        }
        .frame(minHeight: PanelGeometry.usageRowHeight + PanelGeometry.dividerHeight + PanelGeometry.usageFooterHeight)
    }

    private var emptyRow: some View {
        HStack(spacing: 8) {
            if monitor.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text(theme.label("Reading omp usage…"))
            } else {
                Image(systemName: "gauge.with.needle")
                    .foregroundStyle(theme.textTertiary)
                Text(theme.label(monitor.lastError == nil ? "No usage data yet" : "Usage unavailable"))
            }
            Spacer(minLength: 0)
        }
        .font(theme.bodyFont)
        .tracking(theme.labelTracking)
        .foregroundStyle(theme.textSecondary)
        .frame(height: PanelGeometry.usageRowHeight)
        .padding(.horizontal, 12)
    }

    /// Staleness and failures live here so a bad poll never blanks the numbers
    /// above, which stay on screen from the last good snapshot.
    private var footer: some View {
        HStack(spacing: 6) {
            if let error = monitor.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.severityVeryLow)
                Text(error)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(error)
            } else if monitor.isRefreshing {
                Text("Refreshing…")
            } else if let stamp = monitor.lastRefresh {
                Text("Updated \(UsageView.clock(stamp))")
            } else {
                Text("Not loaded")
            }

            Spacer(minLength: 0)

            Text("⌃R refresh")
                .foregroundStyle(theme.textTertiary)
        }
        .font(theme.captionFont)
        .foregroundStyle(theme.textSecondary)
        .frame(height: PanelGeometry.usageFooterHeight)
        .padding(.horizontal, 12)
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
