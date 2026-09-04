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

@Test func parsesEveryDayRecurring() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let ref = Date(timeIntervalSince1970: 1_700_035_200) // Wed 2023-11-15 08:00 UTC

    let result = ReminderParser.parseSchedule("every day 9am", reference: ref, calendar: calendar)
    guard case .success(.recurring(let rule, let firstFireDate)) = result else {
        Issue.record("expected recurring schedule")
        return
    }
    #expect(rule == .daily(hour: 9, minute: 0))
    let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: firstFireDate)
    #expect(comps.day == 15)
    #expect(comps.hour == 9)
    #expect(comps.minute == 0)
}

@Test func dailyRecurrenceSkipsToNextDayAfterFireTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let ref = Date(timeIntervalSince1970: 1_700_042_400) // Wed 2023-11-15 10:00 UTC — after 9am

    let result = ReminderParser.parseSchedule("every day 9am", reference: ref, calendar: calendar)
    guard case .success(.recurring(_, let firstFireDate)) = result else {
        Issue.record("expected recurring schedule")
        return
    }
    let comps = calendar.dateComponents([.day, .hour, .minute], from: firstFireDate)
    #expect(comps.day == 16) // bumped across the day boundary to Thursday
    #expect(comps.hour == 9)
    #expect(comps.minute == 0)
}

@Test func parsesEveryWeekdayRecurringFromSaturdaySkipsToMonday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let ref = Date(timeIntervalSince1970: 1_700_308_800) // Sat 2023-11-18 12:00 UTC

    let result = ReminderParser.parseSchedule("every weekday 9am", reference: ref, calendar: calendar)
    guard case .success(.recurring(let rule, let firstFireDate)) = result else {
        Issue.record("expected recurring schedule")
        return
    }
    #expect(rule == .weekdays(hour: 9, minute: 0))
    let comps = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: firstFireDate)
    #expect(comps.day == 20) // Monday, not Sunday the 19th
    #expect(comps.weekday == 2)
    #expect(comps.hour == 9)
}

@Test func parsesEveryWeekdayNameRecurring() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let ref = Date(timeIntervalSince1970: 1_700_308_800) // Sat 2023-11-18 12:00 UTC

    let result = ReminderParser.parseSchedule("every monday 5pm", reference: ref, calendar: calendar)
    guard case .success(.recurring(let rule, let firstFireDate)) = result else {
        Issue.record("expected recurring schedule")
        return
    }
    #expect(rule == .weekly(weekday: 2, hour: 17, minute: 0))
    let comps = calendar.dateComponents([.day, .weekday, .hour], from: firstFireDate)
    #expect(comps.day == 20)
    #expect(comps.weekday == 2)
    #expect(comps.hour == 17)
}

@Test func parsesEveryWeekAsSameWeekdayAsReference() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let ref = Date(timeIntervalSince1970: 1_700_035_200) // Wed 2023-11-15 08:00 UTC
    let refWeekday = calendar.component(.weekday, from: ref)

    let result = ReminderParser.parseSchedule("every week 9am", reference: ref, calendar: calendar)
    guard case .success(.recurring(let rule, _)) = result else {
        Issue.record("expected recurring schedule")
        return
    }
    #expect(rule == .weekly(weekday: refWeekday, hour: 9, minute: 0))
}

@Test func recurringPrefixDoesNotBreakOneShotParsing() {
    let ref = Date(timeIntervalSince1970: 1_700_000_000)
    let result = ReminderParser.parseSchedule("tomorrow 9am", reference: ref)
    guard case .success(.once) = result else {
        Issue.record("expected one-shot schedule")
        return
    }
}

@Test func unrecognizedRecurringPhraseFails() {
    let ref = Date(timeIntervalSince1970: 1_700_000_000)
    let result = ReminderParser.parseSchedule("every fortnight 9am", reference: ref)
    guard case .failure(.unrecognized) = result else {
        Issue.record("expected unrecognized failure")
        return
    }
}

@Test func weekdaysRecurrenceRuleSkipsWeekend() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let saturday = Date(timeIntervalSince1970: 1_700_308_800) // Sat 2023-11-18 12:00 UTC

    let next = RecurrenceRule.weekdays(hour: 9, minute: 0).nextFireDate(after: saturday, calendar: calendar)
    let comps = calendar.dateComponents([.weekday], from: next!)
    #expect(comps.weekday == 2) // Monday
}

@Test func splitsRecurringReminderBody() {
    let split = ReminderParser.splitArgument("every weekday 9am stretch and hydrate")
    #expect(split.when == "every weekday 9am")
    #expect(split.body == "stretch and hydrate")
}
