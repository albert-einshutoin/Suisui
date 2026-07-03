import Foundation
import XCTest
@testable import SoloPMCore
@testable import SoloPMGoogleCalendarRuntime

final class GoogleCalendarAppRuntimeTests: XCTestCase {
    func testGoogleCalendarPersistentKeysStayLiteralCompatible() throws {
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let namespaceStore = SQLiteGoogleCalendarIdempotencyNamespaceStore(connection: connection)

        try metadataStore.saveMetadata(GoogleCalendarOAuthCredentialMetadata(
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: nil,
            accessTokenKey: GoogleCalendarOAuthCredentialStore.accessTokenKey,
            refreshTokenKey: GoogleCalendarOAuthCredentialStore.refreshTokenKey
        ))
        _ = try namespaceStore.idempotencyNamespace()

        XCTAssertEqual(ExternalIntegrationIdentifier.googleCalendar, "google_calendar")
        XCTAssertEqual(GoogleCalendarOAuthCredentialStore.accessTokenKey.rawValue, "oauth.google_calendar.access_token")
        XCTAssertEqual(GoogleCalendarOAuthCredentialStore.refreshTokenKey.rawValue, "oauth.google_calendar.refresh_token")
        XCTAssertEqual(
            try connection.queryRows("SELECT value FROM settings WHERE key = 'google_calendar.oauth.metadata.v1';").count,
            1
        )
        XCTAssertEqual(
            try connection.queryRows("SELECT value FROM settings WHERE key = 'google_calendar.idempotency_namespace.v1';").count,
            1
        )
    }

    func testSQLiteMetadataStorePersistsOAuthMetadataWithoutTokenMaterial() throws {
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let metadata = GoogleCalendarOAuthCredentialMetadata(
            grantedScopes: [
                GoogleCalendarRuntimeOAuthScope.eventsWrite,
                GoogleCalendarRuntimeOAuthScope.offlineAccess
            ],
            expiresAt: Date(timeIntervalSince1970: 4_000),
            accessTokenKey: GoogleCalendarOAuthCredentialStore.accessTokenKey,
            refreshTokenKey: GoogleCalendarOAuthCredentialStore.refreshTokenKey
        )

        try metadataStore.saveMetadata(metadata)
        let rows = try connection.queryRows("SELECT value FROM settings WHERE key = 'google_calendar.oauth.metadata.v1';")
        let storedValue = try XCTUnwrap(rows.first?["value"])

        XCTAssertEqual(try metadataStore.loadMetadata(), metadata)
        XCTAssertFalse(storedValue.contains("calendar-access-token"))
        XCTAssertFalse(storedValue.contains("calendar-refresh-token"))
    }

    func testCredentialStatusRequiresAccessTokenInSecretStore() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        let statusStore = GoogleCalendarOAuthCredentialStatusStore(credentialStore: credentialStore)

