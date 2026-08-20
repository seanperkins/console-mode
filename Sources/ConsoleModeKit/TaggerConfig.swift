import Foundation

/// Connection and behaviour settings for the local tagging model.
struct TaggerConfig: Sendable, Equatable {
    var isEnabled: Bool
    var baseURL: String
    var model: String
    /// Verdicts below this land as "no label". The 9B model scores hits ~0.95 and
    /// misses ~0.1, so anything mid-range is genuinely uncertain.
    var minimumConfidence: Double
    var timeout: TimeInterval

    static let standard = TaggerConfig(
        isEnabled: true,
        baseURL: "http://127.0.0.1:1234",
        model: "ornith-1.5-9b-mlx",
        minimumConfidence: 0.5,
        timeout: 30
    )

    /// Accepts a bare host, a trailing slash, or an endpoint that already ends in `/v1`.
    var completionsURL: URL {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        for suffix in ["/v1/chat/completions", "/chat/completions", "/v1"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
            break
        }
        return URL(string: text + "/v1/chat/completions")
            ?? URL(string: "http://127.0.0.1:1234/v1/chat/completions")!
    }
}

/// UserDefaults-backed storage. Read from background tasks, so it stays a plain
/// value type rather than observable state.
enum TaggerSettings {
    private enum Key {
        static let enabled = "tagger.enabled"
        static let baseURL = "tagger.baseURL"
        static let model = "tagger.model"
        static let minimumConfidence = "tagger.minimumConfidence"
    }

    static var current: TaggerConfig {
        get {
            let defaults = UserDefaults.standard
            var config = TaggerConfig.standard
            if defaults.object(forKey: Key.enabled) != nil {
                config.isEnabled = defaults.bool(forKey: Key.enabled)
            }
            if let base = defaults.string(forKey: Key.baseURL), !base.isEmpty {
                config.baseURL = base
            }
            if let model = defaults.string(forKey: Key.model), !model.isEmpty {
                config.model = model
            }
            if defaults.object(forKey: Key.minimumConfidence) != nil {
                config.minimumConfidence = defaults.double(forKey: Key.minimumConfidence)
            }
            return config
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.isEnabled, forKey: Key.enabled)
            defaults.set(newValue.baseURL, forKey: Key.baseURL)
            defaults.set(newValue.model, forKey: Key.model)
            defaults.set(newValue.minimumConfidence, forKey: Key.minimumConfidence)
        }
    }
}
