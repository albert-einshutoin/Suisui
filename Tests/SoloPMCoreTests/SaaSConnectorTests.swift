import XCTest
@testable import SoloPMCore
@testable import SoloPMExternalConnectors

final class SaaSConnectorTests: XCTestCase {
    func testOAuthLifecycleStoresTokensInSecretStoreRefreshesAndDisconnects() throws {
        let secretStore = InMemorySecretStore()
        let metadataStore = InMemoryOAuthCredentialMetadataStore()
        let credentialStore = KeychainOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        let client = RecordingOAuthClient(refreshResponse: OAuthTokenResponse(
            accessToken: "new-access-token",
            refreshToken: "new-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 2_000),
            scopes: [.googleCalendarEvents, .offlineAccess]
        ))
        let lifecycle = OAuthTokenLifecycle(store: credentialStore, client: client)

        try credentialStore.saveTokens(
            connectorID: .googleCalendar,
            accessToken: "old-access-token",
            refreshToken: "old-refresh-token",
            scopes: [.googleCalendarEvents, .offlineAccess],
            expiresAt: Date(timeIntervalSince1970: 1)
        )

        let credential = try lifecycle.validCredential(
            for: .googleCalendar,
            requiredScopes: [.googleCalendarEvents],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(credential.scopes, [.googleCalendarEvents, .offlineAccess])
        XCTAssertEqual(try secretStore.read(credential.accessTokenKey), "new-access-token")
        XCTAssertEqual(client.refreshRequests.map(\.connectorID), [.googleCalendar])
        XCTAssertThrowsError(
            try lifecycle.validCredential(
                for: .googleCalendar,
                requiredScopes: [.googleCalendarEvents, .gmailCompose],
                now: Date(timeIntervalSince1970: 100)
            )
        ) { error in
            XCTAssertEqual(error as? OAuthTokenLifecycleError, .scopeMismatch(.googleCalendar, missing: [.gmailCompose]))
        }

        try credentialStore.saveTokens(
            connectorID: .googleCalendar,
            accessToken: "access-without-refresh",
            refreshToken: nil,
            scopes: [.googleCalendarEvents],
            expiresAt: Date(timeIntervalSince1970: 3_000)
        )
        XCTAssertNil(try credentialStore.loadCredential(for: .googleCalendar)?.refreshTokenKey)
        XCTAssertNil(try secretStore.read(SecretKey("oauth.google_calendar.refresh_token")))

        try lifecycle.disconnect(.googleCalendar)

        XCTAssertNil(try credentialStore.loadCredential(for: .googleCalendar))
        XCTAssertNil(try secretStore.read(SecretKey("oauth.google_calendar.access_token")))
        XCTAssertEqual(client.revokedConnectorIDs, [.googleCalendar])
    }

    func testOAuthCredentialStoreDoesNotDropRefreshTokenDeletionFailure() throws {
        let secretStore = ToggleFailingDeleteSecretStore(failingKey: SecretKey("oauth.slack.refresh_token"))
        let metadataStore = InMemoryOAuthCredentialMetadataStore()
        let credentialStore = KeychainOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)

        try credentialStore.saveTokens(
            connectorID: .slack,
            accessToken: "old-access-token",
            refreshToken: "old-refresh-token",
            scopes: [.slackChannelsRead],
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )

        secretStore.shouldFailDelete = true

        XCTAssertThrowsError(
            try credentialStore.saveTokens(
                connectorID: .slack,
                accessToken: "new-access-token",
                refreshToken: nil,
                scopes: [.slackChannelsRead],
                expiresAt: Date(timeIntervalSince1970: 2_000)
            )
        ) { error in
            XCTAssertEqual(error as? SecretStoreError, .unexpectedStatus(-25291))
        }

        let credential = try XCTUnwrap(try credentialStore.loadCredential(for: .slack))
        XCTAssertEqual(credential.refreshTokenKey, SecretKey("oauth.slack.refresh_token"))
        XCTAssertEqual(try secretStore.read(SecretKey("oauth.slack.access_token")), "old-access-token")
        XCTAssertEqual(try secretStore.read(SecretKey("oauth.slack.refresh_token")), "old-refresh-token")
    }

    func testGoogleCalendarConnectorUsesCalendarAbstractionAndRequiresApproval() throws {
        let client = InMemoryGoogleCalendarClient(validCalendarIDs: ["primary"])
        let connector = GoogleCalendarConnector(client: client)
        let draft = CalendarEventDraft(
            title: "Planning",
            startAt: "2026-06-18T09:00:00Z",
            endAt: "2026-06-18T10:00:00Z",
            isAllDay: false,
            notes: "Phase8"
        )

        XCTAssertThrowsError(
            try connector.createEvent(
                draft,
                calendarID: "primary",
                timeZoneIdentifier: "Asia/Tokyo",
                context: ToolExecutionContext(source: .developerTool)
            )
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .approvalRequired(.googleCalendar))
        }

