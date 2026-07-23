import Foundation

public struct ExternalSideEffectCoordinator: Sendable {
    private let journal: any ExternalSideEffectJournal

    public init(journal: any ExternalSideEffectJournal) {
        self.journal = journal
    }

    public func execute<ExternalResult>(
        request: ExternalSideEffectRequest,
        at: Date,
        prepareLocalState: () throws -> Void = {},
        performExternalWrite: () throws -> ExternalResult,
        externalResourceID: (ExternalResult) -> String?,
        persistLocalState: (ExternalResult) throws -> ToolResult
    ) throws -> ToolResult {
        switch try journal.claim(request, at: at) {
        case .returnSucceeded(let result):
            return result
        case .inProgress(let record):
            throw ToolExecutionError.externalSideEffectInProgress(
                ExternalSideEffectFailureEvidence(record: record)
            )
        case .requiresReconciliation(let record):
            throw ToolExecutionError.externalSideEffectRequiresReconciliation(
                ExternalSideEffectFailureEvidence(record: record)
            )
        case .execute(let prepared):
            return try executeClaimed(
                prepared,
                request: request,
                at: at,
                prepareLocalState: prepareLocalState,
                performExternalWrite: performExternalWrite,
                externalResourceID: externalResourceID,
                persistLocalState: persistLocalState
            )
        }
    }

    private func executeClaimed<ExternalResult>(
        _ prepared: ExternalSideEffectRecord,
        request: ExternalSideEffectRequest,
        at: Date,
        prepareLocalState: () throws -> Void,
        performExternalWrite: () throws -> ExternalResult,
        externalResourceID: (ExternalResult) -> String?,
        persistLocalState: (ExternalResult) throws -> ToolResult
    ) throws -> ToolResult {
        try journal.markStarted(id: prepared.id, at: at)
        do {
            try prepareLocalState()
        } catch {
            try journal.markFailedBeforeSideEffect(
                id: prepared.id,
                failureCategory: "local_preparation_failed",
                at: at
            )
            throw error
        }
        let externalResult: ExternalResult
        do {
            externalResult = try performExternalWrite()
        } catch let error as ToolClientError {
            try journal.markFailedBeforeSideEffect(
                id: prepared.id,
                failureCategory: Self.failureCategory(for: error),
                at: at
            )
            throw error
        } catch {
            try? journal.markUnknown(
                id: prepared.id,
                externalResourceID: nil,
                failureCategory: "external_result_uncertain",
                at: at
            )
            throw ToolExecutionError.externalSideEffectRequiresReconciliation(
                failureEvidence(
                    prepared,
                    request: request,
                    externalResourceID: nil,
                    state: .unknown
                )
            )
        }

        let resourceID = externalResourceID(externalResult)
        let persistedResult: ToolResult
        do {
            persistedResult = try persistLocalState(externalResult)
        } catch {
            // The external write has already returned success. Treat any local
            // persistence failure as uncertain so a retry cannot duplicate it.
            try? journal.markUnknown(
                id: prepared.id,
                externalResourceID: resourceID,
                failureCategory: "local_persistence_failed_after_external_success",
                at: at
            )
            throw ToolExecutionError.externalSideEffectRequiresReconciliation(
                failureEvidence(
                    prepared,
                    request: request,
                    externalResourceID: resourceID,
                    state: .unknown
                )
            )
        }

        var result = persistedResult
        result.output["idempotencyKey"] = .string(request.idempotencyKey)
        result.output["journalRecordId"] = .string(prepared.id)
        result.output["journalState"] = .string(ExternalSideEffectState.succeeded.rawValue)
        if let resourceID {
            result.output["externalResourceId"] = .string(resourceID)
        }
        do {
            try journal.markSucceeded(
                id: prepared.id,
                externalResourceID: resourceID,
                result: result,
                at: at
            )
        } catch {
            try? journal.markUnknown(
                id: prepared.id,
                externalResourceID: resourceID,
                failureCategory: "journal_commit_failed_after_external_success",
                at: at
            )
            throw ToolExecutionError.externalSideEffectRequiresReconciliation(
                failureEvidence(
                    prepared,
                    request: request,
                    externalResourceID: resourceID,
                    state: .unknown
                )
            )
        }
        return result
    }

    private func failureEvidence(
        _ prepared: ExternalSideEffectRecord,
        request: ExternalSideEffectRequest,
        externalResourceID: String?,
        state: ExternalSideEffectState
    ) -> ExternalSideEffectFailureEvidence {
        ExternalSideEffectFailureEvidence(
            tool: request.tool,
            idempotencyKey: request.idempotencyKey,
            journalRecordID: prepared.id,
            externalResourceID: externalResourceID,
            state: state
        )
    }

    private static func failureCategory(for error: ToolClientError) -> String {
        switch error {
        case .permissionDenied:
            "permission_denied"
        case .invalidRequest:
            "invalid_request"
        case .notFound:
            "not_found"
        case .conflict:
            "conflict_before_side_effect"
        }
    }
}
