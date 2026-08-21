import Foundation

enum ConsoleTab: String, CaseIterable, Identifiable, Sendable {
    case notes
    case usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .usage: return "Usage"
        }
    }

    var symbol: String {
        switch self {
        case .notes: return "note.text"
        case .usage: return "gauge.with.needle"
        }
    }

    /// ⌃1 / ⌃2, matching the tab order.
    var commandDigit: String {
        switch self {
        case .notes: return "1"
        case .usage: return "2"
        }
    }

    var next: ConsoleTab {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
