import Foundation

/// One note's actionability verdict from the review model.
struct ActionReviewVerdict: Equatable, Sendable {
    let noteID: Int64
    let actionable: Bool
    let summary: String?
    let detail: String?
}

/// Batch response shape from the model.
struct ActionReviewBatch: Equatable, Sendable {
    let reviews: [ActionReviewVerdict]
}

enum ActionReviewerError: LocalizedError, Equatable {
    case emptyResponse
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Action review returned no text."
        case .undecodable(let detail):
            return "Could not read action review output: \(detail)"
        }
    }
}

/// Builds prompts and parses JSON from `omp` print mode.
enum ActionReviewer {
    static let systemPrompt = """
    You review personal capture notes and classify whether each requires the user to DO something.

    Actionable: tasks, follow-ups, decisions pending, replies owed, appointments to schedule, \
    purchases to make, bugs to fix, calls to make, forms to submit.
    Not actionable: references, ideas to revisit later, facts, journal entries, quotes, \
    context-only notes, things already done.

    For each note return:
    - id: exact numeric id from the input (do not invent ids)
    - actionable: boolean
    - summary: one short phrase describing the action (empty string when not actionable)
    - detail: one sentence on what "done" looks like or the concrete next step (empty when not actionable)

    Reply with JSON only, no markdown fences:
    {"reviews":[{"id":1,"actionable":true,"summary":"…","detail":"…"}]}
    """

    static func userPrompt(for notes: [Note]) -> String {
        let payload = notes.compactMap { note -> [String: Any]? in
            guard let id = note.id else { return nil }
            return ["id": id, "body": note.body]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return notes.map { "[\($0.id ?? 0)] \($0.body)" }.joined(separator: "\n")
        }
        return "Review these notes:\n\(json)"
    }

    static func parseResponse(_ text: String) throws -> ActionReviewBatch {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ActionReviewerError.emptyResponse }

        guard let object = ProjectTagger.firstJSONObject(in: trimmed),
              let reviewsRaw = object["reviews"] as? [[String: Any]]
        else {
            throw ActionReviewerError.undecodable("missing reviews array")
        }

        var reviews: [ActionReviewVerdict] = []
        for item in reviewsRaw {
            let id: Int64?
            if let number = item["id"] as? NSNumber {
                id = number.int64Value
            } else if let int = item["id"] as? Int {
                id = Int64(int)
            } else {
                id = nil
            }
            guard let id else { continue }

            let actionable = (item["actionable"] as? Bool)
                ?? (item["actionable"] as? NSNumber)?.boolValue
                ?? false
            let summary = normalizedOptionalString(item["summary"])
            let detail = normalizedOptionalString(item["detail"])
            reviews.append(
                ActionReviewVerdict(
                    noteID: id,
                    actionable: actionable,
                    summary: actionable ? summary : nil,
                    detail: actionable ? detail : nil
                )
            )
        }

        guard !reviews.isEmpty else {
            throw ActionReviewerError.undecodable("no valid review entries")
        }
        return ActionReviewBatch(reviews: reviews)
    }

    private static func normalizedOptionalString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
