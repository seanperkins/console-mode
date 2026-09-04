import Foundation


/// Either fires once, or recurs indefinitely according to a `RecurrenceRule`.
enum ReminderSchedule: Equatable {
    case once(Date)
    case recurring(RecurrenceRule, firstFireDate: Date)

    /// The date this schedule will next (or only) fire.
    var fireDate: Date {
        switch self {
        case .once(let date): date
        case .recurring(_, let firstFireDate): firstFireDate
        }
    }
}

/// A repeating cadence for a reminder. Carries just enough to compute the next
/// fire date after any given moment — see `nextFireDate(after:calendar:)`.
enum RecurrenceRule: Equatable, Codable {
    case daily(hour: Int, minute: Int)
    case weekdays(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)

    var hour: Int {
        switch self {
        case .daily(let hour, _), .weekdays(let hour, _), .weekly(_, let hour, _): hour
        }
    }

    var minute: Int {
        switch self {
        case .daily(_, let minute), .weekdays(_, let minute), .weekly(_, _, let minute): minute
        }
    }

    private func matches(weekday: Int) -> Bool {
        switch self {
        case .daily: true
        case .weekdays: (2...6).contains(weekday)
        case .weekly(let target, _, _): weekday == target
        }
    }

    /// The earliest date strictly after `date` that satisfies this rule. Scans
    /// forward day by day (at most a week) rather than doing raw interval math,
    /// so DST transitions and "weekdays only" both fall out for free.
    func nextFireDate(after date: Date, calendar: Calendar = .current) -> Date? {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<8 {
            let weekday = calendar.component(.weekday, from: day)
            if matches(weekday: weekday),
               let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
               candidate > date {
                return candidate
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
        return nil
    }
}

/// Parses lightweight reminder expressions like "tomorrow 9am" or "in 30m".
enum ReminderParser {
    enum ParseError: Error, Equatable {
        case empty
        case unrecognized(String)
    }

    /// Parses `when` relative to `reference` (defaults to now).
    static func parse(_ raw: String, reference: Date = Date(), calendar: Calendar = .current) -> Result<Date, ParseError> {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .failure(.empty) }

        if text.hasPrefix("in ") {
            if let date = parseRelativeDuration(String(text.dropFirst(3)), reference: reference) {
                return .success(date)
            }
        }

        var working = text
        var dayStart = calendar.startOfDay(for: reference)

        if working.hasPrefix("tomorrow ") {
            dayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            working = String(working.dropFirst("tomorrow ".count))
        } else if working.hasPrefix("today ") {
            working = String(working.dropFirst("today ".count))
        } else if working == "tomorrow" {
            let atNine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart.addingTimeInterval(86_400))
            return atNine.map { .success($0) } ?? .failure(.unrecognized(raw))
        } else if working == "today" {
            let atNine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart)
            return atNine.map { .success($0) } ?? .failure(.unrecognized(raw))
        }

        if let time = parseClock(working, on: dayStart, calendar: calendar) {
            if time <= reference, !text.hasPrefix("tomorrow"), text != working {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                if let bumped = parseClock(working, on: tomorrow, calendar: calendar) {
                    return .success(bumped)
                }
            }
            if time <= reference, text.hasPrefix("today ") {
                return .failure(.unrecognized(raw))
            }
            return .success(time)
        }

        if let iso = parseISO(text, calendar: calendar), iso > reference {
            return .success(iso)
        }

