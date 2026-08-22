import CryptoKit
import Foundation
import SuisuiCore

public enum GoogleCalendarRuntimeOAuthScope {
    public static let eventsWrite = ExternalAuthorizationScopeIdentifier.googleCalendarEventsWrite
    public static let calendarListReadOnly = ExternalAuthorizationScopeIdentifier.googleCalendarCalendarListReadOnly
    public static let offlineAccess = ExternalAuthorizationScopeIdentifier.offlineAccess
}

public enum GoogleCalendarRuntimeError: Error, Equatable, Sendable {
    case disconnected
    case invalidAccessToken
    case missingRequiredScope(String)
    case rateLimited(retryAfterSeconds: TimeInterval?)
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
    private static let settingsKey = "\(ExternalIntegrationIdentifier.googleCalendar).oauth.metadata.v1"

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
    public static let accessTokenKey = SecretKey("oauth.\(ExternalIntegrationIdentifier.googleCalendar).access_token")
    public static let refreshTokenKey = SecretKey("oauth.\(ExternalIntegrationIdentifier.googleCalendar).refresh_token")

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

    public func saveRefreshedAccessToken(
        accessToken: String,
        refreshToken: String?,
        grantedScopes: Set<String>,
        expiresAt: Date?,
        previousMetadata: GoogleCalendarOAuthCredentialMetadata
    ) throws {
        guard accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw GoogleCalendarRuntimeError.invalidAccessToken
        }
        let normalizedRefreshToken = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        try secretStore.save(accessToken, for: Self.accessTokenKey)

        let refreshTokenKey: SecretKey?
        if let refreshToken, normalizedRefreshToken?.isEmpty == false {
            try secretStore.save(refreshToken, for: Self.refreshTokenKey)
            refreshTokenKey = Self.refreshTokenKey
        } else {
            // Google normally omits refresh_token on refresh responses. Preserve
            // the existing Keychain refresh token reference so future refreshes
            // remain possible without writing token material into SQLite.
            refreshTokenKey = previousMetadata.refreshTokenKey
        }

        try metadataStore.saveMetadata(GoogleCalendarOAuthCredentialMetadata(
            grantedScopes: grantedScopes,
            expiresAt: expiresAt,
            accessTokenKey: Self.accessTokenKey,
            refreshTokenKey: refreshTokenKey
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
        // Also clear the well-known Suisui OAuth keys even if metadata is
        // missing or stale. This handles interrupted writes and corrupted
        // metadata without leaving token material in Keychain after disconnect.
        try secretStore.delete(Self.accessTokenKey)
        try secretStore.delete(Self.refreshTokenKey)
        try metadataStore.deleteMetadata()
    }
}

public struct GoogleCalendarOAuthAuthorizationConfiguration: Equatable, Sendable {
    public var clientID: String
    public var redirectURI: String
    public var authorizationEndpoint: URL
    public var tokenEndpoint: URL
    public var scopes: Set<String>

    public init(
        clientID: String,
        redirectURI: String,
        authorizationEndpoint: URL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!,
        scopes: Set<String> = [
            GoogleCalendarRuntimeOAuthScope.eventsWrite,
            GoogleCalendarRuntimeOAuthScope.calendarListReadOnly
        ]
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
    }
}

public struct GoogleCalendarOAuthTokenRefreshConfiguration: Equatable, Sendable {
    public var clientID: String
    public var tokenEndpoint: URL
    public var minimumTokenLifetime: TimeInterval

    public init(
        clientID: String,
        tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!,
        minimumTokenLifetime: TimeInterval = 60
    ) {
        self.clientID = clientID
        self.tokenEndpoint = tokenEndpoint
        self.minimumTokenLifetime = minimumTokenLifetime
    }
}

public struct GoogleCalendarOAuthAuthorizationRequest: Equatable, Sendable {
    public var authorizationURL: URL
    public var state: String
    public var codeVerifier: String
    public var codeChallenge: String

