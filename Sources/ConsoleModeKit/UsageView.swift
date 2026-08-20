import AppKit
import SwiftUI

/// One provider on one line: name, bar, remaining, window and reset.
///
/// The tightest window is the only one shown, because that is the limit that
/// will actually stop work. The full breakdown is in the row tooltip.
struct UsageRow: View {
    @Environment(\.theme) private var theme
    let provider: ProviderUsage

    private var tint: Color { theme.color(for: provider.severity) }

    var body: some View {
        HStack(spacing: 10) {
            Text(theme.label(provider.displayName))
                .font(theme.bodyFont)
                .tracking(theme.labelTracking)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)

            meter
                .frame(width: 130)

            Text(remainingText)
                .font(theme.meterFont)
                .foregroundStyle(provider.remainingFraction == nil ? theme.textTertiary : tint)
                // Monospaced "100% left" needs the room, and must never wrap.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 82, alignment: .trailing)

            Text(windowText)
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)

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
        let used = provider.remainingFraction.map { 1 - $0 }
        switch theme.meterStyle {
        case .capsule:
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.meterTrack)
                    if let used {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(2, geometry.size.width * used))
                    }
                }
            }
            .frame(height: 6)

        case .segmented(let count):
            // Terminal-style cells: the count of lit blocks is readable at a glance
            // without reading the number.
            let lit = used.map { Int(($0 * Double(count)).rounded(.up)) } ?? 0
            HStack(spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    Rectangle()
                        .fill(index < lit ? tint : theme.meterTrack)
                        .frame(height: 10)
                }
            }
            .shadow(color: tint.opacity(theme.glowRadius > 0 ? 0.7 : 0), radius: 3)
        }
    }

    private var remainingText: String {
        guard let fraction = provider.remainingFraction else { return "—" }
        return UsageAlert.format(fraction) + " left"
    }

    private var windowText: String {
        provider.limit?.windowLabel ?? ""
    }

    private var resetText: String {
        if provider.limit?.isExhausted == true, provider.limit?.window?.resetDate == nil {
            return "exhausted"
        }
        guard let reset = provider.limit?.window?.resetDate else { return "" }
        return "resets " + UsageRow.relative(reset)
    }

    /// Short relative form: the exact minute rarely matters, the day does.
    static func relative(_ date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "now" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds < 3600 ? [.minute] : (seconds < 86_400 ? [.hour] : [.day])
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        return "in " + (formatter.string(from: seconds) ?? "")
    }

    private var tooltip: String {
        provider.allLimits.map { limit in
            let remaining = limit.remainingFraction.map { UsageAlert.format($0) + " left" } ?? "no data"
            let reset = limit.window?.resetDate.map { " · resets " + UsageRow.relative($0) } ?? ""
            let flag = limit.isExhausted ? " · exhausted" : ""
            return "\(limit.windowLabel): \(remaining)\(reset)\(flag)"
        }
        .joined(separator: "\n")
    }

    private var accessibilityText: String {
        let remaining = provider.remainingFraction.map { UsageAlert.format($0) + " remaining" } ?? "no data"
        return "\(provider.displayName), \(windowText), \(remaining)"
    }
}

struct UsageView: View {
    @Environment(\.theme) private var theme
    @Bindable var monitor: UsageMonitor

    var body: some View {
        VStack(spacing: 0) {
            if monitor.rollup.isEmpty {
                emptyRow
            } else {
                ForEach(monitor.rollup) { provider in
                    UsageRow(provider: provider)
                }
            }

            Rectangle()
                .fill(theme.dividerColor)
                .frame(height: PanelGeometry.dividerHeight)

            footer
        }
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

            Text("⌘R refresh")
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
