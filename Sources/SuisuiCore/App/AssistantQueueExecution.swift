import Foundation

public enum AssistantQueueExecutionError: Error, Equatable, Sendable {
    case unsupportedPayload
    case receiptPersistenceFailed(queueStateMarkedFailed: Bool)
    case managedUsageLedgerPersistenceFailed(queueStateMarkedFailed: Bool)
    case managedUsageCapCheckFailed(queueStateMarkedFailed: Bool)
    case managedUsageCapExceeded(projection: ManagedAIUsageCapProjection, queueStateMarkedFailed: Bool)
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
