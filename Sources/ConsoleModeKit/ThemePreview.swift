import SwiftUI

/// A miniature of the real card so a preset can be judged in Settings without
/// summoning the panel. Built from the same tokens the panel uses.
struct ThemePreview: View {
    let tokens: ThemeTokens

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Rectangle()
                .fill(tokens.dividerColor)
                .frame(height: 1)
            sampleRow(name: "Codex", fraction: 0.11, severity: .low)
            sampleRow(name: "Anthropic", fraction: 0.81, severity: .healthy)
            inputLine
        }
        .padding(10)
        .background {
            let shape = RoundedRectangle(cornerRadius: tokens.cornerRadius, style: .continuous)
            ZStack {
                switch tokens.surface {
                case .glass:
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                case .solid(let color):
                    shape.fill(color)
                }
                if tokens.surfaceOverlay != .clear { shape.fill(tokens.surfaceOverlay) }
                if tokens.borderWidth > 0 {
                    shape.strokeBorder(tokens.borderColor, lineWidth: tokens.borderWidth)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.cornerRadius, style: .continuous))
        .shadow(color: tokens.glowColor, radius: tokens.glowRadius / 2)
        .frame(height: 116)
        .accessibilityHidden(true)
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ForEach(ConsoleTab.allCases) { tab in
                Text(tokens.label(tab.title))
                    .font(.system(size: 9, weight: .semibold, design: tokens.fontDesign))
                    .tracking(tokens.labelTracking)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        if tab == .usage {
                            RoundedRectangle(cornerRadius: 3).fill(tokens.selectionFill)
                        }
                    }
                    .foregroundStyle(tab == .usage ? tokens.accent : tokens.textSecondary)
            }
            Spacer()
        }
        .padding(.bottom, 6)
    }

    private func sampleRow(name: String, fraction: Double, severity: UsageSeverity) -> some View {
        HStack(spacing: 6) {
            Text(tokens.label(name))
                .font(.system(size: 9, design: tokens.fontDesign))
                .tracking(tokens.labelTracking)
                .foregroundStyle(tokens.textPrimary)
                .frame(width: 62, alignment: .leading)

            miniMeter(used: 1 - fraction, tint: tokens.color(for: severity))

            Text("\(Int(fraction * 100))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(tokens.color(for: severity))
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func miniMeter(used: Double, tint: Color) -> some View {
        switch tokens.meterStyle {
        case .capsule:
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(tokens.meterTrack)
                    Capsule().fill(tint).frame(width: max(2, geometry.size.width * used))
                }
            }
            .frame(height: 5)

        case .segmented(let count):
            let cells = min(count, 12)
            let lit = Int((used * Double(cells)).rounded(.up))
            HStack(spacing: 1.5) {
                ForEach(0..<cells, id: \.self) { index in
                    Rectangle()
                        .fill(index < lit ? tint : tokens.meterTrack)
                        .frame(height: 7)
                }
            }
        }
    }

    private var inputLine: some View {
        HStack(spacing: 5) {
            if let glyph = tokens.promptGlyph {
                Text(glyph)
                    .font(.system(size: 10, weight: .bold, design: tokens.fontDesign))
                    .foregroundStyle(tokens.accent)
            }
            Text(tokens.label("New note…"))
                .font(.system(size: 9, design: tokens.fontDesign))
                .tracking(tokens.labelTracking)
                .foregroundStyle(tokens.textTertiary)
            Spacer()
        }
        .padding(.top, 6)
    }
}
