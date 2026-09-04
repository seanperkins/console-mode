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

/// Dropdown palette listing slash-command matches above the capture field.
final class CommandSuggestionPanel: NSView {
    static let rowHeight: CGFloat = PanelGeometry.suggestionRowHeight
    static let maxVisibleRows = PanelGeometry.suggestionMaxVisibleRows
    static let padding: CGFloat = PanelGeometry.suggestionPadding

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private var heightConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.horizontalScrollElasticity = .none

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stackView)
        scrollView.documentView = document
        addSubview(scrollView)

        heightConstraint = heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            heightConstraint!,
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding / 2),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding / 2),

            stackView.topAnchor.constraint(equalTo: document.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        theme: ThemeTokens,
        suggestions: [CommandSuggestion],
        selectedIndex: Int,
        maxHeight: CGFloat
    ) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !suggestions.isEmpty else {
            isHidden = true
            heightConstraint?.constant = 0
            return
        }

        let layout = PanelGeometry.commandSuggestionLayout(
            suggestionCount: suggestions.count,
            maxHeight: maxHeight
        )
        guard layout.visibleRows > 0 else {
            isHidden = true
            heightConstraint?.constant = 0
            return
        }

        isHidden = false
        heightConstraint?.constant = layout.height

        layer?.backgroundColor = NSColor(theme.selectionFill).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = theme.nsAccent.withAlphaComponent(0.25).cgColor

        for (index, suggestion) in suggestions.enumerated() {
            stackView.addArrangedSubview(makeRow(theme: theme, suggestion: suggestion, selected: index == selectedIndex))
        }
    }

    private func makeRow(theme: ThemeTokens, suggestion: CommandSuggestion, selected: Bool) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        if selected {
            row.layer?.backgroundColor = theme.nsAccent.withAlphaComponent(0.18).cgColor
        }

        let name = NSTextField(labelWithString: "/\(suggestion.name)")
        name.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        name.textColor = theme.nsAccent
        name.translatesAutoresizingMaskIntoConstraints = false

        let summary = NSTextField(labelWithString: suggestion.summary)
        summary.font = NSFont.systemFont(ofSize: 11)
        summary.textColor = theme.nsTextSecondary
        summary.lineBreakMode = .byTruncatingTail
        summary.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(name)
        row.addSubview(summary)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            name.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            name.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),

            summary.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 8),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -8),
            summary.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return row
    }
}

/// AppKit input bar: reliable typing, Tab focus, and arrow keys in a nonactivating panel.
/// Layout is suggestion palette (optional) above checkbox | command chrome | chevron.
struct ConsoleInputBar: NSViewRepresentable {
    @Bindable var model: NoteListModel
    /// Passed in rather than read from the environment: `updateNSView` needs the
    /// tokens to restyle AppKit views when the preset changes.
    var theme: ThemeTokens

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        let coordinator = context.coordinator

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.clipsToBounds = false

        let suggestionPanel = CommandSuggestionPanel()
        suggestionPanel.translatesAutoresizingMaskIntoConstraints = false
        suggestionPanel.isHidden = true

        let inputRow = NSView()
        inputRow.translatesAutoresizingMaskIntoConstraints = false

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

        let commandChrome = NSView()
        commandChrome.translatesAutoresizingMaskIntoConstraints = false
        commandChrome.wantsLayer = true

        let badge = NSTextField(labelWithString: "/")
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isBezeled = false
        badge.drawsBackground = false
        badge.isEditable = false
        badge.isSelectable = false
        badge.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        badge.textColor = theme.nsAccent
        badge.setContentHuggingPriority(.required, for: .horizontal)

