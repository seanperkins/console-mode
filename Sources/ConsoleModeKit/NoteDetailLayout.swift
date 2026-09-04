import CoreGraphics
import Foundation

/// Metadata and sizing for the note detail strip shown when a row is selected.
enum NoteDetailLayout {
    static let verticalPadding: CGFloat = 8
    static let bodyLineHeight: CGFloat = 17
    static let metadataLineHeight: CGFloat = 16
    static let metadataSpacing: CGFloat = 4
    static let maxBodyLines = 6
    static let charactersPerLine = 72

    enum MetadataLine: Equatable {
        case project(String)
        case action(summary: String, detail: String?)
        case reference
        case reminder(Date)
        case created(Date)

        var label: String {
            switch self {
            case .project(let slug):
                return "Project · \(slug)"
            case .action(let summary, let detail):
                if let detail, !detail.isEmpty {
                    return "Action · \(summary) — \(detail)"
                }
                return "Action · \(summary)"
            case .reference:
                return "Reference · not actionable"
            case .reminder(let date):
                let formatted = date.formatted(date: .abbreviated, time: .shortened)
                return "Reminder · \(formatted)"
            case .created(let date):
                let formatted = date.formatted(date: .abbreviated, time: .shortened)
                return "Created · \(formatted)"
            }
        }
    }

    static func metadata(for note: Note) -> [MetadataLine] {
        var lines: [MetadataLine] = []
        if let project = note.project, !project.isEmpty {
            lines.append(.project(project))
        }
        if note.isActionable, let summary = note.actionSummary, !summary.isEmpty {
            lines.append(.action(summary: summary, detail: note.actionDetail))
        } else if note.isActionReviewed {
            lines.append(.reference)
        }
        if note.hasReminder, let remindDate = note.remindDate {
            lines.append(.reminder(remindDate))
        }
        lines.append(.created(note.createdDate))
        return lines
    }

    static func estimatedBodyLineCount(_ body: String) -> Int {
        let paragraphs = body.split(separator: "\n", omittingEmptySubsequences: false)
        var total = 0
        for paragraph in paragraphs {
            let length = max(paragraph.count, 1)
            total += max(1, Int(ceil(Double(length) / Double(charactersPerLine))))
        }
        return max(1, total)
    }

    static func detailHeight(for note: Note) -> CGFloat {
        let bodyLines = min(maxBodyLines, estimatedBodyLineCount(note.body))
        let bodyHeight = CGFloat(bodyLines) * bodyLineHeight
        let metaCount = metadata(for: note).count
        let metaHeight = metaCount > 0
            ? CGFloat(metaCount) * metadataLineHeight + CGFloat(max(0, metaCount - 1)) * metadataSpacing
            : 0
        let spacing: CGFloat = metaCount > 0 ? 6 : 0
        return verticalPadding + bodyHeight + spacing + metaHeight + verticalPadding
    }
}
