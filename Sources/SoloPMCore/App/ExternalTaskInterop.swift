import CryptoKit
import Foundation

public enum ExternalTaskSource: String, Codable, CaseIterable, Sendable {
    case soloPMJSON = "solopm_json"
    case googleCalendar = "google_calendar"
    case todoist
    case notion
    case linear
    case githubIssues = "github_issues"
}

public struct TaskInteropProject: Codable, Equatable, Sendable {
    public var localID: Int64
    public var title: String
    public var status: String

    public init(localID: Int64, title: String, status: String) {
        self.localID = localID
        self.title = title
        self.status = status
    }
}

public struct TaskInteropTask: Codable, Equatable, Sendable {
    public var localID: Int64
    public var localProjectID: Int64
    public var projectTitle: String
    public var title: String
    public var detail: String
    public var status: ProjectTaskStatus
    public var priority: ProjectTaskPriority
    public var dueAt: String?

    public init(
        localID: Int64,
        localProjectID: Int64,
        projectTitle: String,
        title: String,
        detail: String,
        status: ProjectTaskStatus,
        priority: ProjectTaskPriority,
        dueAt: String?
    ) {
        self.localID = localID
        self.localProjectID = localProjectID
        self.projectTitle = projectTitle
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
    }
}

public struct TaskInteropDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var projects: [TaskInteropProject]
    public var tasks: [TaskInteropTask]

    public init(
        schemaVersion: Int = 1,
        exportedAt: Date,
        projects: [TaskInteropProject],
        tasks: [TaskInteropTask]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.projects = projects
        self.tasks = tasks
    }

    public static func decode(_ data: Data) throws -> TaskInteropDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TaskInteropDocument.self, from: data)
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public final class TaskInteropExportService {
    private let store: any ProjectBoardStore

    public init(store: any ProjectBoardStore) {
        self.store = store
    }

    public func exportDocument(exportedAt: Date = Date()) throws -> TaskInteropDocument {
        let snapshot = try store.loadSnapshot(includeArchived: true)
        let projects = snapshot.projects.map {
            TaskInteropProject(localID: $0.id, title: $0.title, status: $0.status)
        }
        let tasks = snapshot.projects.flatMap { project in
            project.tasks.map { task in
                TaskInteropTask(
                    localID: task.id,
                    localProjectID: project.id,
                    projectTitle: project.title,
                    title: task.title,
                    detail: task.detail,
                    status: task.status,
                    priority: task.priority,
                    dueAt: task.dueAt
                )
            }
        }
        return TaskInteropDocument(exportedAt: exportedAt, projects: projects, tasks: tasks)
    }

    public func exportJSON(exportedAt: Date = Date()) throws -> Data {
        try exportDocument(exportedAt: exportedAt).encode()
    }
}

public struct ExternalTaskImportItem: Equatable, Sendable {
    public var source: ExternalTaskSource
    public var externalID: String
    public var projectTitle: String
    public var title: String
    public var detail: String
    public var status: ProjectTaskStatus
    public var priority: ProjectTaskPriority
    public var dueAt: String?

    public init(
        source: ExternalTaskSource,
        externalID: String,
        projectTitle: String,
        title: String,
        detail: String = "",
        status: ProjectTaskStatus = .backlog,
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) {
        self.source = source
        self.externalID = externalID
        self.projectTitle = projectTitle
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
    }
}

public struct ExternalTaskImportResult: Equatable, Sendable {
    public var createdProjectCount: Int
    public var createdTaskCount: Int
    public var skippedDuplicateCount: Int

    public init(createdProjectCount: Int = 0, createdTaskCount: Int = 0, skippedDuplicateCount: Int = 0) {
        self.createdProjectCount = createdProjectCount
        self.createdTaskCount = createdTaskCount
        self.skippedDuplicateCount = skippedDuplicateCount
    }
}

public final class ExternalTaskImportService {
    private let store: any ProjectBoardStore
    private let linkStore: any ExternalTaskLinkStore

