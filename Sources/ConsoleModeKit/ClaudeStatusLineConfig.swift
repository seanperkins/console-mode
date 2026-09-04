import Foundation

/// Settings for the Claude Code statusline integration (see
/// `ClaudeStatusLineInstaller`).
struct ClaudeStatusLineConfig: Sendable, Equatable {
    /// Empty means `~/.claude/settings.json`. Override for a non-default
    /// `CLAUDE_CONFIG_DIR`.
    var settingsPath: String

    static let standard = ClaudeStatusLineConfig(settingsPath: "")
}

enum ClaudeStatusLineSettings {
    private enum Key {
        static let settingsPath = "claudeStatusLine.settingsPath"
    }

    static var current: ClaudeStatusLineConfig {
        get {
            let defaults = UserDefaults.standard
            var config = ClaudeStatusLineConfig.standard
            if let path = defaults.string(forKey: Key.settingsPath) {
                config.settingsPath = path
            }
            return config
        }
        set {
            UserDefaults.standard.set(newValue.settingsPath, forKey: Key.settingsPath)
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
