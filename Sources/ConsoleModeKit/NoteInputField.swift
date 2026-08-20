import AppKit
import SwiftUI

/// AppKit text field for reliable typing in a nonactivating `NSPanel`.
struct NoteInputField: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var onCommit: () -> Void
    var onFieldCreated: (Coordinator.NSTextFieldBox) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "New note…"
        field.delegate = context.coordinator

        let box = Coordinator.NSTextFieldBox(field: field)
        context.coordinator.fieldBox = box
        onFieldCreated(box)

        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NoteInputField
        var fieldBox: NSTextFieldBox?
        var lastFocusToken: Int

        init(parent: NoteInputField) {
            self.parent = parent
            self.lastFocusToken = parent.focusToken
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            return false
        }

        final class NSTextFieldBox {
            let field: NSTextField
            init(field: NSTextField) { self.field = field }
        }
    }
}
