import XCTest
@testable import SuisuiCore

final class NotificationQuietHoursTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else {
            XCTFail("Invalid fixture date: \(iso)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func overnightSettings(enabled: Bool = true) -> NotificationQuietHoursSettings {
        NotificationQuietHoursSettings(
            enabled: enabled,
            startMinuteOfDay: 22 * 60,
            endMinuteOfDay: 8 * 60
        )
    }

    func testDisabledSettingsReturnInputUnchanged() {
        let fireDate = date("2026-07-07T23:30:00Z")

        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(
                for: fireDate,
                settings: overnightSettings(enabled: false),
                timeZone: utc
            ),
            fireDate
        )
    }

    func testDateOutsideWindowReturnsInputUnchanged() {
        let fireDate = date("2026-07-07T12:00:00Z")

        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(for: fireDate, settings: overnightSettings(), timeZone: utc),
            fireDate
        )
    }

    func testOvernightWindowDefersEveningDateToNextMorning() {
        let fireDate = date("2026-07-07T23:30:00Z")

        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(for: fireDate, settings: overnightSettings(), timeZone: utc),
            date("2026-07-08T08:00:00Z")
        )
    }

    func testOvernightWindowDefersEarlyMorningDateToSameMorning() {
        let fireDate = date("2026-07-08T06:15:00Z")

        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(for: fireDate, settings: overnightSettings(), timeZone: utc),
            date("2026-07-08T08:00:00Z")
        )
    }

    func testSameDayWindowDefersToWindowEnd() {
        let settings = NotificationQuietHoursSettings(
            enabled: true,
            startMinuteOfDay: 13 * 60,
            endMinuteOfDay: 15 * 60
        )

        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(
                for: date("2026-07-07T14:00:00Z"),
                settings: settings,
                timeZone: utc
            ),
            date("2026-07-07T15:00:00Z")
        )
        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(
                for: date("2026-07-07T12:59:00Z"),
                settings: settings,
                timeZone: utc
            ),
            date("2026-07-07T12:59:00Z")
        )
        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(
                for: date("2026-07-07T15:01:00Z"),
                settings: settings,
                timeZone: utc
            ),
            date("2026-07-07T15:01:00Z")
        )
    }

    func testExactWindowStartIsDeferredAndExactWindowEndIsNot() {
        let atStart = date("2026-07-07T22:00:00Z")
        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(for: atStart, settings: overnightSettings(), timeZone: utc),
            date("2026-07-08T08:00:00Z")
        )

        let atEnd = date("2026-07-08T08:00:00Z")
        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(for: atEnd, settings: overnightSettings(), timeZone: utc),
            atEnd
        )
    }

    func testDegenerateStartEqualsEndWindowIsTreatedAsDisabled() {
        let settings = NotificationQuietHoursSettings(
            enabled: true,
            startMinuteOfDay: 9 * 60,
            endMinuteOfDay: 9 * 60
        )
        let fireDate = date("2026-07-07T09:00:00Z")

        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(for: fireDate, settings: settings, timeZone: utc),
            fireDate
        )
    }

    func testDeferralUsesTheProvidedTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        // 2026-07-07T14:00:00Z == 23:00 in Tokyo (UTC+9): inside 22:00-08:00.
        let fireDate = date("2026-07-07T14:00:00Z")

        let deferred = NotificationQuietHours.deferredFireDate(
            for: fireDate,
            settings: overnightSettings(),
            timeZone: tokyo
        )

        // 08:00 Tokyo the next day == 2026-07-07T23:00:00Z.
        XCTAssertEqual(deferred, date("2026-07-07T23:00:00Z"))
        // The same instant is outside the window in UTC (14:00) and stays put.
        XCTAssertEqual(
            NotificationQuietHours.deferredFireDate(for: fireDate, settings: overnightSettings(), timeZone: utc),
            fireDate
        )
    }

    func testSchedulingPolicyShiftsPreDeadlineRemindersByLeadTimeThenDefers() {
        let preferences = NotificationPreferences(
            quietHours: overnightSettings(),
            deadlineReminderLeadTime: .oneHourBefore
        )
        // Due 23:00: one hour earlier is 22:00, exactly at the quiet window
        // start, so the reminder lands at 08:00 the next morning.
        let dueAt = date("2026-07-07T23:00:00Z")

        XCTAssertEqual(
            NotificationSchedulingPolicy.finalFireDate(
                proposed: dueAt,
                kind: .preDeadlineReminder,
                preferences: preferences,
                timeZone: utc
            ),
            date("2026-07-08T08:00:00Z")
        )

        // Outside quiet hours only the lead-time shift applies.
        XCTAssertEqual(
            NotificationSchedulingPolicy.finalFireDate(
                proposed: date("2026-07-07T15:00:00Z"),
                kind: .preDeadlineReminder,
                preferences: preferences,
                timeZone: utc
            ),
            date("2026-07-07T14:00:00Z")
        )
    }

    func testSchedulingPolicyNeverShiftsFixedTimeNotificationsByLeadTime() {
        let preferences = NotificationPreferences(
            quietHours: overnightSettings(),
            deadlineReminderLeadTime: .oneDayBefore
        )

        // Digest/weekly/snooze fire dates only pass quiet-hours deferral.
        XCTAssertEqual(
            NotificationSchedulingPolicy.finalFireDate(
                proposed: date("2026-07-07T09:00:00Z"),
                kind: .fixedTime,
                preferences: preferences,
                timeZone: utc
            ),
            date("2026-07-07T09:00:00Z")
        )
        XCTAssertEqual(
            NotificationSchedulingPolicy.finalFireDate(
                proposed: date("2026-07-07T23:00:00Z"),
                kind: .fixedTime,
                preferences: preferences,
                timeZone: utc
            ),
            date("2026-07-08T08:00:00Z")
        )
    }

    func testNotificationPreferencesDecodeLegacyJSONWithoutNewKeys() throws {
        let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: Data("{}".utf8))

        XCTAssertEqual(decoded, .default)
        XCTAssertFalse(decoded.quietHours.enabled)
        XCTAssertEqual(decoded.quietHours.startMinuteOfDay, 22 * 60)
        XCTAssertEqual(decoded.quietHours.endMinuteOfDay, 8 * 60)
        XCTAssertEqual(decoded.deadlineReminderLeadTime, .atDue)
        XCTAssertTrue(decoded.avoidsWeekends)
    }

    func testAppSettingsDecodeLegacyJSONWithoutNotificationPreferences() throws {
        // The persisted shape from before quiet hours existed.
        let legacyData = Data("""
        {
            "aiProvider": "openaiResponses",
            "sttProvider": "openAITranscribe",
            "notificationsEnabled": true,
            "timeZoneIdentifier": "UTC",
            "googleCalendarID": "primary"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)

        XCTAssertTrue(decoded.notificationsEnabled)
        XCTAssertEqual(decoded.notificationPreferences, .default)
    }

    func testNotificationPreferencesRoundTripKeepsConfiguredValues() throws {
        let preferences = NotificationPreferences(
            quietHours: NotificationQuietHoursSettings(
                enabled: true,
                startMinuteOfDay: 21 * 60 + 30,
                endMinuteOfDay: 7 * 60 + 15
            ),
            deadlineReminderLeadTime: .thirtyMinutesBefore,
            avoidsWeekends: false
        )

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: data)

        XCTAssertEqual(decoded, preferences)
    }
}