        try metadataStore.saveMetadata(GoogleCalendarOAuthCredentialMetadata(
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 4_000),
            accessTokenKey: GoogleCalendarOAuthCredentialStore.accessTokenKey,
            refreshTokenKey: nil
        ))

        XCTAssertNil(try statusStore.loadGoogleCalendarCredentialStatus())

        try credentialStore.saveTokens(
            accessToken: "calendar-access-token",
            refreshToken: "calendar-refresh-token",
            grantedScopes: [
                GoogleCalendarRuntimeOAuthScope.eventsWrite,
                GoogleCalendarRuntimeOAuthScope.offlineAccess
            ],
            expiresAt: Date(timeIntervalSince1970: 4_000)
        )

        let status = try XCTUnwrap(try statusStore.loadGoogleCalendarCredentialStatus())
        XCTAssertEqual(status.grantedScopes, [
            GoogleCalendarRuntimeOAuthScope.eventsWrite,
            GoogleCalendarRuntimeOAuthScope.offlineAccess
        ])
        XCTAssertEqual(status.expiresAt, Date(timeIntervalSince1970: 4_000))
        XCTAssertFalse(status.hasRefreshToken)
    }

    func testCredentialStoreRejectsBlankAccessTokenBeforePersistingMetadata() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)

        XCTAssertThrowsError(
            try credentialStore.saveTokens(
                accessToken: " \n ",
                refreshToken: "calendar-refresh-token",
                grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
                expiresAt: nil
            )
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarRuntimeError, .invalidAccessToken)
        }
        XCTAssertNil(try metadataStore.loadMetadata())
        XCTAssertNil(try secretStore.read(GoogleCalendarOAuthCredentialStore.accessTokenKey))
    }

    func testFactoryDisconnectClearsOAuthMetadataAndKeychainTokens() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        try credentialStore.saveTokens(
            accessToken: "calendar-access-token",
            refreshToken: "calendar-refresh-token",
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 5_000)
        )
        XCTAssertEqual(try makeController(secretStore: secretStore, connection: connection)
            .status(now: Date(timeIntervalSince1970: 4_000)).state, .ready)

        try GoogleCalendarAppRuntimeFactory.disconnectOAuthCredential(
            secretStore: secretStore,
            connection: connection
        )

        XCTAssertNil(try metadataStore.loadMetadata())
        XCTAssertNil(try secretStore.read(GoogleCalendarOAuthCredentialStore.accessTokenKey))
        XCTAssertNil(try secretStore.read(GoogleCalendarOAuthCredentialStore.refreshTokenKey))
        XCTAssertEqual(try makeController(secretStore: secretStore, connection: connection)
            .status(now: Date(timeIntervalSince1970: 4_000)).state, .oauthDisconnected)
    }

    func testFactoryDisconnectClearsKnownKeychainTokensWhenMetadataIsMissing() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        try secretStore.save("orphaned-calendar-access-token", for: GoogleCalendarOAuthCredentialStore.accessTokenKey)
        try secretStore.save("orphaned-calendar-refresh-token", for: GoogleCalendarOAuthCredentialStore.refreshTokenKey)
        XCTAssertNil(try metadataStore.loadMetadata())

        try GoogleCalendarAppRuntimeFactory.disconnectOAuthCredential(
            secretStore: secretStore,
            connection: connection
        )

        XCTAssertNil(try secretStore.read(GoogleCalendarOAuthCredentialStore.accessTokenKey))
        XCTAssertNil(try secretStore.read(GoogleCalendarOAuthCredentialStore.refreshTokenKey))
        XCTAssertNil(try metadataStore.loadMetadata())
    }

    func testCredentialStatusReportsRefreshOnlyWhenRuntimeSupportsRefresh() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        try credentialStore.saveTokens(
            accessToken: "calendar-access-token",
            refreshToken: "calendar-refresh-token",
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 4_000)
        )

        let refreshUnavailableStatusStore = GoogleCalendarOAuthCredentialStatusStore(
            credentialStore: credentialStore,
            refreshTokenSupportEnabled: false
        )
        let refreshAvailableStatusStore = GoogleCalendarOAuthCredentialStatusStore(
            credentialStore: credentialStore,
            refreshTokenSupportEnabled: true
        )

        XCTAssertFalse(try XCTUnwrap(try refreshUnavailableStatusStore.loadGoogleCalendarCredentialStatus()).hasRefreshToken)
        XCTAssertTrue(try XCTUnwrap(try refreshAvailableStatusStore.loadGoogleCalendarCredentialStatus()).hasRefreshToken)
    }

    func testOAuthBearerTokenProviderRefreshesExpiredAccessTokenWithoutLeakingSecrets() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        try credentialStore.saveTokens(
            accessToken: "expired-calendar-access-token",
            refreshToken: "calendar-refresh-token",
            grantedScopes: [
                GoogleCalendarRuntimeOAuthScope.eventsWrite,
                GoogleCalendarRuntimeOAuthScope.calendarListReadOnly
            ],
            expiresAt: Date(timeIntervalSince1970: 3_000)
        )
        let httpClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: """
            {
              "access_token": "new-calendar-access-token",
              "expires_in": 3600,
              "scope": "\(GoogleCalendarRuntimeOAuthScope.eventsWrite) \(GoogleCalendarRuntimeOAuthScope.calendarListReadOnly)",
              "token_type": "Bearer"
            }
            """.data(using: .utf8)!,
            statusCode: 200
        )
        let provider = GoogleCalendarOAuthBearerTokenProvider(
            credentialStore: credentialStore,
            refreshService: GoogleCalendarOAuthTokenRefreshService(
                configuration: GoogleCalendarOAuthTokenRefreshConfiguration(
                    clientID: "google-client-id.apps.googleusercontent.com"
                ),
                httpClient: httpClient,
                credentialStore: credentialStore
            ),
            nowProvider: { Date(timeIntervalSince1970: 4_000) }
        )

        let accessToken = try provider.bearerToken()
        let request = try XCTUnwrap(httpClient.requests.first)
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
        let storedValue = try XCTUnwrap(try connection.queryRows(
            "SELECT value FROM settings WHERE key = 'google_calendar.oauth.metadata.v1';"
        ).first?["value"])
        let metadata = try XCTUnwrap(try credentialStore.loadMetadata())

        XCTAssertEqual(accessToken, "new-calendar-access-token")
        XCTAssertEqual(request.url?.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("refresh_token=calendar-refresh-token"))
        XCTAssertTrue(body.contains("client_id=google-client-id.apps.googleusercontent.com"))
        XCTAssertFalse(body.contains("client_secret"))
        XCTAssertEqual(try secretStore.read(GoogleCalendarOAuthCredentialStore.accessTokenKey), "new-calendar-access-token")
        XCTAssertEqual(try secretStore.read(GoogleCalendarOAuthCredentialStore.refreshTokenKey), "calendar-refresh-token")
        XCTAssertEqual(metadata.expiresAt, Date(timeIntervalSince1970: 7_600))
        XCTAssertFalse(storedValue.contains("expired-calendar-access-token"))
        XCTAssertFalse(storedValue.contains("new-calendar-access-token"))
        XCTAssertFalse(storedValue.contains("calendar-refresh-token"))
    }

    func testOAuthBearerTokenProviderSkipsRefreshForUsableAccessToken() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        try credentialStore.saveTokens(
            accessToken: "current-calendar-access-token",
            refreshToken: "calendar-refresh-token",
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 8_000)
        )
        let httpClient = GoogleCalendarRecordingHTTPDataClient(responseBody: Data(), statusCode: 200)
        let provider = GoogleCalendarOAuthBearerTokenProvider(
            credentialStore: credentialStore,
            refreshService: GoogleCalendarOAuthTokenRefreshService(
                configuration: GoogleCalendarOAuthTokenRefreshConfiguration(
                    clientID: "google-client-id.apps.googleusercontent.com"
                ),
                httpClient: httpClient,
                credentialStore: credentialStore
            ),
            nowProvider: { Date(timeIntervalSince1970: 4_000) }
        )

        XCTAssertEqual(try provider.bearerToken(), "current-calendar-access-token")
        XCTAssertTrue(httpClient.requests.isEmpty)
    }

    func testOAuthBearerTokenProviderRejectsFailedRefreshWithoutPersistingTokenBody() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        try credentialStore.saveTokens(
            accessToken: "expired-calendar-access-token",
            refreshToken: "calendar-refresh-token",
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 3_000)
        )
        let httpClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: #"{"error":"invalid_grant","access_token":"leaked-token"}"#.data(using: .utf8)!,
            statusCode: 400
        )
        let provider = GoogleCalendarOAuthBearerTokenProvider(
            credentialStore: credentialStore,
            refreshService: GoogleCalendarOAuthTokenRefreshService(
                configuration: GoogleCalendarOAuthTokenRefreshConfiguration(
                    clientID: "google-client-id.apps.googleusercontent.com"
                ),
                httpClient: httpClient,
                credentialStore: credentialStore
            ),
            nowProvider: { Date(timeIntervalSince1970: 4_000) }
        )

        XCTAssertThrowsError(try provider.bearerToken()) { error in
            XCTAssertEqual(
                error as? GoogleCalendarRuntimeError,
                .apiFailure("Google OAuth token refresh failed with HTTP 400.")
            )
            XCTAssertFalse(String(describing: error).contains("leaked-token"))
        }
        XCTAssertEqual(try secretStore.read(GoogleCalendarOAuthCredentialStore.accessTokenKey), "expired-calendar-access-token")
    }

    func testSQLiteIdempotencyNamespaceSurvivesReopeningDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloPMGoogleCalendarRuntime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("SoloPM.sqlite")
        let firstNamespace: String
        do {
            let connection = try migratedConnection(path: databaseURL.path)
            firstNamespace = try SQLiteGoogleCalendarIdempotencyNamespaceStore(connection: connection).idempotencyNamespace()
        }
        do {
            let reopenedConnection = try migratedConnection(path: databaseURL.path)
            let secondNamespace = try SQLiteGoogleCalendarIdempotencyNamespaceStore(connection: reopenedConnection).idempotencyNamespace()
            XCTAssertEqual(secondNamespace, firstNamespace)
        }
    }

    func testHTTPEventClientCreatesEventsInsertRequestWithOAuthTokenAndStableID() throws {
        let httpClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: #"{"id":"event-123"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = GoogleCalendarHTTPEventClient(
            tokenProvider: StaticGoogleCalendarBearerTokenProvider(token: "calendar-access-token"),
            httpClient: httpClient,
            configuration: GoogleCalendarHTTPConfiguration(baseURL: URL(string: "https://www.googleapis.com/calendar/v3")!)
        )

        let record = try client.createEvent(
            CalendarEventDraft(
                title: "Planning",
                startAt: "2026-07-07",
                endAt: "2026-07-08",
                isAllDay: true,
                notes: "SoloPM",
                idempotencyKey: "solopm\(String(repeating: "a", count: 64))"
            ),
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let request = try XCTUnwrap(httpClient.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let start = try XCTUnwrap(body["start"] as? [String: Any])
        let extendedProperties = try XCTUnwrap(body["extendedProperties"] as? [String: Any])
        let privateProperties = try XCTUnwrap(extendedProperties["private"] as? [String: Any])

        XCTAssertEqual(record.event.id, "event-123")
        XCTAssertEqual(request.url?.absoluteString, "https://www.googleapis.com/calendar/v3/calendars/primary/events")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer calendar-access-token")
        XCTAssertEqual(body["summary"] as? String, "Planning")
        XCTAssertEqual(body["id"] as? String, "solopm\(String(repeating: "a", count: 64))")
        XCTAssertEqual(start["date"] as? String, "2026-07-07")
        XCTAssertNil(start["dateTime"])
        XCTAssertEqual(privateProperties["soloPMIdempotencyKey"] as? String, "solopm\(String(repeating: "a", count: 64))")
        XCTAssertFalse(request.url?.absoluteString.contains("calendar-access-token") ?? true)
    }

    func testHTTPEventClientRefreshesExpiredOAuthTokenBeforeInsert() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        try credentialStore.saveTokens(
            accessToken: "expired-calendar-access-token",
            refreshToken: "calendar-refresh-token",
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 3_000)
        )
        let refreshHTTPClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: """
            {
              "access_token": "new-calendar-access-token",
              "expires_in": 3600,
              "token_type": "Bearer"
            }
            """.data(using: .utf8)!,
            statusCode: 200
        )
        let eventHTTPClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: #"{"id":"event-123"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let tokenProvider = GoogleCalendarOAuthBearerTokenProvider(
            credentialStore: credentialStore,
            refreshService: GoogleCalendarOAuthTokenRefreshService(
                configuration: GoogleCalendarOAuthTokenRefreshConfiguration(
                    clientID: "google-client-id.apps.googleusercontent.com"
                ),
                httpClient: refreshHTTPClient,
                credentialStore: credentialStore
            ),
            nowProvider: { Date(timeIntervalSince1970: 4_000) }
        )
        let client = GoogleCalendarHTTPEventClient(
            tokenProvider: tokenProvider,
            httpClient: eventHTTPClient
        )

        _ = try client.createEvent(
            CalendarEventDraft(title: "Planning", startAt: "2026-07-07", endAt: "2026-07-08", isAllDay: true),
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        let refreshRequest = try XCTUnwrap(refreshHTTPClient.requests.first)
        let eventRequest = try XCTUnwrap(eventHTTPClient.requests.first)
        XCTAssertEqual(refreshRequest.url?.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(eventRequest.value(forHTTPHeaderField: "Authorization"), "Bearer new-calendar-access-token")
        XCTAssertFalse(eventRequest.value(forHTTPHeaderField: "Authorization")?.contains("expired-calendar-access-token") ?? true)
    }

    func testHTTPEventClientTreatsDuplicateStableEventIDAsIdempotentSuccess() throws {
        let httpClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: #"{"error":{"code":409}}"#.data(using: .utf8)!,
            statusCode: 409
        )
        let client = GoogleCalendarHTTPEventClient(
            tokenProvider: StaticGoogleCalendarBearerTokenProvider(token: "calendar-access-token"),
            httpClient: httpClient
        )

        let record = try client.createEvent(
            CalendarEventDraft(
                title: "Due task",
                startAt: "2026-07-04",
                endAt: "2026-07-05",
                isAllDay: true,
                idempotencyKey: "solopm\(String(repeating: "b", count: 64))"
            ),
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        XCTAssertEqual(record.event.id, "solopm\(String(repeating: "b", count: 64))")
        XCTAssertEqual(record.event.draft.title, "Due task")
    }

    func testHTTPCalendarListClientListsWritableCalendarsWithOAuthToken() throws {
        let httpClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: """
            {
              "items": [
                { "id": "primary", "summary": "Personal", "primary": true, "accessRole": "owner" },
                { "id": "team@example.com", "summary": "Team Calendar", "accessRole": "writer" },
                { "id": "read-only@example.com", "summary": "Read Only", "accessRole": "reader" },
                { "id": "   ", "summary": "Blank", "accessRole": "writer" }
              ]
            }
            """.data(using: .utf8)!,
            statusCode: 200
        )
        let client = GoogleCalendarHTTPCalendarListClient(
            tokenProvider: StaticGoogleCalendarBearerTokenProvider(token: "calendar-access-token"),
            httpClient: httpClient,
            configuration: GoogleCalendarHTTPConfiguration(baseURL: URL(string: "https://www.googleapis.com/calendar/v3")!)
        )

        let calendars = try client.listWritableCalendars()
        let request = try XCTUnwrap(httpClient.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(calendars.map(\.id), ["primary", "team@example.com"])
        XCTAssertEqual(calendars.map(\.summary), ["Personal", "Team Calendar"])
        XCTAssertEqual(calendars.map(\.isPrimary), [true, false])
        XCTAssertEqual(components.path, "/calendar/v3/users/me/calendarList")
        XCTAssertEqual(query["maxResults"], "250")
        XCTAssertEqual(query["minAccessRole"], "writer")
        XCTAssertEqual(query["showDeleted"], "false")
        XCTAssertEqual(query["showHidden"], "false")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer calendar-access-token")
        XCTAssertFalse(request.url?.absoluteString.contains("calendar-access-token") ?? true)
    }

    func testHTTPCalendarListClientRefreshesExpiredOAuthTokenBeforeListing() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        try credentialStore.saveTokens(
            accessToken: "expired-calendar-access-token",
            refreshToken: "calendar-refresh-token",
            grantedScopes: [
                GoogleCalendarRuntimeOAuthScope.eventsWrite,
                GoogleCalendarRuntimeOAuthScope.calendarListReadOnly
            ],
            expiresAt: Date(timeIntervalSince1970: 3_000)
        )
        let refreshHTTPClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: """
            {
              "access_token": "new-calendar-access-token",
              "expires_in": 3600,
              "scope": "\(GoogleCalendarRuntimeOAuthScope.eventsWrite) \(GoogleCalendarRuntimeOAuthScope.calendarListReadOnly)",
              "token_type": "Bearer"
            }
            """.data(using: .utf8)!,
            statusCode: 200
        )
        let listHTTPClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: #"{ "items": [ { "id": "primary", "summary": "Personal", "primary": true, "accessRole": "owner" } ] }"#.data(using: .utf8)!,
            statusCode: 200
        )
        let tokenProvider = GoogleCalendarOAuthBearerTokenProvider(
            credentialStore: credentialStore,
            requiredScopes: [GoogleCalendarRuntimeOAuthScope.calendarListReadOnly],
            refreshService: GoogleCalendarOAuthTokenRefreshService(
                configuration: GoogleCalendarOAuthTokenRefreshConfiguration(
                    clientID: "google-client-id.apps.googleusercontent.com"
                ),
                httpClient: refreshHTTPClient,
                credentialStore: credentialStore
            ),
            nowProvider: { Date(timeIntervalSince1970: 4_000) }
        )
        let client = GoogleCalendarHTTPCalendarListClient(
            tokenProvider: tokenProvider,
            httpClient: listHTTPClient
        )

        let calendars = try client.listWritableCalendars()
        let listRequest = try XCTUnwrap(listHTTPClient.requests.first)

        XCTAssertEqual(calendars.map(\.id), ["primary"])
        XCTAssertEqual(refreshHTTPClient.requests.count, 1)
        XCTAssertEqual(listRequest.value(forHTTPHeaderField: "Authorization"), "Bearer new-calendar-access-token")
        XCTAssertFalse(listRequest.value(forHTTPHeaderField: "Authorization")?.contains("expired-calendar-access-token") ?? true)
    }

    func testHTTPCalendarListClientRequiresCalendarListScopeBeforeNetwork() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        try GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore).saveTokens(
            accessToken: "calendar-access-token",
            refreshToken: nil,
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 5_000)
        )
        let httpClient = GoogleCalendarRecordingHTTPDataClient(responseBody: Data(), statusCode: 200)
        let client = GoogleCalendarHTTPCalendarListClient(
            tokenProvider: GoogleCalendarOAuthBearerTokenProvider(
                credentialStore: GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore),
                requiredScopes: [GoogleCalendarRuntimeOAuthScope.calendarListReadOnly]
            ),
            httpClient: httpClient
        )

        XCTAssertThrowsError(try client.listWritableCalendars()) { error in
            XCTAssertEqual(
                error as? GoogleCalendarRuntimeError,
                .missingRequiredScope(GoogleCalendarRuntimeOAuthScope.calendarListReadOnly)
            )
        }
        XCTAssertTrue(httpClient.requests.isEmpty)
    }

    func testHTTPCalendarListClientFollowsPageTokens() throws {
        let httpClient = GoogleCalendarRecordingHTTPDataClient(responses: [
            (
                """
                {
                  "nextPageToken": "page-2",
                  "items": [
                    { "id": "primary", "summary": "Personal", "primary": true, "accessRole": "owner" }
                  ]
                }
                """.data(using: .utf8)!,
                200
            ),
            (
                """
                {
                  "items": [
                    { "id": "team@example.com", "summary": "Team Calendar", "accessRole": "writer" }
                  ]
                }
                """.data(using: .utf8)!,
                200
            )
        ])
        let client = GoogleCalendarHTTPCalendarListClient(
            tokenProvider: StaticGoogleCalendarBearerTokenProvider(token: "calendar-access-token"),
            httpClient: httpClient
        )

        let calendars = try client.listWritableCalendars()
        let secondRequest = try XCTUnwrap(httpClient.requests.dropFirst().first)
        let secondQuery = Dictionary(uniqueKeysWithValues: (URLComponents(
            url: try XCTUnwrap(secondRequest.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(calendars.map(\.id), ["primary", "team@example.com"])
        XCTAssertEqual(httpClient.requests.count, 2)
        XCTAssertEqual(secondQuery["pageToken"], "page-2")
        XCTAssertFalse(secondRequest.url?.absoluteString.contains("calendar-access-token") ?? true)
    }

    func testHTTPCalendarListClientRejectsRepeatedPageToken() throws {
        let httpClient = GoogleCalendarRecordingHTTPDataClient(responses: [
            (
                #"{"nextPageToken":"repeat","items":[]}"#.data(using: .utf8)!,
                200
            ),
            (
                #"{"nextPageToken":"repeat","items":[]}"#.data(using: .utf8)!,
                200
            )
        ])
        let client = GoogleCalendarHTTPCalendarListClient(
            tokenProvider: StaticGoogleCalendarBearerTokenProvider(token: "calendar-access-token"),
            httpClient: httpClient
        )

        XCTAssertThrowsError(try client.listWritableCalendars()) { error in
            XCTAssertEqual(
                error as? GoogleCalendarRuntimeError,
                .apiFailure("Google Calendar calendarList.list returned a repeated page token.")
            )
        }
    }

    func testHTTPCalendarListClientRejectsHTTPAndDecodeFailuresWithoutLeakingBodies() throws {
        let failedClient = GoogleCalendarHTTPCalendarListClient(
            tokenProvider: StaticGoogleCalendarBearerTokenProvider(token: "calendar-access-token"),
            httpClient: GoogleCalendarRecordingHTTPDataClient(
                responseBody: #"{"error":"calendar-access-token"}"#.data(using: .utf8)!,
                statusCode: 403
            )
        )
        XCTAssertThrowsError(try failedClient.listWritableCalendars()) { error in
            XCTAssertEqual(
                error as? GoogleCalendarRuntimeError,
                .apiFailure("Google Calendar calendarList.list failed with HTTP 403.")
            )
            XCTAssertFalse(String(describing: error).contains("calendar-access-token"))
        }

        let malformedClient = GoogleCalendarHTTPCalendarListClient(
            tokenProvider: StaticGoogleCalendarBearerTokenProvider(token: "calendar-access-token"),
            httpClient: GoogleCalendarRecordingHTTPDataClient(
                responseBody: #"{"items":"not-a-list"}"#.data(using: .utf8)!,
                statusCode: 200
            )
        )
        XCTAssertThrowsError(try malformedClient.listWritableCalendars()) { error in
            XCTAssertEqual(
                error as? GoogleCalendarRuntimeError,
                .apiFailure("Google Calendar calendar list response could not be decoded.")
            )
            XCTAssertFalse(String(describing: error).contains("calendar-access-token"))
        }
    }

    func testAppRuntimeFactoryReportsOAuthDisconnectedBeforeTokensAndReadyAfterTokens() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let controller = try makeController(secretStore: secretStore, connection: connection)

        XCTAssertEqual(try controller.status(now: Date(timeIntervalSince1970: 4_000)).state, .oauthDisconnected)

        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        try GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore).saveTokens(
            accessToken: "calendar-access-token",
            refreshToken: nil,
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 5_000)
        )

        XCTAssertEqual(try controller.status(now: Date(timeIntervalSince1970: 4_000)).state, .ready)
    }

    func testAppRuntimeFactoryDoesNotTreatExpiredRefreshTokenAsReadyBeforeRefreshSupport() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        try GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore).saveTokens(
            accessToken: "calendar-access-token",
            refreshToken: "calendar-refresh-token",
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 3_000)
        )

        let controller = try makeController(secretStore: secretStore, connection: connection)

        XCTAssertEqual(try controller.status(now: Date(timeIntervalSince1970: 4_000)).state, .tokenExpiredWithoutRefresh)
    }

    func testAppRuntimeFactoryTreatsExpiredRefreshTokenAsReadyWhenOAuthClientIDIsConfigured() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        try GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore).saveTokens(
            accessToken: "expired-calendar-access-token",
            refreshToken: "calendar-refresh-token",
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 3_000)
        )

        let controller = try makeController(
            secretStore: secretStore,
            connection: connection,
            oauthClientID: "google-client-id.apps.googleusercontent.com"
        )

        XCTAssertEqual(try controller.status(now: Date(timeIntervalSince1970: 4_000)).state, .ready)
    }

    func testAppRuntimeStatusCheckDoesNotCreateIdempotencyNamespace() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        try GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore).saveTokens(
            accessToken: "calendar-access-token",
            refreshToken: nil,
            grantedScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            expiresAt: Date(timeIntervalSince1970: 5_000)
        )

        let status = try GoogleCalendarAppRuntimeFactory.syncStatus(
            entitlementStore: GoogleCalendarRuntimeStaticEntitlementStore(plan: .pro),
            secretStore: secretStore,
            connection: connection,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo",
            now: Date(timeIntervalSince1970: 4_000)
        )
        let namespaceRows = try connection.queryRows(
            "SELECT value FROM settings WHERE key = 'google_calendar.idempotency_namespace.v1';"
        )

        XCTAssertEqual(status.state, .ready)
        XCTAssertTrue(namespaceRows.isEmpty)
    }

    func testTaskSyncServiceUsesConfiguredCalendarID() throws {
        let connection = try migratedConnection()
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let linkStore = SQLiteExternalTaskLinkStore(connection: connection)
        let calendarSink = GoogleCalendarRecordingEventSink()
        let project = try boardStore.createProject(title: "Client Launch")
        _ = try boardStore.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Send launch brief",
            dueAt: "2026-07-07"
        ))
        let service = GoogleCalendarTaskSyncService(
            entitlementStore: GoogleCalendarRuntimeStaticEntitlementStore(plan: .pro),
            store: boardStore,
            linkStore: linkStore,
            calendarSink: calendarSink,
            calendarID: "team-calendar@example.com",
            timeZoneIdentifier: "Asia/Tokyo",
            idempotencyNamespace: "test-namespace"
        )

        let result = try service.syncDueTasks(context: ToolExecutionContext(
            approvalToken: ApprovalToken(id: "approved", sessionID: "google-calendar-test"),
            source: .reviewUI
        ))

        XCTAssertEqual(result, GoogleCalendarTaskSyncResult(createdEventCount: 1, skippedAlreadyLinkedCount: 0))
        XCTAssertEqual(calendarSink.records.map(\.calendarID), ["team-calendar@example.com"])
        XCTAssertEqual(calendarSink.records.map(\.timeZoneIdentifier), ["Asia/Tokyo"])
    }

    func testOAuthPKCEBuildsGoogleAuthorizationURLWithoutClientSecret() throws {
        let configuration = GoogleCalendarOAuthAuthorizationConfiguration(
            clientID: "google-client-id.apps.googleusercontent.com",
            redirectURI: "solopm://oauth/google-calendar"
        )

        let request = try GoogleCalendarOAuthAuthorizationService(configuration: configuration)
            .makeAuthorizationRequest(
                state: "calendar-state",
                codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
            )
        let components = try XCTUnwrap(URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(request.codeChallenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "accounts.google.com")
        XCTAssertEqual(query["client_id"], "google-client-id.apps.googleusercontent.com")
        XCTAssertEqual(query["redirect_uri"], "solopm://oauth/google-calendar")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["code_challenge"], request.codeChallenge)
        XCTAssertEqual(
            Set((query["scope"] ?? "").split(separator: " ").map(String.init)),
            [
                GoogleCalendarRuntimeOAuthScope.eventsWrite,
                GoogleCalendarRuntimeOAuthScope.calendarListReadOnly
            ]
        )
        XCTAssertEqual(query["access_type"], "offline")
        XCTAssertEqual(query["prompt"], "consent")
        XCTAssertNil(query["client_secret"])
        XCTAssertFalse(request.authorizationURL.absoluteString.contains("calendar-access-token"))
    }

    func testOAuthAuthorizationRejectsUnsafeRequestConfiguration() throws {
        XCTAssertThrowsError(
            try GoogleCalendarOAuthAuthorizationService(configuration: GoogleCalendarOAuthAuthorizationConfiguration(
                clientID: " \n ",
                redirectURI: "solopm://oauth/google-calendar"
            )).makeAuthorizationRequest(state: "calendar-state", codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarOAuthAuthorizationError, .missingClientID)
        }
        XCTAssertThrowsError(
            try GoogleCalendarOAuthAuthorizationService(configuration: GoogleCalendarOAuthAuthorizationConfiguration(
                clientID: "google-client-id.apps.googleusercontent.com",
                redirectURI: "solopm://oauth/google-calendar?unexpected=query"
            )).makeAuthorizationRequest(state: "calendar-state", codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarOAuthAuthorizationError, .invalidRedirectURI)
        }
        XCTAssertThrowsError(
            try GoogleCalendarOAuthAuthorizationService(configuration: GoogleCalendarOAuthAuthorizationConfiguration(
                clientID: "google-client-id.apps.googleusercontent.com",
                redirectURI: "solopm://oauth/google-calendar",
                scopes: []
            )).makeAuthorizationRequest(state: "calendar-state", codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        ) { error in
            XCTAssertEqual(
                error as? GoogleCalendarOAuthAuthorizationError,
                .missingRequiredScope(GoogleCalendarRuntimeOAuthScope.eventsWrite)
            )
        }
        XCTAssertThrowsError(
            try GoogleCalendarOAuthAuthorizationService(configuration: GoogleCalendarOAuthAuthorizationConfiguration(
                clientID: "google-client-id.apps.googleusercontent.com",
                redirectURI: "solopm://oauth/google-calendar"
            )).makeAuthorizationRequest(state: " \n ", codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarOAuthAuthorizationError, .invalidState)
        }
    }

    func testOAuthCallbackExchangesCodeAndStoresTokensInSecretStore() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        let httpClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: """
            {
              "access_token": "calendar-access-token",
              "refresh_token": "calendar-refresh-token",
              "expires_in": 3600,
              "scope": "\(GoogleCalendarRuntimeOAuthScope.eventsWrite) \(GoogleCalendarRuntimeOAuthScope.calendarListReadOnly)",
              "token_type": "Bearer"
            }
            """.data(using: .utf8)!,
            statusCode: 200
        )
        let service = GoogleCalendarOAuthAuthorizationService(
            configuration: GoogleCalendarOAuthAuthorizationConfiguration(
                clientID: "google-client-id.apps.googleusercontent.com",
                redirectURI: "solopm://oauth/google-calendar"
            ),
            httpClient: httpClient,
            credentialStore: credentialStore
        )
        let pendingRequest = try service.makeAuthorizationRequest(
            state: "calendar-state",
            codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        )

        let metadata = try service.completeAuthorization(
            callbackURL: URL(string: "solopm://oauth/google-calendar?state=calendar-state&code=authorization-code")!,
            pendingRequest: pendingRequest,
            now: Date(timeIntervalSince1970: 4_000)
        )
        let request = try XCTUnwrap(httpClient.requests.first)
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
        let storedValue = try XCTUnwrap(try connection.queryRows(
            "SELECT value FROM settings WHERE key = 'google_calendar.oauth.metadata.v1';"
        ).first?["value"])

        XCTAssertEqual(request.url?.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=authorization-code"))
        XCTAssertTrue(body.contains("client_id=google-client-id.apps.googleusercontent.com"))
        XCTAssertTrue(body.contains("redirect_uri=solopm%3A%2F%2Foauth%2Fgoogle-calendar"))
        XCTAssertTrue(body.contains("code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
        XCTAssertFalse(body.contains("client_secret"))
        XCTAssertEqual(metadata.grantedScopes, [
            GoogleCalendarRuntimeOAuthScope.eventsWrite,
            GoogleCalendarRuntimeOAuthScope.calendarListReadOnly
        ])
        XCTAssertEqual(metadata.expiresAt, Date(timeIntervalSince1970: 7_600))
        XCTAssertEqual(try secretStore.read(GoogleCalendarOAuthCredentialStore.accessTokenKey), "calendar-access-token")
        XCTAssertEqual(try secretStore.read(GoogleCalendarOAuthCredentialStore.refreshTokenKey), "calendar-refresh-token")
        XCTAssertFalse(storedValue.contains("calendar-access-token"))
        XCTAssertFalse(storedValue.contains("calendar-refresh-token"))
    }

    func testOAuthCallbackRejectsRedirectStateAndProviderErrorsBeforeTokenExchange() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        let httpClient = GoogleCalendarRecordingHTTPDataClient(responseBody: Data(), statusCode: 200)
        let service = GoogleCalendarOAuthAuthorizationService(
            configuration: GoogleCalendarOAuthAuthorizationConfiguration(
                clientID: "google-client-id.apps.googleusercontent.com",
                redirectURI: "solopm://oauth/google-calendar"
            ),
            httpClient: httpClient,
            credentialStore: credentialStore
        )
        let pendingRequest = try service.makeAuthorizationRequest(
            state: "calendar-state",
            codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        )

        XCTAssertThrowsError(
            try service.completeAuthorization(
                callbackURL: URL(string: "solopm://oauth/other?state=calendar-state&code=authorization-code")!,
                pendingRequest: pendingRequest
            )
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarOAuthAuthorizationError, .callbackRedirectMismatch)
        }
        XCTAssertThrowsError(
            try service.completeAuthorization(
                callbackURL: URL(string: "solopm://oauth/google-calendar?state=wrong-state&code=authorization-code")!,
                pendingRequest: pendingRequest
            )
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarOAuthAuthorizationError, .callbackStateMismatch)
        }
        XCTAssertThrowsError(
            try service.completeAuthorization(
                callbackURL: URL(string: "solopm://oauth/google-calendar?state=calendar-state&error=access_denied")!,
                pendingRequest: pendingRequest
            )
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarOAuthAuthorizationError, .callbackError("access_denied"))
        }
        XCTAssertThrowsError(
            try service.completeAuthorization(
                callbackURL: URL(string: "solopm://oauth/google-calendar?state=calendar-state")!,
                pendingRequest: pendingRequest
            )
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarOAuthAuthorizationError, .callbackMissingCode)
        }

        XCTAssertTrue(httpClient.requests.isEmpty)
        XCTAssertNil(try metadataStore.loadMetadata())
    }

    func testOAuthCallbackRejectsDuplicateSecurityParametersBeforeTokenExchange() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        let httpClient = GoogleCalendarRecordingHTTPDataClient(responseBody: Data(), statusCode: 200)
        let service = GoogleCalendarOAuthAuthorizationService(
            configuration: GoogleCalendarOAuthAuthorizationConfiguration(
                clientID: " google-client-id.apps.googleusercontent.com ",
                redirectURI: "solopm://oauth/google-calendar"
            ),
            httpClient: httpClient,
            credentialStore: credentialStore
        )
        let pendingRequest = try service.makeAuthorizationRequest(
            state: "calendar-state",
            codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        )

        XCTAssertThrowsError(
            try service.completeAuthorization(
                callbackURL: URL(string: "solopm://oauth/google-calendar?state=calendar-state&state=other&code=authorization-code")!,
                pendingRequest: pendingRequest
            )
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarOAuthAuthorizationError, .callbackInvalidQuery)
        }
        XCTAssertTrue(httpClient.requests.isEmpty)
        XCTAssertNil(try metadataStore.loadMetadata())
    }

    func testOAuthCallbackRejectsScopeMismatchAndInvalidTokenResponse() throws {
        let secretStore = InMemorySecretStore()
        let connection = try migratedConnection()
        let metadataStore = SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        let credentialStore = GoogleCalendarOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        let configuration = GoogleCalendarOAuthAuthorizationConfiguration(
            clientID: "google-client-id.apps.googleusercontent.com",
            redirectURI: "solopm://oauth/google-calendar"
        )
        let scopeMismatchClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: """
            {
              "access_token": "calendar-access-token",
              "scope": "openid profile"
            }
            """.data(using: .utf8)!,
            statusCode: 200
        )
        let invalidTokenClient = GoogleCalendarRecordingHTTPDataClient(
            responseBody: """
            {
              "access_token": "   "
            }
            """.data(using: .utf8)!,
            statusCode: 200
        )
        let scopeMismatchService = GoogleCalendarOAuthAuthorizationService(
            configuration: configuration,
            httpClient: scopeMismatchClient,
            credentialStore: credentialStore
        )
        let invalidTokenService = GoogleCalendarOAuthAuthorizationService(
            configuration: configuration,
            httpClient: invalidTokenClient,
            credentialStore: credentialStore
        )
        let pendingRequest = try scopeMismatchService.makeAuthorizationRequest(
            state: "calendar-state",
            codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        )

        XCTAssertThrowsError(
            try scopeMismatchService.completeAuthorization(
                callbackURL: URL(string: "solopm://oauth/google-calendar?state=calendar-state&code=authorization-code")!,
                pendingRequest: pendingRequest
            )
        ) { error in
            XCTAssertEqual(
                error as? GoogleCalendarOAuthAuthorizationError,
                .missingRequiredScope([
                    GoogleCalendarRuntimeOAuthScope.calendarListReadOnly,
                    GoogleCalendarRuntimeOAuthScope.eventsWrite
                ].sorted().joined(separator: ","))
            )
        }
        XCTAssertNil(try metadataStore.loadMetadata())
        XCTAssertNil(try secretStore.read(GoogleCalendarOAuthCredentialStore.accessTokenKey))

        XCTAssertThrowsError(
            try invalidTokenService.completeAuthorization(
                callbackURL: URL(string: "solopm://oauth/google-calendar?state=calendar-state&code=authorization-code")!,
                pendingRequest: pendingRequest
            )
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarOAuthAuthorizationError, .invalidTokenResponse)
        }
        XCTAssertNil(try metadataStore.loadMetadata())
        XCTAssertNil(try secretStore.read(GoogleCalendarOAuthCredentialStore.accessTokenKey))
    }

    func testOAuthCallbackRequiresTokenExchangeRuntime() throws {
        let service = GoogleCalendarOAuthAuthorizationService(
            configuration: GoogleCalendarOAuthAuthorizationConfiguration(
                clientID: "google-client-id.apps.googleusercontent.com",
                redirectURI: "solopm://oauth/google-calendar"
            )
        )
        let pendingRequest = try service.makeAuthorizationRequest(
            state: "calendar-state",
            codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        )

        XCTAssertThrowsError(
            try service.completeAuthorization(
                callbackURL: URL(string: "solopm://oauth/google-calendar?state=calendar-state&code=authorization-code")!,
                pendingRequest: pendingRequest
            )
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarOAuthAuthorizationError, .missingTokenExchangeRuntime)
        }
    }

    private func makeController(
        secretStore: any SecretStore,
        connection: SQLiteConnection,
        oauthClientID: String? = nil
    ) throws -> GoogleCalendarRuntimeSyncController {
        try GoogleCalendarAppRuntimeFactory.makeSyncController(
            entitlementStore: GoogleCalendarRuntimeStaticEntitlementStore(plan: .pro),
            store: SQLiteProjectBoardStore(connection: connection),
            linkStore: SQLiteExternalTaskLinkStore(connection: connection),
            secretStore: secretStore,
            connection: connection,
            idempotencyNamespaceStore: SQLiteGoogleCalendarIdempotencyNamespaceStore(connection: connection),
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo",
            oauthClientID: oauthClientID
        )
    }

    private func migratedConnection(path: String = ":memory:") throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }
}

