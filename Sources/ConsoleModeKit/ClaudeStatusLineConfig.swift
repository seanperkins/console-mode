import Foundation

/// Settings for the Claude Code statusline integration (see
/// `ClaudeStatusLineInstaller`).
struct ClaudeStatusLineConfig: Sendable, Equatable {
    /// Empty means `~/.claude/settings.json`. Override for a non-default
    /// `CLAUDE_CONFIG_DIR`.
    var settingsPath: String
    /// True once the user has toggled this on — independent of the live
    /// `isInstalled` ground truth, which reflects whatever `settings.json`
    /// currently says. The gap between the two is what lets Settings tell
    /// "never turned on" apart from "was on, but something else (a hand
    /// edit, another tool) has since taken over the statusline command" —
    /// see `SettingsView.claudeStatusLineStatusText`.
    var wasEverInstalled: Bool

    static let standard = ClaudeStatusLineConfig(settingsPath: "", wasEverInstalled: false)
}

enum ClaudeStatusLineSettings {
    private enum Key {
        static let settingsPath = "claudeStatusLine.settingsPath"
        static let wasEverInstalled = "claudeStatusLine.wasEverInstalled"
    }

    static var current: ClaudeStatusLineConfig {
        get {
            let defaults = UserDefaults.standard
            var config = ClaudeStatusLineConfig.standard
            if let path = defaults.string(forKey: Key.settingsPath) {
                config.settingsPath = path
            }
            config.wasEverInstalled = defaults.bool(forKey: Key.wasEverInstalled)
            return config
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.settingsPath, forKey: Key.settingsPath)
            defaults.set(newValue.wasEverInstalled, forKey: Key.wasEverInstalled)
        }
    }
}

extension ClaudeStatusLineInstaller {
    /// Applies a settings.json path override from `ClaudeStatusLineConfig`,
    /// falling back to `.default` when the override is blank.
    static func resolved(settingsPath: String) -> ClaudeStatusLineInstaller {
        let trimmed = settingsPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .default }
        return ClaudeStatusLineInstaller(
            settingsURL: URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath),
            supportDirectory: Self.default.supportDirectory
        )
    }
}
