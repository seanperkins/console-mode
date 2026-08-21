import AppKit
import SwiftUI

/// Draws whatever surface the active theme asks for. Reduce Transparency always
/// wins over glass, so an accessibility setting is never overridden by a preset.
private struct CardBackground: View {
    @Environment(\.theme) private var theme

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        ZStack {
            switch theme.surface {
            case .glass where !reduceTransparency:
                shape.glassEffect(.regular, in: .rect(cornerRadius: theme.cornerRadius))
            case .glass:
                shape.fill(Color(nsColor: .windowBackgroundColor))
            case .solid(let color):
                shape.fill(color)
            }

            if theme.surfaceOverlay != .clear {
                shape.fill(theme.surfaceOverlay)
            }

            if theme.borderWidth > 0 {
                shape
                    .strokeBorder(theme.borderColor, lineWidth: theme.borderWidth)
                    .shadow(color: theme.glowColor, radius: theme.glowRadius)
            }
        }
    }
}

/// Compact tab strip. Clicking switches tabs; ⌃1/⌃2 and ⌃Tab do the same from the
/// keyboard without leaving the capture field.
struct ConsoleTabBar: View {
    @Bindable var shell: ConsoleShell

    var body: some View {
        HStack(spacing: 4) {
            ForEach(shell.tabs) { tab in
                tabButton(tab)
            }
            Spacer(minLength: 0)
            if shell.tabs.contains(.usage) {
                severityDot
            }
        }
        .padding(.horizontal, 10)
        .frame(height: PanelGeometry.tabBarHeight)
    }

    @Environment(\.theme) private var theme

    private func tabButton(_ tab: ConsoleTab) -> some View {
        let isActive = shell.activeTab == tab
        return Button {
            shell.select(tab)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(theme.label(tab.title))
                    .font(theme.tabFont)
                    .tracking(theme.labelTracking)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: max(2, theme.cornerRadius / 2), style: .continuous)
                        .fill(theme.selectionFill)
                }
            }
            .foregroundStyle(isActive ? theme.accent : theme.textSecondary)
        }
        .buttonStyle(.plain)
        .help("\(tab.title)  ⌃\(tab.commandDigit)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// Mirrors the menu bar indicator so the worst provider is visible from the
    /// notes tab without switching.
    @ViewBuilder
    private var severityDot: some View {
        let severity = shell.usage.worstSeverity
        if severity > .healthy {
            Circle()
                .fill(theme.color(for: severity))
                .frame(width: 7, height: 7)
                .shadow(color: theme.color(for: severity).opacity(0.8), radius: theme.glowRadius / 3)
                .help("Usage low — press ⌃2")
        }
    }
}

struct ConsoleView: View {
    @Bindable var shell: ConsoleShell

    private var model: NoteListModel { shell.notes }

    var body: some View {
        let theme = shell.theme
        return VStack(spacing: 0) {
            ConsoleTabBar(shell: shell)

            switch shell.activeTab {
            case .notes:
                notesTab(theme)
            case .usage:
                UsageView(monitor: shell.usage)
            }
        }
        .padding(.vertical, PanelGeometry.verticalPadding)
        .frame(width: PanelGeometry.cardWidth)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        // One injection point: every descendant reads tokens from here.
        .environment(\.theme, theme)
        .foregroundStyle(theme.textPrimary)
        .font(theme.bodyFont)
    }

    private func notesTab(_ theme: ThemeTokens) -> some View {
        VStack(spacing: 0) {
            noteSection

            Rectangle()
                .fill(theme.dividerColor)
                .frame(height: PanelGeometry.dividerHeight)

            inputBar
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        if model.expanded {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.displayNotes) { note in
                            NoteRow(
                                note: note,
                                isSelected: model.isNoteSelected(note),
                                onToggle: { model.toggleCompletion(for: note) }
                            )
                            .id(note.id)
                        }
                        if model.displayNotes.isEmpty {
                            placeholderRow
                        }
                    }
                }
                .onChange(of: model.scrollTargetID) { _, noteID in
                    guard let noteID else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(noteID, anchor: .center)
                    }
                }
                .onChange(of: model.notes.count) { _, _ in
                    scrollToNewest(proxy, animated: true)
                }
                .onAppear {
                    scrollToNewest(proxy, animated: false)
                }
            }
        } else if !model.displayNotes.isEmpty {
            // Collapsed still shows a short list: the baseline height is set by the
            // usage tab, so spend the spare rows on history rather than padding.
            VStack(spacing: 0) {
                ForEach(model.displayNotes) { note in
                    NoteRow(
                        note: note,
                        isSelected: model.isNoteSelected(note),
                        onToggle: { model.toggleCompletion(for: note) }
                    )
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 0) {
                placeholderRow
                Spacer(minLength: 0)
            }
        }
    }

    /// Keep the newest note pinned just above the input unless the user is
    /// walking the list with the arrow keys.
    private func scrollToNewest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard model.editingNoteID == nil, let newestID = model.newestNote?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(newestID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(newestID, anchor: .bottom)
        }
    }

    private var placeholderRow: some View {
        let theme = shell.theme
        return HStack {
            Image(systemName: "circle")
                .foregroundStyle(theme.textTertiary)
            // Secondary, not tertiary: this is the only text on an empty card.
            Text(theme.label("No notes yet"))
                .font(theme.bodyFont)
                .tracking(theme.labelTracking)
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .frame(height: PanelGeometry.rowHeight)
        .padding(.horizontal, 12)
    }

    private var inputBar: some View {
        ConsoleInputBar(model: model, theme: shell.theme)
            .padding(.horizontal, 12)
    }
}
