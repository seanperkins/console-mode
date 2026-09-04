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

    static func schedule(note: Note) async {
        guard let center else { return }
        guard let id = note.id, let fireDate = note.remindDate, fireDate > Date() else {
            if let id = note.id {
                cancel(noteID: id)
            }
            return
        }

        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Console Mode"
        content.body = note.body
        if let project = note.project, !project.isEmpty {
            content.subtitle = project
        }
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: id), content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancel(noteID: Int64) {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: noteID)])
    }

    private static func identifier(for noteID: Int64) -> String {
        "console-mode-note-\(noteID)"
    }
}