        let record = try connector.createEvent(
            draft,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo",
            context: approvedContext()
        )

        XCTAssertEqual(record.calendarID, "primary")
        XCTAssertEqual(record.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(record.event.draft.title, "Planning")

        XCTAssertThrowsError(
            try connector.createEvent(draft, calendarID: "missing", timeZoneIdentifier: "Asia/Tokyo", context: approvedContext())
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .invalidRequest(.googleCalendar, "Calendar missing is not available."))
        }
    }

    func testGoogleCalendarHTTPClientCreatesEventsInsertRequestWithOAuthToken() throws {
        let secretStore = InMemorySecretStore()
        let metadataStore = InMemoryOAuthCredentialMetadataStore()
        let credentialStore = KeychainOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        try credentialStore.saveTokens(
            connectorID: .googleCalendar,
            accessToken: "calendar-access-token",
            refreshToken: "calendar-refresh-token",
            scopes: [.googleCalendarEvents, .offlineAccess],
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
        )
        let httpClient = RecordingSynchronousHTTPDataClient(
            responseBody: #"{"id":"event-123"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = GoogleCalendarHTTPClient(
            tokenProvider: OAuthCredentialBearerTokenProvider(
                connectorID: .googleCalendar,
                requiredScopes: [.googleCalendarEvents],
                lifecycle: OAuthTokenLifecycle(
                    store: credentialStore,
                    client: RecordingOAuthClient(refreshResponse: OAuthTokenResponse(
                        accessToken: "unused",
                        refreshToken: nil,
                        expiresAt: Date(timeIntervalSince1970: 5_000),
                        scopes: [.googleCalendarEvents]
                    ))
                ),
                credentialStore: credentialStore
            ),
            httpClient: httpClient,
            configuration: GoogleCalendarHTTPConfiguration(baseURL: URL(string: "https://www.googleapis.com/calendar/v3")!)
        )

        let record = try client.createEvent(
            CalendarEventDraft(
                title: "Planning",
                startAt: "2026-07-07",
                endAt: "2026-07-07",
                isAllDay: true,
                notes: "SoloPM"
            ),
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let request = try XCTUnwrap(httpClient.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let start = try XCTUnwrap(body["start"] as? [String: Any])

        XCTAssertEqual(record.event.id, "event-123")
        XCTAssertEqual(request.url?.absoluteString, "https://www.googleapis.com/calendar/v3/calendars/primary/events")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer calendar-access-token")
        XCTAssertEqual(body["summary"] as? String, "Planning")
        XCTAssertEqual(start["date"] as? String, "2026-07-07")
        XCTAssertNil(start["dateTime"])
        XCTAssertFalse(request.url?.absoluteString.contains("calendar-access-token") ?? true)
    }

    func testGoogleCalendarHTTPClientSendsStableEventIDAndPrivateSoloPMIdentity() throws {
        let httpClient = RecordingSynchronousHTTPDataClient(
            responseBody: #"{"id":"solopmp42t1"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = GoogleCalendarHTTPClient(
            tokenProvider: StaticBearerTokenProvider(token: "calendar-access-token"),
            httpClient: httpClient,
            configuration: GoogleCalendarHTTPConfiguration(baseURL: URL(string: "https://www.googleapis.com/calendar/v3")!)
        )

        _ = try client.createEvent(
            CalendarEventDraft(
                title: "Due task",
                startAt: "2026-07-04",
                endAt: "2026-07-05",
                isAllDay: true,
                notes: "SoloPM",
                idempotencyKey: "solopm\(String(repeating: "a", count: 64))"
            ),
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        let request = try XCTUnwrap(httpClient.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let extendedProperties = try XCTUnwrap(body["extendedProperties"] as? [String: Any])
        let privateProperties = try XCTUnwrap(extendedProperties["private"] as? [String: Any])

        XCTAssertEqual(body["id"] as? String, "solopm\(String(repeating: "a", count: 64))")
        XCTAssertEqual(privateProperties["soloPMIdempotencyKey"] as? String, "solopm\(String(repeating: "a", count: 64))")
    }

    func testGoogleCalendarHTTPClientTreatsDuplicateStableEventIDAsIdempotentSuccess() throws {
        let httpClient = RecordingSynchronousHTTPDataClient(
            responseBody: #"{"error":{"code":409}}"#.data(using: .utf8)!,
            statusCode: 409
        )
        let client = GoogleCalendarHTTPClient(
            tokenProvider: StaticBearerTokenProvider(token: "calendar-access-token"),
            httpClient: httpClient,
            configuration: GoogleCalendarHTTPConfiguration(baseURL: URL(string: "https://www.googleapis.com/calendar/v3")!)
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

    func testGoogleCalendarHTTPClientDropsUnsafeIdempotencyKeys() throws {
        let httpClient = RecordingSynchronousHTTPDataClient(
            responseBody: #"{"id":"event-123"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = GoogleCalendarHTTPClient(
            tokenProvider: StaticBearerTokenProvider(token: "calendar-access-token"),
            httpClient: httpClient,
            configuration: GoogleCalendarHTTPConfiguration(baseURL: URL(string: "https://www.googleapis.com/calendar/v3")!)
        )

        _ = try client.createEvent(
            CalendarEventDraft(
                title: "Due task",
                startAt: "2026-07-04",
                endAt: "2026-07-05",
                isAllDay: true,
                idempotencyKey: "solopmp42t1"
            ),
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        let request = try XCTUnwrap(httpClient.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })

        XCTAssertNil(body["id"])
        XCTAssertNil(body["extendedProperties"])
    }

    func testGoogleCalendarCredentialStatusStoreMapsOAuthCredentialMetadataThroughKeychainBoundary() throws {
        let secretStore = InMemorySecretStore()
        let metadataStore = InMemoryOAuthCredentialMetadataStore()
        let credentialStore = KeychainOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        let statusStore = GoogleCalendarOAuthCredentialStatusStore(credentialStore: credentialStore)

        XCTAssertNil(try statusStore.loadGoogleCalendarCredentialStatus())

        try credentialStore.saveTokens(
            connectorID: .googleCalendar,
            accessToken: "calendar-access-token",
            refreshToken: "calendar-refresh-token",
            scopes: [.googleCalendarEvents, .offlineAccess],
            expiresAt: Date(timeIntervalSince1970: 4_000)
        )

        let status = try XCTUnwrap(try statusStore.loadGoogleCalendarCredentialStatus())
        XCTAssertEqual(status.grantedScopes, [
            OAuthScope.googleCalendarEvents.rawValue,
            OAuthScope.offlineAccess.rawValue
        ])
        XCTAssertEqual(status.expiresAt, Date(timeIntervalSince1970: 4_000))
        XCTAssertTrue(status.hasRefreshToken)

        try secretStore.delete(SecretKey("oauth.google_calendar.access_token"))
        XCTAssertNil(try statusStore.loadGoogleCalendarCredentialStatus())
    }

    func testGoogleCalendarConnectorEventSinkBridgesApprovedConnectorWrites() throws {
        let client = InMemoryGoogleCalendarClient(validCalendarIDs: ["primary"])
        let sink = GoogleCalendarConnectorEventSink(connector: GoogleCalendarConnector(client: client))
        let draft = CalendarEventDraft(
            title: "Planning",
            startAt: "2026-07-07",
            endAt: "2026-07-08",
            isAllDay: true,
            notes: "SoloPM",
            idempotencyKey: "solopm\(String(repeating: "c", count: 64))"
        )

        XCTAssertThrowsError(
            try sink.createEvent(draft, calendarID: "primary", timeZoneIdentifier: "Asia/Tokyo", context: ToolExecutionContext(source: .developerTool))
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .approvalRequired(.googleCalendar))
        }

        let record = try sink.createEvent(
            draft,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo",
            context: approvedContext()
        )

        XCTAssertEqual(record.providerID, ExternalTaskSource.googleCalendar.rawValue)
        XCTAssertEqual(record.externalID, "google-calendar-event-1")
        XCTAssertEqual(record.calendarID, "primary")
        XCTAssertEqual(record.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(record.title, "Planning")
    }

    func testGmailDraftConnectorNeverExposesSendAndRequiresApproval() throws {
        let connector = GmailDraftConnector(client: InMemoryGmailDraftClient())

        XCTAssertEqual(connector.requiredScopes, [.gmailCompose])
        XCTAssertFalse(connector.requiredScopes.contains(.gmailSend))
        XCTAssertFalse(connector.supportedOperations.contains(.send))

        XCTAssertThrowsError(
            try connector.createDraft(
                GmailDraft(to: ["team@example.com"], subject: "Status", body: "Draft only"),
                context: ToolExecutionContext(source: .developerTool)
            )
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .approvalRequired(.gmail))
        }

        let record = try connector.createDraft(
            GmailDraft(to: ["team@example.com"], subject: "Status", body: "Draft only"),
            context: approvedContext()
        )

        XCTAssertEqual(record.subject, "Status")
        XCTAssertEqual(record.to, ["team@example.com"])
    }

    func testSlackConnectorSeparatesDraftPostApprovalChannelAndRevocation() throws {
        let client = InMemorySlackClient(channels: ["C123": "team"])
        let connector = SlackConnector(client: client)

        let draft = try connector.draftMessage(channelID: "C123", text: "Review ready")
        XCTAssertEqual(draft.channelID, "C123")

        XCTAssertThrowsError(
            try connector.postMessage(channelID: "C123", text: "Review ready", context: ToolExecutionContext(source: .developerTool))
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .approvalRequired(.slack))
        }
        XCTAssertThrowsError(
            try connector.postMessage(channelID: "missing", text: "Review ready", context: approvedContext())
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .notFound(.slack, "Slack channel missing was not found."))
        }

        client.isTokenRevoked = true
        XCTAssertThrowsError(
            try connector.postMessage(channelID: "C123", text: "Review ready", context: approvedContext())
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .tokenRevoked(.slack))
        }
    }

    func testGoogleDriveConnectorWritesOnlyInsideSelectedFolder() throws {
        let connector = GoogleDriveConnector(
            selectedFolderID: "folder-1",
            client: InMemoryGoogleDriveClient()
        )

        XCTAssertThrowsError(
            try connector.createDocument(
                title: "Spec",
                body: "Approved scope",
                folderID: "folder-2",
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .permissionDenied(.googleDrive, "Folder folder-2 is outside the selected Drive scope."))
        }

        let record = try connector.createDocument(title: "Spec", body: "Approved scope", folderID: "folder-1", context: approvedContext())

        XCTAssertEqual(record.folderID, "folder-1")
        XCTAssertEqual(record.title, "Spec")
    }

    func testNotionConnectorRequiresMappingApprovalAndSurfacesAPIFailure() throws {
        let client = InMemoryNotionClient()
        let connector = NotionConnector(
            mappings: [.task: NotionMapping(databaseID: "db-task", titleProperty: "Name")],
            client: client
        )

        XCTAssertThrowsError(
            try connector.createPage(kind: .project, title: "Launch", properties: [:], context: approvedContext())
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .mappingMissing(.notion, "project"))
        }
        XCTAssertThrowsError(
            try connector.createPage(kind: .task, title: "Ship", properties: [:], context: ToolExecutionContext(source: .developerTool))
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .approvalRequired(.notion))
        }

        client.nextError = .apiFailure(.notion, "notion 500")
        XCTAssertThrowsError(
            try connector.createPage(kind: .task, title: "Ship", properties: [:], context: approvedContext())
        ) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .apiFailure(.notion, "notion 500"))
        }
    }

    func testTaskManagementConnectorsSupportImportExportAndRequireApproval() throws {
        let draft = ExternalTaskDraft(
            title: "Ship import/export",
            detail: "Round-trip with external task tools.",
            status: "planned",
            priority: "high",
            dueAt: "2026-07-06"
        )
        let todoist = TodoistConnector(client: InMemoryExternalTaskClient(providerID: .todoist))
        let linear = LinearConnector(teamID: "team-1", client: InMemoryExternalTaskClient(providerID: .linear))
        let github = GitHubIssuesConnector(repository: "owner/repo", client: InMemoryExternalTaskClient(providerID: .githubIssues))

        XCTAssertEqual(todoist.requiredScopes, [.todoistDataReadWrite])
        XCTAssertEqual(linear.requiredScopes, [.linearIssuesCreate])
        XCTAssertEqual(github.requiredScopes, [.githubIssuesWrite])
        XCTAssertTrue(todoist.supportedOperations.isSuperset(of: [.create, .importItems, .exportItems]))
        XCTAssertTrue(linear.supportedOperations.isSuperset(of: [.create, .importItems, .exportItems]))
        XCTAssertTrue(github.supportedOperations.isSuperset(of: [.create, .importItems, .exportItems]))

        XCTAssertThrowsError(try todoist.exportTask(draft, projectID: "project-1", context: ToolExecutionContext(source: .developerTool))) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .approvalRequired(.todoist))
        }
        XCTAssertThrowsError(try linear.importTasks(context: ToolExecutionContext(source: .developerTool))) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .approvalRequired(.linear))
        }
        XCTAssertThrowsError(try github.exportTask(draft, context: ToolExecutionContext(source: .developerTool))) { error in
            XCTAssertEqual(error as? SaaSConnectorError, .approvalRequired(.githubIssues))
        }

        let todoistRecord = try todoist.exportTask(draft, projectID: "project-1", context: approvedContext())
        let linearRecord = try linear.exportTask(draft, context: approvedContext())
        let githubRecord = try github.exportTask(draft, context: approvedContext())

        XCTAssertEqual(todoistRecord.providerID, .todoist)
        XCTAssertEqual(todoistRecord.externalID, "todoist-task-1")
        XCTAssertEqual(linearRecord.providerID, .linear)
        XCTAssertEqual(linearRecord.externalID, "linear-task-1")
        XCTAssertEqual(githubRecord.providerID, .githubIssues)
        XCTAssertEqual(githubRecord.externalID, "github_issues-task-1")
        XCTAssertEqual(try todoist.importTasks(projectID: "project-1", context: approvedContext()).map(\.title), ["Ship import/export"])
    }

    func testConnectorHealthDashboardShowsTokenExpiryReconnectAndAuditError() throws {
        let secretStore = InMemorySecretStore()
        let metadataStore = InMemoryOAuthCredentialMetadataStore()
        let store = KeychainOAuthCredentialStore(secretStore: secretStore, metadataStore: metadataStore)
        try store.saveTokens(
            connectorID: .slack,
            accessToken: "xoxb-token",
            refreshToken: nil,
            scopes: [.slackChannelsRead],
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        let dashboard = ConnectorHealthDashboard(
            credentialStore: store,
            healthClient: StaticConnectorHealthClient(results: [.slack: .permissionIssue("missing channels:read")]),
            auditEvents: [
                AuditEvent(
                    category: "saas_connector",
                    action: "slack.post",
                    status: .failed,
                    metadata: ["connector_id": "slack", "error": "missing channels:read"]
                )
            ]
        )

        let snapshot = try dashboard.snapshot(for: [.gmail, .slack], now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(snapshot.first { $0.connectorID == .gmail }?.status, .disconnected)
        let slack = try XCTUnwrap(snapshot.first { $0.connectorID == .slack })
        XCTAssertEqual(slack.status, .tokenExpired)
        XCTAssertEqual(slack.reconnectAction, .reconnect(.slack))
        XCTAssertEqual(slack.lastError, "missing channels:read")
    }

    private func approvedContext() -> ToolExecutionContext {
        ToolExecutionContext(
            approvalToken: ApprovalToken(id: "approval", sessionID: "session"),
            source: .developerTool
        )
    }
}

private final class RecordingOAuthClient: OAuthClient, @unchecked Sendable {
    private let refreshResponse: OAuthTokenResponse
    private let lock = NSLock()
    private var recordedRefreshRequests: [OAuthRefreshRequest] = []
    private var recordedRevokedConnectorIDs: [SaaSConnectorID] = []

    init(refreshResponse: OAuthTokenResponse) {
        self.refreshResponse = refreshResponse
    }

    var refreshRequests: [OAuthRefreshRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRefreshRequests
    }

    var revokedConnectorIDs: [SaaSConnectorID] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRevokedConnectorIDs
    }

    func refreshToken(_ request: OAuthRefreshRequest) throws -> OAuthTokenResponse {
        lock.lock()
        defer { lock.unlock() }
        recordedRefreshRequests.append(request)
        return refreshResponse
    }

    func revokeToken(connectorID: SaaSConnectorID, accessToken: String?) throws {
        lock.lock()
        defer { lock.unlock() }
        recordedRevokedConnectorIDs.append(connectorID)
    }
}

private final class ToggleFailingDeleteSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private let failingKey: SecretKey
    private var values: [SecretKey: String] = [:]
    var shouldFailDelete = false

    init(failingKey: SecretKey) {
        self.failingKey = failingKey
    }

    func save(_ value: String, for key: SecretKey) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func read(_ key: SecretKey) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func delete(_ key: SecretKey) throws {
        lock.lock()
        defer { lock.unlock() }
        if shouldFailDelete, key == failingKey {
            throw SecretStoreError.unexpectedStatus(-25291)
        }
        values.removeValue(forKey: key)
    }
}

private final class RecordingSynchronousHTTPDataClient: SynchronousHTTPDataClient, @unchecked Sendable {
    private let lock = NSLock()
    private let responseBody: Data
    private let statusCode: Int
    private var recordedRequests: [URLRequest] = []

    init(responseBody: Data, statusCode: Int) {
        self.responseBody = responseBody
        self.statusCode = statusCode
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        lock.lock()
        recordedRequests.append(request)
        lock.unlock()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (responseBody, response)
    }
}

private struct StaticBearerTokenProvider: BearerTokenProvider {
    var token: String

    func bearerToken() throws -> String {
        token
    }
}
