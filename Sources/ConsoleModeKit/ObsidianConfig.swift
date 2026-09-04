import Foundation

struct ObsidianConfig: Sendable, Equatable {
    var isEnabled: Bool
    /// Absolute path to the Obsidian vault root.
    var vaultPath: String
    /// Folder inside the vault for daily notes, e.g. "Daily". Empty = vault root.
    var dailyFolder: String

    static let standard = ObsidianConfig(
        isEnabled: false,
        vaultPath: "",
        dailyFolder: ""
    )
}

enum ObsidianSettings {
    private enum Key {
        static let enabled = "obsidian.enabled"
        static let vaultPath = "obsidian.vaultPath"
        static let dailyFolder = "obsidian.dailyFolder"
    }

    static var current: ObsidianConfig {
        get {
            let defaults = UserDefaults.standard
            var config = ObsidianConfig.standard
            if defaults.object(forKey: Key.enabled) != nil {
                config.isEnabled = defaults.bool(forKey: Key.enabled)
            }
            if let path = defaults.string(forKey: Key.vaultPath) {
                config.vaultPath = path
            }
            if let folder = defaults.string(forKey: Key.dailyFolder) {
                config.dailyFolder = folder
            }
            return config
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.isEnabled, forKey: Key.enabled)
            defaults.set(newValue.vaultPath, forKey: Key.vaultPath)
            defaults.set(newValue.dailyFolder, forKey: Key.dailyFolder)
        }
    }
}
