import Foundation

public struct PlanningRequest: Equatable, Sendable {
    public var userInput: String
    public var currentDate: Date
    public var timeZoneIdentifier: String
    public var availableTools: [ActionTool]
    public var knowledgeFrameCandidates: [KnowledgeFrameCandidate]

    public init(
        userInput: String,
        currentDate: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier,
        availableTools: [ActionTool] = ActionTool.allCases,
        knowledgeFrameCandidates: [KnowledgeFrameCandidate] = []
    ) {
        self.userInput = userInput
        self.currentDate = currentDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.availableTools = availableTools
        self.knowledgeFrameCandidates = knowledgeFrameCandidates
    }
}

public struct KnowledgeFrameCandidate: Equatable, Sendable {
    public var id: String
    public var name: String
    public var triggers: [String]
    public var bodyPreview: String

    public init(id: String, name: String, triggers: [String], bodyPreview: String) {
        self.id = id
        self.name = name
        self.triggers = triggers
        self.bodyPreview = bodyPreview
    }
}

public struct PlanningPrompt: Equatable, Sendable {
    public var system: String
    public var user: String

    public init(system: String, user: String) {
        self.system = system
        self.user = user
    }
}

public struct PlanningResponse: Equatable, Sendable {
    public var providerID: String
    public var rawContent: String
    public var actionPlan: ActionPlan?
    public var validationResult: ActionPlanValidationResult

    public init(
        providerID: String,
        rawContent: String,
        actionPlan: ActionPlan?,
        validationResult: ActionPlanValidationResult
    ) {
        self.providerID = providerID
        self.rawContent = rawContent
        self.actionPlan = actionPlan
        self.validationResult = validationResult
    }
}