    public init(
        authorizationURL: URL,
        state: String,
        codeVerifier: String,
        codeChallenge: String
    ) {
        self.authorizationURL = authorizationURL
        self.state = state
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
    }
}

public enum GoogleCalendarOAuthAuthorizationError: Error, Equatable, Sendable {
    case missingClientID
    case invalidRedirectURI
    case invalidState
    case invalidCodeVerifier
    case missingTokenExchangeRuntime
    case callbackRedirectMismatch
    case callbackInvalidQuery
    case callbackStateMismatch
    case callbackMissingCode
    case callbackError(String)
    case invalidTokenResponse
    case missingRequiredScope(String)
    case tokenExchangeFailed(String)
}

public enum GoogleCalendarOAuthPKCE {
    public static func makeCodeChallenge(for verifier: String) throws -> String {
        guard (43...128).contains(verifier.count),
              verifier.range(of: #"^[A-Za-z0-9._~-]+$"#, options: .regularExpression) != nil else {
            throw GoogleCalendarOAuthAuthorizationError.invalidCodeVerifier
        }
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

public struct GoogleCalendarOAuthAuthorizationService: Sendable {
    private let configuration: GoogleCalendarOAuthAuthorizationConfiguration
    private let httpClient: (any SynchronousHTTPDataClient)?
    private let credentialStore: GoogleCalendarOAuthCredentialStore?

    public init(
        configuration: GoogleCalendarOAuthAuthorizationConfiguration,
        httpClient: (any SynchronousHTTPDataClient)? = nil,
        credentialStore: GoogleCalendarOAuthCredentialStore? = nil
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.credentialStore = credentialStore
    }

    public func makeAuthorizationRequest() throws -> GoogleCalendarOAuthAuthorizationRequest {
        try makeAuthorizationRequest(
            state: UUID().uuidString,
            codeVerifier: Self.makeCodeVerifier()
        )
    }

    public func makeAuthorizationRequest(state: String) throws -> GoogleCalendarOAuthAuthorizationRequest {
        try makeAuthorizationRequest(
            state: state,
            codeVerifier: Self.makeCodeVerifier()
        )
    }

    public func makeAuthorizationRequest(
        state: String,
        codeVerifier: String
    ) throws -> GoogleCalendarOAuthAuthorizationRequest {
        let normalizedClientID = configuration.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedClientID.isEmpty == false else {
            throw GoogleCalendarOAuthAuthorizationError.missingClientID
        }
        let normalizedState = state.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedState.isEmpty == false else {
            throw GoogleCalendarOAuthAuthorizationError.invalidState
        }
        let requiredScope = GoogleCalendarRuntimeOAuthScope.eventsWrite
        guard configuration.scopes.contains(requiredScope) else {
            throw GoogleCalendarOAuthAuthorizationError.missingRequiredScope(requiredScope)
        }
        guard redirectComponents != nil else {
            throw GoogleCalendarOAuthAuthorizationError.invalidRedirectURI
        }
        let codeChallenge = try GoogleCalendarOAuthPKCE.makeCodeChallenge(for: codeVerifier)
        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: normalizedClientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopes.sorted().joined(separator: " ")),
            URLQueryItem(name: "state", value: normalizedState),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authorizationURL = components?.url else {
            throw GoogleCalendarOAuthAuthorizationError.invalidRedirectURI
        }
        return GoogleCalendarOAuthAuthorizationRequest(
            authorizationURL: authorizationURL,
            state: normalizedState,
            codeVerifier: codeVerifier,
            codeChallenge: codeChallenge
        )
    }

    public func completeAuthorization(
        callbackURL: URL,
        pendingRequest: GoogleCalendarOAuthAuthorizationRequest,
        now: Date = Date()
    ) throws -> GoogleCalendarOAuthCredentialMetadata {
        guard let httpClient, let credentialStore else {
            throw GoogleCalendarOAuthAuthorizationError.missingTokenExchangeRuntime
        }
        let code = try authorizationCode(
            from: callbackURL,
            pendingRequest: pendingRequest
        )
        let request = try makeTokenExchangeRequest(
            code: code,
            codeVerifier: pendingRequest.codeVerifier
        )
        let (data, response) = try httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleCalendarOAuthAuthorizationError.tokenExchangeFailed(
                "Google OAuth token exchange failed with HTTP \(response.statusCode)."
            )
        }

        let tokenResponse: GoogleCalendarOAuthTokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(GoogleCalendarOAuthTokenResponse.self, from: data)
        } catch {
            throw GoogleCalendarOAuthAuthorizationError.invalidTokenResponse
        }

        let accessToken = tokenResponse.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard accessToken.isEmpty == false else {
            throw GoogleCalendarOAuthAuthorizationError.invalidTokenResponse
        }

        let grantedScopes = tokenResponse.grantedScopes(defaultScopes: configuration.scopes)
        let missingScopes = configuration.scopes.subtracting(grantedScopes)
        guard missingScopes.isEmpty else {
            throw GoogleCalendarOAuthAuthorizationError.missingRequiredScope(
                missingScopes.sorted().joined(separator: ",")
            )
        }

        let expiresAt = tokenResponse.expiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
        try credentialStore.saveTokens(
            accessToken: accessToken,
            refreshToken: tokenResponse.refreshToken,
            grantedScopes: grantedScopes,
            expiresAt: expiresAt
        )
        guard let metadata = try credentialStore.loadMetadata() else {
            throw GoogleCalendarOAuthAuthorizationError.invalidTokenResponse
        }
        return metadata
    }

