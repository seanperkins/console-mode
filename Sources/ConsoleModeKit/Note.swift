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
    /// Recurrence cadence for the reminder above, or nil for a one-shot reminder.
    var recurrenceRule: RecurrenceRule? = nil
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
        case recurrenceRule = "recurrence_rule"
        case actionable
        case actionSummary = "action_summary"
        case actionDetail = "action_detail"
        case actionReviewedAt = "action_reviewed_at"
    }

    var isCompleted: Bool { completedAt != nil }

    var isTagged: Bool { taggedAt != nil }

    var createdDate: Date { Date(timeIntervalSince1970: createdAt) }

    /// The next date this reminder will fire. For a recurring reminder whose
    /// stored `remindAt` has already passed (e.g. the app was closed through it),
    /// this recomputes the next occurrence on the fly rather than showing a
    /// stale, past date.
    var remindDate: Date? {
        guard let remindAt else { return nil }
        let stored = Date(timeIntervalSince1970: remindAt)
        guard let recurrenceRule, stored <= Date() else { return stored }
        return recurrenceRule.nextFireDate(after: Date()) ?? stored
    }

    var hasReminder: Bool {
        guard let remindDate else { return false }
        return remindDate > Date()
    }

    var isActionReviewed: Bool { actionReviewedAt != nil }

    var isActionable: Bool { actionable == true }
}
