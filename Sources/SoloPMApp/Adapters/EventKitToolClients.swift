import Foundation
import SoloPMCore
@preconcurrency import EventKit

final class EventKitCalendarClient: CalendarClient, @unchecked Sendable {
    private let eventStore: EKEventStore
    private let dateFormatter = ISO8601DateFormatter()

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEventRecord {
        guard Self.isAuthorized(EKEventStore.authorizationStatus(for: .event)) else {
            throw ToolClientError.permissionDenied("Calendar permission is denied.")
        }

        guard let startDate = dateFormatter.date(from: draft.startAt),
              let endDate = dateFormatter.date(from: draft.endAt) else {
            throw ToolClientError.invalidRequest("Calendar event dates must be ISO8601.")
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = draft.isAllDay
        event.notes = draft.notes
        event.calendar = eventStore.defaultCalendarForNewEvents

        try eventStore.save(event, span: .thisEvent, commit: true)

        return CalendarEventRecord(id: event.eventIdentifier ?? UUID().uuidString, draft: draft)
    }

    func listEvents() throws -> [CalendarEventRecord] {
        []
    }

    private static func isAuthorized(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .fullAccess, .writeOnly:
            return true
        case .notDetermined, .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }
}

final class EventKitReminderClient: ReminderClient, @unchecked Sendable {
    private let eventStore: EKEventStore
    private let dateFormatter = ISO8601DateFormatter()

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func create(_ draft: ReminderDraft) throws -> ReminderRecord {
        guard Self.isAuthorized(EKEventStore.authorizationStatus(for: .reminder)) else {
            throw ToolClientError.permissionDenied("Reminder permission is denied.")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = draft.title
        reminder.calendar = try calendar(named: draft.listName)
        if let dueAt = draft.dueAt {
            guard let dueDate = dateFormatter.date(from: dueAt) else {
                throw ToolClientError.invalidRequest("Reminder due date must be ISO8601.")
            }
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }

        try eventStore.save(reminder, commit: true)

        return ReminderRecord(
            id: reminder.calendarItemIdentifier,
            title: reminder.title,
            dueAt: draft.dueAt,
            listName: draft.listName,
            isCompleted: reminder.isCompleted
        )
    }

    func markComplete(id: String) throws -> ReminderRecord {
        guard Self.isAuthorized(EKEventStore.authorizationStatus(for: .reminder)) else {
            throw ToolClientError.permissionDenied("Reminder permission is denied.")
        }
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw ToolClientError.notFound("Reminder \(id) was not found.")
        }

        reminder.isCompleted = true
        try eventStore.save(reminder, commit: true)

        return ReminderRecord(
            id: reminder.calendarItemIdentifier,
            title: reminder.title,
            dueAt: nil,
            listName: reminder.calendar.title,
            isCompleted: reminder.isCompleted
        )
    }

    func list() throws -> [ReminderRecord] {
        []
    }

    private func calendar(named listName: String?) throws -> EKCalendar {
        if let listName,
           let calendar = eventStore.calendars(for: .reminder).first(where: { $0.title == listName }) {
            return calendar
        }

        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw ToolClientError.notFound("Default reminder list was not found.")
        }

        return calendar
    }

    private static func isAuthorized(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .fullAccess, .writeOnly:
            return true
        case .notDetermined, .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }
}
