import AppKit

enum ConsoleKeyAction: Equatable, Sendable {
    case selectTab(ConsoleTab)
    case cycleTab
    case refreshUsage
    case dismiss
}

/// Maps a key event to a console action.
///
/// Kept pure and separate from AppKit dispatch so the bindings can be tested
/// directly. It is consulted from a local `NSEvent` monitor rather than
/// `performKeyEquivalent`, because AppKit only offers Command-modified events as
/// key equivalents — a Control-modified key would go straight to the focused
/// text field and never reach the panel.
enum ConsoleKeyBinding {
    static let escapeKeyCode: UInt16 = 53
    static let tabKeyCode: UInt16 = 48

    /// Control is the primary modifier: the summon chord is ⌃⇧`, so that hand is
    /// already holding Control when the panel appears. Command is accepted too,
    /// for anyone who reaches for it out of habit.
    ///
    /// ⌘` is deliberately absent — macOS binds it to "Move focus to next window
    /// in application", which is enabled by default.
    static func action(for event: NSEvent) -> ConsoleKeyAction? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == escapeKeyCode, flags.isEmpty {
            return .dismiss
        }

        let hasControl = flags.contains(.control)
        let hasCommand = flags.contains(.command)
        guard hasControl || hasCommand else { return nil }
        // Ignore chords carrying extra modifiers so ⌃⇧` (the summon hotkey) and
        // friends are never mistaken for a tab switch.
        guard !flags.contains(.option), !flags.contains(.shift) else { return nil }

        if event.keyCode == tabKeyCode, hasControl {
            return .cycleTab
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "1": return .selectTab(.notes)
        case "2": return .selectTab(.usage)
        case "r": return .refreshUsage
        default: return nil
        }
    }
}
