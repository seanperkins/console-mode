import Foundation

/// Settings for the terminal tab. Mirrors `UsageConfig`'s shape and storage
/// pattern exactly, so a change to one convention updates both consistently.
struct TerminalConfig: Sendable, Equatable {
    var isEnabled: Bool
    /// Empty means "the user's home directory", resolved at spawn time, not
    /// stored as an absolute path here (a moved home directory should not
    /// strand an old setting).
    var workingDirectory: String
    /// Empty means "the user's login shell" (`$SHELL`, resolved at spawn
    /// time), matching how a real terminal picks a shell.
    var shellPath: String
    /// Scrollback is bounded so a session left open for days keeps flat
    /// memory. `libghostty` enforces the actual cap; this is the number
    /// handed to it.
    var scrollbackLines: Int

    static let standard = TerminalConfig(
        isEnabled: false,
        workingDirectory: "",
        shellPath: "",
        scrollbackLines: 5000
    )
}

enum TerminalSettings {
    private enum Key {
        static let enabled = "terminal.enabled"
        static let workingDirectory = "terminal.workingDirectory"
        static let shellPath = "terminal.shellPath"
        static let scrollbackLines = "terminal.scrollbackLines"
    }

    static var current: TerminalConfig {
        get {
            let defaults = UserDefaults.standard
            var config = TerminalConfig.standard
            if defaults.object(forKey: Key.enabled) != nil {
                config.isEnabled = defaults.bool(forKey: Key.enabled)
            }
            if let directory = defaults.string(forKey: Key.workingDirectory) {
                config.workingDirectory = directory
            }
            if let shell = defaults.string(forKey: Key.shellPath) {
                config.shellPath = shell
            }
            if defaults.object(forKey: Key.scrollbackLines) != nil {
                config.scrollbackLines = max(500, defaults.integer(forKey: Key.scrollbackLines))
            }
            return config
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.isEnabled, forKey: Key.enabled)
            defaults.set(newValue.workingDirectory, forKey: Key.workingDirectory)
            defaults.set(newValue.shellPath, forKey: Key.shellPath)
            defaults.set(newValue.scrollbackLines, forKey: Key.scrollbackLines)
        }
    }
}
