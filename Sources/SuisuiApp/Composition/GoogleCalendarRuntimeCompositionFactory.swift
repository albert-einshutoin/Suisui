import Foundation
import SuisuiCore
import SuisuiGoogleCalendarRuntime
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(AppKit)
import AppKit
#endif

extension AppRuntimeFactory {
    private static let googleCalendarOAuthRedirectURI = URL(string: "suisui://oauth/google-calendar")!

    static func isGoogleCalendarRuntimeEnabled(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let rawPolicy = (bundle.object(forInfoDictionaryKey: "SuisuiRuntimePolicy") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildPolicy = rawPolicy.flatMap(GoogleCalendarRuntimeBuildPolicy.init(rawValue:))
            ?? .publicAlpha
        return GoogleCalendarRuntimeAvailabilityPolicy.isEnabled(
            buildPolicy: buildPolicy,
            environmentOptIn: environment["SUISUI_ENABLE_EXPERIMENTAL_GOOGLE_CALENDAR_RUNTIME"] == "1"
        )
    }

    static func makeGoogleCalendarRuntimeSyncStatus() -> GoogleCalendarRuntimeSyncStatus {
        guard isGoogleCalendarRuntimeEnabled() else {
            return .runtimeNotConfigured
        }
        do {
            let connection = try migratedConnection()
            return makeGoogleCalendarRuntimeSyncStatus(connection: connection)
        } catch {
            return GoogleCalendarRuntimeSyncStatus(
                plan: .free,
                state: .failed(message: UserFacingErrorMessageSanitizer.message(
                    from: error,
                    fallback: "Google Calendar sync status is unavailable."
                ))
            )
        }
    }

    static func makeGoogleCalendarRuntimeSyncStatus(connection: SQLiteConnection) -> GoogleCalendarRuntimeSyncStatus {
        guard isGoogleCalendarRuntimeEnabled() else {
            return .runtimeNotConfigured
        }
        do {
            let secretStore = makeSecretStore()
            let runtimeSettings = loadRuntimeAppSettings()
            return try GoogleCalendarAppRuntimeFactory.syncStatus(
                entitlementStore: makeEntitlementStore(secretStore: secretStore),
                secretStore: secretStore,
                connection: connection,
                calendarID: runtimeSettings.googleCalendarID,
                timeZoneIdentifier: runtimeSettings.timeZoneIdentifier,
                oauthClientID: googleCalendarOAuthClientID()
            )
        } catch {
            return GoogleCalendarRuntimeSyncStatus(
                plan: .free,
                state: .failed(message: UserFacingErrorMessageSanitizer.message(
                    from: error,
                    fallback: "Google Calendar sync status is unavailable."
                ))
            )
        }
    }

    @MainActor
    static func makeGoogleCalendarOAuthConnector() -> (any GoogleCalendarOAuthConnecting)? {
        guard isGoogleCalendarRuntimeEnabled() else {
            return nil
        }
#if canImport(AuthenticationServices) && canImport(AppKit)
        return GoogleCalendarOAuthAuthenticationSessionController(
            callbackURLScheme: googleCalendarOAuthRedirectURI.scheme,
            serviceFactory: {
                try makeGoogleCalendarOAuthAuthorizationService()
            }
        )
#else
        nil
#endif
    }

    @MainActor
    static func makeGoogleCalendarOAuthDisconnecter() -> (any GoogleCalendarOAuthDisconnecting)? {
        guard isGoogleCalendarRuntimeEnabled() else {
            return nil
        }
        return GoogleCalendarOAuthCredentialDisconnectController {
            try GoogleCalendarAppRuntimeFactory.disconnectOAuthCredential(
                secretStore: makeSecretStore(),
                connection: migratedConnection()
            )
        }
    }

    static func makeGoogleCalendarListProvider() -> (any GoogleCalendarListProviding)? {
        guard isGoogleCalendarRuntimeEnabled() else {
            return nil
        }
        do {
            let secretStore = makeSecretStore()
            let client = try GoogleCalendarAppRuntimeFactory.makeCalendarListClient(
                secretStore: secretStore,
                connection: migratedConnection(),
                oauthClientID: googleCalendarOAuthClientID()
            )
            return GoogleCalendarRuntimeCalendarListProvider(client: client)
        } catch {
            return nil
        }
    }

    static func makeGoogleCalendarScheduleEventSource(
        connection: SQLiteConnection
    ) -> (any ExternalScheduleEventSource)? {
        guard isGoogleCalendarRuntimeEnabled() else { return nil }
        let reader = GoogleCalendarAppRuntimeFactory.makeEventsReader(
            secretStore: makeSecretStore(),
            connection: connection,
            oauthClientID: googleCalendarOAuthClientID()
        )
        return SettingsBackedGoogleCalendarScheduleEventSource(
            settingsStore: UserDefaultsAppSettingsStore(),
            reader: reader
        )
    }

    static func makeSettingsBackedGoogleCalendarSyncController(
        connection: SQLiteConnection,
        entitlementStore: any EntitlementStore,
        store: any ProjectBoardStore,
        linkStore: any ExternalTaskLinkStore,
        secretStore: any SecretStore
    ) -> any GoogleCalendarRuntimeSyncing {
        guard isGoogleCalendarRuntimeEnabled() else {
            return DisabledGoogleCalendarRuntimeSync()
        }
        return SettingsBackedGoogleCalendarRuntimeSync(
            settingsStore: UserDefaultsAppSettingsStore(),
            statusFactory: { settings, now in
                try GoogleCalendarAppRuntimeFactory.syncStatus(
                    entitlementStore: entitlementStore,
                    secretStore: secretStore,
                    connection: connection,
                    calendarID: settings.googleCalendarID,
                    timeZoneIdentifier: settings.timeZoneIdentifier,
                    now: now,
                    oauthClientID: googleCalendarOAuthClientID()
                )
            },
            syncFactory: { settings in
                try makeGoogleCalendarSyncController(
                    connection: connection,
                    entitlementStore: entitlementStore,
                    store: store,
                    linkStore: linkStore,
                    secretStore: secretStore,
                    calendarID: settings.googleCalendarID,
                    timeZoneIdentifier: settings.timeZoneIdentifier
                )
            }
        )
    }

    private static func makeGoogleCalendarSyncController(
        connection: SQLiteConnection,
        entitlementStore: any EntitlementStore,
        store: any ProjectBoardStore,
        linkStore: any ExternalTaskLinkStore,
        secretStore: any SecretStore,
        calendarID: String,
        timeZoneIdentifier: String
    ) throws -> GoogleCalendarRuntimeSyncController {
        try GoogleCalendarAppRuntimeFactory.makeSyncController(
            entitlementStore: entitlementStore,
            store: store,
            linkStore: linkStore,
            secretStore: secretStore,
            connection: connection,
            idempotencyNamespaceStore: SQLiteGoogleCalendarIdempotencyNamespaceStore(connection: connection),
            calendarID: calendarID,
            timeZoneIdentifier: timeZoneIdentifier,
            oauthClientID: googleCalendarOAuthClientID()
        )
    }

    private static func makeGoogleCalendarOAuthAuthorizationService() throws -> GoogleCalendarOAuthAuthorizationService {
        guard isGoogleCalendarRuntimeEnabled() else {
            throw GoogleCalendarOAuthConnectionError.runtimeDisabled
        }
        let connection = try migratedConnection()
        let secretStore = makeSecretStore()
        let credentialStore = GoogleCalendarOAuthCredentialStore(
            secretStore: secretStore,
            metadataStore: SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        )
        return GoogleCalendarOAuthAuthorizationService(
            configuration: GoogleCalendarOAuthAuthorizationConfiguration(
                clientID: googleCalendarOAuthClientID() ?? "",
                redirectURI: googleCalendarOAuthRedirectURI.absoluteString
            ),
            httpClient: URLSessionSynchronousHTTPDataClient(),
            credentialStore: credentialStore
        )
    }

    static func googleCalendarOAuthClientID() -> String? {
        for key in ["SUISUI_GOOGLE_CALENDAR_OAUTH_CLIENT_ID", "GOOGLE_CALENDAR_OAUTH_CLIENT_ID"] {
            if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               value.isEmpty == false {
                return value
            }
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "SuisuiGoogleCalendarOAuthClientID") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}

@MainActor
protocol GoogleCalendarOAuthConnecting: AnyObject {
    func startAuthorization(
        completion: @escaping @MainActor (Result<GoogleCalendarOAuthCredentialMetadata, Error>) -> Void
    )
}

@MainActor
protocol GoogleCalendarOAuthDisconnecting: AnyObject {
    func disconnect() throws
}

protocol GoogleCalendarListProviding: Sendable {
    func listWritableCalendars() throws -> [GoogleCalendarRuntimeCalendarListEntry]
}

@MainActor
private final class GoogleCalendarOAuthCredentialDisconnectController: GoogleCalendarOAuthDisconnecting {
    private let disconnectAction: () throws -> Void

    init(disconnectAction: @escaping () throws -> Void) {
        self.disconnectAction = disconnectAction
    }

    func disconnect() throws {
        try disconnectAction()
    }
}

private struct GoogleCalendarRuntimeCalendarListProvider: GoogleCalendarListProviding {
    let client: any GoogleCalendarRuntimeCalendarListClient

    func listWritableCalendars() throws -> [GoogleCalendarRuntimeCalendarListEntry] {
        try client.listWritableCalendars()
    }
}

private struct SettingsBackedGoogleCalendarScheduleEventSource: ExternalScheduleEventSource {
    let settingsStore: any AppSettingsStore
    let reader: any GoogleCalendarRuntimeEventsReader

    func listEvents(in interval: DateInterval) throws -> [ExternalScheduleEvent] {
        let settings = try settingsStore.load()
        return try reader.listEvents(
            calendarID: settings.googleCalendarID,
            timeZoneIdentifier: settings.timeZoneIdentifier,
            in: interval
        )
    }
}

private enum GoogleCalendarOAuthConnectionError: LocalizedError, Equatable {
    case runtimeDisabled
    case authorizationCancelled
    case callbackURLMissing
    case sessionDidNotStart

    var errorDescription: String? {
        switch self {
        case .runtimeDisabled:
            return "Google Calendar OAuth is disabled by this build policy."
        case .authorizationCancelled:
            return "Google Calendar OAuth authorization was cancelled."
        case .callbackURLMissing:
            return "Google Calendar OAuth authorization did not return a callback URL."
        case .sessionDidNotStart:
            return "Google Calendar OAuth authorization could not start."
        }
    }
}

private struct DisabledGoogleCalendarRuntimeSync: GoogleCalendarRuntimeSyncing {
    func status(now: Date) throws -> GoogleCalendarRuntimeSyncStatus {
        .runtimeNotConfigured
    }

    func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        throw GoogleCalendarRuntimeSyncError.notReady(.runtimeNotConfigured)
    }
}

#if canImport(AuthenticationServices) && canImport(AppKit)
@MainActor
private final class GoogleCalendarOAuthAuthenticationSessionController: NSObject, GoogleCalendarOAuthConnecting, ASWebAuthenticationPresentationContextProviding {
    private let callbackURLScheme: String?
    private let serviceFactory: () throws -> GoogleCalendarOAuthAuthorizationService
    private var activeSession: ASWebAuthenticationSession?

