import XCTest
@testable import SoloPMCore

final class SyncEntitlementTests: XCTestCase {
    func testSubscriptionPlansGatePaidFeatures() {
        XCTAssertFalse(SubscriptionPlan.free.allows(.externalSync))
        XCTAssertFalse(SubscriptionPlan.free.allows(.advancedMCPExecution))
        XCTAssertFalse(SubscriptionPlan.free.allows(.providerPresets))
        XCTAssertTrue(SubscriptionPlan.pro.allows(.externalSync))
        XCTAssertTrue(SubscriptionPlan.pro.allows(.advancedMCPExecution))
        XCTAssertTrue(SubscriptionPlan.founder.allows(.providerPresets))
    }

    func testKeychainEntitlementStoreDefaultsToFreeWhenNoLicenseIsConfigured() throws {
        let store = KeychainEntitlementStore(secretStore: InMemorySecretStore())

        let snapshot = try store.snapshot()

        XCTAssertEqual(snapshot.plan, .free)
        XCTAssertEqual(snapshot.source, .defaultFree)
    }

    func testKeychainEntitlementStoreDoesNotTreatRawPlanStringAsPaidLicense() throws {
        let store = KeychainEntitlementStore(
            secretStore: InMemorySecretStore(values: [.subscriptionLicense: "pro"])
        )

        let snapshot = try store.snapshot()

        XCTAssertEqual(snapshot.plan, .free)
        XCTAssertEqual(snapshot.source, .invalidLocalLicense)
    }

    func testEntitlementCheckerStopsFreeFeatureBeforeWorkStarts() throws {
        let checker = EntitlementChecker(store: StaticEntitlementStore(plan: .free))

        XCTAssertThrowsError(try checker.require(.externalSync)) { error in
            XCTAssertEqual(error as? EntitlementError, .upgradeRequired(feature: .externalSync, requiredPlan: .pro))
        }
    }

    func testSyncServiceFreeStartFailsBeforeNetworkClientIsReached() throws {
        let networkClient = RecordingSyncNetworkClient()
        let service = SyncService(
            entitlementStore: StaticEntitlementStore(plan: .free),
            configuration: SyncConfiguration(backendEndpoint: URL(string: "https://sync.solopm.example/v1")),
            networkClient: networkClient
        )

        XCTAssertThrowsError(try service.startSync()) { error in
            XCTAssertEqual(error as? SyncServiceError, .upgradeRequired(requiredPlan: .pro))
        }
        XCTAssertEqual(networkClient.startCallCount, 0)
        XCTAssertEqual(try service.status().state, .upgradeRequired)
    }

    func testSyncServiceProWithoutBackendDoesNotReturnMockSuccess() throws {
        let networkClient = RecordingSyncNetworkClient()
        let service = SyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            configuration: .notConfigured,
            networkClient: networkClient
        )

