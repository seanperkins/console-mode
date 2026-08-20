import SwiftUI

struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(note.isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(note.isCompleted ? "Mark incomplete" : "Mark complete")

            Text(note.body)
                .font(.body)
                .lineLimit(1)
                .strikethrough(note.isCompleted)
                .opacity(note.isCompleted ? 0.4 : 1)

            Spacer(minLength: 8)

            if let project = note.project, !project.isEmpty {
                Text(project)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.14))
                    )
                    .opacity(note.isCompleted ? 0.4 : 1)
                    .accessibilityLabel("Project \(project)")
            }

            Text(note.createdDate.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .strikethrough(note.isCompleted)
                .opacity(note.isCompleted ? 0.4 : 1)
        }
        .frame(height: PanelGeometry.rowHeight)
        .padding(.horizontal, 12)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            }
        }
    }
}
