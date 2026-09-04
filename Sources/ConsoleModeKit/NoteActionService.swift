import Foundation

/// Runs actionability review off the main actor and writes results to SQLite.
struct NoteActionService: Sendable {
    let store: NoteStore

    @discardableResult
    func reviewNotes(_ notes: [Note], config: ActionReviewConfig) async throws -> Int {
        guard config.isEnabled, !notes.isEmpty else { return 0 }

        let client = ActionReviewClient(config: config)
        let batch = try await client.review(notes: notes)
        let allowedIDs = Set(notes.compactMap(\.id))

        var applied = 0
        for verdict in batch.reviews {
            guard allowedIDs.contains(verdict.noteID) else { continue }
            try store.setActionReview(
                id: verdict.noteID,
                actionable: verdict.actionable,
                summary: verdict.summary,
                detail: verdict.detail
            )
            applied += 1
        }
        return applied
    }

    func unreviewedCount() -> Int {
        (try? store.fetchUnreviewed(limit: 500).count) ?? 0
    }
}