        XCTAssertThrowsError(try service.startSync()) { error in
            XCTAssertEqual(error as? SyncServiceError, .syncBackendNotConfigured)
        }
        XCTAssertEqual(networkClient.startCallCount, 0)
        XCTAssertEqual(try service.status().state, .backendNotConfigured)
    }

    func testSyncServiceConfiguredBackendRecordsNetworkFailureInsteadOfReturningReady() throws {
        let networkClient = RecordingSyncNetworkClient(error: SyncServiceError.networkUnavailable)
        let service = SyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            configuration: SyncConfiguration(backendEndpoint: URL(string: "https://sync.solopm.example/v1")),
            networkClient: networkClient
        )

        XCTAssertThrowsError(try service.startSync()) { error in
            XCTAssertEqual(error as? SyncServiceError, .networkUnavailable)
        }

        let status = try service.status()
        XCTAssertEqual(status.state, .failed)
        XCTAssertNotNil(status.lastAttemptAt)
        XCTAssertEqual(networkClient.startCallCount, 1)
    }

    func testSyncServiceDryRunDefinesLocalDataClassesWithoutExternalSaaS() throws {
        let service = SyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            configuration: .notConfigured,
            networkClient: RecordingSyncNetworkClient()
        )

        XCTAssertEqual(try service.exportDryRun().includedData, [.projects, .tasks, .settings])
    }

    @MainActor
    func testSyncSettingsViewModelShowsUpgradeGateWithoutStartingNetwork() {
        let networkClient = RecordingSyncNetworkClient()
        let viewModel = SyncSettingsViewModel(
            service: SyncService(
                entitlementStore: StaticEntitlementStore(plan: .free),
                configuration: SyncConfiguration(backendEndpoint: URL(string: "https://sync.solopm.example/v1")),
                networkClient: networkClient
            )
        )

        XCTAssertEqual(viewModel.planLabel, "Free")
        XCTAssertEqual(viewModel.statusLabel, "Upgrade required")
        XCTAssertEqual(viewModel.dataIncludedLabel, "Projects, Tasks, Settings")
        XCTAssertFalse(viewModel.canEnableSync)
        XCTAssertEqual(viewModel.syncUnavailableLabel, "Upgrade required")

        viewModel.startSync()

        XCTAssertEqual(viewModel.errorMessage, "Upgrade to Pro to sync SoloPM data.")
        XCTAssertEqual(networkClient.startCallCount, 0)
    }

    @MainActor
    func testSyncSettingsViewModelShowsBackendNotConfiguredForPro() {
        let viewModel = SyncSettingsViewModel(
            service: SyncService(
                entitlementStore: StaticEntitlementStore(plan: .pro),
                configuration: .notConfigured,
                networkClient: RecordingSyncNetworkClient()
            )
        )

        XCTAssertEqual(viewModel.planLabel, "Pro")
        XCTAssertEqual(viewModel.statusLabel, "Sync backend is not configured")
        XCTAssertFalse(viewModel.canEnableSync)
        XCTAssertEqual(viewModel.syncUnavailableLabel, "Sync backend is not configured")

        viewModel.startSync()

        XCTAssertEqual(viewModel.errorMessage, "Sync backend is not configured.")
    }

    @MainActor
    func testSyncSettingsViewModelAllowsProToggleOnlyWhenBackendIsConfigured() {
        let networkClient = RecordingSyncNetworkClient()
        let viewModel = SyncSettingsViewModel(
            service: SyncService(
                entitlementStore: StaticEntitlementStore(plan: .pro),
                configuration: SyncConfiguration(backendEndpoint: URL(string: "https://sync.solopm.example/v1")),
                networkClient: networkClient
            )
        )

        XCTAssertEqual(viewModel.planLabel, "Pro")
        XCTAssertEqual(viewModel.statusLabel, "Ready")
        XCTAssertTrue(viewModel.canEnableSync)
        XCTAssertNil(viewModel.syncUnavailableLabel)

        viewModel.setSyncEnabled(true)

        XCTAssertTrue(viewModel.isSyncEnabled)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(networkClient.startCallCount, 1)
    }

    @MainActor
    func testSyncSettingsViewModelShowsFailedStateAfterNetworkFailure() {
        let networkClient = RecordingSyncNetworkClient(error: SyncServiceError.networkUnavailable)
        let viewModel = SyncSettingsViewModel(
            service: SyncService(
                entitlementStore: StaticEntitlementStore(plan: .pro),
                configuration: SyncConfiguration(backendEndpoint: URL(string: "https://sync.solopm.example/v1")),
                networkClient: networkClient
            )
        )

        XCTAssertEqual(viewModel.statusLabel, "Ready")
        XCTAssertTrue(viewModel.canEnableSync)

        viewModel.setSyncEnabled(true)

        XCTAssertFalse(viewModel.isSyncEnabled)
        XCTAssertEqual(viewModel.statusLabel, "Failed")
        XCTAssertEqual(viewModel.errorMessage, "Sync network client is unavailable in this build.")
        XCTAssertTrue(viewModel.canEnableSync)
        XCTAssertNil(viewModel.syncUnavailableLabel)
        XCTAssertEqual(networkClient.startCallCount, 1)
    }
}

private struct StaticEntitlementStore: EntitlementStore {
    var plan: SubscriptionPlan

    func snapshot() throws -> EntitlementSnapshot {
        EntitlementSnapshot(plan: plan, source: .localLicense)
    }
}

private final class RecordingSyncNetworkClient: SyncNetworkClient, @unchecked Sendable {
    private(set) var startCallCount = 0
    var error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func startSync(endpoint: URL, payload: SyncStartPayload) throws -> SyncStartResult {
        startCallCount += 1
        if let error {
            throw error
        }
        return SyncStartResult(startedAt: Date(timeIntervalSince1970: 1))
    }
}
