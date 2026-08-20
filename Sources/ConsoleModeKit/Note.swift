import Foundation
import GRDB

struct Note: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "note"

    var id: Int64?
    var body: String
    var createdAt: TimeInterval
    var completedAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    var isCompleted: Bool { completedAt != nil }

    var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
}
