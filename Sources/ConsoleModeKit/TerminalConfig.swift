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
    /// memory. `libghostty`'s real config key (`scrollback-limit`) is
    /// bytes, not lines — a line-count knob would be imprecise anyway,
    /// since actual bytes-per-line vary with terminal width and content
    /// (Ghostty's own docs call this out). Stored here as whole megabytes,
    /// the unit a Settings stepper can show meaningfully.
    var scrollbackLimitMB: Int

    static let standard = TerminalConfig(
        isEnabled: false,
        workingDirectory: "",
        shellPath: "",
        scrollbackLimitMB: 50
    )
}

enum TerminalSettings {
    private enum Key {
        static let enabled = "terminal.enabled"
        static let workingDirectory = "terminal.workingDirectory"
        static let shellPath = "terminal.shellPath"
        static let scrollbackLimitMB = "terminal.scrollbackLimitMB"
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
            if defaults.object(forKey: Key.scrollbackLimitMB) != nil {
                config.scrollbackLimitMB = max(5, defaults.integer(forKey: Key.scrollbackLimitMB))
            }
            return config
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.isEnabled, forKey: Key.enabled)
            defaults.set(newValue.workingDirectory, forKey: Key.workingDirectory)
            defaults.set(newValue.shellPath, forKey: Key.shellPath)
            defaults.set(newValue.scrollbackLimitMB, forKey: Key.scrollbackLimitMB)
        }
    }
}
