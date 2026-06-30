import Foundation
import SoloPMCore

public enum GoogleCalendarRuntimeOAuthScope {
    public static let eventsWrite = GoogleCalendarRuntimeCredentialStatus.eventsWriteScope
    public static let offlineAccess = "offline_access"
}

public enum GoogleCalendarRuntimeError: Error, Equatable, Sendable {
    case disconnected
    case invalidAccessToken
    case missingRequiredScope(String)
    case apiFailure(String)
}

public struct GoogleCalendarOAuthCredentialMetadata: Codable, Equatable, Sendable {
    public var grantedScopes: Set<String>
    public var expiresAt: Date?
    public var accessTokenKey: SecretKey
    public var refreshTokenKey: SecretKey?

    public init(
        grantedScopes: Set<String>,
        expiresAt: Date?,
        accessTokenKey: SecretKey,
        refreshTokenKey: SecretKey?
    ) {
        self.grantedScopes = grantedScopes
        self.expiresAt = expiresAt
        self.accessTokenKey = accessTokenKey
        self.refreshTokenKey = refreshTokenKey
    }
}

public protocol GoogleCalendarOAuthCredentialMetadataStore: Sendable {
    func loadMetadata() throws -> GoogleCalendarOAuthCredentialMetadata?
    func saveMetadata(_ metadata: GoogleCalendarOAuthCredentialMetadata) throws
    func deleteMetadata() throws
}

public final class SQLiteGoogleCalendarOAuthCredentialMetadataStore: GoogleCalendarOAuthCredentialMetadataStore, @unchecked Sendable {
    private static let settingsKey = "google_calendar.oauth.metadata.v1"

    private let connection: SQLiteConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(connection: SQLiteConnection) {
        self.connection = connection
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadMetadata() throws -> GoogleCalendarOAuthCredentialMetadata? {
        guard let value = try SQLiteSettingsValueStore.loadValue(Self.settingsKey, connection: connection) else {
            return nil
        }
        return try decoder.decode(GoogleCalendarOAuthCredentialMetadata.self, from: Data(value.utf8))
    }

    public func saveMetadata(_ metadata: GoogleCalendarOAuthCredentialMetadata) throws {
        let data = try encoder.encode(metadata)
        guard let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.encodingFailed
        }
        try SQLiteSettingsValueStore.saveValue(value, for: Self.settingsKey, connection: connection)
    }

    public func deleteMetadata() throws {
        try SQLiteSettingsValueStore.deleteValue(Self.settingsKey, connection: connection)
    }
}

public final class GoogleCalendarOAuthCredentialStore: @unchecked Sendable {
    public static let accessTokenKey = SecretKey("oauth.google_calendar.access_token")
    public static let refreshTokenKey = SecretKey("oauth.google_calendar.refresh_token")

    private let secretStore: any SecretStore
    private let metadataStore: any GoogleCalendarOAuthCredentialMetadataStore

    public init(
        secretStore: any SecretStore,
        metadataStore: any GoogleCalendarOAuthCredentialMetadataStore
    ) {
        self.secretStore = secretStore
        self.metadataStore = metadataStore
    }

    public func loadMetadata() throws -> GoogleCalendarOAuthCredentialMetadata? {
        try metadataStore.loadMetadata()
    }

