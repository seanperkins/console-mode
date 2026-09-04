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
    /// - Parameter terminalActive: `true` once a terminal tab holds a live
    ///   PTY session and is the active tab. While it is, this binding claims
    ///   only the explicit tab-cycle chord (⌃Tab) and lets every other
    ///   Control/Command chord — Esc for vim's normal mode, ⌃R for
    ///   reverse-i-search, ⌃1/⌃2 as a shell tool might bind them — reach the
    ///   PTY instead of being swallowed here. Defaults to `false` so every
    ///   existing call site (and the Notes/Usage tabs) is unaffected.
    static func action(for event: NSEvent, terminalActive: Bool = false) -> ConsoleKeyAction? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == escapeKeyCode, flags.isEmpty {
            return terminalActive ? nil : .dismiss
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

        guard !terminalActive else { return nil }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "1": return .selectTab(.notes)
        case "2": return .selectTab(.usage)
        case "r": return .refreshUsage
        default: return nil
        }
    }
}
