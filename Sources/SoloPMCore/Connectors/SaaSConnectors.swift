import Foundation

public enum SaaSConnectorID: String, Codable, CaseIterable, Hashable, Sendable {
    case googleCalendar = "google_calendar"
    case gmail
    case slack
    case googleDrive = "google_drive"
    case notion
    case weKnora = "weknora"
}

public struct OAuthScope: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let offlineAccess: OAuthScope = "offline_access"
    public static let googleCalendarEvents: OAuthScope = "https://www.googleapis.com/auth/calendar.events"
    public static let gmailCompose: OAuthScope = "https://www.googleapis.com/auth/gmail.compose"
    public static let gmailSend: OAuthScope = "https://www.googleapis.com/auth/gmail.send"
    public static let slackChannelsRead: OAuthScope = "channels:read"
    public static let slackChatWrite: OAuthScope = "chat:write"
    public static let googleDriveFile: OAuthScope = "https://www.googleapis.com/auth/drive.file"
    public static let notionInsertContent: OAuthScope = "notion.insert_content"
}

public struct OAuthCredential: Equatable, Sendable {
    public var connectorID: SaaSConnectorID
    public var scopes: Set<OAuthScope>
    public var expiresAt: Date
    public var accessTokenKey: SecretKey
    public var refreshTokenKey: SecretKey?

    public init(
        connectorID: SaaSConnectorID,
        scopes: Set<OAuthScope>,
        expiresAt: Date,
        accessTokenKey: SecretKey,
        refreshTokenKey: SecretKey?
    ) {
        self.connectorID = connectorID
        self.scopes = scopes
        self.expiresAt = expiresAt
        self.accessTokenKey = accessTokenKey
        self.refreshTokenKey = refreshTokenKey
    }
}

public struct OAuthCredentialMetadata: Codable, Equatable, Sendable {
    public var connectorID: SaaSConnectorID
    public var scopes: Set<OAuthScope>
    public var expiresAt: Date
    public var accessTokenKey: SecretKey
    public var refreshTokenKey: SecretKey?

    public init(credential: OAuthCredential) {
        self.connectorID = credential.connectorID
        self.scopes = credential.scopes
        self.expiresAt = credential.expiresAt
        self.accessTokenKey = credential.accessTokenKey
        self.refreshTokenKey = credential.refreshTokenKey
    }

    public var credential: OAuthCredential {
        OAuthCredential(
            connectorID: connectorID,
            scopes: scopes,
            expiresAt: expiresAt,
            accessTokenKey: accessTokenKey,
            refreshTokenKey: refreshTokenKey
        )
    }
}

public protocol OAuthCredentialMetadataStore: Sendable {
    func loadMetadata(for connectorID: SaaSConnectorID) throws -> OAuthCredentialMetadata?
    func saveMetadata(_ metadata: OAuthCredentialMetadata) throws
    func deleteMetadata(for connectorID: SaaSConnectorID) throws
}

public final class InMemoryOAuthCredentialMetadataStore: OAuthCredentialMetadataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var metadata: [SaaSConnectorID: OAuthCredentialMetadata]

    public init(metadata: [SaaSConnectorID: OAuthCredentialMetadata] = [:]) {
        self.metadata = metadata
    }

    public func loadMetadata(for connectorID: SaaSConnectorID) throws -> OAuthCredentialMetadata? {
        lock.withLock {
            metadata[connectorID]
        }
    }

    public func saveMetadata(_ metadata: OAuthCredentialMetadata) throws {
        lock.withLock {
            self.metadata[metadata.connectorID] = metadata
        }
    }

    public func deleteMetadata(for connectorID: SaaSConnectorID) throws {
        _ = lock.withLock {
            metadata.removeValue(forKey: connectorID)
        }
    }
}

public protocol OAuthCredentialStore: Sendable {
    func loadCredential(for connectorID: SaaSConnectorID) throws -> OAuthCredential?
    func saveTokens(
        connectorID: SaaSConnectorID,
        accessToken: String,
        refreshToken: String?,
        scopes: Set<OAuthScope>,
        expiresAt: Date
    ) throws
    func accessToken(for credential: OAuthCredential) throws -> String?
    func refreshToken(for credential: OAuthCredential) throws -> String?
    func deleteCredential(for connectorID: SaaSConnectorID) throws
}

public final class KeychainOAuthCredentialStore: OAuthCredentialStore, @unchecked Sendable {
    private let secretStore: any SecretStore
    private let metadataStore: any OAuthCredentialMetadataStore

    public init(secretStore: any SecretStore, metadataStore: any OAuthCredentialMetadataStore) {
        self.secretStore = secretStore
        self.metadataStore = metadataStore
    }

