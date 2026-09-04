import Foundation

enum DeepSeekClientError: LocalizedError, Equatable {
    case notConfigured
    case requestFailed(String)
    case exitFailure(code: Int, message: String)
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Set a DeepSeek API key in Settings."
        case .requestFailed(let detail):
            return "Could not reach DeepSeek: \(detail)"
        case .exitFailure(let code, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "DeepSeek balance request failed (\(code))." : trimmed
        case .undecodable(let detail):
            return "Could not read DeepSeek balance response: \(detail)"
        }
    }
}

/// Calls DeepSeek's documented account balance endpoint directly — a real
/// dollar figure billed by DeepSeek itself, not a catalog-priced token
/// estimate. Deliberately a plain value type, mirroring `UsageClient` and
/// `StatsClient`: it owns no state, so `UsageMonitor` decides entirely when
/// a fetch happens.
struct DeepSeekClient: Sendable {
    var apiKey: String
    var timeout: TimeInterval = 15

    static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    func fetch() async throws -> DeepSeekBalanceResponse {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw DeepSeekClientError.notConfigured }

        var request = URLRequest(url: Self.balanceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DeepSeekClientError.requestFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekClientError.requestFailed("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekClientError.exitFailure(code: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }

        do {
            return try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        } catch {
            throw DeepSeekClientError.undecodable(error.localizedDescription)
        }
    }
}
