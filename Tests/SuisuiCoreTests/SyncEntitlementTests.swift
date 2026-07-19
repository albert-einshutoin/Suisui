import Foundation
import CryptoKit
import XCTest
@testable import SuisuiCore

final class SyncEntitlementTests: XCTestCase {
    func testSubscriptionPlansGatePaidFeatures() {
        XCTAssertFalse(SubscriptionPlan.free.allows(.externalSync))
        XCTAssertFalse(SubscriptionPlan.free.allows(.advancedMCPExecution))
        XCTAssertFalse(SubscriptionPlan.free.allows(.providerPresets))
        XCTAssertTrue(SubscriptionPlan.sync.allows(.externalSync))
        XCTAssertFalse(SubscriptionPlan.sync.allows(.advancedMCPExecution))
        XCTAssertFalse(SubscriptionPlan.sync.allows(.cloudRelay))
        XCTAssertFalse(SubscriptionPlan.sync.allows(.hostedMCPEndpoint))
        XCTAssertFalse(SubscriptionPlan.sync.allows(.documentScopedAutomation))
        XCTAssertFalse(SubscriptionPlan.sync.allows(.harnessHistory))
        XCTAssertFalse(SubscriptionPlan.sync.allows(.externalConnectorWrite))
        XCTAssertTrue(SubscriptionPlan.pro.allows(.externalSync))
        XCTAssertTrue(SubscriptionPlan.pro.allows(.advancedMCPExecution))
        XCTAssertTrue(SubscriptionPlan.pro.allows(.cloudRelay))
        XCTAssertTrue(SubscriptionPlan.pro.allows(.hostedMCPEndpoint))
        XCTAssertTrue(SubscriptionPlan.pro.allows(.documentScopedAutomation))
        XCTAssertTrue(SubscriptionPlan.pro.allows(.harnessHistory))
        XCTAssertTrue(SubscriptionPlan.pro.allows(.externalConnectorWrite))
        XCTAssertTrue(SubscriptionPlan.founder.allows(.providerPresets))
    }

    func testFeatureGateRequiredPlansMatchPricingPackaging() {
        XCTAssertEqual(FeatureGate.externalSync.requiredPlan, .sync)
        XCTAssertEqual(FeatureGate.advancedMCPExecution.requiredPlan, .pro)
        XCTAssertEqual(FeatureGate.cloudRelay.requiredPlan, .pro)
        XCTAssertEqual(FeatureGate.hostedMCPEndpoint.requiredPlan, .pro)
        XCTAssertEqual(FeatureGate.documentScopedAutomation.requiredPlan, .pro)
        XCTAssertEqual(FeatureGate.harnessHistory.requiredPlan, .pro)
        XCTAssertEqual(FeatureGate.externalConnectorWrite.requiredPlan, .pro)
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

    func testKeychainEntitlementStoreAcceptsSignedFounderLocalLicense() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let license = signedLocalLicense(
            id: "founder-local-001",
            plan: .founder,
            signingKey: signingKey
        )
        let store = KeychainEntitlementStore(
            secretStore: InMemorySecretStore(values: [.subscriptionLicense: license]),
            verifier: SignedLocalLicenseVerifier(publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString())
        )

        let snapshot = try store.snapshot()

        XCTAssertEqual(snapshot.plan, .founder)
        XCTAssertEqual(snapshot.source, .localLicense)
    }

    func testKeychainEntitlementStoreMapsSignedPersonalPlusLocalLicenseToPro() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let license = signedLocalLicense(
            id: "personal-plus-001",
            plan: .personalPlus,
            signingKey: signingKey
        )
        let store = KeychainEntitlementStore(
            secretStore: InMemorySecretStore(values: [.subscriptionLicense: license]),
            verifier: SignedLocalLicenseVerifier(publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString())
        )

        let snapshot = try store.snapshot()