    private var redirectComponents: URLComponents? {
        guard let components = URLComponents(string: configuration.redirectURI),
              let scheme = components.scheme,
              scheme.isEmpty == false,
              (components.queryItems ?? []).isEmpty,
              components.fragment == nil else {
            return nil
        }
        return components
    }

    private static func makeCodeVerifier(length: Int = 64) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters.randomElement(using: &generator)! })
    }

    private func authorizationCode(
        from callbackURL: URL,
        pendingRequest: GoogleCalendarOAuthAuthorizationRequest
    ) throws -> String {
        guard callbackURLMatchesRedirect(callbackURL) else {
            throw GoogleCalendarOAuthAuthorizationError.callbackRedirectMismatch
        }
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let query = try validatedOAuthCallbackQuery(queryItems)
        if let callbackError = query["error"],
           callbackError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            throw GoogleCalendarOAuthAuthorizationError.callbackError(callbackError)
        }
        guard query["state"] == pendingRequest.state else {
            throw GoogleCalendarOAuthAuthorizationError.callbackStateMismatch
        }
        guard let code = query["code"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              code.isEmpty == false else {
            throw GoogleCalendarOAuthAuthorizationError.callbackMissingCode
        }
        return code
    }

    private func validatedOAuthCallbackQuery(_ queryItems: [URLQueryItem]) throws -> [String: String] {
        var query: [String: String] = [:]
        for item in queryItems {
            guard let value = item.value,
                  query[item.name] == nil else {
                throw GoogleCalendarOAuthAuthorizationError.callbackInvalidQuery
            }
            query[item.name] = value
        }
        return query
    }

    private func callbackURLMatchesRedirect(_ callbackURL: URL) -> Bool {
        guard let expected = redirectComponents,
              let actual = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        return expected.scheme == actual.scheme
            && expected.user == actual.user
            && expected.password == actual.password
            && expected.host == actual.host
            && expected.port == actual.port
            && expected.path == actual.path
    }

    private func makeTokenExchangeRequest(
        code: String,
        codeVerifier: String
    ) throws -> URLRequest {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let normalizedClientID = configuration.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        request.httpBody = GoogleCalendarFormURLEncoder.encode([
            "client_id": normalizedClientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.redirectURI
        ]).data(using: .utf8)
        return request
    }
}

public struct GoogleCalendarOAuthTokenRefreshService: Sendable {
    private let configuration: GoogleCalendarOAuthTokenRefreshConfiguration
    private let httpClient: any SynchronousHTTPDataClient
    private let credentialStore: GoogleCalendarOAuthCredentialStore

    var minimumTokenLifetime: TimeInterval {
        configuration.minimumTokenLifetime
    }

    public init(
        configuration: GoogleCalendarOAuthTokenRefreshConfiguration,
        httpClient: any SynchronousHTTPDataClient = URLSessionSynchronousHTTPDataClient(),
        credentialStore: GoogleCalendarOAuthCredentialStore
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.credentialStore = credentialStore
    }

    public func refreshAccessToken(
        previousMetadata: GoogleCalendarOAuthCredentialMetadata,
        now: Date = Date()
    ) throws -> GoogleCalendarOAuthCredentialMetadata {
        let normalizedClientID = configuration.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedClientID.isEmpty == false else {
            throw GoogleCalendarRuntimeError.apiFailure("Google OAuth token refresh client ID is not configured.")
        }
        guard let refreshToken = try credentialStore.refreshToken(for: previousMetadata)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            refreshToken.isEmpty == false else {
            throw GoogleCalendarRuntimeError.invalidAccessToken
        }

        let request = try makeRefreshRequest(clientID: normalizedClientID, refreshToken: refreshToken)
        let (data, response) = try httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleCalendarRuntimeError.apiFailure("Google OAuth token refresh failed with HTTP \(response.statusCode).")
        }

        let tokenResponse: GoogleCalendarOAuthTokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(GoogleCalendarOAuthTokenResponse.self, from: data)
        } catch {
            throw GoogleCalendarRuntimeError.apiFailure("Google OAuth token refresh response could not be decoded.")
        }

        let accessToken = tokenResponse.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard accessToken.isEmpty == false else {
            throw GoogleCalendarRuntimeError.invalidAccessToken
        }

        try credentialStore.saveRefreshedAccessToken(
            accessToken: accessToken,
            refreshToken: tokenResponse.refreshToken,
            grantedScopes: tokenResponse.grantedScopes(defaultScopes: previousMetadata.grantedScopes),
            expiresAt: tokenResponse.expiresIn.map { now.addingTimeInterval(TimeInterval($0)) },
            previousMetadata: previousMetadata
        )
        guard let metadata = try credentialStore.loadMetadata() else {
            throw GoogleCalendarRuntimeError.invalidAccessToken
        }
        return metadata
    }

    private func makeRefreshRequest(clientID: String, refreshToken: String) throws -> URLRequest {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = GoogleCalendarFormURLEncoder.encode([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]).data(using: .utf8)
        return request
    }
}

