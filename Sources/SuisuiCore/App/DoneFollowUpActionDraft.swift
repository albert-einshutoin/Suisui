import CryptoKit
import Foundation

public struct DoneFollowUpActionDraft: Equatable, Sendable {
    public var id: String
    public var actionPlan: ActionPlan
    public var queueReason: String

    public init(id: String, actionPlan: ActionPlan, queueReason: String) {
        self.id = id
        self.actionPlan = actionPlan
        self.queueReason = queueReason
    }
}

public enum DoneFollowUpActionDraftBuilder {
    public static func makeDraft(
        task: ProjectBoardTask?,
        projectTitle: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DoneFollowUpActionDraft? {
        guard let task, task.completedAt != nil || task.status == .done else {
            return nil
        }

        let redactor = ExecutionReceiptRedactor()
        let taskTitle = redactedDisplayText(task.title, fallback: "completed task", redactor: redactor)
        let sourceProjectTitle = redactedDisplayText(projectTitle, fallback: "source project", redactor: redactor)
        let draftID = "done-follow-up:\(dateKey(for: referenceDate, calendar: calendar)):\(contentDigest(for: task, projectTitle: projectTitle)):task:\(task.id)"
        let action = PlanAction(
            id: "\(draftID):create",
            tool: .taskCreate,
            arguments: taskCreateArguments(
                task: task,
                taskTitle: taskTitle,
                sourceProjectTitle: sourceProjectTitle,
                redactor: redactor
            ),
            riskLevel: .write
        )

        return DoneFollowUpActionDraft(
            id: draftID,
            actionPlan: ActionPlan(
                id: draftID,
                userInput: "Queue Done follow-up for \(taskTitle)",
                summary: "Create a reviewable follow-up from Done history for \(taskTitle).",
                actions: [action],
                riskLevel: .write,
                requiresApproval: true
            ),
            queueReason: "Done suggested a reviewable follow-up for \(taskTitle)."
        )
    }

    private static func taskCreateArguments(
        task: ProjectBoardTask,
        taskTitle: String,
        sourceProjectTitle: String,
        redactor: ExecutionReceiptRedactor
    ) -> [String: JSONValue] {
        var arguments: [String: JSONValue] = [
            "title": .string("Follow up: \(taskTitle)"),
            "projectId": .number(Double(task.projectID)),
            "priority": .string(task.priority.rawValue),
            "sourceCommand": .string("Done follow-up from task \(task.id)"),
            "detail": .string(followUpDetail(
                task: task,
                sourceProjectTitle: sourceProjectTitle,
                redactor: redactor
            ))
        ]
        if let dueAt = trimmedOptional(task.dueAt) {
            arguments["dueAt"] = .string(redactor.redact(dueAt))
        }
        return arguments
    }

    private static func followUpDetail(
        task: ProjectBoardTask,
        sourceProjectTitle: String,
        redactor: ExecutionReceiptRedactor
    ) -> String {
        var parts = [
            "Reviewable follow-up generated from Done history.",
            "Source task ID: \(task.id).",
            "Source project: \(sourceProjectTitle)."
        ]
        if let completedAt = trimmedOptional(task.completedAt) {
            parts.append("Source completed at: \(redactor.redact(completedAt)).")
        }
        if let sourceDetail = trimmedOptional(task.detail) {
            // The detail is persisted in Assistant Queue JSON before execution,
            // so redact durable source context while preserving review intent.
            parts.append("Source detail: \(redactor.redact(sourceDetail, maxLength: 300))")
        }
        return parts.joined(separator: " ")
    }

    private static func redactedDisplayText(
        _ value: String,
        fallback: String,
        redactor: ExecutionReceiptRedactor
    ) -> String {
        let redacted = redactor.redact(value, maxLength: 180).trimmingCharacters(in: .whitespacesAndNewlines)
        return redacted.isEmpty ? fallback : redacted
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private static func contentDigest(for task: ProjectBoardTask, projectTitle: String) -> String {
        let content = [
            String(task.id),
            String(task.projectID),
            projectTitle,
            task.title,
            task.detail,
            task.priority.rawValue,
            task.dueAt ?? "",
            task.completedAt ?? ""
        ].joined(separator: "|")
        // Queue identity must change with the proposal content without leaking
        // task titles, notes, or project names into item IDs and logs.
        let digest = SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(16))
    }
}
