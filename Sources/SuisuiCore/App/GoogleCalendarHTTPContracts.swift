import Foundation

public struct GoogleCalendarHTTPConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var timeoutInterval: TimeInterval

    public init(
        baseURL: URL = URL(string: "https://www.googleapis.com/calendar/v3")!,
        timeoutInterval: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
    }
}

public protocol SynchronousHTTPDataClient: Sendable {
    func data(for request: URLRequest) throws -> (Data, HTTPURLResponse)
}

package struct GoogleCalendarEventRequest: Encodable {
    package var id: String?
    package var summary: String
    package var description: String?
    package var start: GoogleCalendarEventDate
    package var end: GoogleCalendarEventDate
    package var extendedProperties: GoogleCalendarEventExtendedProperties?

    package init(draft: CalendarEventDraft, timeZoneIdentifier: String) {
        let normalizedID = GoogleCalendarEventID.normalized(draft.idempotencyKey)
        id = normalizedID
        summary = draft.title
        description = draft.notes
        if draft.isAllDay {
            start = GoogleCalendarEventDate(date: draft.startAt, dateTime: nil, timeZone: nil)
            end = GoogleCalendarEventDate(date: draft.endAt, dateTime: nil, timeZone: nil)
        } else {
            start = GoogleCalendarEventDate(date: nil, dateTime: draft.startAt, timeZone: timeZoneIdentifier)
            end = GoogleCalendarEventDate(date: nil, dateTime: draft.endAt, timeZone: timeZoneIdentifier)
        }
        extendedProperties = normalizedID.map {
            GoogleCalendarEventExtendedProperties(privateProperties: ["suisuiIdempotencyKey": $0])
        }
    }
}

package struct GoogleCalendarEventDate: Encodable {
    package var date: String?
    package var dateTime: String?
    package var timeZone: String?
}

package struct GoogleCalendarEventExtendedProperties: Encodable {
    package var privateProperties: [String: String]

    enum CodingKeys: String, CodingKey {
        case privateProperties = "private"
    }
}

package enum GoogleCalendarEventID {
    private static let allowedCharacters = Set("0123456789abcdefghijklmnopqrstuv")
    private static let prefix = "suisui"
    private static let digestLength = 64

    package static func normalized(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let suffix = candidate.dropFirst(prefix.count)
        guard candidate.hasPrefix(prefix),
              suffix.count == digestLength,
              candidate.allSatisfy({ allowedCharacters.contains($0) }) else {
            // Google rejects invalid caller-provided event IDs. Dropping a bad
            // key is safer than turning an approved user write into a 400 while
            // the Core sync service owns generation of valid Suisui keys.
            return nil
        }
        return candidate
    }
}

package struct GoogleCalendarEventResponse: Decodable {
    package var id: String?
}