private enum GoogleCalendarFormURLEncoder {
    static func encode(_ values: [String: String]) -> String {
        values
            .sorted { $0.key < $1.key }
            .map { key, value in "\(key.formEncoded)=\(value.formEncoded)" }
            .joined(separator: "&")
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
            // Report refresh capability only when app composition provides the
            // refresh runtime, otherwise expired OAuth metadata would look ready
            // even though the next calendar write cannot renew its bearer token.
            hasRefreshToken: refreshTokenSupportEnabled && refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        )
    }
}

public protocol GoogleCalendarIdempotencyNamespaceStore: Sendable {
    func idempotencyNamespace() throws -> String
}

public final class SQLiteGoogleCalendarIdempotencyNamespaceStore: GoogleCalendarIdempotencyNamespaceStore, @unchecked Sendable {
    private static let settingsKey = "\(ExternalIntegrationIdentifier.googleCalendar).idempotency_namespace.v1"

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

public typealias GoogleCalendarHTTPConfiguration = SuisuiCore.GoogleCalendarHTTPConfiguration

public protocol GoogleCalendarBearerTokenProvider: Sendable {
    func bearerToken() throws -> String
}

public struct GoogleCalendarOAuthBearerTokenProvider: GoogleCalendarBearerTokenProvider {
    private let credentialStore: GoogleCalendarOAuthCredentialStore
    private let requiredScopes: Set<String>
    private let refreshService: GoogleCalendarOAuthTokenRefreshService?
    private let nowProvider: @Sendable () -> Date

    public init(
        credentialStore: GoogleCalendarOAuthCredentialStore,
        requiredScopes: Set<String> = [GoogleCalendarRuntimeOAuthScope.eventsWrite],
        refreshService: GoogleCalendarOAuthTokenRefreshService? = nil,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        self.requiredScopes = requiredScopes
        self.refreshService = refreshService
        self.nowProvider = nowProvider
    }

    public func bearerToken() throws -> String {
        var metadata = try loadMetadata()
        try validateScopes(metadata)
        if shouldRefresh(metadata) {
            guard let refreshService else {
                throw GoogleCalendarRuntimeError.invalidAccessToken
            }
            metadata = try refreshService.refreshAccessToken(previousMetadata: metadata, now: nowProvider())
            try validateScopes(metadata)
        }
        guard let accessToken = try credentialStore.accessToken(for: metadata),
              accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw GoogleCalendarRuntimeError.disconnected
        }
        return accessToken
    }

    private func loadMetadata() throws -> GoogleCalendarOAuthCredentialMetadata {
        guard let metadata = try credentialStore.loadMetadata() else {
            throw GoogleCalendarRuntimeError.disconnected
        }
        return metadata
    }

    private func validateScopes(_ metadata: GoogleCalendarOAuthCredentialMetadata) throws {
        let missingScopes = requiredScopes.subtracting(metadata.grantedScopes)
        guard missingScopes.isEmpty else {
            throw GoogleCalendarRuntimeError.missingRequiredScope(missingScopes.sorted().joined(separator: ","))
        }
    }

    private func shouldRefresh(_ metadata: GoogleCalendarOAuthCredentialMetadata) -> Bool {
        guard let expiresAt = metadata.expiresAt else {
            return false
        }
        let refreshDeadline = nowProvider().addingTimeInterval(refreshService?.minimumTokenLifetime ?? 0)
        return expiresAt <= refreshDeadline
    }
}

public typealias SynchronousHTTPDataClient = SuisuiCore.SynchronousHTTPDataClient

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

public protocol GoogleCalendarRuntimeEventsReader: Sendable {
    func listEvents(
        calendarID: String,
        timeZoneIdentifier: String,
        in interval: DateInterval
    ) throws -> [ExternalScheduleEvent]
}

public struct GoogleCalendarRuntimeCalendarListEntry: Equatable, Identifiable, Sendable {
    public var id: String
    public var summary: String
    public var accessRole: String
    public var isPrimary: Bool

    public init(
        id: String,
        summary: String,
        accessRole: String,
        isPrimary: Bool
    ) {
        self.id = id
        self.summary = summary
        self.accessRole = accessRole
        self.isPrimary = isPrimary
    }
}

