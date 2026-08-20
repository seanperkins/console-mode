import Foundation

/// Asks a local LM Studio model which project a note belongs to.
///
/// Deliberately conservative: any transport error, malformed body, or
/// below-threshold answer resolves to "no label" rather than a guess. Notes are
/// never blocked on this — capture stays local and instant.
struct ProjectTagger: Sendable {
    struct Verdict: Equatable, Sendable {
        /// nil means the model declined to label the note.
        let project: String?
        let confidence: Double
    }

    enum TaggerError: Error, Equatable {
        case badStatus(Int)
        case emptyResponse
        case undecodable(String)
    }

    let config: TaggerConfig
    private let session: URLSession

    init(config: TaggerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Prompting

    private static let systemPrompt = """
    You label a short personal note with the project it belongs to.

    Rules:
    - Prefer an EXACT string from known_projects when one plausibly fits.
    - Otherwise invent a short kebab-case slug (2-3 words max).
    - If the note is generic, a test, or gives no signal, return an empty string for project.
    - Never explain. Return only JSON.
    """

    static func userPrompt(body: String, knownProjects: [String]) -> String {
        let known = knownProjects.map { "\"\($0)\"" }.joined(separator: ", ")
        return "known_projects: [\(known)]\n\nnote: \"\(body)\""
    }

    /// The MLX backend rejects union types like `["string","null"]`, so `project`
    /// is a plain string and an empty value stands in for "no label".
    private static var responseFormat: [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": "note_tag",
                "strict": true,
                "schema": [
                    "type": "object",
                    "properties": [
                        "project": ["type": "string"],
                        "confidence": ["type": "number"],
                    ],
                    "required": ["project", "confidence"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }

    func requestBody(for body: String, knownProjects: [String]) -> [String: Any] {
        [
            "model": config.model,
            "temperature": 0,
            "max_tokens": 120,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": Self.userPrompt(body: body, knownProjects: knownProjects)],
            ],
            "response_format": Self.responseFormat,
        ]
    }

    // MARK: - Networking

    func tag(body: String, knownProjects: [String]) async throws -> Verdict {
        var request = URLRequest(url: config.completionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = config.timeout
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody(for: body, knownProjects: knownProjects)
        )

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TaggerError.badStatus(http.statusCode)
        }

        return try Self.parseVerdict(data: data, minimumConfidence: config.minimumConfidence)
    }

    // MARK: - Parsing

    /// Ornith emits its JSON inside the thinking block, so LM Studio returns it in
    /// `reasoning_content` with `content` empty. Read content first, then fall back.
    static func extractPayload(data: Data) throws -> String {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw TaggerError.undecodable(String(decoding: data.prefix(200), as: UTF8.self))
        }

        if let message = root["error"] as? String {
            throw TaggerError.undecodable(message)
        }

        guard
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else {
            throw TaggerError.emptyResponse
        }

        let content = (message["content"] as? String) ?? ""
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }

        let reasoning = (message["reasoning_content"] as? String) ?? ""
        guard !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TaggerError.emptyResponse
        }
        return reasoning
    }

    static func parseVerdict(data: Data, minimumConfidence: Double) throws -> Verdict {
        let payload = try extractPayload(data: data)
        return try parseVerdict(payload: payload, minimumConfidence: minimumConfidence)
    }

    static func parseVerdict(payload: String, minimumConfidence: Double) throws -> Verdict {
        guard let json = firstJSONObject(in: payload) else {
            throw TaggerError.undecodable(String(payload.prefix(200)))
        }

        let confidence = (json["confidence"] as? Double) ?? 0
        let raw = (json["project"] as? String) ?? ""
        let slug = normalize(raw)

        guard let slug, confidence >= minimumConfidence else {
            return Verdict(project: nil, confidence: confidence)
        }
        return Verdict(project: slug, confidence: confidence)
    }

    /// Models sometimes wrap JSON in prose or fences; take the first balanced object.
    static func firstJSONObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        let slice = text[start...index]
                        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8)))
                            as? [String: Any]
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Collapse to a stable kebab-case slug so trivial spelling differences do not
    /// fragment the vocabulary. Returns nil for "no label" sentinels.
    static func normalize(_ raw: String) -> String? {
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty, !["none", "null", "n/a", "unknown", "other"].contains(lowered) else {
            return nil
        }

        let allowed = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let slug = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")

        return slug.isEmpty ? nil : slug
    }
}
