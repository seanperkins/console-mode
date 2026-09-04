import Foundation

/// Non-secret settings for the optional OpenRouter real-balance row (see
/// `OpenRouterClient`). The management key itself is a credential and lives
/// in the Keychain via `OpenRouterCredentialStore`, never here.
struct OpenRouterConfig: Sendable, Equatable {
    var isEnabled: Bool

    static let standard = OpenRouterConfig(isEnabled: false)
}

enum OpenRouterSettings {
    private enum Key {
        static let enabled = "openrouter.enabled"
    }

    static var current: OpenRouterConfig {
        get {
            let defaults = UserDefaults.standard
            var config = OpenRouterConfig.standard
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
