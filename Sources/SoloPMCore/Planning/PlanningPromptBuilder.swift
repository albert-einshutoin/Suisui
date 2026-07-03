import Foundation

public struct PlanningPromptBuilder: Sendable {
    private let actionPlanSchema: String

    public init(actionPlanSchema: String) {
        self.actionPlanSchema = actionPlanSchema
    }

    public static func loadDefault() throws -> PlanningPromptBuilder {
        PlanningPromptBuilder(actionPlanSchema: try ActionPlanSchema.loadString())
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

        let scopedSchema = scopedActionPlanSchema(availableTools: request.availableTools)
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
        \(scopedSchema)
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

    private func scopedActionPlanSchema(availableTools: [ActionTool]) -> String {
        guard let schemaData = actionPlanSchema.data(using: .utf8),
              var schemaObject = try? JSONSerialization.jsonObject(with: schemaData) as? [String: Any],
              var definitions = schemaObject["$defs"] as? [String: Any],
              var toolDefinition = definitions["tool"] as? [String: Any],
              toolDefinition["enum"] != nil else {
            return actionPlanSchema
        }

        // The packaged schema documents every tool, but the prompt must describe
        // only the tools allowed for this request so developer mode tools do not
        // leak into ordinary personal planning.
        toolDefinition["enum"] = availableTools.map(\.rawValue).sorted()
        definitions["tool"] = toolDefinition
        schemaObject["$defs"] = definitions

        guard JSONSerialization.isValidJSONObject(schemaObject),
              let scopedData = try? JSONSerialization.data(withJSONObject: schemaObject, options: [.prettyPrinted, .sortedKeys]),
              let scopedSchema = String(data: scopedData, encoding: .utf8) else {
            return actionPlanSchema
        }
        return scopedSchema
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
