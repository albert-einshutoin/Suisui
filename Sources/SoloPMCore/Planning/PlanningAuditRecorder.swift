import Foundation

public struct PlanningAuditRecorder: Sendable {
    private let logger: any AuditLogger

    public init(logger: any AuditLogger) {
        self.logger = logger
    }

    public func recordStarted(input: String, providerID: String) throws {
        try logger.record(
            AuditEvent(
                category: "planning",
                action: "generate_plan",
                status: .started,
                metadata: [
                    "provider": providerID,
                    "input_summary": summarize(input)
                ]
            )
        )
    }

    public func recordCompleted(response: PlanningResponse) throws {
        try logger.record(
            AuditEvent(
                category: "planning",
                action: "generate_plan",
                status: response.validationResult.isValid ? .succeeded : .failed,
                metadata: [
                    "provider": response.providerID,
                    "plan_id": response.actionPlan?.id ?? "",
                    "summary": response.actionPlan?.summary ?? "",
                    "validation": response.validationResult.isValid ? "valid" : "invalid",
                    "issue_count": String(response.validationResult.issues.count)
                ]
            )
        )
    }

    public func recordFailed(input: String, providerID: String, error: Error) throws {
        try logger.record(
            AuditEvent(
                category: "planning",
                action: "generate_plan",
                status: .failed,
                metadata: [
                    "provider": providerID,
                    "input_summary": summarize(input),
                    "error": String(describing: error)
                ]
            )
        )
    }

    private func summarize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 160 else {
            return trimmed
        }

        return "\(trimmed.prefix(157))..."
    }
}
