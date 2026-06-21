import Combine
import Foundation

public enum SyncDataClass: String, Codable, CaseIterable, Equatable, Sendable {
    case projects
    case tasks
    case settings
    case conversations
    case documents
    case actionPlans
    case automationRequests
    case harnessRuns

    public var displayName: String {
        switch self {
        case .projects:
            "Projects"
        case .tasks:
            "Tasks"
        case .settings:
            "Settings"
        case .conversations:
            "Conversations"
        case .documents:
            "Documents"
        case .actionPlans:
            "Action Plans"
        case .automationRequests:
            "Automation Requests"
        case .harnessRuns:
            "Harness Runs"
        }
    }
}

public struct SyncConfiguration: Equatable, Sendable {
    public var backendEndpoint: URL?

    public init(backendEndpoint: URL?) {
        self.backendEndpoint = backendEndpoint
    }

    public static let notConfigured = SyncConfiguration(backendEndpoint: nil)
}

public struct SyncStartPayload: Equatable, Sendable {
    public var includedData: [SyncDataClass]

    public init(includedData: [SyncDataClass]) {
        self.includedData = includedData
    }
}

public struct SyncStartResult: Equatable, Sendable {
    public var startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }
}

public struct SyncExportDryRun: Equatable, Sendable {
    public var includedData: [SyncDataClass]

    public init(includedData: [SyncDataClass]) {
        self.includedData = includedData
    }
}

public enum SyncStatusState: String, Codable, Equatable, Sendable {
    case idle
    case upgradeRequired
    case backendNotConfigured
    case syncing
    case failed
}

public struct SyncStatus: Equatable, Sendable {
    public var plan: SubscriptionPlan
    public var state: SyncStatusState
    public var lastAttemptAt: Date?
    public var includedData: [SyncDataClass]

    public init(
        plan: SubscriptionPlan,
        state: SyncStatusState,
        lastAttemptAt: Date? = nil,
        includedData: [SyncDataClass]
    ) {
        self.plan = plan
        self.state = state
        self.lastAttemptAt = lastAttemptAt
        self.includedData = includedData
    }
}

public enum SyncServiceError: Error, Equatable, Sendable {
    case upgradeRequired(requiredPlan: SubscriptionPlan)
    case syncBackendNotConfigured
    case networkUnavailable
}

public protocol SyncNetworkClient: Sendable {
    func startSync(endpoint: URL, payload: SyncStartPayload) throws -> SyncStartResult
}

public struct UnavailableSyncNetworkClient: SyncNetworkClient {
    public init() {}

    public func startSync(endpoint: URL, payload: SyncStartPayload) throws -> SyncStartResult {
        throw SyncServiceError.networkUnavailable
    }
}

public final class SyncService: @unchecked Sendable {
    private let entitlementStore: any EntitlementStore
    private let configuration: SyncConfiguration
    private let networkClient: any SyncNetworkClient
    private let includedData: [SyncDataClass]
    private var lastAttemptAt: Date?
    private var lastAttemptFailed = false
    private let lock = NSLock()

    public init(
        entitlementStore: any EntitlementStore,
        configuration: SyncConfiguration,
        networkClient: any SyncNetworkClient,
        includedData: [SyncDataClass] = [.projects, .tasks, .settings]
    ) {
        self.entitlementStore = entitlementStore
        self.configuration = configuration
        self.networkClient = networkClient
        self.includedData = includedData
    }

    public func status() throws -> SyncStatus {
        let snapshot = try entitlementStore.snapshot()
        let attemptState = currentAttemptState()
        return SyncStatus(
            plan: snapshot.plan,
            state: state(for: snapshot.plan, lastAttemptFailed: attemptState.failed),
            lastAttemptAt: attemptState.date,
            includedData: includedData
        )
    }