private struct GoogleCalendarRuntimeStaticEntitlementStore: EntitlementStore {
    var plan: SubscriptionPlan

    func snapshot() throws -> EntitlementSnapshot {
        EntitlementSnapshot(plan: plan, source: .localLicense)
    }
}

private struct StaticGoogleCalendarBearerTokenProvider: GoogleCalendarBearerTokenProvider {
    var token: String

    func bearerToken() throws -> String {
        token
    }
}

private final class GoogleCalendarRecordingHTTPDataClient: SynchronousHTTPDataClient, @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [(body: Data, statusCode: Int)]
    private var recordedRequests: [URLRequest] = []

    init(responseBody: Data, statusCode: Int) {
        self.responses = [(responseBody, statusCode)]
    }

    init(responses: [(Data, Int)]) {
        self.responses = responses.map { (body: $0.0, statusCode: $0.1) }
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        lock.lock()
        let responseIndex = recordedRequests.count
        recordedRequests.append(request)
        let response = responses[min(responseIndex, responses.count - 1)]
        lock.unlock()
        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "https://www.googleapis.com")!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response.body, httpResponse)
    }
}

private final class GoogleCalendarRecordingEventSink: ExternalCalendarEventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRecords: [ExternalCalendarEventRecord] = []

    var records: [ExternalCalendarEventRecord] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRecords
    }

    func createEvent(
        _ draft: CalendarEventDraft,
        calendarID: String,
        timeZoneIdentifier: String,
        context: ToolExecutionContext
    ) throws -> ExternalCalendarEventRecord {
        guard context.approvalToken != nil else {
            throw GoogleCalendarRuntimeSyncError.approvalRequired
        }
        lock.lock()
        let record = ExternalCalendarEventRecord(
            providerID: ExternalTaskSource.googleCalendar.rawValue,
            externalID: "event-\(recordedRecords.count + 1)",
            calendarID: calendarID,
            timeZoneIdentifier: timeZoneIdentifier,
            title: draft.title
        )
        recordedRecords.append(record)
        lock.unlock()
        return record
    }
}
