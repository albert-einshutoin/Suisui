import Foundation

public enum ExternalIntegrationIdentifier {
    // Keep cross-target provider IDs in Core so connector/runtime targets do not drift
    // while still avoiding dependencies on concrete OAuth, HTTP, or platform adapters.
    public static let googleCalendar = "google_calendar"
}

public enum ExternalAuthorizationScopeIdentifier {
    public static let googleCalendarEventsWrite = "https://www.googleapis.com/auth/calendar.events"
    public static let googleCalendarCalendarListReadOnly = "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    public static let offlineAccess = "offline_access"
}
