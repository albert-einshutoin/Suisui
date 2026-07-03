import Foundation

public enum IOSCompanionSurface: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case inbox
    case today
    case projectTaskList
    case boardLiteStatusControls
    case conversation
    case pendingActionApprovalInbox
}

public enum IOSCompanionCaptureInput: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case textConversation
    case voiceInput
    case shortcutsCreateTask
    case shortcutsAskSoloPM
    case shareSheetCapture
}

public enum IOSDeviceRegistrationStep: String, Codable, CaseIterable, Equatable, Sendable {
    case signIn
    case restoreEntitlement
    case registerDevice
    case enableSync
}

public struct IOSDeviceRegistrationFlow: Codable, Equatable, Sendable {
    public var steps: [IOSDeviceRegistrationStep]

    public init(steps: [IOSDeviceRegistrationStep]) {
        self.steps = steps
    }
}

public struct IOSCompanionMVPConfiguration: Codable, Equatable, Sendable {
    public var surfaces: [IOSCompanionSurface]
    public var captureInputs: [IOSCompanionCaptureInput]
    public var registrationFlow: IOSDeviceRegistrationFlow

    public init(
        surfaces: [IOSCompanionSurface],
        captureInputs: [IOSCompanionCaptureInput],
        registrationFlow: IOSDeviceRegistrationFlow
    ) {
        self.surfaces = surfaces
        self.captureInputs = captureInputs
        self.registrationFlow = registrationFlow
    }

    public static let `default` = IOSCompanionMVPConfiguration(
        surfaces: [
            .inbox,
            .today,
            .projectTaskList,
            .boardLiteStatusControls,
            .conversation,
            .pendingActionApprovalInbox
        ],
        captureInputs: [
            .textConversation,
            .voiceInput,
            .shortcutsCreateTask,
            .shortcutsAskSoloPM,
            .shareSheetCapture
        ],
        registrationFlow: IOSDeviceRegistrationFlow(
            steps: [.signIn, .restoreEntitlement, .registerDevice, .enableSync]
        )
    )
}

public enum IOSCompanionTaskActionError: Error, Equatable, Sendable {
    case blankTitle
    case blankStatus
    case blankDueDate
}

public enum IOSCompanionTaskAction: Codable, Equatable, Sendable {
    case create(title: String, projectID: Int64?)
    case complete(taskID: Int64)
    case changeStatus(taskID: Int64, status: String)
    case changeDueDate(taskID: Int64, dueAt: String)
    case moveToProject(taskID: Int64, projectID: Int64)

    public func mutationPayload(source: SyncMutationSource) throws -> SyncTaskMutationPayload {
        switch self {
        case let .create(title, projectID):
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else {
                throw IOSCompanionTaskActionError.blankTitle
            }
            return SyncTaskMutationPayload(
                operation: .create,
                title: trimmedTitle,
                projectID: projectID,
                source: source,
                approvalState: .pendingApproval
            )
        case let .complete(taskID):
            return SyncTaskMutationPayload(
                taskID: taskID,
                operation: .complete,
                status: "completed",
                source: source,
                approvalState: .pendingApproval
            )
        case let .changeStatus(taskID, status):
            let trimmedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedStatus.isEmpty else {
                throw IOSCompanionTaskActionError.blankStatus
            }
            return SyncTaskMutationPayload(
                taskID: taskID,
                operation: .update,
                status: trimmedStatus,
                source: source,
                approvalState: .pendingApproval
            )
        case let .changeDueDate(taskID, dueAt):
            let trimmedDueAt = dueAt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDueAt.isEmpty else {
                throw IOSCompanionTaskActionError.blankDueDate
            }
            return SyncTaskMutationPayload(
                taskID: taskID,
                operation: .updateDueDate,
                dueAt: trimmedDueAt,
                source: source,
                approvalState: .pendingApproval
            )
        case let .moveToProject(taskID, projectID):
            return SyncTaskMutationPayload(
                taskID: taskID,
                operation: .moveProject,
                projectID: projectID,
                source: source,
                approvalState: .pendingApproval
            )
        }
    }
}

public enum IOSPendingActionApprovalError: Error, Equatable, Sendable {
    case requestIsNotPending
}

public enum IOSPendingActionApproval {
    public static func approve(
        _ request: SyncAutomationRequestPayload
    ) throws -> SyncAutomationRequestPayload {
        guard request.approvalState == .pendingApproval else {
            throw IOSPendingActionApprovalError.requestIsNotPending
        }

        var approved = request
        approved.approvalState = .approved
        if var taskMutation = approved.taskMutation {
            // Mobile approvals should preserve the original mutation details while
            // only moving the review state forward for later sync/execution.
            taskMutation.approvalState = .approved
            approved.taskMutation = taskMutation
        }
        return approved
    }
}