    private struct ExternalTaskLinkProviderAndExternalIDKey: Hashable {
        let providerID: String
        let externalID: String
    }

    public init(store: any ProjectBoardStore, linkStore: any ExternalTaskLinkStore) {
        self.store = store
        self.linkStore = linkStore
    }

    public func importItems(_ items: [ExternalTaskImportItem]) throws -> ExternalTaskImportResult {
        var activeProjectIndex = Self.activeProjectIndex(from: try store.loadSnapshot(includeArchived: true))
        return try importItems(items, activeProjectIndex: &activeProjectIndex)
    }

    func importItems(
        _ items: [ExternalTaskImportItem],
        activeProjectIndex: inout [String: ProjectBoardProject]
    ) throws -> ExternalTaskImportResult {
        var result = ExternalTaskImportResult()

        // Fetch existing links as a single batch per provider so each import item
        // doesn't trigger one lookup query.
        var existingLinks = try existingLinksLookup(for: items)

        for item in items {
            let key = ExternalTaskLinkProviderAndExternalIDKey(
                providerID: item.source.rawValue,
                externalID: item.externalID
            )
            if existingLinks[key] != nil {
                result.skippedDuplicateCount += 1
                continue
            }

            let project = try projectForImport(
                title: item.projectTitle,
                createdProjectCount: &result.createdProjectCount,
                activeProjectIndex: &activeProjectIndex
            )
            let task = try store.createTask(ProjectBoardTaskDraft(
                projectID: project.id,
                title: item.title,
                detail: item.detail,
                status: item.status,
                priority: item.priority,
                dueAt: item.dueAt
            ))
            let linkedRecord = try linkStore.link(
                providerID: item.source.rawValue,
                externalID: item.externalID,
                taskID: task.id,
                projectID: task.projectID,
                title: task.title
            )
            existingLinks[key] = linkedRecord
            result.createdTaskCount += 1
        }

        return result
    }

