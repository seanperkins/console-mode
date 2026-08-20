@preconcurrency import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    @MainActor static let toggleConsole = Self(
        "toggleConsole",
        default: Shortcut(.backtick, modifiers: [.control, .shift])
    )
}