    public func saveTokens(
        accessToken: String,
        refreshToken: String?,
        grantedScopes: Set<String>,
        expiresAt: Date?
    ) throws {
        guard accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw GoogleCalendarRuntimeError.invalidAccessToken
        }
        let normalizedRefreshToken = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        try secretStore.save(accessToken, for: Self.accessTokenKey)
        if let refreshToken, normalizedRefreshToken?.isEmpty == false {
            try secretStore.save(refreshToken, for: Self.refreshTokenKey)
        } else {
            try secretStore.delete(Self.refreshTokenKey)
        }
        try metadataStore.saveMetadata(GoogleCalendarOAuthCredentialMetadata(
            grantedScopes: grantedScopes,
            expiresAt: expiresAt,
            accessTokenKey: Self.accessTokenKey,
            refreshTokenKey: normalizedRefreshToken?.isEmpty == false ? Self.refreshTokenKey : nil
        ))
    }

    public func accessToken(for metadata: GoogleCalendarOAuthCredentialMetadata) throws -> String? {
        try secretStore.read(metadata.accessTokenKey)
    }

    public func refreshToken(for metadata: GoogleCalendarOAuthCredentialMetadata) throws -> String? {
        guard let key = metadata.refreshTokenKey else {
            return nil
        }
        return try secretStore.read(key)
    }

    public func deleteCredential() throws {
        if let metadata = try loadMetadata() {
            try secretStore.delete(metadata.accessTokenKey)
            if let refreshTokenKey = metadata.refreshTokenKey {
                try secretStore.delete(refreshTokenKey)
            }
        }
        try metadataStore.deleteMetadata()
    }
}

public struct GoogleCalendarOAuthCredentialStatusStore: GoogleCalendarRuntimeCredentialStatusStore {
    private let credentialStore: GoogleCalendarOAuthCredentialStore
    private let refreshTokenSupportEnabled: Bool

    public init(
        credentialStore: GoogleCalendarOAuthCredentialStore,
        refreshTokenSupportEnabled: Bool = false
    ) {
        self.credentialStore = credentialStore
        self.refreshTokenSupportEnabled = refreshTokenSupportEnabled
    }

    public func loadGoogleCalendarCredentialStatus() throws -> GoogleCalendarRuntimeCredentialStatus? {
        guard let metadata = try credentialStore.loadMetadata() else {
            return nil
        }
        guard let accessToken = try credentialStore.accessToken(for: metadata),
              accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        let refreshToken = try credentialStore.refreshToken(for: metadata)
        return GoogleCalendarRuntimeCredentialStatus(
            grantedScopes: metadata.grantedScopes,
            expiresAt: metadata.expiresAt,
            // The personal MVP does not implement token refresh yet. Reporting
            // refresh capability only when the runtime owns refresh avoids a
            // misleading ready state for already-expired OAuth sessions.
            hasRefreshToken: refreshTokenSupportEnabled && refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        )
    }
}

public protocol GoogleCalendarIdempotencyNamespaceStore: Sendable {
    func idempotencyNamespace() throws -> String
}

public final class SQLiteGoogleCalendarIdempotencyNamespaceStore: GoogleCalendarIdempotencyNamespaceStore, @unchecked Sendable {
    private static let settingsKey = "google_calendar.idempotency_namespace.v1"

    private let connection: SQLiteConnection

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func idempotencyNamespace() throws -> String {
        if let stored = try SQLiteSettingsValueStore.loadValue(Self.settingsKey, connection: connection),
           stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return stored
        }

        // This namespace is local, non-secret runtime metadata. Keeping it
        // stable per SQLite database makes Google caller-provided event IDs
        // idempotent across app restarts without leaking task titles.
        let namespace = UUID().uuidString.lowercased()
        try SQLiteSettingsValueStore.saveValue(namespace, for: Self.settingsKey, connection: connection)
        return namespace
    }
}

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

public protocol GoogleCalendarBearerTokenProvider: Sendable {
    func bearerToken() throws -> String
}

public struct GoogleCalendarOAuthBearerTokenProvider: GoogleCalendarBearerTokenProvider {
    private let credentialStore: GoogleCalendarOAuthCredentialStore
    private let requiredScopes: Set<String>

    public init(
        credentialStore: GoogleCalendarOAuthCredentialStore,
        requiredScopes: Set<String> = [GoogleCalendarRuntimeOAuthScope.eventsWrite]
    ) {
        self.credentialStore = credentialStore
        self.requiredScopes = requiredScopes
    }

    public func bearerToken() throws -> String {
        guard let metadata = try credentialStore.loadMetadata() else {
            throw GoogleCalendarRuntimeError.disconnected
        }
        let missingScopes = requiredScopes.subtracting(metadata.grantedScopes)
        guard missingScopes.isEmpty else {
            throw GoogleCalendarRuntimeError.missingRequiredScope(missingScopes.sorted().joined(separator: ","))
        }
        guard let accessToken = try credentialStore.accessToken(for: metadata),
              accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw GoogleCalendarRuntimeError.disconnected
        }
        return accessToken
    }
}