public protocol GoogleCalendarRuntimeCalendarListClient: Sendable {
    func listWritableCalendars() throws -> [GoogleCalendarRuntimeCalendarListEntry]
}

public struct GoogleCalendarHTTPCalendarListClient: GoogleCalendarRuntimeCalendarListClient {
    private static let maximumCalendarListPages = 20
    private static let writableAccessRoles: Set<String> = ["owner", "writer"]

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

    public func listWritableCalendars() throws -> [GoogleCalendarRuntimeCalendarListEntry] {
        let accessToken = try tokenProvider.bearerToken()
        var pageToken: String?
        var seenPageTokens: Set<String> = []
        var loadedPageCount = 0
        var entries: [GoogleCalendarRuntimeCalendarListEntry] = []

        repeat {
            loadedPageCount += 1
            guard loadedPageCount <= Self.maximumCalendarListPages else {
                throw GoogleCalendarRuntimeError.apiFailure("Google Calendar calendarList.list exceeded the page limit.")
            }
            if let pageToken, seenPageTokens.insert(pageToken).inserted == false {
                throw GoogleCalendarRuntimeError.apiFailure("Google Calendar calendarList.list returned a repeated page token.")
            }
            let request = try makeCalendarListRequest(accessToken: accessToken, pageToken: pageToken)
            let (data, response) = try httpClient.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                throw GoogleCalendarRuntimeError.apiFailure("Google Calendar calendarList.list failed with HTTP \(response.statusCode).")
            }

            let body: GoogleCalendarCalendarListResponse
            do {
                body = try JSONDecoder().decode(GoogleCalendarCalendarListResponse.self, from: data)
            } catch {
                throw GoogleCalendarRuntimeError.apiFailure("Google Calendar calendar list response could not be decoded.")
            }
            entries.append(contentsOf: body.items.compactMap(Self.entry(from:)))
            pageToken = body.nextPageToken?.trimmingCharacters(in: .whitespacesAndNewlines)
            if pageToken?.isEmpty == true {
                pageToken = nil
            }
        } while pageToken != nil

