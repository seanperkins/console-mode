import Foundation

/// Settings for batch actionability review via `omp`.
struct ActionReviewConfig: Sendable, Equatable {
    var isEnabled: Bool
    /// Passed to `omp --model=` (fuzzy match, e.g. "opus" or "claude-opus-5").
    var model: String
    /// How many unreviewed notes `/analyze` processes per run.
    var batchSize: Int
    var timeout: TimeInterval
    /// Blank uses the same auto-detect path as LLM usage settings.
    var ompPath: String

    static let standard = ActionReviewConfig(
        isEnabled: true,
        model: "claude-opus-5",
        batchSize: 15,
        timeout: 180,
        ompPath: ""
    )
}

enum ActionReviewSettings {
    private enum Key {
        static let enabled = "actionReview.enabled"
        static let model = "actionReview.model"
        static let batchSize = "actionReview.batchSize"
        static let ompPath = "actionReview.ompPath"
    }

    static var current: ActionReviewConfig {
        get {
            let defaults = UserDefaults.standard
            var config = ActionReviewConfig.standard
            if defaults.object(forKey: Key.enabled) != nil {
                config.isEnabled = defaults.bool(forKey: Key.enabled)
            }
            if let model = defaults.string(forKey: Key.model), !model.isEmpty {
                config.model = model
            }
            if defaults.object(forKey: Key.batchSize) != nil {
                let size = defaults.integer(forKey: Key.batchSize)
                if size > 0 { config.batchSize = size }
            }
            if let path = defaults.string(forKey: Key.ompPath) {
                config.ompPath = path
            }
            return config
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.isEnabled, forKey: Key.enabled)
            defaults.set(newValue.model, forKey: Key.model)
            defaults.set(newValue.batchSize, forKey: Key.batchSize)
            defaults.set(newValue.ompPath, forKey: Key.ompPath)
        }
    }

    /// Action review falls back to the usage tab's omp path when its own field is blank.
    static func resolvedOmpPath(from config: ActionReviewConfig) -> String {
        let trimmed = config.ompPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return UsageSettings.current.ompPath
    }
}
