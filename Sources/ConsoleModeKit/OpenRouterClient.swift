import Foundation

enum OpenRouterClientError: LocalizedError, Equatable {
    case notConfigured
    case requestFailed(String)
    case exitFailure(code: Int, message: String)
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Set an OpenRouter management key in Settings."
        case .requestFailed(let detail):
            return "Could not reach OpenRouter: \(detail)"
        case .exitFailure(let code, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if code == 403 {
                return "OpenRouter rejected this key — /credits needs a Management key, not a standard inference key."
            }
            return trimmed.isEmpty ? "OpenRouter balance request failed (\(code))." : trimmed
        case .undecodable(let detail):
            return "Could not read OpenRouter balance response: \(detail)"
        }
    }
}

/// Calls OpenRouter's documented account credits endpoint directly — a real
/// dollar figure OpenRouter itself bills, not a catalog-priced token
/// estimate. Mirrors `DeepSeekClient` rather than sharing code with it (see
/// also `StatsClient`/`UsageClient`): each of these small provider clients
/// owns its own request shape and error messages, which genuinely differ —
/// OpenRouter's 403 in particular means "wrong *kind* of key", not "wrong
/// key", and needs its own message.
struct OpenRouterClient: Sendable {
    var apiKey: String
    var timeout: TimeInterval = 15

    static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!

    func fetch() async throws -> OpenRouterBalanceResponse {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw OpenRouterClientError.notConfigured }

        var request = URLRequest(url: Self.creditsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenRouterClientError.requestFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterClientError.requestFailed("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenRouterClientError.exitFailure(code: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }

        do {
            return try JSONDecoder().decode(OpenRouterBalanceResponse.self, from: data)
        } catch {
            throw OpenRouterClientError.undecodable(error.localizedDescription)
        }
    }
}
