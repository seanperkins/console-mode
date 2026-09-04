import Foundation

enum ConsoleTab: String, CaseIterable, Identifiable, Sendable {
    case notes
    case usage
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .usage: return "Usage"
        case .terminal: return "Terminal"
        }
    }

    var symbol: String {
        switch self {
        case .notes: return "note.text"
        case .usage: return "gauge.with.needle"
        case .terminal: return "terminal"
        }
    }

    /// ⌃1 / ⌃2 / ⌃3, matching the tab order.
    var commandDigit: String {
        switch self {
        case .notes: return "1"
        case .usage: return "2"
        case .terminal: return "3"
        }
    }

    var next: ConsoleTab {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
