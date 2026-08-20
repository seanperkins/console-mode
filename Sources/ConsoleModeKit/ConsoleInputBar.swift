import AppKit
import SwiftUI

/// NSButton refuses key focus unless Full Keyboard Access is on, so Tab would skip
/// these controls on a default Mac. This subclass opts into the key view loop always
/// and routes horizontal arrows back out to its neighbours.
final class FocusableButton: NSButton {
    var onMoveLeft: (() -> Void)?
    var onMoveRight: (() -> Void)?

    override var canBecomeKeyView: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "\t":
            window?.selectNextKeyView(nil)
        case "\u{19}": // Shift-Tab
            window?.selectPreviousKeyView(nil)
        case " ", "\r":
            performClick(nil)
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!):
            onMoveLeft?()
        case String(UnicodeScalar(NSRightArrowFunctionKey)!):
            onMoveRight?()
        default:
            super.keyDown(with: event)
        }
    }
}

/// AppKit input bar: reliable typing, Tab focus, and arrow keys in a nonactivating panel.
/// Layout is checkbox | text field | expand chevron.
struct ConsoleInputBar: NSViewRepresentable {
    @Bindable var model: NoteListModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        let coordinator = context.coordinator

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let checkbox = FocusableButton(
            image: Self.checkboxImage(completed: false),
            target: coordinator,
            action: #selector(Coordinator.toggleCompletion)
        )
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.isBordered = false
        checkbox.bezelStyle = .regularSquare
        checkbox.imagePosition = .imageOnly
        checkbox.setButtonType(.momentaryChange)

        let field = NSTextField(string: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "New note…"
        field.delegate = coordinator

        let chevron = FocusableButton(
            image: Self.chevronImage(expanded: false),
            target: coordinator,
            action: #selector(Coordinator.toggleExpanded)
        )
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.isBordered = false
        chevron.bezelStyle = .regularSquare
        chevron.imagePosition = .imageOnly
        chevron.setButtonType(.momentaryChange)
        chevron.toolTip = "Expand list"

        container.addSubview(checkbox)
        container.addSubview(field)
        container.addSubview(chevron)

        // Left-to-right key view loop, wrapping at both ends.
        checkbox.nextKeyView = field
        field.nextKeyView = chevron
        chevron.nextKeyView = checkbox

        // Horizontal arrows hop between the controls.
        checkbox.onMoveRight = { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }
        chevron.onMoveLeft = { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            checkbox.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 20),
            checkbox.heightAnchor.constraint(equalToConstant: 20),

            field.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            field.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),

            chevron.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 24),
            chevron.heightAnchor.constraint(equalToConstant: 24),

            container.heightAnchor.constraint(equalToConstant: PanelGeometry.inputHeight),
        ])

        coordinator.checkbox = checkbox
        coordinator.field = field
        coordinator.chevron = chevron
        coordinator.syncFromModel()

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.model = model
        context.coordinator.syncFromModel()

        if context.coordinator.lastFocusToken != model.focusToken {
            context.coordinator.lastFocusToken = model.focusToken
            DispatchQueue.main.async {
                context.coordinator.field?.window?.makeFirstResponder(context.coordinator.field)
            }
        }
    }

    private static func symbol(_ name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
    }

    private static func chevronImage(expanded: Bool) -> NSImage {
        symbol(expanded ? "chevron.up" : "chevron.down")
    }

    private static func checkboxImage(completed: Bool) -> NSImage {
        symbol(completed ? "checkmark.circle.fill" : "circle")
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var model: NoteListModel
        weak var checkbox: FocusableButton?
        weak var field: NSTextField?
        weak var chevron: FocusableButton?
        var lastFocusToken: Int

        init(model: NoteListModel) {
            self.model = model
            self.lastFocusToken = model.focusToken
        }

        func syncFromModel() {
            if let field, field.stringValue != model.draft {
                field.stringValue = model.draft
            }
            field?.placeholderString = model.isEditingExistingNote ? "Edit note…" : "New note…"

            chevron?.image = ConsoleInputBar.chevronImage(expanded: model.expanded)
            chevron?.toolTip = model.expanded ? "Collapse list" : "Expand list"

            // Dimmed while composing a new note: there is nothing to complete yet.
            let editing = model.isEditingExistingNote
            checkbox?.image = ConsoleInputBar.checkboxImage(completed: model.isEditingNoteCompleted)
            checkbox?.contentTintColor = editing ? nil : .tertiaryLabelColor
            checkbox?.toolTip = editing
                ? (model.isEditingNoteCompleted ? "Mark note incomplete" : "Mark note complete")
                : "Press ↑ to select a note, then toggle it here"
        }

        @objc func toggleExpanded() {
            model.toggleExpanded()
            syncFromModel()
        }

        @objc func toggleCompletion() {
            model.toggleCompletionForEditingNote()
            syncFromModel()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.draft = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                model.commitDraft()
                syncFromModel()
                return true
            case #selector(NSResponder.moveUp(_:)):
                model.navigateToOlderNote()
                syncFromModel()
                return true
            case #selector(NSResponder.moveDown(_:)):
                model.navigateToNewerNote()
                syncFromModel()
                return true
            case #selector(NSResponder.moveLeft(_:)):
                // Only leave the field when the caret is already at the far left.
                guard isCaretAtStart(textView) else { return false }
                focus(checkbox)
                return true
            case #selector(NSResponder.insertTab(_:)):
                focus(chevron)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                focus(checkbox)
                return true
            default:
                return false
            }
        }

        private func isCaretAtStart(_ textView: NSTextView) -> Bool {
            let range = textView.selectedRange()
            return range.location == 0 && range.length == 0
        }

        private func focus(_ view: NSView?) {
            guard let view, let window = view.window else { return }
            window.makeFirstResponder(view)
        }
    }
}
