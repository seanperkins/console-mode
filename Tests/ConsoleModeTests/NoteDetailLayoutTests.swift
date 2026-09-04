import Foundation
import Testing
@testable import ConsoleModeKit

@Test func noteDetailMetadataIncludesProjectAndAction() {
    let note = Note(
        id: 1,
        body: "Email landlord about lease",
        createdAt: 1_700_000_000,
        project: "home",
        actionable: true,
        actionSummary: "Email landlord",
        actionDetail: "Send renewal reply before month end.",
        actionReviewedAt: 1_700_000_100
    )
    let lines = NoteDetailLayout.metadata(for: note)
    #expect(lines.contains(.project("home")))
    #expect(lines.contains(where: {
        if case .action(summary: "Email landlord", detail: "Send renewal reply before month end.") = $0 {
            return true
        }
        return false
    }))
    #expect(lines.contains(where: { if case .created = $0 { return true }; return false }))
}

@Test func noteDetailHeightGrowsWithBodyAndMetadata() {
    let short = Note(id: 1, body: "hi", createdAt: 1_700_000_000)
    let rich = Note(
        id: 2,
        body: String(repeating: "word ", count: 40),
        createdAt: 1_700_000_000,
        project: "console-mode",
        remindAt: Date().addingTimeInterval(3600).timeIntervalSince1970,
        actionable: true,
        actionSummary: "Ship feature",
        actionDetail: "Add tests and docs",
        actionReviewedAt: 1_700_000_100
    )
    #expect(NoteDetailLayout.detailHeight(for: rich) > NoteDetailLayout.detailHeight(for: short))
}
