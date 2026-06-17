import Foundation

public struct PlanningPromptBuilder: Sendable {
    private let actionPlanSchema: String

    public init(actionPlanSchema: String? = nil) {
        self.actionPlanSchema = actionPlanSchema
            ?? (try? ActionPlanSchema.loadString())
            ?? ActionPlanSchema.fallbackPromptContract
    }

    public func buildPrompt(for request: PlanningRequest) -> PlanningPrompt {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let tools = request.availableTools
            .map(\.rawValue)
            .sorted()
            .map { "- \($0)" }
            .joined(separator: "\n")

        let frames = request.knowledgeFrameCandidates.isEmpty
            ? "No Knowledge Frame candidates."
            : request.knowledgeFrameCandidates.map(formatFrame).joined(separator: "\n\n")

        let system = """
        You are SoloPM's planning engine.
        Convert the user's input into a strict ActionPlan JSON object.
        Do not execute tools.
        Do not invent tools outside the available tool list.
        Do not create dangerous actions.
        Dangerous operations are forbidden in the MVP: email send, Slack auto-post, file delete, file overwrite, Git push, Calendar deletion, Reminder deletion.
        Write actions must set requiresApproval to true.
        Ambiguous dates or destinations must set requiresUserConfirmation on the affected action.
        Return JSON only.

        ActionPlan JSON Schema:
        \(actionPlanSchema)
        """

        let user = """
        Current date: \(dateFormatter.string(from: request.currentDate))
        Time zone: \(request.timeZoneIdentifier)

        Available tools:
        \(tools)

        Knowledge Frame candidates:
        \(frames)

        User input:
        \(request.userInput)
        """

        return PlanningPrompt(system: system, user: user)
    }

    private func formatFrame(_ frame: KnowledgeFrameCandidate) -> String {
        """
        - id: \(frame.id)
          name: \(frame.name)
          triggers: \(frame.triggers.joined(separator: ", "))
          preview: \(frame.bodyPreview)
        """
    }
}