    public func loadCredential(for connectorID: SaaSConnectorID) throws -> OAuthCredential? {
        try metadataStore.loadMetadata(for: connectorID)?.credential
    }

    public func saveTokens(
        connectorID: SaaSConnectorID,
        accessToken: String,
        refreshToken: String?,
        scopes: Set<OAuthScope>,
        expiresAt: Date
    ) throws {
        let accessTokenKey = Self.accessTokenKey(connectorID)
        let refreshTokenKey = refreshToken.map { _ in Self.refreshTokenKey(connectorID) }
        try secretStore.save(accessToken, for: accessTokenKey)
        if let refreshToken, let refreshTokenKey {
            try secretStore.save(refreshToken, for: refreshTokenKey)
        }

        try metadataStore.saveMetadata(OAuthCredentialMetadata(credential: OAuthCredential(
            connectorID: connectorID,
            scopes: scopes,
            expiresAt: expiresAt,
            accessTokenKey: accessTokenKey,
            refreshTokenKey: refreshTokenKey
        )))
    }

    public func accessToken(for credential: OAuthCredential) throws -> String? {
        try secretStore.read(credential.accessTokenKey)
    }

    public func refreshToken(for credential: OAuthCredential) throws -> String? {
        guard let key = credential.refreshTokenKey else {
            return nil
        }
        return try secretStore.read(key)
    }

    public func deleteCredential(for connectorID: SaaSConnectorID) throws {
        if let credential = try loadCredential(for: connectorID) {
            try secretStore.delete(credential.accessTokenKey)
            if let refreshTokenKey = credential.refreshTokenKey {
                try secretStore.delete(refreshTokenKey)
            }
        }
        try metadataStore.deleteMetadata(for: connectorID)
    }

    private static func accessTokenKey(_ connectorID: SaaSConnectorID) -> SecretKey {
        SecretKey("oauth.\(connectorID.rawValue).access_token")
    }

    private static func refreshTokenKey(_ connectorID: SaaSConnectorID) -> SecretKey {
        SecretKey("oauth.\(connectorID.rawValue).refresh_token")
    }
}

public struct OAuthTokenResponse: Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var scopes: Set<OAuthScope>

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, scopes: Set<OAuthScope>) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }
}

public struct OAuthRefreshRequest: Equatable, Sendable {
    public var connectorID: SaaSConnectorID
    public var refreshToken: String
    public var scopes: Set<OAuthScope>
}

public protocol OAuthClient: Sendable {
    func refreshToken(_ request: OAuthRefreshRequest) throws -> OAuthTokenResponse
    func revokeToken(connectorID: SaaSConnectorID, accessToken: String?) throws
}

public enum OAuthTokenLifecycleError: Error, Equatable, Sendable {
    case disconnected(SaaSConnectorID)
    case tokenExpired(SaaSConnectorID)
    case scopeMismatch(SaaSConnectorID, missing: Set<OAuthScope>)
}

public struct OAuthTokenLifecycle: Sendable {
    private let store: any OAuthCredentialStore
    private let client: any OAuthClient

    public init(store: any OAuthCredentialStore, client: any OAuthClient) {
        self.store = store
        self.client = client
    }

    public func validCredential(
        for connectorID: SaaSConnectorID,
        requiredScopes: Set<OAuthScope>,
        now: Date = Date()
    ) throws -> OAuthCredential {
        guard var credential = try store.loadCredential(for: connectorID) else {
            throw OAuthTokenLifecycleError.disconnected(connectorID)
        }

        try assertScopes(credential.scopes, include: requiredScopes, connectorID: connectorID)

        guard credential.expiresAt <= now else {
            return credential
        }

        guard let refreshToken = try store.refreshToken(for: credential), !refreshToken.isEmpty else {
            throw OAuthTokenLifecycleError.tokenExpired(connectorID)
        }

        let response = try client.refreshToken(OAuthRefreshRequest(
            connectorID: connectorID,
            refreshToken: refreshToken,
            scopes: credential.scopes
        ))
        try assertScopes(response.scopes, include: requiredScopes, connectorID: connectorID)
        try store.saveTokens(
            connectorID: connectorID,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            scopes: response.scopes,
            expiresAt: response.expiresAt
        )
        credential = try store.loadCredential(for: connectorID) ?? credential
        return credential
    }

    public func disconnect(_ connectorID: SaaSConnectorID) throws {
        let accessToken: String?
        if let credential = try store.loadCredential(for: connectorID) {
            accessToken = try store.accessToken(for: credential)
        } else {
            accessToken = nil
        }
        try client.revokeToken(connectorID: connectorID, accessToken: accessToken)
        try store.deleteCredential(for: connectorID)
    }

