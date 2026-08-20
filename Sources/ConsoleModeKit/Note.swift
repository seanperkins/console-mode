import Foundation
import GRDB

struct Note: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "note"

    var id: Int64?
    var body: String
    var createdAt: TimeInterval
    var completedAt: TimeInterval?
    /// Project label assigned by `ProjectTagger`, or nil when unlabelled.
    var project: String? = nil
    var projectConfidence: Double? = nil
    /// Set once the tagger has run, whether or not it produced a label.
    var taggedAt: TimeInterval? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case project
        case projectConfidence = "project_confidence"
        case taggedAt = "tagged_at"
    }

    var isCompleted: Bool { completedAt != nil }

    var isTagged: Bool { taggedAt != nil }

    var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
}