public protocol SynchronousHTTPDataClient: Sendable {
    func data(for request: URLRequest) throws -> (Data, HTTPURLResponse)
}

public struct URLSessionSynchronousHTTPDataClient: SynchronousHTTPDataClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedResultBox()

        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                box.store(.failure(error))
                return
            }
            guard let data, let response = response as? HTTPURLResponse else {
                box.store(.failure(GoogleCalendarRuntimeError.apiFailure("Response was not HTTP.")))
                return
            }
            box.store(.success((data, response)))
        }.resume()

        semaphore.wait()
        return try box.value()
    }
}

public struct GoogleCalendarRuntimeEventRecord: Equatable, Sendable {
    public var calendarID: String
    public var timeZoneIdentifier: String
    public var event: CalendarEventRecord

    public init(calendarID: String, timeZoneIdentifier: String, event: CalendarEventRecord) {
        self.calendarID = calendarID
        self.timeZoneIdentifier = timeZoneIdentifier
        self.event = event
    }
}

public protocol GoogleCalendarRuntimeEventClient: Sendable {
    func createEvent(
        _ draft: CalendarEventDraft,
        calendarID: String,
        timeZoneIdentifier: String
    ) throws -> GoogleCalendarRuntimeEventRecord
}

public struct GoogleCalendarHTTPEventClient: GoogleCalendarRuntimeEventClient {
    private let tokenProvider: any GoogleCalendarBearerTokenProvider
    private let httpClient: any SynchronousHTTPDataClient
    private let configuration: GoogleCalendarHTTPConfiguration

    public init(
        tokenProvider: any GoogleCalendarBearerTokenProvider,
        httpClient: any SynchronousHTTPDataClient = URLSessionSynchronousHTTPDataClient(),
        configuration: GoogleCalendarHTTPConfiguration = GoogleCalendarHTTPConfiguration()
    ) {
        self.tokenProvider = tokenProvider
        self.httpClient = httpClient
        self.configuration = configuration
    }

    public func createEvent(
        _ draft: CalendarEventDraft,
        calendarID: String,
        timeZoneIdentifier: String
    ) throws -> GoogleCalendarRuntimeEventRecord {
        let idempotencyID = GoogleCalendarEventID.normalized(draft.idempotencyKey)
        let request = try makeCreateEventRequest(
            draft,
            calendarID: calendarID,
            timeZoneIdentifier: timeZoneIdentifier,
            accessToken: try tokenProvider.bearerToken()
        )
        let (data, response) = try httpClient.data(for: request)
        if response.statusCode == 409, let idempotencyID, idempotencyID.hasPrefix("solopm") {
            // Google Calendar reports a conflict when the approved insert
            // already exists. For SoloPM-generated IDs this reconstructs the
            // local link path instead of creating duplicate calendar events.
            return GoogleCalendarRuntimeEventRecord(
                calendarID: calendarID,
                timeZoneIdentifier: timeZoneIdentifier,
                event: CalendarEventRecord(id: idempotencyID, draft: draft)
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleCalendarRuntimeError.apiFailure("Google Calendar events.insert failed with HTTP \(response.statusCode).")
        }

        let body: GoogleCalendarEventResponse
        do {
            body = try JSONDecoder().decode(GoogleCalendarEventResponse.self, from: data)
        } catch {
            throw GoogleCalendarRuntimeError.apiFailure("Google Calendar response could not be decoded.")
        }
        guard let id = body.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw GoogleCalendarRuntimeError.apiFailure("Google Calendar response did not contain an event id.")
        }
        return GoogleCalendarRuntimeEventRecord(
            calendarID: calendarID,
            timeZoneIdentifier: timeZoneIdentifier,
            event: CalendarEventRecord(id: id, draft: draft)
        )
    }

