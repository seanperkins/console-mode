import Foundation

/// Non-secret settings for the optional DeepSeek real-balance row (see
/// `DeepSeekClient`). The API key itself is a credential and lives in the
/// Keychain via `DeepSeekCredentialStore`, never here.
struct DeepSeekConfig: Sendable, Equatable {
    var isEnabled: Bool

    static let standard = DeepSeekConfig(isEnabled: false)
}

enum DeepSeekSettings {
    private enum Key {
        static let enabled = "deepseek.enabled"
    }

    static var current: DeepSeekConfig {
        get {
            let defaults = UserDefaults.standard
            var config = DeepSeekConfig.standard
            if defaults.object(forKey: Key.enabled) != nil {
                config.isEnabled = defaults.bool(forKey: Key.enabled)
            }
            return config
        }
        set {
            UserDefaults.standard.set(newValue.isEnabled, forKey: Key.enabled)
        }
    }
}
