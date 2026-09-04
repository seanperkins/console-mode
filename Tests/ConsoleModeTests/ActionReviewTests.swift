import Testing
@testable import ConsoleModeKit

@Test func parsesActionReviewBatch() throws {
    let text = """
    {"reviews":[{"id":42,"actionable":true,"summary":"Email landlord","detail":"Send renewal reply before month end."},{"id":7,"actionable":false,"summary":"","detail":""}]}
    """
    let batch = try ActionReviewer.parseResponse(text)
    #expect(batch.reviews.count == 2)
    #expect(batch.reviews[0].noteID == 42)
    #expect(batch.reviews[0].actionable)
    #expect(batch.reviews[0].summary == "Email landlord")
    #expect(batch.reviews[1].noteID == 7)
    #expect(!batch.reviews[1].actionable)
    #expect(batch.reviews[1].summary == nil)
}

@Test func actionReviewRoundTrip() throws {
    let store = try NoteStore.inMemory()
    let note = try store.append("call dentist")!
    let id = note.id!

    try store.setActionReview(id: id, actionable: true, summary: "Schedule cleaning", detail: "Book before Friday")

    let fetched = try store.fetchNote(id: id)!
    #expect(fetched.isActionable)
    #expect(fetched.actionSummary == "Schedule cleaning")
    #expect(fetched.isActionReviewed)

    let actionable = try store.fetchFiltered(.actionable, limit: 10)
    #expect(actionable.count == 1)

    try store.clearActionReview(id: id)
    let cleared = try store.fetchNote(id: id)!
    #expect(cleared.actionable == nil)
    #expect(!cleared.isActionReviewed)
}

@Test func fetchUnreviewedSkipsCompletedAndReviewed() throws {
    let store = try NoteStore.inMemory()
    let fresh = try store.append("todo one")!
    let done = try store.append("done")!
    let reviewed = try store.append("already reviewed")!
    try store.setCompleted(id: done.id!, completed: true)
    try store.setActionReview(id: reviewed.id!, actionable: false, summary: nil, detail: nil)

    let pending = try store.fetchUnreviewed(limit: 10)
    #expect(pending.map(\.id) == [fresh.id])
}