    public func makeCreateEventRequest(
        _ draft: CalendarEventDraft,
        calendarID: String,
        timeZoneIdentifier: String,
        accessToken: String
    ) throws -> URLRequest {
        let url = configuration.baseURL
            .appendingPathComponent("calendars")
            .appendingPathComponent(calendarID)
            .appendingPathComponent("events")
        var request = URLRequest(url: url, timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(GoogleCalendarEventRequest(draft: draft, timeZoneIdentifier: timeZoneIdentifier))
        return request
    }
}

public struct GoogleCalendarHTTPEventSink: ExternalCalendarEventSink {
    private let client: any GoogleCalendarRuntimeEventClient

    public init(client: any GoogleCalendarRuntimeEventClient) {
        self.client = client
    }

    public func createEvent(
        _ draft: CalendarEventDraft,
        calendarID: String,
        timeZoneIdentifier: String,
        context: ToolExecutionContext
    ) throws -> ExternalCalendarEventRecord {
        guard context.approvalToken != nil else {
            throw GoogleCalendarRuntimeSyncError.approvalRequired
        }
        let record = try client.createEvent(draft, calendarID: calendarID, timeZoneIdentifier: timeZoneIdentifier)
        return ExternalCalendarEventRecord(
            providerID: ExternalTaskSource.googleCalendar.rawValue,
            externalID: record.event.id,
            calendarID: record.calendarID,
            timeZoneIdentifier: record.timeZoneIdentifier,
            title: record.event.draft.title
        )
    }
}

public enum GoogleCalendarAppRuntimeFactory {
    public static func syncStatus(
        entitlementStore: any EntitlementStore,
        secretStore: any SecretStore,
        metadataStore: any GoogleCalendarOAuthCredentialMetadataStore,
        calendarID: String = "primary",
        timeZoneIdentifier: String = TimeZone.current.identifier,
        now: Date = Date()
    ) throws -> GoogleCalendarRuntimeSyncStatus {
        let credentialStore = GoogleCalendarOAuthCredentialStore(
            secretStore: secretStore,
            metadataStore: metadataStore
        )
        // Settings needs a read-only readiness check: app composition proves the write runtime
        // exists, while this path avoids constructing idempotency state or calendar write sinks.
        return try GoogleCalendarRuntimeSyncReadiness.status(
            entitlementStore: entitlementStore,
            credentialStatusStore: GoogleCalendarOAuthCredentialStatusStore(credentialStore: credentialStore),
            configuration: GoogleCalendarRuntimeSyncConfiguration(
                calendarID: calendarID,
                timeZoneIdentifier: timeZoneIdentifier
            ),
            isWriteRuntimeConfigured: true,
            now: now
        )
    }

    public static func syncStatus(
        entitlementStore: any EntitlementStore,
        secretStore: any SecretStore,
        connection: SQLiteConnection,
        calendarID: String = "primary",
        timeZoneIdentifier: String = TimeZone.current.identifier,
        now: Date = Date()
    ) throws -> GoogleCalendarRuntimeSyncStatus {
        try syncStatus(
            entitlementStore: entitlementStore,
            secretStore: secretStore,
            metadataStore: SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection),
            calendarID: calendarID,
            timeZoneIdentifier: timeZoneIdentifier,
            now: now
        )
    }

