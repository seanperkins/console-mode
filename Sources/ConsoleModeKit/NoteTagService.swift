import Foundation

/// Runs tagging off the main actor and writes results straight to SQLite, letting
/// the existing `ValueObservation` push the label into the UI. Failures are logged
/// and swallowed: a missing LM Studio must never cost the user a note.
struct NoteTagService: Sendable {
    let store: NoteStore

    /// Tag one note. Marks `tagged_at` even when the model declines, so the note is
    /// not retried on every launch.
    func tag(noteID: Int64, body: String, config: TaggerConfig) async {
        guard config.isEnabled else { return }

        let known = (try? store.knownProjects()) ?? []
        let tagger = ProjectTagger(config: config)

        do {
            let verdict = try await tagger.tag(body: body, knownProjects: known)
            try store.setProject(
                id: noteID,
                project: verdict.project,
                confidence: verdict.confidence
            )
        } catch {
            // Leave `tagged_at` nil so a later backfill can retry once the
            // server is reachable again.
            NSLog("ProjectTagger failed for note \(noteID): \(error)")
        }
    }

    /// Work through notes the tagger has never seen. Returns how many were labelled.
    @discardableResult
    func backfill(limit: Int, config: TaggerConfig) async -> Int {
        guard config.isEnabled else { return 0 }
        guard let pending = try? store.fetchUntagged(limit: limit), !pending.isEmpty else {
            return 0
        }

        var labelled = 0
        for note in pending {
            guard let id = note.id else { continue }
            if Task.isCancelled { break }

            let known = (try? store.knownProjects()) ?? []
            let tagger = ProjectTagger(config: config)
            do {
                let verdict = try await tagger.tag(body: note.body, knownProjects: known)
                try store.setProject(id: id, project: verdict.project, confidence: verdict.confidence)
                if verdict.project != nil {
                    labelled += 1
                }
            } catch {
                // Stop on transport failure rather than hammering a down server.
                NSLog("ProjectTagger backfill stopped at note \(id): \(error)")
                break
            }
        }
        return labelled
    }

    func untaggedCount() -> Int {
        (try? store.fetchUntagged(limit: 500).count) ?? 0
    }
}
