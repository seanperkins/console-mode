import SwiftUI

struct NoteRow: View {
    @Environment(\.theme) private var theme
    let note: Note
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(note.isCompleted ? theme.accent : theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(note.isCompleted ? "Mark incomplete" : "Mark complete")

            Text(note.body)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .strikethrough(note.isCompleted)
                .opacity(note.isCompleted ? 0.4 : 1)

            Spacer(minLength: 8)

            if let project = note.project, !project.isEmpty {
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

            Text(note.createdDate.formatted(date: .omitted, time: .shortened))
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
                .strikethrough(note.isCompleted)
                .opacity(note.isCompleted ? 0.4 : 1)
        }
        .frame(height: PanelGeometry.rowHeight)
        .padding(.horizontal, 12)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: max(2, theme.cornerRadius / 2), style: .continuous)
                    .fill(theme.selectionFill)
            }
        }
    }
}
