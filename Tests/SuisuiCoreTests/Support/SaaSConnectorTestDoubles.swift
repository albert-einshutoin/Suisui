import Foundation
@testable import SuisuiCore
@testable import SuisuiExternalConnectors

final class InMemoryOAuthCredentialMetadataStore: OAuthCredentialMetadataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var metadata: [SaaSConnectorID: OAuthCredentialMetadata]

    init(metadata: [SaaSConnectorID: OAuthCredentialMetadata] = [:]) {
        self.metadata = metadata
    }

    func loadMetadata(for connectorID: SaaSConnectorID) throws -> OAuthCredentialMetadata? {
        lock.withLock {
            metadata[connectorID]
        }
    }

    func saveMetadata(_ metadata: OAuthCredentialMetadata) throws {
        lock.withLock {
            self.metadata[metadata.connectorID] = metadata
        }
    }

    func deleteMetadata(for connectorID: SaaSConnectorID) throws {
        _ = lock.withLock {
            metadata.removeValue(forKey: connectorID)
        }
    }
}

final class InMemoryGoogleCalendarClient: GoogleCalendarClient, @unchecked Sendable {
    private let validCalendarIDs: Set<String>
    private let lock = NSLock()
    private var records: [GoogleCalendarEventRecord] = []
    private var nextID = 1

    init(validCalendarIDs: Set<String>) {
        self.validCalendarIDs = validCalendarIDs
    }

    func createEvent(_ draft: CalendarEventDraft, calendarID: String, timeZoneIdentifier: String) throws -> GoogleCalendarEventRecord {
        guard validCalendarIDs.contains(calendarID) else {
            throw SaaSConnectorError.invalidRequest(.googleCalendar, "Calendar \(calendarID) is not available.")
        }

        return lock.withLock {
            let record = GoogleCalendarEventRecord(
                calendarID: calendarID,
                timeZoneIdentifier: timeZoneIdentifier,
                event: CalendarEventRecord(id: "google-calendar-event-\(nextID)", draft: draft)
            )
            nextID += 1
            records.append(record)
            return record
        }
    }
}

final class InMemoryGmailDraftClient: GmailDraftClient, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [GmailDraftRecord] = []
    private var nextID = 1

    func createDraft(_ draft: GmailDraft) throws -> GmailDraftRecord {
        lock.withLock {
            let record = GmailDraftRecord(id: "gmail-draft-\(nextID)", to: draft.to, subject: draft.subject, body: draft.body)
            nextID += 1
            records.append(record)
            return record
        }
    }
}

final class InMemorySlackClient: SlackClient, @unchecked Sendable {
    private let lock = NSLock()
    private var channels: [String: String]
    private var nextID = 1
    var isTokenRevoked: Bool

    init(channels: [String: String], isTokenRevoked: Bool = false) {
        self.channels = channels
        self.isTokenRevoked = isTokenRevoked
    }

    func channelExists(_ channelID: String) throws -> Bool {
        lock.withLock {
            channels[channelID] != nil
        }
    }

    func postMessage(channelID: String, text: String) throws -> SlackMessageRecord {
        guard !isTokenRevoked else {
            throw SaaSConnectorError.tokenRevoked(.slack)
        }
        return lock.withLock {
            let record = SlackMessageRecord(id: "slack-message-\(nextID)", channelID: channelID, text: text)
            nextID += 1
            return record
        }
    }
}

final class InMemoryGoogleDriveClient: GoogleDriveClient, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 1

    func createDocument(title: String, body: String, folderID: String) throws -> GoogleDriveDocumentRecord {
        lock.withLock {
            let record = GoogleDriveDocumentRecord(id: "drive-doc-\(nextID)", folderID: folderID, title: title, body: body)
            nextID += 1
            return record
        }
    }
}

final class InMemoryNotionClient: NotionClient, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 1
    var nextError: SaaSConnectorError?

    init(nextError: SaaSConnectorError? = nil) {
        self.nextError = nextError
    }

    func createPage(databaseID: String, title: String, properties: [String: String]) throws -> NotionPageRecord {
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        return lock.withLock {
            let record = NotionPageRecord(id: "notion-page-\(nextID)", databaseID: databaseID, title: title, properties: properties)
            nextID += 1
            return record
        }
    }
}

final class InMemoryExternalTaskClient: ExternalTaskClient, @unchecked Sendable {
    private let lock = NSLock()
    private let providerID: SaaSConnectorID
    private var records: [ExternalTaskRecord] = []
    private var nextID = 1

    init(providerID: SaaSConnectorID) {
        self.providerID = providerID
    }

    func createTask(_ draft: ExternalTaskDraft, destination: ExternalTaskDestination) throws -> ExternalTaskRecord {
        lock.withLock {
            let record = ExternalTaskRecord(
                providerID: providerID,
                externalID: "\(providerID.rawValue)-task-\(nextID)",
                title: draft.title,
                detail: draft.detail,
                status: draft.status,
                priority: draft.priority,
                dueAt: draft.dueAt,
                url: "https://example.com/\(providerID.rawValue)/\(nextID)"
            )
            nextID += 1
            records.append(record)
            return record
        }
    }

    func listTasks(destination: ExternalTaskDestination?) throws -> [ExternalTaskRecord] {
        lock.withLock { records }
    }
}

struct StaticConnectorHealthClient: ConnectorHealthClient {
    private let results: [SaaSConnectorID: ConnectorHealthStatus]

    init(results: [SaaSConnectorID: ConnectorHealthStatus] = [:]) {
        self.results = results
    }

    func health(for connectorID: SaaSConnectorID, credential: OAuthCredential) throws -> ConnectorHealthStatus {
        results[connectorID] ?? .connected
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
