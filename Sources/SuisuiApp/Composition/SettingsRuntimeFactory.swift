import Foundation
import SuisuiCore

extension AppRuntimeFactory {
    @MainActor
    static func makeAppSettingsViewModel(refreshProviderSecretStatusesOnInit: Bool = true) -> AppSettingsViewModel {
        AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(),
            secretStore: makeSecretStore(),
            ollamaHealthChecker: URLSessionOllamaEndpointHealthChecker(),
            appleSpeechReadinessProvider: {
                AppleSpeechReadinessSnapshotReader.snapshot()
            },
            systemSpeechReadinessProvider: {
                SystemSpeechReadinessSnapshotReader.snapshot()
            },
            refreshProviderSecretStatusesOnInit: refreshProviderSecretStatusesOnInit
        )
    }

    static func loadTaskAutoExecutionSettings() -> TaskAutoExecutionSettings {
        // Fallback AppKit windows are created outside the SwiftUI App state,
        // so they read only the persisted non-secret automation settings here.
        // Provider secrets stay in Keychain and are never materialized for this UI decision.
        (try? UserDefaultsAppSettingsStore().load().normalizedForRuntime.taskAutoExecution) ?? .default
    }

    static func loadRuntimeAppSettings() -> AppSettings {
        // Fallback AppKit windows are created outside the SwiftUI App state, so
        // they reload persisted non-secret settings for notification and time
        // zone decisions without touching Keychain-backed provider secrets.
        (try? UserDefaultsAppSettingsStore().load().normalizedForRuntime) ?? .default
    }

    @MainActor
    static func makeTodayWeatherModel() -> TodayWeatherModel {
        TodayWeatherRuntime.subscription.model
    }

    @MainActor
    static func requestTodayWeatherLocationAuthorization() {
#if canImport(WeatherKit) && canImport(CoreLocation)
        TodayWeatherRuntime.subscription.requestAuthorization?()
#endif
    }

    @MainActor
    static func observeTodayWeatherSettingsChanges(
        for model: TodayWeatherModel,
        notificationCenter: NotificationCenter = .default
    ) -> NSObjectProtocol {
        notificationCenter.addObserver(
            forName: .suisuiWeatherLocationDidChange,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            Task { @MainActor [weak model] in
                await model?.refresh()
            }
        }
    }

    @MainActor
    private enum TodayWeatherRuntime {
        static let subscription: (model: TodayWeatherModel, observer: NSObjectProtocol, requestAuthorization: (@MainActor () -> Void)?) = {
#if canImport(WeatherKit) && canImport(CoreLocation)
            let weatherProvider: any TodayWeatherProviding = WeatherKitTodayProvider()
            let locationProvider = CoreLocationTodayProvider()
            let requestAuthorization: (@MainActor () -> Void)? = { locationProvider.requestAuthorization() }
#else
            let weatherProvider: any TodayWeatherProviding = UnavailableTodayWeatherProvider()
            let locationProvider: UnavailableTodayLocationProvider? = nil
            let requestAuthorization: (@MainActor () -> Void)? = nil
#endif
            let model = TodayWeatherModel(
                preferenceProvider: { loadRuntimeAppSettings().weatherLocationPreference },
                weatherProvider: weatherProvider,
                locationProvider: locationProvider
            )
            return (
                model,
                observeTodayWeatherSettingsChanges(for: model),
                requestAuthorization
            )
        }()
    }

    @MainActor
    static func makeLaunchAtLoginSettingsViewModel() -> LaunchAtLoginSettingsViewModel {
        LaunchAtLoginSettingsViewModel(client: SMAppServiceLaunchAtLoginClient())
    }

    @MainActor
    static func makeSyncSettingsViewModel() -> SyncSettingsViewModel {
        let secretStore = makeSecretStore()
        return SyncSettingsViewModel(
            service: SyncService(
                entitlementStore: makeEntitlementStore(secretStore: secretStore),
                configuration: .notConfigured,
                networkClient: UnavailableSyncNetworkClient()
            )
        )
    }

    static func makeIntegrationPermissionSnapshot() -> PermissionSnapshot {
        // The microphone reader must run after EventKit/Notification readers so
        // it never clobbers their statuses; AVFoundation cannot appear in Core
        // because the import-boundary test forbids it there.
        AVFoundationMicrophonePermissionSnapshotReader.snapshot(
            base: EventKitPermissionSnapshotReader.snapshot(
                base: UserNotificationsPermissionSnapshotReader.snapshot()
            )
        )
    }

    /// `Sendable` wrapper that lets SwiftUI views call the snapshot factory
    /// from a detached background queue. The underlying factory only reads
    /// AVFoundation / EventKit / UserNotifications status, all of which are
    /// safe to call from any thread.
    static let makeIntegrationPermissionSnapshotSendable: @Sendable () -> PermissionSnapshot = {
        makeIntegrationPermissionSnapshot()
    }

    static func makeWatcherDiagnosticsSnapshot() -> WatcherDiagnosticsSnapshot {
        let permissionSnapshot = UserNotificationsPermissionSnapshotReader.snapshot()
        do {
            let connection = try migratedConnection()
            let settings = loadRuntimeSettings().settings
            return try WatcherDiagnosticsProvider(
                stateStore: SQLiteDailyCheckStateStore(connection: connection),
                permissionSnapshot: permissionSnapshot,
                settings: settings
            ).snapshot()
        } catch {
            return WatcherDiagnosticsSnapshot(
                notificationPermissionStatus: permissionSnapshot.status(for: .notifications),
                errorMessage: "Watcher diagnostics are unavailable because local state could not be opened."
            )
        }
    }

    @MainActor
    static func makeExternalMCPSettingsViewModel() -> ExternalMCPSettingsViewModel {
        let secretStore = makeSecretStore()
        let launcher = MCPStdioServerLauncher(
            environmentResolver: SecretStoreMCPEnvironmentResolver(secretStore: secretStore)
        )
        let store: any MCPServerRegistrationStore
        do {
            store = SQLiteMCPServerRegistrationStore(connection: try migratedConnection())
        } catch {
            store = UnavailableMCPServerRegistrationStore(error: error)
        }
        let auditLoadResult = externalMCPAuditLoadResult()

        return ExternalMCPSettingsViewModel(
            store: store,
            launcher: launcher,
            auditRows: auditLoadResult.rows,
            auditErrorMessage: auditLoadResult.errorMessage
        )
    }

    private static func externalMCPAuditLoadResult() -> ExternalMCPAuditLoadResult {
        do {
            let logger = try SQLiteAuditLogger(path: applicationDatabaseURL().path)
            return ExternalMCPAuditLoadResult(rows: try ExternalMCPAuditHistory.rows(from: logger.list(limit: 50)))
        } catch {
            return ExternalMCPAuditLoadResult(
                rows: [],
                errorMessage: "MCP audit history is unavailable because audit logging could not be opened."
            )
        }
    }
}

private struct ExternalMCPAuditLoadResult {
    let rows: [ExternalMCPAuditHistoryRow]
    let errorMessage: String?

    init(rows: [ExternalMCPAuditHistoryRow], errorMessage: String? = nil) {
        self.rows = rows
        self.errorMessage = errorMessage
    }
}

private struct UnavailableMCPServerRegistrationStore: MCPServerRegistrationStore {
    let error: Error

    func loadRegistrations() throws -> [MCPServerRegistration] {
        throw error
    }

    func saveRegistrations(_ registrations: [MCPServerRegistration]) throws {
        throw error
    }
}