    public static func makeSyncController(
        entitlementStore: any EntitlementStore,
        store: any ProjectBoardStore,
        linkStore: any ExternalTaskLinkStore,
        secretStore: any SecretStore,
        metadataStore: any GoogleCalendarOAuthCredentialMetadataStore,
        idempotencyNamespaceStore: any GoogleCalendarIdempotencyNamespaceStore,
        calendarID: String = "primary",
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> GoogleCalendarRuntimeSyncController {
        let credentialStore = GoogleCalendarOAuthCredentialStore(
            secretStore: secretStore,
            metadataStore: metadataStore
        )
        let eventSink = GoogleCalendarHTTPEventSink(client: GoogleCalendarHTTPEventClient(
            tokenProvider: GoogleCalendarOAuthBearerTokenProvider(credentialStore: credentialStore)
        ))
        return GoogleCalendarRuntimeSyncController(
            entitlementStore: entitlementStore,
            credentialStatusStore: GoogleCalendarOAuthCredentialStatusStore(credentialStore: credentialStore),
            configuration: GoogleCalendarRuntimeSyncConfiguration(
                calendarID: calendarID,
                timeZoneIdentifier: timeZoneIdentifier
            ),
            taskSyncService: GoogleCalendarTaskSyncService(
                entitlementStore: entitlementStore,
                store: store,
                linkStore: linkStore,
                calendarSink: eventSink,
                calendarID: calendarID,
                timeZoneIdentifier: timeZoneIdentifier,
                idempotencyNamespace: try idempotencyNamespaceStore.idempotencyNamespace()
            )
        )
    }

    public static func makeSyncController(
        entitlementStore: any EntitlementStore,
        store: any ProjectBoardStore,
        linkStore: any ExternalTaskLinkStore,
        secretStore: any SecretStore,
        connection: SQLiteConnection,
        idempotencyNamespaceStore: any GoogleCalendarIdempotencyNamespaceStore,
        calendarID: String = "primary",
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> GoogleCalendarRuntimeSyncController {
        try makeSyncController(
            entitlementStore: entitlementStore,
            store: store,
            linkStore: linkStore,
            secretStore: secretStore,
            metadataStore: SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection),
            idempotencyNamespaceStore: idempotencyNamespaceStore,
            calendarID: calendarID,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

private enum SQLiteSettingsValueStore {
    static func loadValue(_ key: String, connection: SQLiteConnection) throws -> String? {
        let rows = try connection.queryRows(
            "SELECT value FROM settings WHERE key = \(sqlLiteral(key)) LIMIT 1;"
        )
        return rows.first?["value"]
    }

    static func saveValue(_ value: String, for key: String, connection: SQLiteConnection) throws {
        try connection.execute(
            """
            INSERT INTO settings (key, value, updated_at)
            VALUES (\(sqlLiteral(key)), \(sqlLiteral(value)), CURRENT_TIMESTAMP)
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = CURRENT_TIMESTAMP;
            """
        )
    }

    static func deleteValue(_ key: String, connection: SQLiteConnection) throws {
        try connection.execute("DELETE FROM settings WHERE key = \(sqlLiteral(key));")
    }

    private static func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

private struct GoogleCalendarEventRequest: Encodable {
    var id: String?
    var summary: String
    var description: String?
    var start: GoogleCalendarEventDate
    var end: GoogleCalendarEventDate
    var extendedProperties: GoogleCalendarEventExtendedProperties?

    init(draft: CalendarEventDraft, timeZoneIdentifier: String) {
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
            GoogleCalendarEventExtendedProperties(privateProperties: ["soloPMIdempotencyKey": $0])
        }
    }
}

private struct GoogleCalendarEventDate: Encodable {
    var date: String?
    var dateTime: String?
    var timeZone: String?
}

private struct GoogleCalendarEventExtendedProperties: Encodable {
    var privateProperties: [String: String]

    enum CodingKeys: String, CodingKey {
        case privateProperties = "private"
    }
}

private enum GoogleCalendarEventID {
    private static let allowedCharacters = Set("0123456789abcdefghijklmnopqrstuv")
    private static let prefix = "solopm"
    private static let digestLength = 64

    static func normalized(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let suffix = candidate.dropFirst(prefix.count)
        guard candidate.hasPrefix(prefix),
              suffix.count == digestLength,
              candidate.allSatisfy({ allowedCharacters.contains($0) }) else {
            return nil
        }
        return candidate
    }
}

private struct GoogleCalendarEventResponse: Decodable {
    var id: String?
}

private final class LockedResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<(Data, HTTPURLResponse), Error>?

    func store(_ result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        defer { lock.unlock() }
        self.result = result
    }

    func value() throws -> (Data, HTTPURLResponse) {
        lock.lock()
        defer { lock.unlock() }
        return try result?.get() ?? {
            throw GoogleCalendarRuntimeError.apiFailure("HTTP request did not complete.")
        }()
    }
}