        let field = NSTextField(string: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = theme.nsBodyFont
        field.textColor = theme.nsTextPrimary
        field.placeholderString = "New note…"
        field.delegate = coordinator

        commandChrome.addSubview(badge)
        commandChrome.addSubview(field)

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

        inputRow.addSubview(checkbox)
        inputRow.addSubview(commandChrome)
        inputRow.addSubview(chevron)

        container.addSubview(suggestionPanel)
        container.addSubview(inputRow)

        checkbox.nextKeyView = field
        field.nextKeyView = chevron
        chevron.nextKeyView = checkbox

        checkbox.onMoveRight = { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }
        chevron.onMoveLeft = { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }

        NSLayoutConstraint.activate([
            suggestionPanel.topAnchor.constraint(equalTo: container.topAnchor),
            suggestionPanel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            suggestionPanel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            inputRow.topAnchor.constraint(equalTo: suggestionPanel.bottomAnchor),
            inputRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inputRow.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            inputRow.heightAnchor.constraint(equalToConstant: PanelGeometry.inputHeight),

            checkbox.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor),
            checkbox.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 20),
            checkbox.heightAnchor.constraint(equalToConstant: 20),

            commandChrome.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            commandChrome.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            commandChrome.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            commandChrome.heightAnchor.constraint(equalToConstant: 24),

            badge.leadingAnchor.constraint(equalTo: commandChrome.leadingAnchor, constant: 6),
            badge.centerYAnchor.constraint(equalTo: commandChrome.centerYAnchor),

            field.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: commandChrome.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: commandChrome.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 24),
            chevron.heightAnchor.constraint(equalToConstant: 24),
        ])

        coordinator.checkbox = checkbox
        coordinator.commandChrome = commandChrome
        coordinator.badge = badge
        coordinator.field = field
        coordinator.chevron = chevron
        coordinator.suggestionPanel = suggestionPanel
        coordinator.syncFromModel()

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.model = model
        context.coordinator.applyTheme(theme)
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
        weak var commandChrome: NSView?
        weak var badge: NSTextField?
        weak var field: NSTextField?
        weak var chevron: FocusableButton?
        weak var suggestionPanel: CommandSuggestionPanel?
        var lastFocusToken: Int
        private var theme: ThemeTokens = .system
        private var suggestionSelectionIndex = 0
        private var lastSuggestionSignature = ""

        func applyTheme(_ tokens: ThemeTokens) {
            guard tokens != theme else { return }
            theme = tokens
            chevron?.contentTintColor = tokens.nsTextSecondary
            syncFromModel()
        }

        func applyCaretColor() {
            guard let editor = field?.currentEditor() as? NSTextView else { return }
            editor.insertionPointColor = theme.nsAccent
        }

        init(model: NoteListModel) {
            self.model = model
            self.lastFocusToken = model.focusToken
        }

        private var suggestions: [CommandSuggestion] {
            ConsoleInput.commandSuggestions(for: model.draft)
        }

        private var showsSuggestions: Bool {
            !suggestions.isEmpty
        }

        private func syncSuggestionSelection() {
            let signature = suggestions.map(\.name).joined(separator: "\u{1f}")
            if signature != lastSuggestionSignature {
                lastSuggestionSignature = signature
                suggestionSelectionIndex = 0
            }
            if suggestionSelectionIndex >= suggestions.count {
                suggestionSelectionIndex = max(0, suggestions.count - 1)
            }
        }

        func syncFromModel() {
            applyCaretColor()
            if let field, field.stringValue != model.draft {
                field.stringValue = model.draft
            }

            let commandMode = ConsoleInput.isCommandDraft(model.draft)
            applyInputMode(commandMode)
            syncSuggestionSelection()
            suggestionPanel?.update(
                theme: theme,
                suggestions: suggestions,
                selectedIndex: suggestionSelectionIndex,
                maxHeight: model.commandSuggestionOverlayMaxHeight
            )

            if let status = model.statusMessage {
                field?.placeholderString = status
            } else if commandMode {
                if showsSuggestions {
                    field?.placeholderString = "Tab to complete · ↑↓ to browse"
                } else {
                    field?.placeholderString = ConsoleInput.commandPlaceholder(for: model.draft)
                }
            } else {
                field?.placeholderString = model.isEditingExistingNote ? "Edit note…" : "New note…"
            }

            chevron?.image = ConsoleInputBar.chevronImage(expanded: model.expanded)
            chevron?.toolTip = model.expanded ? "Collapse list" : "Expand list"

            let editing = model.isEditingExistingNote
            checkbox?.image = ConsoleInputBar.checkboxImage(completed: model.isEditingNoteCompleted)
            checkbox?.contentTintColor = editing ? theme.nsAccent : theme.nsTextSecondary.withAlphaComponent(0.5)
            checkbox?.toolTip = editing
                ? (model.isEditingNoteCompleted ? "Mark note incomplete" : "Mark note complete")
                : "Press ↑ to select a note, then toggle it here"
        }

        private func applyInputMode(_ commandMode: Bool) {
            badge?.stringValue = theme.promptGlyph ?? "/"
            badge?.textColor = theme.nsAccent
            badge?.isHidden = !commandMode

            if commandMode {
                field?.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
                field?.textColor = theme.nsAccent
                commandChrome?.layer?.cornerRadius = 6
                commandChrome?.layer?.backgroundColor = NSColor(theme.selectionFill).cgColor
                commandChrome?.layer?.borderWidth = 1
                commandChrome?.layer?.borderColor = theme.nsAccent.withAlphaComponent(0.35).cgColor
            } else {
                field?.font = theme.nsBodyFont
                field?.textColor = theme.nsTextPrimary
                commandChrome?.layer?.backgroundColor = NSColor.clear.cgColor
                commandChrome?.layer?.borderWidth = 0
            }
        }

        private func setDraft(_ text: String) {
            model.draft = text
            field?.stringValue = text
            syncFromModel()
        }

        private func acceptSuggestion(at index: Int) {
            guard suggestions.indices.contains(index) else { return }
            setDraft(ConsoleInput.applyCommandSuggestion(suggestions[index], to: model.draft))
        }

        private func acceptSelectedSuggestion() {
            guard showsSuggestions else { return }
            acceptSuggestion(at: suggestionSelectionIndex)
        }

        private func acceptCommonPrefixIfPossible(textView: NSTextView) -> Bool {
            if suggestions.count == 1, isCaretAtEnd(textView) {
                acceptSuggestion(at: 0)
                return true
            }
            if let completed = ConsoleInput.applyCommonCommandPrefix(from: model.draft) {
                setDraft(completed)
                return true
            }
            return false
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
            if model.statusMessage != nil {
                model.statusMessage = nil
            }
            syncFromModel()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                model.commitDraft()
                syncFromModel()
                return true
            case #selector(NSResponder.moveUp(_:)):
                if showsSuggestions {
                    suggestionSelectionIndex = max(0, suggestionSelectionIndex - 1)
                    syncFromModel()
                    return true
                }
                model.navigateToOlderNote()
                syncFromModel()
                return true
            case #selector(NSResponder.moveDown(_:)):
                if showsSuggestions {
                    suggestionSelectionIndex = min(suggestions.count - 1, suggestionSelectionIndex + 1)
                    syncFromModel()
                    return true
                }
                model.navigateToNewerNote()
                syncFromModel()
                return true
            case #selector(NSResponder.moveLeft(_:)):
                guard isCaretAtStart(textView) else { return false }
                focus(checkbox)
                return true
            case #selector(NSResponder.moveRight(_:)):
                if showsSuggestions, acceptCommonPrefixIfPossible(textView: textView) {
                    return true
                }
                return false
            case #selector(NSResponder.insertTab(_:)):
                if showsSuggestions {
                    acceptSelectedSuggestion()
                    return true
                }
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

        private func isCaretAtEnd(_ textView: NSTextView) -> Bool {
            let range = textView.selectedRange()
            return range.location == textView.string.count && range.length == 0
        }

        private func focus(_ view: NSView?) {
            guard let view, let window = view.window else { return }
            window.makeFirstResponder(view)
        }
    }
}
