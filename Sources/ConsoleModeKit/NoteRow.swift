import SwiftUI

struct NoteRow: View {
    @Environment(\.theme) private var theme
    let note: Note
    let isSelected: Bool
    let showsDetail: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactRow
            if showsDetail {
                detailSection
            }
        }
        .frame(height: rowHeight, alignment: .top)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: max(2, theme.cornerRadius / 2), style: .continuous)
                    .fill(theme.selectionFill)
            }
        }
    }

    private var rowHeight: CGFloat {
        PanelGeometry.rowHeight + (showsDetail ? NoteDetailLayout.detailHeight(for: note) : 0)
    }

    private var compactRow: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(note.isCompleted ? theme.accent : theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(note.isCompleted ? "Mark incomplete" : "Mark complete")

            if note.isActionable {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .help(note.actionSummary ?? "Actionable")
            }

            HStack(spacing: 4) {
                Text(note.body)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(showsDetail ? 1 : 1)
                    .strikethrough(note.isCompleted)
                    .opacity(note.isCompleted ? 0.4 : 1)
                    .layoutPriority(1)

                if !showsDetail, note.isActionable, let summary = note.actionSummary {
                    Text("· \(summary)")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                        .opacity(note.isCompleted ? 0.4 : 1)
                }
            }

            Spacer(minLength: 8)

            if !showsDetail, let project = note.project, !project.isEmpty {
                projectCapsule(project)
            }
            if note.hasReminder, let remindDate = note.remindDate {
                Image(systemName: "bell.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .help("Reminder \(remindDate.formatted(date: .abbreviated, time: .shortened))")
            }

            Text(note.createdDate.formatted(date: .omitted, time: .shortened))
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
                .strikethrough(note.isCompleted)
                .opacity(note.isCompleted ? 0.4 : 1)
        }
        .frame(height: PanelGeometry.rowHeight)
        .padding(.horizontal, 12)
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.body)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .strikethrough(note.isCompleted)
                .opacity(note.isCompleted ? 0.4 : 1)
                .lineLimit(NoteDetailLayout.maxBodyLines)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(NoteDetailLayout.metadata(for: note).enumerated()), id: \.offset) { _, item in
                switch item {
                case .project(let slug):
                    projectCapsule(slug)
                default:
                    Text(theme.label(item.label))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .padding(.leading, 36)
        .padding(.trailing, 12)
        .padding(.bottom, NoteDetailLayout.verticalPadding)
    }

    private func projectCapsule(_ project: String) -> some View {
        Text(theme.label(project))
            .font(theme.captionFont)
            .tracking(theme.labelTracking)
            .foregroundStyle(theme.accent)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.selectionFill)
            )
            .opacity(note.isCompleted ? 0.4 : 1)
            .accessibilityLabel("Project \(project)")
    }
}
