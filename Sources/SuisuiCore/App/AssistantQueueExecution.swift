import Foundation

public enum AssistantQueueExecutionError: Error, Equatable, Sendable {
    case unsupportedPayload
    case receiptPersistenceFailed(queueStateMarkedFailed: Bool)
    case managedUsageLedgerPersistenceFailed(queueStateMarkedFailed: Bool)
    case managedUsageCapCheckFailed(queueStateMarkedFailed: Bool)
    case managedUsageCapExceeded(projection: ManagedAIUsageCapProjection, queueStateMarkedFailed: Bool)
}

public struct AssistantQueueConversationLinkRequiresReviewError:
    Error,
    Equatable,
    Sendable
{
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

public struct AssistantQueueConversationLinkUnavailableError:
    Error,
    Equatable,
    Sendable
{
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

public struct AssistantQueueConversationLinkPersistenceError:
    Error,
    Equatable,
    Sendable
{
    public let queueStateMarkedFailed: Bool

    public init(queueStateMarkedFailed: Bool) {
        self.queueStateMarkedFailed = queueStateMarkedFailed
    }
}

public struct AssistantQueueExecutionResult: Equatable, Sendable {
    public var item: AssistantQueueItem
    public var session: ReviewSession
    public var receipt: ExecutionReceipt

    public init(item: AssistantQueueItem, session: ReviewSession, receipt: ExecutionReceipt) {
        self.item = item
        self.session = session
        self.receipt = receipt
    }
}
