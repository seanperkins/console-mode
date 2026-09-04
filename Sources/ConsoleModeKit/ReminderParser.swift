import Foundation

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

    /// Longest leading substring that parses as a reminder time.
    static func splitArgument(_ argument: String) -> (when: String, body: String?) {
        let parts = argument.split(separator: " ", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return (argument, nil) }
        for i in stride(from: parts.count, through: 1, by: -1) {
            let when = parts.prefix(i).joined(separator: " ")
            if case .success = parse(when) {
                let tail = parts.dropFirst(i).joined(separator: " ")
                let body = tail.trimmingCharacters(in: .whitespacesAndNewlines)
                return (when, body.isEmpty ? nil : body)
            }
        }
        return (argument, nil)
    }
}