    public func startSync() throws -> SyncStartResult {
        let snapshot = try entitlementStore.snapshot()
        guard snapshot.plan.allows(.externalSync) else {
            recordAttempt()
            throw SyncServiceError.upgradeRequired(requiredPlan: FeatureGate.externalSync.requiredPlan)
        }

        guard let endpoint = configuration.backendEndpoint else {
            recordAttempt()
            throw SyncServiceError.syncBackendNotConfigured
        }

        do {
            let result = try networkClient.startSync(
                endpoint: endpoint,
                payload: SyncStartPayload(includedData: includedData)
            )
            setLastAttempt(at: result.startedAt, failed: false)
            return result
        } catch {
            setLastAttempt(at: Date(), failed: true)
            throw error
        }
    }

    public func stopSync() throws -> SyncStatus {
        try status()
    }

    public func exportDryRun() throws -> SyncExportDryRun {
        SyncExportDryRun(includedData: includedData)
    }

    private func state(for plan: SubscriptionPlan, lastAttemptFailed: Bool) -> SyncStatusState {
        guard plan.allows(.externalSync) else {
            return .upgradeRequired
        }

        guard configuration.backendEndpoint != nil else {
            return .backendNotConfigured
        }

        if lastAttemptFailed {
            return .failed
        }

        return .idle
    }

    private func recordAttempt() {
        setLastAttempt(at: Date(), failed: false)
    }

    private func currentAttemptState() -> (date: Date?, failed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (lastAttemptAt, lastAttemptFailed)
    }

    private func setLastAttempt(at date: Date, failed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        lastAttemptAt = date
        lastAttemptFailed = failed
    }
}

@MainActor
public final class SyncSettingsViewModel: ObservableObject {
    @Published public private(set) var status: SyncStatus
    @Published public private(set) var isSyncEnabled: Bool
    @Published public private(set) var errorMessage: String?

    private let service: SyncService

    public init(service: SyncService) {
        self.service = service
        self.status = SyncStatus(
            plan: .free,
            state: .upgradeRequired,
            includedData: [.projects, .tasks, .settings]
        )
        self.isSyncEnabled = false
        self.errorMessage = nil
        refresh()
    }

    public var planLabel: String {
        status.plan.displayName
    }

    public var statusLabel: String {
        switch status.state {
        case .idle:
            "Ready"
        case .upgradeRequired:
            "Upgrade required"
        case .backendNotConfigured:
            "Sync backend is not configured"
        case .syncing:
            "Syncing"
        case .failed:
            "Failed"
        }
    }

    public var lastAttemptLabel: String {
        guard let lastAttemptAt = status.lastAttemptAt else {
            return "Never"
        }

        return lastAttemptAt.formatted(date: .abbreviated, time: .shortened)
    }

    public var dataIncludedLabel: String {
        status.includedData.map(\.displayName).joined(separator: ", ")
    }

    public var canEnableSync: Bool {
        status.state == .idle || status.state == .failed
    }

    public var syncUnavailableLabel: String? {
        switch status.state {
        case .idle, .syncing, .failed:
            nil
        case .upgradeRequired:
            "Upgrade required"
        case .backendNotConfigured:
            "Sync backend is not configured"
        }
    }

    public func setSyncEnabled(_ isEnabled: Bool) {
        if isEnabled {
            startSync()
        } else {
            stopSync()
        }
    }

    public func startSync() {
        do {
            _ = try service.startSync()
            isSyncEnabled = true
            errorMessage = nil
            refresh()
        } catch {
            isSyncEnabled = false
            errorMessage = message(for: error)
            refresh()
        }
    }

    public func stopSync() {
        do {
            status = try service.stopSync()
            isSyncEnabled = false
            errorMessage = nil
        } catch {
            isSyncEnabled = false
            errorMessage = message(for: error)
            refresh()
        }
    }

    public func refresh() {
        do {
            status = try service.status()
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        guard let serviceError = error as? SyncServiceError else {
            return "Sync status is unavailable."
        }

        switch serviceError {
        case let .upgradeRequired(requiredPlan):
            return "Upgrade to \(requiredPlan.displayName) to sync SoloPM data."
        case .syncBackendNotConfigured:
            return "Sync backend is not configured."
        case .networkUnavailable:
            return "Sync network client is unavailable in this build."
        }
    }
}
