import AppKit
import SwiftUI

private struct CardChrome: View {
    var body: some View {
        RoundedRectangle(cornerRadius: PanelGeometry.cornerRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
    }
}

struct ConsoleView: View {
    @Bindable var model: NoteListModel
    var onInputFieldCreated: (NoteInputField.Coordinator.NSTextFieldBox) -> Void

    var body: some View {
        VStack(spacing: 0) {
            noteSection

            Divider()
                .opacity(0.35)

            inputBar
        }
        .padding(.vertical, PanelGeometry.verticalPadding)
        .frame(width: PanelGeometry.cardWidth)
        .background(CardChrome())
        .clipShape(RoundedRectangle(cornerRadius: PanelGeometry.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var noteSection: some View {
        if model.expanded {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.notes) { note in
                        NoteRow(note: note) {
                            model.toggleCompletion(for: note)
                        }
                    }
                    if model.notes.isEmpty {
                        placeholderRow
                    }
                }
            }
        } else if let note = model.notes.first {
            NoteRow(note: note) {
                model.toggleCompletion(for: note)
            }
        } else {
            placeholderRow
        }
    }

    private var placeholderRow: some View {
        HStack {
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
            Text("No notes yet")
                .font(.body)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(height: PanelGeometry.rowHeight)
        .padding(.horizontal, 12)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            NoteInputField(
                text: $model.draft,
                focusToken: model.focusToken,
                onCommit: { model.commitDraft() },
                onFieldCreated: onInputFieldCreated
            )
            .frame(height: PanelGeometry.inputHeight)

            Button {
                model.toggleExpanded()
            } label: {
                Image(systemName: model.expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(model.expanded ? "Collapse list" : "Expand list")
        }
        .frame(height: PanelGeometry.inputHeight)
        .padding(.horizontal, 12)
    }
}
