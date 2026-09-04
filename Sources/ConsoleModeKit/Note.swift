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
    /// When to fire a local notification for this note.
    var remindAt: TimeInterval? = nil
    /// Whether the note needs doing something; nil = not reviewed yet.
    var actionable: Bool? = nil
    /// Short action phrase from `/analyze` (e.g. "Email landlord").
    var actionSummary: String? = nil
    /// One-line next step or definition of done.
    var actionDetail: String? = nil
    /// When action review last ran on this note.
    var actionReviewedAt: TimeInterval? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case project
        case projectConfidence = "project_confidence"
        case taggedAt = "tagged_at"
        case remindAt = "remind_at"
        case actionable
        case actionSummary = "action_summary"
        case actionDetail = "action_detail"
        case actionReviewedAt = "action_reviewed_at"
    }

    var isCompleted: Bool { completedAt != nil }

    var isTagged: Bool { taggedAt != nil }

    var createdDate: Date { Date(timeIntervalSince1970: createdAt) }

    var remindDate: Date? {
        remindAt.map { Date(timeIntervalSince1970: $0) }
    }

    var hasReminder: Bool {
        guard let remindDate else { return false }
        return remindDate > Date()
    }

    var isActionReviewed: Bool { actionReviewedAt != nil }

    var isActionable: Bool { actionable == true }
}