    private func assertScopes(_ scopes: Set<OAuthScope>, include requiredScopes: Set<OAuthScope>, connectorID: SaaSConnectorID) throws {
        let missing = requiredScopes.subtracting(scopes)
        guard missing.isEmpty else {
            throw OAuthTokenLifecycleError.scopeMismatch(connectorID, missing: missing)
        }
    }
}

public enum SaaSConnectorError: Error, Equatable, Sendable {
    case approvalRequired(SaaSConnectorID)
    case permissionDenied(SaaSConnectorID, String)
    case invalidRequest(SaaSConnectorID, String)
    case notFound(SaaSConnectorID, String)
    case tokenRevoked(SaaSConnectorID)
    case mappingMissing(SaaSConnectorID, String)
    case apiFailure(SaaSConnectorID, String)
}

public enum SaaSConnectorOperation: String, Equatable, Sendable {
    case createDraft
    case send
    case post
    case create
}

public struct GoogleCalendarEventRecord: Equatable, Sendable {
    public var calendarID: String
    public var timeZoneIdentifier: String
    public var event: CalendarEventRecord
}

public protocol GoogleCalendarClient: Sendable {
    func createEvent(_ draft: CalendarEventDraft, calendarID: String, timeZoneIdentifier: String) throws -> GoogleCalendarEventRecord
}

public struct GoogleCalendarConnector: Sendable {
    public let connectorID: SaaSConnectorID = .googleCalendar
    public let requiredScopes: Set<OAuthScope> = [.googleCalendarEvents]
    private let client: any GoogleCalendarClient

    public init(client: any GoogleCalendarClient) {
        self.client = client
    }

    public func createEvent(
        _ draft: CalendarEventDraft,
        calendarID: String,
        timeZoneIdentifier: String,
        context: ToolExecutionContext
    ) throws -> GoogleCalendarEventRecord {
        try requireApproval(context)
        return try client.createEvent(draft, calendarID: calendarID, timeZoneIdentifier: timeZoneIdentifier)
    }
}

public final class InMemoryGoogleCalendarClient: GoogleCalendarClient, @unchecked Sendable {
    private let validCalendarIDs: Set<String>
    private let lock = NSLock()
    private var records: [GoogleCalendarEventRecord] = []
    private var nextID = 1

    public init(validCalendarIDs: Set<String>) {
        self.validCalendarIDs = validCalendarIDs
    }

    public func createEvent(_ draft: CalendarEventDraft, calendarID: String, timeZoneIdentifier: String) throws -> GoogleCalendarEventRecord {
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

public struct GmailDraft: Equatable, Sendable {
    public var to: [String]
    public var subject: String
    public var body: String

    public init(to: [String], subject: String, body: String) {
        self.to = to
        self.subject = subject
        self.body = body
    }
}

public struct GmailDraftRecord: Equatable, Sendable {
    public var id: String
    public var to: [String]
    public var subject: String
    public var body: String
}

public protocol GmailDraftClient: Sendable {
    func createDraft(_ draft: GmailDraft) throws -> GmailDraftRecord
}

public struct GmailDraftConnector: Sendable {
    public let connectorID: SaaSConnectorID = .gmail
    public let requiredScopes: Set<OAuthScope> = [.gmailCompose]
    public let supportedOperations: Set<SaaSConnectorOperation> = [.createDraft]
    private let client: any GmailDraftClient

    public init(client: any GmailDraftClient) {
        self.client = client
    }

    public func createDraft(_ draft: GmailDraft, context: ToolExecutionContext) throws -> GmailDraftRecord {
        try requireApproval(context)
        return try client.createDraft(draft)
    }
}

public final class InMemoryGmailDraftClient: GmailDraftClient, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [GmailDraftRecord] = []
    private var nextID = 1

    public init() {}

    public func createDraft(_ draft: GmailDraft) throws -> GmailDraftRecord {
        lock.withLock {
            let record = GmailDraftRecord(id: "gmail-draft-\(nextID)", to: draft.to, subject: draft.subject, body: draft.body)
            nextID += 1
            records.append(record)
            return record
        }
    }
}

public struct SlackMessageDraft: Equatable, Sendable {
    public var channelID: String
    public var text: String
}

public struct SlackMessageRecord: Equatable, Sendable {
    public var id: String
    public var channelID: String
    public var text: String
}

public protocol SlackClient: Sendable {
    func channelExists(_ channelID: String) throws -> Bool
    func postMessage(channelID: String, text: String) throws -> SlackMessageRecord
}

public struct SlackConnector: Sendable {
    public let connectorID: SaaSConnectorID = .slack
    public let channelReadScopes: Set<OAuthScope> = [.slackChannelsRead]
    public let postScopes: Set<OAuthScope> = [.slackChatWrite]
    private let client: any SlackClient

