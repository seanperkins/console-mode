import AppKit
import SwiftUI

/// AppKit input bar: reliable typing, Tab focus, and arrow keys in a nonactivating panel.
struct ConsoleInputBar: NSViewRepresentable {
    @Bindable var model: NoteListModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let field = NSTextField(string: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "New note…"
        field.delegate = context.coordinator

        let button = NSButton(
            image: Self.chevronImage(expanded: false),
            target: context.coordinator,
            action: #selector(Coordinator.toggleExpanded)
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        button.toolTip = "Expand list"

        container.addSubview(field)
        container.addSubview(button)

        field.nextKeyView = button
        button.nextKeyView = field

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            field.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -8),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
            container.heightAnchor.constraint(equalToConstant: PanelGeometry.inputHeight),
        ])

        context.coordinator.field = field
        context.coordinator.button = button
        context.coordinator.syncFromModel()

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

    private static func chevronImage(expanded: Bool) -> NSImage {
        let name = expanded ? "chevron.up" : "chevron.down"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var model: NoteListModel
        weak var field: NSTextField?
        weak var button: NSButton?
        var lastFocusToken: Int

        init(model: NoteListModel) {
            self.model = model
            self.lastFocusToken = model.focusToken
        }

        func syncFromModel() {
            guard let field else { return }
            if field.stringValue != model.draft {
                field.stringValue = model.draft
            }
            field.placeholderString = model.isEditingExistingNote ? "Edit note…" : "New note…"
            button?.image = ConsoleInputBar.chevronImage(expanded: model.expanded)
            button?.toolTip = model.expanded ? "Collapse list" : "Expand list"
        }

        @objc func toggleExpanded() {
            model.toggleExpanded()
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
            case #selector(NSResponder.insertTab(_:)):
                if let button, let window = button.window {
                    window.makeFirstResponder(button)
                }
                return true
            default:
                return false
            }
        }
    }
}