        XCTAssertEqual(snapshot.plan, .pro)
        XCTAssertEqual(snapshot.source, .localLicense)
    }

    func testKeychainEntitlementStoreRejectsTamperedSignedLocalLicense() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let license = signedLocalLicense(
            id: "founder-local-001",
            plan: .founder,
            signingKey: signingKey
        ).replacingOccurrences(of: "\"plan\":\"founder\"", with: "\"plan\":\"personalPlus\"")
        let store = KeychainEntitlementStore(
            secretStore: InMemorySecretStore(values: [.subscriptionLicense: license]),
            verifier: SignedLocalLicenseVerifier(publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString())
        )

        let snapshot = try store.snapshot()

        XCTAssertEqual(snapshot.plan, .free)
        XCTAssertEqual(snapshot.source, .invalidLocalLicense)
    }

    func testKeychainEntitlementStoreRejectsUnsignedLocalLicenseJSON() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let license = """
        {
          "id": "founder-local-001",
          "plan": "founder",
          "issuedAt": "2026-06-01T00:00:00Z",
          "expiresAt": null,
          "features": ["unlimitedProjects"],
          "signature": "local-alpha-placeholder"
        }
        """
        let store = KeychainEntitlementStore(
            secretStore: InMemorySecretStore(values: [.subscriptionLicense: license]),
            verifier: SignedLocalLicenseVerifier(publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString())
        )

        let snapshot = try store.snapshot()

        XCTAssertEqual(snapshot.plan, .free)
        XCTAssertEqual(snapshot.source, .invalidLocalLicense)
    }

    func testKeychainEntitlementStoreRejectsExpiredSignedLocalLicense() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let license = signedLocalLicense(
            id: "expired-personal-plus-001",
            plan: .personalPlus,
            signingKey: signingKey,
            issuedAt: ISO8601DateFormatter().date(from: "2019-01-01T00:00:00Z")!,
            expiresAt: ISO8601DateFormatter().date(from: "2020-01-01T00:00:00Z")!
        )
        let store = KeychainEntitlementStore(
            secretStore: InMemorySecretStore(values: [.subscriptionLicense: license]),
            verifier: SignedLocalLicenseVerifier(publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString())
        )

        let snapshot = try store.snapshot()

        XCTAssertEqual(snapshot.plan, .free)
        XCTAssertEqual(snapshot.source, .invalidLocalLicense)
    }

    func testKeychainEntitlementStoreRejectsSignedLocalLicenseWhenPublicKeyIsInvalid() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let license = signedLocalLicense(
            id: "founder-local-001",
            plan: .founder,
            signingKey: signingKey
        )
        let store = KeychainEntitlementStore(
            secretStore: InMemorySecretStore(values: [.subscriptionLicense: license]),
            verifier: SignedLocalLicenseVerifier(publicKeyBase64: "not a base64 public key")
        )

        let snapshot = try store.snapshot()

        XCTAssertEqual(snapshot.plan, .free)
        XCTAssertEqual(snapshot.source, .invalidLocalLicense)
    }

    func testSignedLocalLicensePayloadFramesFeatureValues() {
        let issuedAt = ISO8601DateFormatter().date(from: "2026-06-17T00:00:00Z")!
        let singleCommaFeature = LocalLicense(
            id: "feature-framing-001",
            plan: .founder,
            issuedAt: issuedAt,
            features: ["a,b"]
        )
        let multipleFeatures = LocalLicense(
            id: "feature-framing-001",
            plan: .founder,
            issuedAt: issuedAt,
            features: ["a", "b"]
        )

        XCTAssertNotEqual(
            SignedLocalLicenseVerifier.signingPayload(for: singleCommaFeature),
            SignedLocalLicenseVerifier.signingPayload(for: multipleFeatures)
        )
    }

    func testEntitlementCheckerStopsFreeFeatureBeforeWorkStarts() throws {
        let checker = EntitlementChecker(store: StaticEntitlementStore(plan: .free))

        XCTAssertThrowsError(try checker.require(.externalSync)) { error in
            XCTAssertEqual(error as? EntitlementError, .upgradeRequired(feature: .externalSync, requiredPlan: .sync))
        }
    }

    func testCloudExecutionGatesStopFreeAndSyncPlansBeforeRemoteWorkStarts() throws {
        let freeChecker = EntitlementChecker(store: StaticEntitlementStore(plan: .free))
        let syncChecker = EntitlementChecker(store: StaticEntitlementStore(plan: .sync))

        XCTAssertThrowsError(try freeChecker.require(.cloudRelay)) { error in
            XCTAssertEqual(error as? EntitlementError, .upgradeRequired(feature: .cloudRelay, requiredPlan: .pro))
        }
        XCTAssertThrowsError(try syncChecker.require(.hostedMCPEndpoint)) { error in
            XCTAssertEqual(error as? EntitlementError, .upgradeRequired(feature: .hostedMCPEndpoint, requiredPlan: .pro))
        }
    }

    func testSyncServiceFreeStartFailsBeforeNetworkClientIsReached() throws {
        let networkClient = RecordingSyncNetworkClient()
        let service = SyncService(
            entitlementStore: StaticEntitlementStore(plan: .free),
            configuration: SyncConfiguration(backendEndpoint: URL(string: "https://sync.suisui.example/v1")),
            networkClient: networkClient
        )

        XCTAssertThrowsError(try service.startSync()) { error in
            XCTAssertEqual(error as? SyncServiceError, .upgradeRequired(requiredPlan: .sync))
        }
        XCTAssertEqual(networkClient.startCallCount, 0)
        XCTAssertEqual(try service.status().state, .upgradeRequired)
    }

    func testSyncServiceSyncPlanWithoutBackendDoesNotReturnMockSuccess() throws {
        let networkClient = RecordingSyncNetworkClient()
        let service = SyncService(
            entitlementStore: StaticEntitlementStore(plan: .sync),
            configuration: .notConfigured,
            networkClient: networkClient
        )

        XCTAssertThrowsError(try service.startSync()) { error in
            XCTAssertEqual(error as? SyncServiceError, .syncBackendNotConfigured)
        }
        XCTAssertEqual(networkClient.startCallCount, 0)
        XCTAssertEqual(try service.status().state, .backendNotConfigured)
    }

    func testSyncServiceConfiguredBackendAllowsSyncPlanAndRecordsNetworkFailureInsteadOfReturningReady() throws {
        let networkClient = RecordingSyncNetworkClient(error: SyncServiceError.networkUnavailable)
        let service = SyncService(
            entitlementStore: StaticEntitlementStore(plan: .sync),
            configuration: SyncConfiguration(backendEndpoint: URL(string: "https://sync.suisui.example/v1")),
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
            entitlementStore: StaticEntitlementStore(plan: .sync),
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
                configuration: SyncConfiguration(backendEndpoint: URL(string: "https://sync.suisui.example/v1")),
                networkClient: networkClient
            )
        )

        XCTAssertEqual(viewModel.planLabel, "Free")
        XCTAssertEqual(viewModel.statusLabel, "Upgrade required")
        XCTAssertEqual(viewModel.dataIncludedLabel, "Projects, Tasks, Settings")
        XCTAssertFalse(viewModel.canEnableSync)
        XCTAssertEqual(viewModel.syncUnavailableLabel, "Upgrade required")

        viewModel.startSync()

        XCTAssertEqual(viewModel.errorMessage, "Upgrade to Sync to sync Suisui data.")
        XCTAssertEqual(networkClient.startCallCount, 0)
    }

    private func signedLocalLicense(
        id: String,
        plan: LicensePlan,
        signingKey: Curve25519.Signing.PrivateKey,
        issuedAt: Date = ISO8601DateFormatter().date(from: "2026-06-17T00:00:00Z")!,
        expiresAt: Date? = nil,
        features: [String] = []
    ) -> String {
        let unsigned = LocalLicense(
            id: id,
            plan: plan,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            features: features,
            signature: nil
        )
        let signature = try! signingKey.signature(for: SignedLocalLicenseVerifier.signingPayload(for: unsigned))
        let signed = LocalLicense(
            id: id,
            plan: plan,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            features: features,
            signature: signature.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try! encoder.encode(signed), encoding: .utf8)!
    }

    @MainActor
    func testSyncSettingsViewModelShowsBackendNotConfiguredForSyncPlan() {
        let viewModel = SyncSettingsViewModel(
            service: SyncService(
                entitlementStore: StaticEntitlementStore(plan: .sync),
                configuration: .notConfigured,
                networkClient: RecordingSyncNetworkClient()
            )
        )

        XCTAssertEqual(viewModel.planLabel, "Sync")
        XCTAssertEqual(viewModel.statusLabel, "Sync backend is not configured")
        XCTAssertFalse(viewModel.canEnableSync)
        XCTAssertEqual(viewModel.syncUnavailableLabel, "Sync backend is not configured")

        viewModel.startSync()

        XCTAssertEqual(viewModel.errorMessage, "Sync backend is not configured.")
    }

    @MainActor
    func testSyncSettingsViewModelAllowsSyncPlanToggleOnlyWhenBackendIsConfigured() {
        let networkClient = RecordingSyncNetworkClient()
        let viewModel = SyncSettingsViewModel(
            service: SyncService(
                entitlementStore: StaticEntitlementStore(plan: .sync),
                configuration: SyncConfiguration(backendEndpoint: URL(string: "https://sync.suisui.example/v1")),
                networkClient: networkClient
            )
        )

        XCTAssertEqual(viewModel.planLabel, "Sync")
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
                entitlementStore: StaticEntitlementStore(plan: .sync),
                configuration: SyncConfiguration(backendEndpoint: URL(string: "https://sync.suisui.example/v1")),
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