    public init(client: any SlackClient) {
        self.client = client
    }

    public func draftMessage(channelID: String, text: String) throws -> SlackMessageDraft {
        guard try client.channelExists(channelID) else {
            throw SaaSConnectorError.notFound(.slack, "Slack channel \(channelID) was not found.")
        }
        return SlackMessageDraft(channelID: channelID, text: text)
    }

    public func postMessage(channelID: String, text: String, context: ToolExecutionContext) throws -> SlackMessageRecord {
        try requireApproval(context)
        guard try client.channelExists(channelID) else {
            throw SaaSConnectorError.notFound(.slack, "Slack channel \(channelID) was not found.")
        }
        return try client.postMessage(channelID: channelID, text: text)
    }
}

public final class InMemorySlackClient: SlackClient, @unchecked Sendable {
    private let lock = NSLock()
    private var channels: [String: String]
    private var nextID = 1
    public var isTokenRevoked: Bool

    public init(channels: [String: String], isTokenRevoked: Bool = false) {
        self.channels = channels
        self.isTokenRevoked = isTokenRevoked
    }

    public func channelExists(_ channelID: String) throws -> Bool {
        lock.withLock {
            channels[channelID] != nil
        }
    }

    public func postMessage(channelID: String, text: String) throws -> SlackMessageRecord {
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

public struct GoogleDriveDocumentRecord: Equatable, Sendable {
    public var id: String
    public var folderID: String
    public var title: String
    public var body: String
}

public protocol GoogleDriveClient: Sendable {
    func createDocument(title: String, body: String, folderID: String) throws -> GoogleDriveDocumentRecord
}

public struct GoogleDriveConnector: Sendable {
    public let connectorID: SaaSConnectorID = .googleDrive
    public let requiredScopes: Set<OAuthScope> = [.googleDriveFile]
    private let selectedFolderID: String
    private let client: any GoogleDriveClient

    public init(selectedFolderID: String, client: any GoogleDriveClient) {
        self.selectedFolderID = selectedFolderID
        self.client = client
    }

    public func createDocument(title: String, body: String, folderID: String, context: ToolExecutionContext) throws -> GoogleDriveDocumentRecord {
        try requireApproval(context)
        guard folderID == selectedFolderID else {
            throw SaaSConnectorError.permissionDenied(.googleDrive, "Folder \(folderID) is outside the selected Drive scope.")
        }
        return try client.createDocument(title: title, body: body, folderID: folderID)
    }
}

public final class InMemoryGoogleDriveClient: GoogleDriveClient, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 1

    public init() {}

    public func createDocument(title: String, body: String, folderID: String) throws -> GoogleDriveDocumentRecord {
        lock.withLock {
            let record = GoogleDriveDocumentRecord(id: "drive-doc-\(nextID)", folderID: folderID, title: title, body: body)
            nextID += 1
            return record
        }
    }
}

public enum NotionMappingKind: String, Codable, Hashable, Sendable {
    case project
    case task
}

public struct NotionMapping: Equatable, Sendable {
    public var databaseID: String
    public var titleProperty: String

    public init(databaseID: String, titleProperty: String) {
        self.databaseID = databaseID
        self.titleProperty = titleProperty
    }
}

public struct NotionPageRecord: Equatable, Sendable {
    public var id: String
    public var databaseID: String
    public var title: String
    public var properties: [String: String]
}

public protocol NotionClient: Sendable {
    func createPage(databaseID: String, title: String, properties: [String: String]) throws -> NotionPageRecord
}

public struct NotionConnector: Sendable {
    public let connectorID: SaaSConnectorID = .notion
    public let requiredScopes: Set<OAuthScope> = [.notionInsertContent]
    private let mappings: [NotionMappingKind: NotionMapping]
    private let client: any NotionClient

    public init(mappings: [NotionMappingKind: NotionMapping], client: any NotionClient) {
        self.mappings = mappings
        self.client = client
    }

    public func createPage(kind: NotionMappingKind, title: String, properties: [String: String], context: ToolExecutionContext) throws -> NotionPageRecord {
        guard let mapping = mappings[kind] else {
            throw SaaSConnectorError.mappingMissing(.notion, kind.rawValue)
        }
        try requireApproval(context)
        return try client.createPage(databaseID: mapping.databaseID, title: title, properties: properties)
    }
}

public final class InMemoryNotionClient: NotionClient, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 1
    public var nextError: SaaSConnectorError?