    init(
        callbackURLScheme: String?,
        serviceFactory: @escaping () throws -> GoogleCalendarOAuthAuthorizationService
    ) {
        self.callbackURLScheme = callbackURLScheme
        self.serviceFactory = serviceFactory
    }

    func startAuthorization(
        completion: @escaping @MainActor (Result<GoogleCalendarOAuthCredentialMetadata, Error>) -> Void
    ) {
        do {
            let service = try serviceFactory()
            let request = try service.makeAuthorizationRequest()
            let session = ASWebAuthenticationSession(
                url: request.authorizationURL,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                if let error {
                    Task { @MainActor in
                        self?.activeSession = nil
                        if Self.isCancellation(error) {
                            completion(.failure(GoogleCalendarOAuthConnectionError.authorizationCancelled))
                        } else {
                            completion(.failure(error))
                        }
                    }
                    return
                }
                guard let callbackURL else {
                    Task { @MainActor in
                        self?.activeSession = nil
                        completion(.failure(GoogleCalendarOAuthConnectionError.callbackURLMissing))
                    }
                    return
                }

                // The runtime token exchange writes secrets through SecretStore immediately after
                // Google returns the callback, so Settings never receives raw token material.
                let result = Result {
                    try service.completeAuthorization(callbackURL: callbackURL, pendingRequest: request)
                }
                Task { @MainActor in
                    self?.activeSession = nil
                    completion(result)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            guard session.start() else {
                activeSession = nil
                completion(.failure(GoogleCalendarOAuthConnectionError.sessionDidNotStart))
                return
            }
        } catch {
            activeSession = nil
            completion(.failure(error))
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASWebAuthenticationSessionError.errorDomain
            && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }
}
#endif