        return .failure(.unrecognized(raw))
    }

    /// Parses `when` as either a one-shot time or a recurring cadence
    /// ("every day 9am", "every weekday 9am", "every monday 5pm", "every week 9am").
    /// Falls back to the one-shot grammar handled by `parse`.
    static func parseSchedule(
        _ raw: String,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Result<ReminderSchedule, ParseError> {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .failure(.empty) }

        if text.hasPrefix("every ") {
            let rest = String(text.dropFirst("every ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return parseRecurring(rest, reference: reference, calendar: calendar, raw: raw)
        }

        return parse(raw, reference: reference, calendar: calendar).map(ReminderSchedule.once)
    }

    static func format(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale.current
        if calendar.isDateInToday(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "today \(formatter.string(from: date))"
        }
        if calendar.isDateInTomorrow(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "tomorrow \(formatter.string(from: date))"
        }
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func parseRelativeDuration(_ text: String, reference: Date) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return nil }
        let unit: Calendar.Component
        switch last {
        case "m": unit = .minute
        case "h": unit = .hour
        case "d": unit = .day
        default: return nil
        }
        let numberText = String(trimmed.dropLast())
        guard let value = Int(numberText), value > 0 else { return nil }
        return Calendar.current.date(byAdding: unit, value: value, to: reference)
    }

    private static func parseClock(_ text: String, on day: Date, calendar: Calendar) -> Date? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        var meridiem: String?
        if trimmed.hasSuffix("am") {
            meridiem = "am"
            trimmed.removeLast(2)
        } else if trimmed.hasSuffix("pm") {
            meridiem = "pm"
            trimmed.removeLast(2)
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)

        let hourText: String
        let minuteText: String
        if let colon = trimmed.firstIndex(of: ":") {
            hourText = String(trimmed[..<colon])
            minuteText = String(trimmed[trimmed.index(after: colon)...])
        } else if let dot = trimmed.firstIndex(of: ".") {
            hourText = String(trimmed[..<dot])
            minuteText = String(trimmed[trimmed.index(after: dot)...])
        } else {
            hourText = trimmed
            minuteText = "0"
        }

        guard let hour = Int(hourText), let minute = Int(minuteText) else { return nil }
        return compose(hour: hour, minute: minute, meridiem: meridiem, on: day, calendar: calendar)
    }

    private static func compose(
        hour: Int,
        minute: Int,
        meridiem: String?,
        on day: Date,
        calendar: Calendar
    ) -> Date? {
        var h = hour
        let m = minute
        if let meridiem {
            guard (1...12).contains(h), (0...59).contains(m) else { return nil }
            if meridiem == "pm", h < 12 { h += 12 }
            if meridiem == "am", h == 12 { h = 0 }
        } else {
            guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        }
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: day)
    }

    private static func parseISO(_ text: String, calendar: Calendar) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                if format == "yyyy-MM-dd" {
                    return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
                }
                return date
            }
        }
        return nil
    }

    /// Weekday names accepted after "every" — both full and common abbreviations.
    /// Values match `Calendar.component(.weekday:)` (1 = Sunday … 7 = Saturday).
    private static let weekdayNames: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7,
    ]

    /// Parses the text after "every " — e.g. "day 9am", "weekday 9am", "week 9am",
    /// or "monday 5pm".
    private static func parseRecurring(
        _ rest: String,
        reference: Date,
        calendar: Calendar,
        raw: String
    ) -> Result<ReminderSchedule, ParseError> {
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return .failure(.unrecognized(raw)) }
        let keyword = String(first)
        let timeText = parts.count > 1 ? String(parts[1]) : ""
        let referenceDay = calendar.startOfDay(for: reference)

        let rule: RecurrenceRule
        switch keyword {
        case "day":
            guard let time = parseTimeOfDay(timeText, on: referenceDay, calendar: calendar) else {
                return .failure(.unrecognized(raw))
            }
            rule = .daily(hour: time.hour, minute: time.minute)
        case "weekday", "weekdays":
            guard let time = parseTimeOfDay(timeText, on: referenceDay, calendar: calendar) else {
                return .failure(.unrecognized(raw))
            }
            rule = .weekdays(hour: time.hour, minute: time.minute)
        case "week":
            guard let time = parseTimeOfDay(timeText, on: referenceDay, calendar: calendar) else {
                return .failure(.unrecognized(raw))
            }
            rule = .weekly(weekday: calendar.component(.weekday, from: reference), hour: time.hour, minute: time.minute)
        default:
            guard let weekday = weekdayNames[keyword] else { return .failure(.unrecognized(raw)) }
            guard let time = parseTimeOfDay(timeText, on: referenceDay, calendar: calendar) else {
                return .failure(.unrecognized(raw))
            }
            rule = .weekly(weekday: weekday, hour: time.hour, minute: time.minute)
        }

        guard let firstFireDate = rule.nextFireDate(after: reference, calendar: calendar) else {
            return .failure(.unrecognized(raw))
        }
        return .success(.recurring(rule, firstFireDate: firstFireDate))
    }

    /// Extracts an hour/minute pair from a clock expression like "9am" or "17:30",
    /// reusing `parseClock`'s grammar without needing a concrete fire date.
    private static func parseTimeOfDay(_ text: String, on day: Date, calendar: Calendar) -> (hour: Int, minute: Int)? {
        guard let date = parseClock(text, on: day, calendar: calendar) else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return (hour, minute)
    }

    /// Human-readable description of a recurrence, e.g. "every weekday at 9:00 AM".
    static func describeRecurrence(_ rule: RecurrenceRule, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let anchor = calendar.startOfDay(for: Date())
        let timeString: String
        if let time = calendar.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: anchor) {
            timeString = formatter.string(from: time)
        } else {
            timeString = String(format: "%02d:%02d", rule.hour, rule.minute)
        }

        switch rule {
        case .daily:
            return "every day at \(timeString)"
        case .weekdays:
            return "every weekday at \(timeString)"
        case .weekly(let weekday, _, _):
            let symbols = calendar.weekdaySymbols
            let index = ((weekday - 1) % symbols.count + symbols.count) % symbols.count
            return "every \(symbols[index]) at \(timeString)"
        }
    }

    /// Longest leading substring that parses as a reminder time.
    static func splitArgument(_ argument: String) -> (when: String, body: String?) {
        let parts = argument.split(separator: " ", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return (argument, nil) }
        for i in stride(from: parts.count, through: 1, by: -1) {
            let when = parts.prefix(i).joined(separator: " ")
            if case .success = parseSchedule(when) {
                let tail = parts.dropFirst(i).joined(separator: " ")
                let body = tail.trimmingCharacters(in: .whitespacesAndNewlines)
                return (when, body.isEmpty ? nil : body)
            }
        }
        return (argument, nil)
    }
}