    public init(nextError: SaaSConnectorError? = nil) {
        self.nextError = nextError
    }

    public func createPage(databaseID: String, title: String, properties: [String: String]) throws -> NotionPageRecord {
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

public enum ConnectorHealthStatus: Equatable, Sendable {
    case connected
    case disconnected
    case tokenExpired
    case permissionIssue(String)
}

public enum ConnectorReconnectAction: Equatable, Sendable {
    case reconnect(SaaSConnectorID)
}

public struct ConnectorHealthSnapshot: Equatable, Sendable {
    public var connectorID: SaaSConnectorID
    public var status: ConnectorHealthStatus
    public var reconnectAction: ConnectorReconnectAction?
    public var lastError: String?
}

public protocol ConnectorHealthClient: Sendable {
    func health(for connectorID: SaaSConnectorID, credential: OAuthCredential) throws -> ConnectorHealthStatus
}

public struct StaticConnectorHealthClient: ConnectorHealthClient {
    private let results: [SaaSConnectorID: ConnectorHealthStatus]

    public init(results: [SaaSConnectorID: ConnectorHealthStatus] = [:]) {
        self.results = results
    }

    public func health(for connectorID: SaaSConnectorID, credential: OAuthCredential) throws -> ConnectorHealthStatus {
        results[connectorID] ?? .connected
    }
}

public struct ConnectorHealthDashboard: Sendable {
    private let credentialStore: any OAuthCredentialStore
    private let healthClient: any ConnectorHealthClient
    private let auditEvents: [AuditEvent]

    public init(
        credentialStore: any OAuthCredentialStore,
        healthClient: any ConnectorHealthClient,
        auditEvents: [AuditEvent]
    ) {
        self.credentialStore = credentialStore
        self.healthClient = healthClient
        self.auditEvents = auditEvents
    }

    public func snapshot(for connectorIDs: [SaaSConnectorID], now: Date = Date()) throws -> [ConnectorHealthSnapshot] {
        try connectorIDs.map { connectorID in
            guard let credential = try credentialStore.loadCredential(for: connectorID) else {
                return ConnectorHealthSnapshot(
                    connectorID: connectorID,
                    status: .disconnected,
                    reconnectAction: .reconnect(connectorID),
                    lastError: lastError(for: connectorID)
                )
            }

            if credential.expiresAt <= now {
                return ConnectorHealthSnapshot(
                    connectorID: connectorID,
                    status: .tokenExpired,
                    reconnectAction: .reconnect(connectorID),
                    lastError: lastError(for: connectorID)
                )
            }

            let status = try healthClient.health(for: connectorID, credential: credential)
            return ConnectorHealthSnapshot(
                connectorID: connectorID,
                status: status,
                reconnectAction: status == .connected ? nil : .reconnect(connectorID),
                lastError: lastError(for: connectorID)
            )
        }
    }

    private func lastError(for connectorID: SaaSConnectorID) -> String? {
        auditEvents
            .reversed()
            .first {
                $0.category == "saas_connector" &&
                $0.status == .failed &&
                $0.metadata["connector_id"] == connectorID.rawValue
            }?
            .metadata["error"]
    }
}

private func requireApproval(_ context: ToolExecutionContext, connectorID: SaaSConnectorID = .gmail) throws {
    guard context.approvalToken != nil else {
        throw SaaSConnectorError.approvalRequired(connectorID)
    }
}

private extension GoogleCalendarConnector {
    func requireApproval(_ context: ToolExecutionContext) throws {
        guard context.approvalToken != nil else {
            throw SaaSConnectorError.approvalRequired(connectorID)
        }
    }
}

private extension GmailDraftConnector {
    func requireApproval(_ context: ToolExecutionContext) throws {
        guard context.approvalToken != nil else {
            throw SaaSConnectorError.approvalRequired(connectorID)
        }
    }
}

private extension SlackConnector {
    func requireApproval(_ context: ToolExecutionContext) throws {
        guard context.approvalToken != nil else {
            throw SaaSConnectorError.approvalRequired(connectorID)
        }
    }
}

private extension GoogleDriveConnector {
    func requireApproval(_ context: ToolExecutionContext) throws {
        guard context.approvalToken != nil else {
            throw SaaSConnectorError.approvalRequired(connectorID)
        }
    }
}

private extension NotionConnector {
    func requireApproval(_ context: ToolExecutionContext) throws {
        guard context.approvalToken != nil else {
            throw SaaSConnectorError.approvalRequired(connectorID)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
