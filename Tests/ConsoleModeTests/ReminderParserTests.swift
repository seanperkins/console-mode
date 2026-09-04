import Foundation
import Testing
@testable import ConsoleModeKit

@Test func parsesTomorrowMorning() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let ref = Date(timeIntervalSince1970: 1_700_000_000) // fixed reference

    let result = ReminderParser.parse("tomorrow 9am", reference: ref, calendar: calendar)
    guard case .success(let date) = result else {
        Issue.record("expected success")
        return
    }
    let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let refDay = calendar.startOfDay(for: ref)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: refDay)!
    let tComps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
    #expect(comps.year == tComps.year)
    #expect(comps.month == tComps.month)
    #expect(comps.day == tComps.day)
    #expect(comps.hour == 9)
    #expect(comps.minute == 0)
}

@Test func parsesInThirtyMinutes() {
    let ref = Date(timeIntervalSince1970: 1_700_000_000)
    let result = ReminderParser.parse("in 30m", reference: ref)
    guard case .success(let date) = result else {
        Issue.record("expected success")
        return
    }
    #expect(abs(date.timeIntervalSince(ref) - 1800) < 1)
}

@Test func splitsReminderBody() {
    let split = ReminderParser.splitArgument("tomorrow 9am buy oat milk")
    #expect(split.when == "tomorrow 9am")
    #expect(split.body == "buy oat milk")
}
