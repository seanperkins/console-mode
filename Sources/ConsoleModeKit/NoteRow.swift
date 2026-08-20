import SwiftUI

struct NoteRow: View {
    let note: Note
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

            Text(note.createdDate.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .strikethrough(note.isCompleted)
                .opacity(note.isCompleted ? 0.4 : 1)
        }
        .frame(height: PanelGeometry.rowHeight)
        .padding(.horizontal, 12)
    }
}