    static func activeProjectIndex(from snapshot: ProjectBoardSnapshot) -> [String: ProjectBoardProject] {
        Dictionary(
            snapshot.projects
                .filter { !$0.isArchived }
                .map { (Self.normalizedProjectTitle($0.title), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func projectForImport(
        title: String,
        createdProjectCount: inout Int,
        activeProjectIndex: inout [String: ProjectBoardProject]
    ) throws -> ProjectBoardProject {
        let normalizedTitle = Self.normalizedProjectTitle(title)
        if let existing = activeProjectIndex[normalizedTitle] {
            return existing
        }

        // Indexing active projects lets each imported item resolve the target
        // project without re-reading the full snapshot on every row.
        let project = try store.createProject(title: normalizedTitle)
        activeProjectIndex[normalizedTitle] = project
        createdProjectCount += 1
        return project
    }

    private func existingLinksLookup(for items: [ExternalTaskImportItem]) throws -> [ExternalTaskImportService.ExternalTaskLinkProviderAndExternalIDKey: ExternalTaskLinkRecord] {
        let linksByProvider = Dictionary(grouping: items, by: { $0.source.rawValue })

        var allLinks: [ExternalTaskLinkRecord] = []
        for (providerID, providerItems) in linksByProvider {
            let externalIDs = Array(Set(providerItems.map { $0.externalID }))
            allLinks += try linkStore.links(providerID: providerID, externalIDs: externalIDs)
        }

        return Dictionary(
            uniqueKeysWithValues: allLinks.map {
                (ExternalTaskLinkProviderAndExternalIDKey(providerID: $0.providerID, externalID: $0.externalID), $0)
            }
        )
    }

    static func normalizedProjectTitle(_ title: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let importTitle = normalizedTitle.isEmpty ? "Imported Tasks" : normalizedTitle
        return importTitle
    }
}

public final class TaskInteropDocumentImportService {
    private let store: any ProjectBoardStore
    private let linkStore: any ExternalTaskLinkStore

    public init(store: any ProjectBoardStore, linkStore: any ExternalTaskLinkStore) {
        self.store = store
        self.linkStore = linkStore
    }

    public func importDocument(_ document: TaskInteropDocument) throws -> ExternalTaskImportResult {
        var result = ExternalTaskImportResult()

        var activeProjectIndex = ExternalTaskImportService.activeProjectIndex(from: try store.loadSnapshot(includeArchived: true))

        for project in document.projects {
            let rawTitle = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawTitle.isEmpty else {
                continue
            }
            let title = ExternalTaskImportService.normalizedProjectTitle(rawTitle)
            guard activeProjectIndex[title] == nil else {
                continue
            }
            let createdProject = try store.createProject(title: title)
            activeProjectIndex[title] = createdProject
            result.createdProjectCount += 1
        }

        let namespace = Self.externalNamespace(for: document)
        let taskItems = document.tasks.map { task in
            ExternalTaskImportItem(
                source: .soloPMJSON,
                externalID: "\(namespace):task:\(task.localID)",
                projectTitle: task.projectTitle,
                title: task.title,
                detail: task.detail,
                status: task.status,
                priority: task.priority,
                dueAt: task.dueAt
            )
        }
        // Reuse the prebuilt project index for all task imports to avoid per-item
        // snapshot reads while keeping project creation/idempotency behavior.
        let taskResult = try ExternalTaskImportService(store: store, linkStore: linkStore)
            .importItems(taskItems, activeProjectIndex: &activeProjectIndex)
        result.createdProjectCount += taskResult.createdProjectCount
        result.createdTaskCount += taskResult.createdTaskCount
        result.skippedDuplicateCount += taskResult.skippedDuplicateCount
        return result
    }

    private static func externalNamespace(for document: TaskInteropDocument) -> String {
        "exported_at:\(document.exportedAt.timeIntervalSince1970)"
    }
}

public struct ExternalTaskLinkRecord: Equatable, Sendable {
    public var id: Int64
    public var providerID: String
    public var externalID: String
    public var projectID: Int64?
    public var taskID: Int64
    public var title: String?

    public init(
        id: Int64,
        providerID: String,
        externalID: String,
        projectID: Int64?,
        taskID: Int64,
        title: String?
    ) {
        self.id = id
        self.providerID = providerID
        self.externalID = externalID
        self.projectID = projectID
        self.taskID = taskID
        self.title = title
    }
}

public protocol ExternalTaskLinkStore: Sendable {
    func link(providerID: String, externalID: String, taskID: Int64, projectID: Int64?, title: String?) throws -> ExternalTaskLinkRecord
    func link(providerID: String, externalID: String) throws -> ExternalTaskLinkRecord?
    func link(providerID: String, taskID: Int64) throws -> ExternalTaskLinkRecord?
    func links(providerID: String, taskIDs: [Int64]) throws -> [ExternalTaskLinkRecord]
    func links(providerID: String, externalIDs: [String]) throws -> [ExternalTaskLinkRecord]
    func list() throws -> [ExternalTaskLinkRecord]
}

public struct ExternalCalendarEventRecord: Equatable, Sendable {
    public var providerID: String
    public var externalID: String
    public var calendarID: String
    public var timeZoneIdentifier: String
    public var title: String

    public init(providerID: String, externalID: String, calendarID: String, timeZoneIdentifier: String, title: String) {
        self.providerID = providerID
        self.externalID = externalID
        self.calendarID = calendarID
        self.timeZoneIdentifier = timeZoneIdentifier
        self.title = title
    }
}

public protocol ExternalCalendarEventSink: Sendable {
    func createEvent(
        _ draft: CalendarEventDraft,
        calendarID: String,
        timeZoneIdentifier: String,
        context: ToolExecutionContext
    ) throws -> ExternalCalendarEventRecord
}

public struct GoogleCalendarRuntimeCredentialStatus: Equatable, Sendable {
    public static let eventsWriteScope = ExternalAuthorizationScopeIdentifier.googleCalendarEventsWrite

    public var grantedScopes: Set<String>
    public var expiresAt: Date?
    public var hasRefreshToken: Bool

    public init(
        grantedScopes: Set<String>,
        expiresAt: Date?,
        hasRefreshToken: Bool
    ) {
        self.grantedScopes = grantedScopes
        self.expiresAt = expiresAt
        self.hasRefreshToken = hasRefreshToken
    }
}

public protocol GoogleCalendarRuntimeCredentialStatusStore: Sendable {
    func loadGoogleCalendarCredentialStatus() throws -> GoogleCalendarRuntimeCredentialStatus?
}

public struct UnavailableGoogleCalendarRuntimeCredentialStatusStore: GoogleCalendarRuntimeCredentialStatusStore {
    public init() {}

    public func loadGoogleCalendarCredentialStatus() throws -> GoogleCalendarRuntimeCredentialStatus? {
        nil
    }
}

public struct GoogleCalendarRuntimeSyncConfiguration: Equatable, Sendable {
    public var calendarID: String?
    public var timeZoneIdentifier: String

    public init(calendarID: String?, timeZoneIdentifier: String) {
        self.calendarID = calendarID
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public static let notConfigured = GoogleCalendarRuntimeSyncConfiguration(
        calendarID: nil,
        timeZoneIdentifier: "UTC"
    )

    var normalizedCalendarID: String? {
        calendarID?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum GoogleCalendarRuntimeSyncState: Equatable, Sendable {
    case upgradeRequired(requiredPlan: SubscriptionPlan)
    case calendarNotConfigured
    case invalidCalendarID
    case oauthDisconnected
    case missingRequiredScope(requiredScope: String)
    case tokenExpiredWithoutRefresh
    case runtimeNotConfigured
    case ready
    case failed(message: String)
}

public struct GoogleCalendarRuntimeSyncStatus: Equatable, Sendable {
    public var plan: SubscriptionPlan
    public var state: GoogleCalendarRuntimeSyncState

    public init(plan: SubscriptionPlan, state: GoogleCalendarRuntimeSyncState) {
        self.plan = plan
        self.state = state
    }

    public static let runtimeNotConfigured = GoogleCalendarRuntimeSyncStatus(
        plan: .free,
        state: .runtimeNotConfigured
    )

    public var canSync: Bool {
        state == .ready
    }

    public var statusLabel: String {
        switch state {
        case .upgradeRequired:
            "Upgrade required"
        case .calendarNotConfigured:
            "Calendar not configured"
        case .invalidCalendarID:
            "Invalid calendar ID"
        case .oauthDisconnected:
            "OAuth required"
        case .missingRequiredScope:
            "Calendar scope missing"
        case .tokenExpiredWithoutRefresh:
            "OAuth expired"
        case .runtimeNotConfigured:
            "Runtime not configured"
        case .ready:
            "Ready"
        case .failed:
            "Sync failed"
        }
    }

    public var detailLabel: String {
        switch state {
        case .upgradeRequired(let requiredPlan):
            "Google Calendar writes require the \(requiredPlan.displayName) plan."
        case .calendarNotConfigured:
            "Choose a Google Calendar before enabling due-task sync."
        case .invalidCalendarID:
            "Google Calendar ID is blank or invalid."
        case .oauthDisconnected:
            "Connect Google Calendar with OAuth before syncing due tasks."
        case .missingRequiredScope(let requiredScope):
            "Google Calendar OAuth is missing the required \(requiredScope) scope."
        case .tokenExpiredWithoutRefresh:
            "Google Calendar OAuth expired and has no refresh token."
        case .runtimeNotConfigured:
            "Google Calendar sync is not configured in this build."
        case .ready:
            "Google Calendar sync is ready. Approval is still required before writing events."
        case .failed(let message):
            message
        }
    }
}

public struct GoogleCalendarSettingsReadinessRow: Equatable, Sendable {
    public var statusLabel: String
    public var detailLabel: String
    public var nextActionLabel: String
    public var statusCheckActionLabel: String
    public var privacyBoundaryLabel: String
    public var isReady: Bool

    public init(status: GoogleCalendarRuntimeSyncStatus) {
        self.init(status: Optional(status))
    }

    public init(status: GoogleCalendarRuntimeSyncStatus?) {
        guard let status else {
            self.statusLabel = "Not checked"
            self.detailLabel = "Check local OAuth, plan, and calendar readiness before syncing."
            self.nextActionLabel = "Check Status"
            self.statusCheckActionLabel = "Check Status"
            self.privacyBoundaryLabel = "Tokens stay in Keychain; Settings uses OAuth only."
            self.isReady = false
            return
        }

        self.statusLabel = status.statusLabel
        self.detailLabel = status.detailLabel
        self.nextActionLabel = Self.nextActionLabel(for: status.state)
        self.statusCheckActionLabel = "Check Status"
        // Google Calendar uses OAuth tokens, not provider API keys. Keeping this label in
        // the shared row model makes every Settings surface repeat the same non-secret boundary.
        self.privacyBoundaryLabel = "Tokens stay in Keychain; Settings uses OAuth only."
        self.isReady = status.canSync
    }

    private static func nextActionLabel(for state: GoogleCalendarRuntimeSyncState) -> String {
        switch state {
        case .upgradeRequired:
            "Upgrade to Pro before OAuth authorization"
        case .calendarNotConfigured, .invalidCalendarID:
            "Choose a calendar before syncing"
        case .oauthDisconnected:
            "Connect with OAuth authorization"
        case .missingRequiredScope:
            "Reconnect with Calendar events scope"
        case .tokenExpiredWithoutRefresh:
            "Reconnect with OAuth authorization"
        case .runtimeNotConfigured:
            "Update Suisui runtime configuration"
        case .ready:
            "Sync due tasks from Project Board"
        case .failed:
            "Check status again"
        }
    }
}

public enum GoogleCalendarRuntimeSyncError: Error, Equatable, Sendable {
    case approvalRequired
    case invalidDueDate(String)
    case notReady(GoogleCalendarRuntimeSyncState)
    case rateLimited(retryAfterSeconds: TimeInterval?)
}

public protocol GoogleCalendarRuntimeSyncing: Sendable {
    func status(now: Date) throws -> GoogleCalendarRuntimeSyncStatus
    func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult
}

public final class SettingsBackedGoogleCalendarRuntimeSync: GoogleCalendarRuntimeSyncing, @unchecked Sendable {
    public typealias StatusFactory = (AppSettings, Date) throws -> GoogleCalendarRuntimeSyncStatus
    public typealias SyncFactory = (AppSettings) throws -> any GoogleCalendarRuntimeSyncing

    private let settingsStore: any AppSettingsStore
    private let statusFactory: StatusFactory
    private let syncFactory: SyncFactory

    public init(
        settingsStore: any AppSettingsStore,
        statusFactory: @escaping StatusFactory,
        syncFactory: @escaping SyncFactory
    ) {
        self.settingsStore = settingsStore
        self.statusFactory = statusFactory
        self.syncFactory = syncFactory
    }

    public func status(now: Date) throws -> GoogleCalendarRuntimeSyncStatus {
        try statusFactory(loadRuntimeSettings(), now)
    }

    public func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        try syncFactory(loadRuntimeSettings()).syncDueTasks(context: context)
    }

    private func loadRuntimeSettings() throws -> AppSettings {
        // The selected calendar is an external write target, so long-lived UI
        // surfaces must not cache it. Reload before each status/write path so
        // Settings changes cannot write approved events to a stale calendar.
        try settingsStore.load().normalizedForRuntime
    }
}

public enum GoogleCalendarRuntimeSyncReadiness {
    public static func status(
        entitlementStore: any EntitlementStore,
        credentialStatusStore: any GoogleCalendarRuntimeCredentialStatusStore,
        configuration: GoogleCalendarRuntimeSyncConfiguration,
        isWriteRuntimeConfigured: Bool,
        now: Date = Date()
    ) throws -> GoogleCalendarRuntimeSyncStatus {
        let entitlement = try entitlementStore.snapshot()
        guard entitlement.plan.allows(.externalConnectorWrite) else {
            return GoogleCalendarRuntimeSyncStatus(
                plan: entitlement.plan,
                state: .upgradeRequired(requiredPlan: FeatureGate.externalConnectorWrite.requiredPlan)
            )
        }

        guard let calendarID = configuration.normalizedCalendarID else {
            return GoogleCalendarRuntimeSyncStatus(plan: entitlement.plan, state: .calendarNotConfigured)
        }
        guard !calendarID.isEmpty else {
            return GoogleCalendarRuntimeSyncStatus(plan: entitlement.plan, state: .invalidCalendarID)
        }

        guard let credentialStatus = try credentialStatusStore.loadGoogleCalendarCredentialStatus() else {
            return GoogleCalendarRuntimeSyncStatus(plan: entitlement.plan, state: .oauthDisconnected)
        }
        guard credentialStatus.grantedScopes.contains(GoogleCalendarRuntimeCredentialStatus.eventsWriteScope) else {
            return GoogleCalendarRuntimeSyncStatus(
                plan: entitlement.plan,
                state: .missingRequiredScope(requiredScope: GoogleCalendarRuntimeCredentialStatus.eventsWriteScope)
            )
        }
        if let expiresAt = credentialStatus.expiresAt, expiresAt <= now, !credentialStatus.hasRefreshToken {
            return GoogleCalendarRuntimeSyncStatus(plan: entitlement.plan, state: .tokenExpiredWithoutRefresh)
        }
        guard isWriteRuntimeConfigured else {
            // Readiness must account for the local app boundary: metadata alone is not enough
            // unless a write sink is present, otherwise the UI could imply an unverified success path.
            return GoogleCalendarRuntimeSyncStatus(plan: entitlement.plan, state: .runtimeNotConfigured)
        }

        return GoogleCalendarRuntimeSyncStatus(plan: entitlement.plan, state: .ready)
    }
}

public final class GoogleCalendarRuntimeSyncController: GoogleCalendarRuntimeSyncing, @unchecked Sendable {
    private let entitlementStore: any EntitlementStore
    private let credentialStatusStore: any GoogleCalendarRuntimeCredentialStatusStore
    private let configuration: GoogleCalendarRuntimeSyncConfiguration
    private let taskSyncService: GoogleCalendarTaskSyncService?

    public init(
        entitlementStore: any EntitlementStore,
        credentialStatusStore: any GoogleCalendarRuntimeCredentialStatusStore,
        configuration: GoogleCalendarRuntimeSyncConfiguration,
        taskSyncService: GoogleCalendarTaskSyncService?
    ) {
        self.entitlementStore = entitlementStore
        self.credentialStatusStore = credentialStatusStore
        self.configuration = configuration
        self.taskSyncService = taskSyncService
    }

    public func status(now: Date = Date()) throws -> GoogleCalendarRuntimeSyncStatus {
        try GoogleCalendarRuntimeSyncReadiness.status(
            entitlementStore: entitlementStore,
            credentialStatusStore: credentialStatusStore,
            configuration: configuration,
            isWriteRuntimeConfigured: taskSyncService != nil,
            now: now
        )
    }

    public func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        let readiness = try status(now: context.now)
        guard readiness.canSync else {
            throw GoogleCalendarRuntimeSyncError.notReady(readiness.state)
        }
        guard let taskSyncService else {
            throw GoogleCalendarRuntimeSyncError.notReady(.runtimeNotConfigured)
        }
        return try taskSyncService.syncDueTasks(context: context)
    }
}

public struct GoogleCalendarTaskSyncResult: Equatable, Sendable {
    public var createdEventCount: Int
    public var skippedAlreadyLinkedCount: Int
    public var deferredDueToRunLimitCount: Int
    public var failedRetryableCount: Int
    public var failedNonRetryableCount: Int

    public init(
        createdEventCount: Int = 0,
        skippedAlreadyLinkedCount: Int = 0,
        deferredDueToRunLimitCount: Int = 0,
        failedRetryableCount: Int = 0,
        failedNonRetryableCount: Int = 0
    ) {
        self.createdEventCount = createdEventCount
        self.skippedAlreadyLinkedCount = skippedAlreadyLinkedCount
        self.deferredDueToRunLimitCount = deferredDueToRunLimitCount
        self.failedRetryableCount = failedRetryableCount
        self.failedNonRetryableCount = failedNonRetryableCount
    }

    public var hasMoreWork: Bool {
        deferredDueToRunLimitCount > 0 || failedRetryableCount > 0
    }
}

public final class GoogleCalendarTaskSyncService: @unchecked Sendable {
    public static let defaultMaximumCreatedEventCountPerRun = 25

    private let entitlementStore: any EntitlementStore
    private let store: any ProjectBoardStore
    private let linkStore: any ExternalTaskLinkStore
    private let calendarSink: any ExternalCalendarEventSink
    private let calendarID: String
    private let timeZoneIdentifier: String
    private let idempotencyNamespace: String?
    private let maximumCreatedEventCountPerRun: Int

    public init(
        entitlementStore: any EntitlementStore,
        store: any ProjectBoardStore,
        linkStore: any ExternalTaskLinkStore,
        calendarSink: any ExternalCalendarEventSink,
        calendarID: String,
        timeZoneIdentifier: String,
        idempotencyNamespace: String? = nil,
        maximumCreatedEventCountPerRun: Int = GoogleCalendarTaskSyncService.defaultMaximumCreatedEventCountPerRun
    ) {
        self.entitlementStore = entitlementStore
        self.store = store
        self.linkStore = linkStore
        self.calendarSink = calendarSink
        self.calendarID = calendarID
        self.timeZoneIdentifier = timeZoneIdentifier
        let normalizedNamespace = idempotencyNamespace?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.idempotencyNamespace = normalizedNamespace?.isEmpty == false ? normalizedNamespace : nil
        self.maximumCreatedEventCountPerRun = max(1, maximumCreatedEventCountPerRun)
    }

    public func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        let snapshot = try entitlementStore.snapshot()
        guard snapshot.plan.allows(.externalConnectorWrite) else {
            // Device sync is a personal data feature; writing to a third-party
            // calendar is an external side effect and must stay behind Pro.
            throw SyncServiceError.upgradeRequired(requiredPlan: FeatureGate.externalConnectorWrite.requiredPlan)
        }
        guard let approvalToken = context.approvalToken,
              !approvalToken.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GoogleCalendarRuntimeSyncError.approvalRequired
        }
        let snapshotProjects = try store.loadSnapshot(includeArchived: false).projects
        let dueTasks = snapshotProjects
            .filter { !$0.isCompleted && !$0.isArchived }
            .flatMap { project in
                project.tasks
                    .filter { $0.status != .done && $0.dueAt != nil }
                    .map { (project, $0) }
            }

        // One batch query for all due-task links avoids N+1 task-by-task lookups.
        let linkedTasks = Set(
            try linkStore.links(
                providerID: ExternalTaskSource.googleCalendar.rawValue,
                taskIDs: dueTasks.map { $0.1.id }
            ).map(\.taskID)
        )

        var result = GoogleCalendarTaskSyncResult(
            skippedAlreadyLinkedCount: dueTasks.filter { linkedTasks.contains($0.1.id) }.count
        )
        let unlinkedDueTasks = dueTasks.filter { !linkedTasks.contains($0.1.id) }
        var attemptedExternalWriteCount = 0

        for (index, pair) in unlinkedDueTasks.enumerated() {
            // Bound each approved run so a large backlog cannot turn one click
            // into an unbounded sequence of external Calendar writes.
            guard attemptedExternalWriteCount < maximumCreatedEventCountPerRun else {
                result.deferredDueToRunLimitCount = unlinkedDueTasks.count - index
                break
            }

            let project = pair.0
            let task = pair.1
            let draft: CalendarEventDraft
            do {
                draft = try calendarDraft(for: task, project: project)
            } catch GoogleCalendarRuntimeSyncError.invalidDueDate(_) {
                result.failedNonRetryableCount += 1
                continue
            }

            let record: ExternalCalendarEventRecord
            attemptedExternalWriteCount += 1
            do {
                record = try calendarSink.createEvent(
                    draft,
                    calendarID: calendarID,
                    timeZoneIdentifier: timeZoneIdentifier,
                    context: context
                )
            } catch GoogleCalendarRuntimeSyncError.rateLimited(_) {
                // A rate-limit response means this approval run has reached the
                // external service boundary. Stop immediately so retries require
                // a later approved run and cannot duplicate already-linked tasks.
                result.failedRetryableCount += 1
                result.deferredDueToRunLimitCount += unlinkedDueTasks.count - index - 1
                break
            } catch {
                result.failedNonRetryableCount += 1
                continue
            }

            _ = try linkStore.link(
                providerID: ExternalTaskSource.googleCalendar.rawValue,
                externalID: record.externalID,
                taskID: task.id,
                projectID: project.id,
                title: task.title
            )
            result.createdEventCount += 1
        }

        return result
    }

    private func calendarDraft(for task: ProjectBoardTask, project: ProjectBoardProject) throws -> CalendarEventDraft {
        let dueAt = task.dueAt ?? ""
        let isAllDay = !dueAt.contains("T")
        let detail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = detail.isEmpty ? "Suisui project: \(project.title)" : "Suisui project: \(project.title)\n\n\(detail)"
        let endAt = isAllDay ? try Self.exclusiveEndDate(forDateOnlyDueAt: dueAt) : dueAt
        return CalendarEventDraft(
            title: task.title,
            startAt: dueAt,
            endAt: endAt,
            isAllDay: isAllDay,
            notes: notes,
            idempotencyKey: idempotencyNamespace.map {
                // The namespace is a durable local-installation/workspace identifier.
                // Hashing it with task identity prevents leaking local titles while
                // avoiding cross-database collisions on Google caller-provided IDs.
                Self.googleCalendarIdempotencyKey(namespace: $0, project: project, task: task)
            }
        )
    }

    private static func exclusiveEndDate(forDateOnlyDueAt dueAt: String) throws -> String {
        let parts = dueAt.split(separator: "-")
        guard parts.count == 3,
              dueAt.count == 10,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            throw GoogleCalendarRuntimeSyncError.invalidDueDate(dueAt)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = components.date else {
            throw GoogleCalendarRuntimeSyncError.invalidDueDate(dueAt)
        }
        let normalizedComponents = calendar.dateComponents([.year, .month, .day], from: date)
        guard normalizedComponents.year == year,
              normalizedComponents.month == month,
              normalizedComponents.day == day,
              let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else {
            throw GoogleCalendarRuntimeSyncError.invalidDueDate(dueAt)
        }

        let nextComponents = calendar.dateComponents([.year, .month, .day], from: nextDate)
        guard let nextYear = nextComponents.year,
              let nextMonth = nextComponents.month,
              let nextDay = nextComponents.day else {
            throw GoogleCalendarRuntimeSyncError.invalidDueDate(dueAt)
        }
        return String(format: "%04d-%02d-%02d", nextYear, nextMonth, nextDay)
    }

    private static func googleCalendarIdempotencyKey(namespace: String, project: ProjectBoardProject, task: ProjectBoardTask) -> String {
        let identity = [
            "v1",
            namespace,
            "\(project.id)",
            project.title,
            "\(task.id)",
            task.title,
            task.dueAt ?? ""
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "solopm\(digest)"
    }
}