        return entries
    }

    public func makeCalendarListRequest(accessToken: String, pageToken: String? = nil) throws -> URLRequest {
        let url = configuration.baseURL
            .appendingPathComponent("users")
            .appendingPathComponent("me")
            .appendingPathComponent("calendarList")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "minAccessRole", value: "writer"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "showHidden", value: "false")
        ]
        if let pageToken, pageToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components?.queryItems = queryItems
        guard let requestURL = components?.url else {
            throw GoogleCalendarRuntimeError.apiFailure("Google Calendar calendar list request URL could not be built.")
        }

        var request = URLRequest(url: requestURL, timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func entry(from item: GoogleCalendarCalendarListItem) -> GoogleCalendarRuntimeCalendarListEntry? {
        let id = item.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let accessRole = item.accessRole?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard id.isEmpty == false,
              writableAccessRoles.contains(accessRole) else {
            return nil
        }
        let summary = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GoogleCalendarRuntimeCalendarListEntry(
            id: id,
            summary: summary.isEmpty ? id : summary,
            accessRole: accessRole,
            isPrimary: item.primary ?? false
        )
    }
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
        if response.statusCode == 409, let idempotencyID, idempotencyID.hasPrefix("suisui") {
            // Google Calendar reports a conflict when the approved insert
            // already exists. For Suisui-generated IDs this reconstructs the
            // local link path instead of creating duplicate calendar events.
            return GoogleCalendarRuntimeEventRecord(
                calendarID: calendarID,
                timeZoneIdentifier: timeZoneIdentifier,
                event: CalendarEventRecord(id: idempotencyID, draft: draft)
            )
        }
        if response.statusCode == 429 || response.statusCode == 503 {
            throw GoogleCalendarRuntimeError.rateLimited(
                retryAfterSeconds: Self.retryAfterSeconds(from: response)
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

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        if let seconds = TimeInterval(value), seconds >= 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        if let retryDate = formatter.date(from: value) {
            return max(0, retryDate.timeIntervalSinceNow)
        }
        return nil
    }
}

public struct GoogleCalendarHTTPEventsReader: GoogleCalendarRuntimeEventsReader {
    private static let maximumPageCount = 4
    private static let maximumInterval: TimeInterval = 31 * 24 * 60 * 60

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

    public func listEvents(
        calendarID: String,
        timeZoneIdentifier: String,
        in interval: DateInterval
    ) throws -> [ExternalScheduleEvent] {
        let normalizedCalendarID = calendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCalendarID.isEmpty == false,
              normalizedCalendarID.count <= 512,
              normalizedCalendarID.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#")) == nil,
              interval.duration > 0,
              interval.duration <= Self.maximumInterval,
              TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw GoogleCalendarRuntimeError.apiFailure("Google Calendar events.list input was invalid.")
        }

        let accessToken = try tokenProvider.bearerToken()
        var events: [ExternalScheduleEvent] = []
        var pageToken: String?
        var seenPageTokens: Set<String> = []
        var pageCount = 0

        repeat {
            pageCount += 1
            guard pageCount <= Self.maximumPageCount else {
                throw GoogleCalendarRuntimeError.apiFailure("Google Calendar events.list exceeded the page limit.")
            }
            if let pageToken, seenPageTokens.insert(pageToken).inserted == false {
                throw GoogleCalendarRuntimeError.apiFailure("Google Calendar events.list returned a repeated page token.")
            }

            let request = try makeListEventsRequest(
                calendarID: normalizedCalendarID,
                timeZoneIdentifier: timeZoneIdentifier,
                interval: interval,
                accessToken: accessToken,
                pageToken: pageToken
            )
            let (data, response) = try httpClient.data(for: request)
            if response.statusCode == 429 || response.statusCode == 503 {
                throw GoogleCalendarRuntimeError.rateLimited(retryAfterSeconds: Self.retryAfterSeconds(from: response))
            }
            guard (200..<300).contains(response.statusCode) else {
                throw GoogleCalendarRuntimeError.apiFailure("Google Calendar events.list failed with HTTP \(response.statusCode).")
            }

            let body: GoogleCalendarEventsListResponse
            do {
                body = try JSONDecoder().decode(GoogleCalendarEventsListResponse.self, from: data)
            } catch {
                throw GoogleCalendarRuntimeError.apiFailure("Google Calendar events.list response could not be decoded.")
            }
            events.append(contentsOf: body.items.compactMap {
                Self.event(from: $0, timeZoneIdentifier: timeZoneIdentifier)
            })
            pageToken = body.nextPageToken?.trimmingCharacters(in: .whitespacesAndNewlines)
            if pageToken?.isEmpty == true { pageToken = nil }
        } while pageToken != nil

        return events
    }

    public func makeListEventsRequest(
        calendarID: String,
        timeZoneIdentifier: String,
        interval: DateInterval,
        accessToken: String,
        pageToken: String? = nil
    ) throws -> URLRequest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let url = configuration.baseURL
            .appendingPathComponent("calendars")
            .appendingPathComponent(calendarID)
            .appendingPathComponent("events")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: interval.start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: interval.end)),
            URLQueryItem(name: "timeZone", value: timeZoneIdentifier),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "fields", value: "nextPageToken,items(id,summary,location,status,transparency,start(date,dateTime,timeZone),end(date,dateTime,timeZone))")
        ]
        if let pageToken, pageToken.isEmpty == false {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components?.queryItems = queryItems
        guard let requestURL = components?.url else {
            throw GoogleCalendarRuntimeError.apiFailure("Google Calendar events.list URL could not be built.")
        }
        var request = URLRequest(url: requestURL, timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func event(
        from item: GoogleCalendarEventsListItem,
        timeZoneIdentifier: String
    ) -> ExternalScheduleEvent? {
        guard item.status != "cancelled",
              let id = item.id?.trimmingCharacters(in: .whitespacesAndNewlines),
              id.isEmpty == false,
              id.count <= 1_024,
              let start = eventDate(item.start, timeZoneIdentifier: timeZoneIdentifier),
              let end = eventDate(item.end, timeZoneIdentifier: timeZoneIdentifier),
              end > start else {
            return nil
        }
        let title = String((item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").prefix(512))
        let location = item.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExternalScheduleEvent(
            id: id,
            title: title.isEmpty ? String(localized: "Busy", bundle: .main) : title,
            startAt: start,
            endAt: end,
            isAllDay: item.start?.date != nil,
            blocksAvailability: item.transparency != "transparent",
            location: location.flatMap { $0.isEmpty ? nil : String($0.prefix(512)) },
            allDayStartDateKey: item.start?.date,
            allDayEndDateKey: item.end?.date
        )
    }

    private static func eventDate(
        _ value: GoogleCalendarEventsListDate?,
        timeZoneIdentifier: String
    ) -> Date? {
        if let dateTime = value?.dateTime {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: dateTime) { return date }
            if let date = ISO8601DateFormatter().date(from: dateTime) { return date }
            guard let timeZone = TimeZone(identifier: value?.timeZone ?? timeZoneIdentifier) else {
                return nil
            }
            let parts = dateTime.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count <= 2,
                  parts.count == 1 || (parts[1].isEmpty == false && parts[1].count <= 9 && parts[1].allSatisfy(\.isNumber)) else {
                return nil
            }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            guard let date = formatter.date(from: String(parts[0])) else { return nil }
            guard parts.count == 2, let fraction = Double("0.\(parts[1])") else { return date }
            return date.addingTimeInterval(fraction)
        }
        guard let dateOnly = value?.date,
              let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateOnly)
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              let seconds = TimeInterval(value),
              seconds >= 0 else {
            return nil
        }
        return seconds
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
        let record: GoogleCalendarRuntimeEventRecord
        do {
            record = try client.createEvent(draft, calendarID: calendarID, timeZoneIdentifier: timeZoneIdentifier)
        } catch GoogleCalendarRuntimeError.rateLimited(let retryAfterSeconds) {
            throw GoogleCalendarRuntimeSyncError.rateLimited(retryAfterSeconds: retryAfterSeconds)
        }
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
    public static func makeEventsReader(
        secretStore: any SecretStore,
        metadataStore: any GoogleCalendarOAuthCredentialMetadataStore,
        oauthClientID: String? = nil
    ) -> GoogleCalendarRuntimeEventsReader {
        let credentialStore = GoogleCalendarOAuthCredentialStore(
            secretStore: secretStore,
            metadataStore: metadataStore
        )
        return GoogleCalendarHTTPEventsReader(tokenProvider: GoogleCalendarOAuthBearerTokenProvider(
            credentialStore: credentialStore,
            requiredScopes: [GoogleCalendarRuntimeOAuthScope.eventsWrite],
            refreshService: makeRefreshService(credentialStore: credentialStore, oauthClientID: oauthClientID)
        ))
    }

    public static func makeEventsReader(
        secretStore: any SecretStore,
        connection: SQLiteConnection,
        oauthClientID: String? = nil
    ) -> GoogleCalendarRuntimeEventsReader {
        makeEventsReader(
            secretStore: secretStore,
            metadataStore: SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection),
            oauthClientID: oauthClientID
        )
    }

    public static func makeCalendarListClient(
        secretStore: any SecretStore,
        metadataStore: any GoogleCalendarOAuthCredentialMetadataStore,
        oauthClientID: String? = nil
    ) -> GoogleCalendarRuntimeCalendarListClient {
        let credentialStore = GoogleCalendarOAuthCredentialStore(
            secretStore: secretStore,
            metadataStore: metadataStore
        )
        return GoogleCalendarHTTPCalendarListClient(tokenProvider: GoogleCalendarOAuthBearerTokenProvider(
            credentialStore: credentialStore,
            requiredScopes: [GoogleCalendarRuntimeOAuthScope.calendarListReadOnly],
            refreshService: makeRefreshService(credentialStore: credentialStore, oauthClientID: oauthClientID)
        ))
    }

    public static func makeCalendarListClient(
        secretStore: any SecretStore,
        connection: SQLiteConnection,
        oauthClientID: String? = nil
    ) -> GoogleCalendarRuntimeCalendarListClient {
        makeCalendarListClient(
            secretStore: secretStore,
            metadataStore: SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection),
            oauthClientID: oauthClientID
        )
    }

    public static func syncStatus(
        entitlementStore: any EntitlementStore,
        secretStore: any SecretStore,
        metadataStore: any GoogleCalendarOAuthCredentialMetadataStore,
        calendarID: String = "primary",
        timeZoneIdentifier: String = TimeZone.current.identifier,
        now: Date = Date(),
        oauthClientID: String? = nil
    ) throws -> GoogleCalendarRuntimeSyncStatus {
        let credentialStore = GoogleCalendarOAuthCredentialStore(
            secretStore: secretStore,
            metadataStore: metadataStore
        )
        // Settings needs a read-only readiness check: app composition proves the write runtime
        // exists, while this path avoids constructing idempotency state or calendar write sinks.
        return try GoogleCalendarRuntimeSyncReadiness.status(
            entitlementStore: entitlementStore,
            credentialStatusStore: GoogleCalendarOAuthCredentialStatusStore(
                credentialStore: credentialStore,
                refreshTokenSupportEnabled: normalizedOAuthClientID(oauthClientID) != nil
            ),
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
        now: Date = Date(),
        oauthClientID: String? = nil
    ) throws -> GoogleCalendarRuntimeSyncStatus {
        try syncStatus(
            entitlementStore: entitlementStore,
            secretStore: secretStore,
            metadataStore: SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection),
            calendarID: calendarID,
            timeZoneIdentifier: timeZoneIdentifier,
            now: now,
            oauthClientID: oauthClientID
        )
    }

    public static func disconnectOAuthCredential(
        secretStore: any SecretStore,
        connection: SQLiteConnection
    ) throws {
        let credentialStore = GoogleCalendarOAuthCredentialStore(
            secretStore: secretStore,
            metadataStore: SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        )
        // Disconnect is user-controlled credential revocation. Delete Keychain
        // secrets and SQLite metadata together so readiness cannot keep stale
        // token references after the user explicitly disconnects Google.
        try credentialStore.deleteCredential()
    }

    public static func makeSyncController(
        entitlementStore: any EntitlementStore,
        store: any ProjectBoardStore,
        linkStore: any ExternalTaskLinkStore,
        secretStore: any SecretStore,
        metadataStore: any GoogleCalendarOAuthCredentialMetadataStore,
        idempotencyNamespaceStore: any GoogleCalendarIdempotencyNamespaceStore,
        calendarID: String = "primary",
        timeZoneIdentifier: String = TimeZone.current.identifier,
        oauthClientID: String? = nil
    ) throws -> GoogleCalendarRuntimeSyncController {
        let credentialStore = GoogleCalendarOAuthCredentialStore(
            secretStore: secretStore,
            metadataStore: metadataStore
        )
        let eventSink = GoogleCalendarHTTPEventSink(client: GoogleCalendarHTTPEventClient(
            tokenProvider: GoogleCalendarOAuthBearerTokenProvider(
                credentialStore: credentialStore,
                refreshService: makeRefreshService(credentialStore: credentialStore, oauthClientID: oauthClientID)
            )
        ))
        return GoogleCalendarRuntimeSyncController(
            entitlementStore: entitlementStore,
            credentialStatusStore: GoogleCalendarOAuthCredentialStatusStore(
                credentialStore: credentialStore,
                refreshTokenSupportEnabled: normalizedOAuthClientID(oauthClientID) != nil
            ),
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
        timeZoneIdentifier: String = TimeZone.current.identifier,
        oauthClientID: String? = nil
    ) throws -> GoogleCalendarRuntimeSyncController {
        try makeSyncController(
            entitlementStore: entitlementStore,
            store: store,
            linkStore: linkStore,
            secretStore: secretStore,
            metadataStore: SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection),
            idempotencyNamespaceStore: idempotencyNamespaceStore,
            calendarID: calendarID,
            timeZoneIdentifier: timeZoneIdentifier,
            oauthClientID: oauthClientID
        )
    }

    private static func makeRefreshService(
        credentialStore: GoogleCalendarOAuthCredentialStore,
        oauthClientID: String?
    ) -> GoogleCalendarOAuthTokenRefreshService? {
        guard let oauthClientID = normalizedOAuthClientID(oauthClientID) else {
            return nil
        }
        return GoogleCalendarOAuthTokenRefreshService(
            configuration: GoogleCalendarOAuthTokenRefreshConfiguration(clientID: oauthClientID),
            credentialStore: credentialStore
        )
    }

    private static func normalizedOAuthClientID(_ oauthClientID: String?) -> String? {
        guard let value = oauthClientID?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        return value
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

private struct GoogleCalendarCalendarListResponse: Decodable {
    var nextPageToken: String?
    var items: [GoogleCalendarCalendarListItem]

    enum CodingKeys: String, CodingKey {
        case nextPageToken
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
        items = try container.decodeIfPresent([GoogleCalendarCalendarListItem].self, forKey: .items) ?? []
    }
}

private struct GoogleCalendarCalendarListItem: Decodable {
    var id: String?
    var summary: String?
    var primary: Bool?
    var accessRole: String?
}

private struct GoogleCalendarEventsListResponse: Decodable {
    var nextPageToken: String?
    var items: [GoogleCalendarEventsListItem]

    enum CodingKeys: String, CodingKey {
        case nextPageToken
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
        items = try container.decodeIfPresent([GoogleCalendarEventsListItem].self, forKey: .items) ?? []
    }
}

private struct GoogleCalendarEventsListItem: Decodable {
    var id: String?
    var summary: String?
    var location: String?
    var status: String?
    var transparency: String?
    var start: GoogleCalendarEventsListDate?
    var end: GoogleCalendarEventsListDate?
}

private struct GoogleCalendarEventsListDate: Decodable {
    var date: String?
    var dateTime: String?
    var timeZone: String?
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

private struct GoogleCalendarOAuthTokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int?
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }

    func grantedScopes(defaultScopes: Set<String>) -> Set<String> {
        guard let scope,
              scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return defaultScopes
        }
        return Set(
            scope
                .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                .map(String.init)
        )
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._*")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
