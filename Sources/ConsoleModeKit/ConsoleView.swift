import AppKit
import SwiftUI

private struct CardBackground: View {
    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    var body: some View {
        Group {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: PanelGeometry.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: PanelGeometry.cornerRadius, style: .continuous)
                    .glassEffect(.regular, in: .rect(cornerRadius: PanelGeometry.cornerRadius))
            }
        }
    }
}

struct ConsoleView: View {
    @Bindable var model: NoteListModel
    @FocusState.Binding var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            noteSection

            Divider()
                .opacity(0.35)

            inputBar
        }
        .padding(.vertical, PanelGeometry.verticalPadding)
        .frame(width: PanelGeometry.cardWidth)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: PanelGeometry.cornerRadius, style: .continuous))
        .onChange(of: model.focusToken) { _, _ in
            inputFocused = true
        }
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
            TextField("New note…", text: $model.draft)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($inputFocused)
                .onSubmit {
                    model.commitDraft()
                }

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
