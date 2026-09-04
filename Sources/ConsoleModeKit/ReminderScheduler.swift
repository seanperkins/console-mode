import Foundation
import UserNotifications

/// Schedules local notifications for note reminders.
@MainActor
enum ReminderScheduler {
    /// `UNUserNotificationCenter` needs a real app bundle; `swift test` runs from the PM helper.
    private static var notificationsAvailable: Bool {
        let path = Bundle.main.bundleURL.path
        if path.contains("/swift/pm") { return false }
        if path.hasSuffix(".xctest") { return false }
        return true
    }

    private static var center: UNUserNotificationCenter? {
        guard notificationsAvailable else { return nil }
        return UNUserNotificationCenter.current()
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        guard let center else { return false }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    static func rescheduleAll(store: NoteStore) async {
        guard let center else { return }
        let pending = (try? store.fetchPendingReminders()) ?? []
        center.removeAllPendingNotificationRequests()
        guard await requestAuthorizationIfNeeded() else { return }
        for note in pending {
            await schedule(note: note)
        }
    }

    /// Schedules the notification(s) for a note.
    ///
    /// Design choice: recurring notes use `UNCalendarNotificationTrigger`'s own
    /// `repeats: true` support, which natively expresses "every day at 9am"
    /// (only hour/minute set) and "every Monday at 9am" (weekday+hour+minute
    /// set) without any app-side rescheduling. `UNCalendarNotificationTrigger`
    /// cannot express "weekdays only" as a single trigger, so that case is
    /// broken into five weekly triggers (Mon–Fri), each independently
    /// repeating. Because the OS owns the repeat, this keeps firing correctly
    /// even across long stretches where the app itself isn't running — unlike
    /// scheduling only the next single occurrence and relying on the app to
    /// notice it fired and queue the next one.
    static func schedule(note: Note) async {
        guard let center else { return }
        guard let id = note.id, note.remindAt != nil else {
            if let id = note.id { cancel(noteID: id) }
            return
        }

        guard await requestAuthorizationIfNeeded() else { return }
        cancel(noteID: id)

        let content = makeContent(for: note)

        if let rule = note.recurrenceRule {
            await scheduleRecurring(rule, noteID: id, content: content, center: center)
            return
        }

        guard let fireDate = note.remindDate, fireDate > Date() else { return }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: id), content: content, trigger: trigger)
        try? await center.add(request)
    }

    private static func makeContent(for note: Note) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Console Mode"
        content.body = note.body
        if let project = note.project, !project.isEmpty {
            content.subtitle = project
        }
        content.sound = .default
        return content
    }

    private static func scheduleRecurring(
        _ rule: RecurrenceRule,
        noteID: Int64,
        content: UNMutableNotificationContent,
        center: UNUserNotificationCenter
    ) async {
        switch rule {
        case .daily(let hour, let minute):
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: identifier(for: noteID), content: content, trigger: trigger)
            try? await center.add(request)

        case .weekly(let weekday, let hour, let minute):
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: identifier(for: noteID), content: content, trigger: trigger)
            try? await center.add(request)

        case .weekdays(let hour, let minute):
            for weekday in 2...6 {
                var components = DateComponents()
                components.weekday = weekday
                components.hour = hour
                components.minute = minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(
                    identifier: weekdayIdentifier(for: noteID, weekday: weekday),
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }
    }

    static func cancel(noteID: Int64) {
        guard let center else { return }
        let identifiers = [identifier(for: noteID)] + (2...6).map { weekdayIdentifier(for: noteID, weekday: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func identifier(for noteID: Int64) -> String {
        "console-mode-note-\(noteID)"
    }

    private static func weekdayIdentifier(for noteID: Int64, weekday: Int) -> String {
        "console-mode-note-\(noteID)-wd\(weekday)"
    }
}