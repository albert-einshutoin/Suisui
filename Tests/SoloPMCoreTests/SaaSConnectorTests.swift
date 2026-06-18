import XCTest
@testable import SoloPMCore

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
