import Foundation

/// Which notes the list shows. Applied at the store layer so observation stays live.
enum NoteFilter: Equatable, Sendable {
    case all
    case text(String)
    case project(String)
    case incomplete
    case actionable

    var isActive: Bool {
        if case .all = self { return false }
        return true
    }

    /// Shown above the list while a filter is active.
    var label: String? {
        switch self {
        case .all:
            return nil
        case .text(let query):
            return "Matching “\(query)”"
        case .project(let slug):
            return "Project \(slug)"
        case .incomplete:
            return "To do"
        case .actionable:
            return "Actionable"
        }
    }
}
