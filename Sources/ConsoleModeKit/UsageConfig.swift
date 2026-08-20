import Foundation

/// Settings for the usage tab and its threshold alerts.
struct UsageConfig: Sendable, Equatable {
    var isEnabled: Bool
    var alertsEnabled: Bool
    /// Empty means "probe the usual install paths, then ask the login shell".
    var ompPath: String
    /// The broker caches usage reports for 5 minutes, so polling faster only
    /// re-reads the same numbers.
    var pollMinutes: Int
    /// How long the transient alert panel stays up.
    var alertSeconds: Double

    static let standard = UsageConfig(
        isEnabled: true,
        alertsEnabled: true,
        ompPath: "",
        pollMinutes: 5,
        alertSeconds: 6
    )
}

enum UsageSettings {
    private enum Key {
        static let enabled = "usage.enabled"
        static let alerts = "usage.alertsEnabled"
        static let ompPath = "usage.ompPath"
        static let pollMinutes = "usage.pollMinutes"
        static let alertSeconds = "usage.alertSeconds"
    }

    static var current: UsageConfig {
        get {
            let defaults = UserDefaults.standard
            var config = UsageConfig.standard
            if defaults.object(forKey: Key.enabled) != nil {
                config.isEnabled = defaults.bool(forKey: Key.enabled)
            }
            if defaults.object(forKey: Key.alerts) != nil {
                config.alertsEnabled = defaults.bool(forKey: Key.alerts)
            }
            if let path = defaults.string(forKey: Key.ompPath) {
                config.ompPath = path
            }
            if defaults.object(forKey: Key.pollMinutes) != nil {
                config.pollMinutes = max(1, defaults.integer(forKey: Key.pollMinutes))
            }
            if defaults.object(forKey: Key.alertSeconds) != nil {
                config.alertSeconds = max(1, defaults.double(forKey: Key.alertSeconds))
            }
            return config
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.isEnabled, forKey: Key.enabled)
            defaults.set(newValue.alertsEnabled, forKey: Key.alerts)
            defaults.set(newValue.ompPath, forKey: Key.ompPath)
            defaults.set(newValue.pollMinutes, forKey: Key.pollMinutes)
            defaults.set(newValue.alertSeconds, forKey: Key.alertSeconds)
        }
    }
}
