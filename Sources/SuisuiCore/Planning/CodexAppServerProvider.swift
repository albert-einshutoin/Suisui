import Foundation

public protocol CodexPlanningPrerequisiteProviding: Sendable {
    func readAccount(refresh: Bool) async throws -> CodexAccountSnapshot
    func listModels() async throws -> [CodexModel]
}

extension CodexAppServerAccountClient: CodexPlanningPrerequisiteProviding {}

public struct CodexAppServerProviderConfiguration: Equatable, Sendable {
    public let modelID: String?
    public let scratchDirectory: URL
    public let turnTimeout: TimeInterval

    public init(modelID: String?, scratchDirectory: URL, turnTimeout: TimeInterval = 120) {
        self.modelID = modelID
        self.scratchDirectory = scratchDirectory
        self.turnTimeout = turnTimeout
    }
}

public struct CodexAppServerProvider: StreamingLLMProvider {
    public let providerID = "codex.local"

    private let transport: any CodexAppServerTransport
    private let prerequisites: any CodexPlanningPrerequisiteProviding
    private let configuration: CodexAppServerProviderConfiguration
    private let promptBuilder: PlanningPromptBuilder?
    private let responseParser: ActionPlanResponseParser

    public init(
        transport: any CodexAppServerTransport,
        prerequisites: any CodexPlanningPrerequisiteProviding,
        configuration: CodexAppServerProviderConfiguration,
        promptBuilder: PlanningPromptBuilder? = nil,
        responseParser: ActionPlanResponseParser = ActionPlanResponseParser()
    ) {
        self.transport = transport
        self.prerequisites = prerequisites
        self.configuration = configuration
        self.promptBuilder = promptBuilder
        self.responseParser = responseParser
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        try await generatePlanStream(for: request, onTextDelta: { _ in })
    }

    public func generatePlanStream(
        for request: PlanningRequest,
        onTextDelta: @escaping @Sendable (String) -> Void
    ) async throws -> PlanningResponse {
        try await validateAccount()
        let modelID = try await selectedModelID()
        let prompt = try (promptBuilder ?? PlanningPromptBuilder.loadDefault()).buildPrompt(for: request)
        let scratchPath = try validatedScratchPath()
        let events = await transport.notifications()

        let threadResponse = try await transport.request(
            method: CodexAppServerMethod.threadStart,
            params: .object([
                "model": .string(modelID),
                "cwd": .string(scratchPath),
                "ephemeral": .bool(true),
                "sandbox": .string("read-only"),
                "approvalPolicy": .string("never"),
                "baseInstructions": .string(prompt.system)
            ]),
            timeout: 15
        )
        let threadID = try nestedString(threadResponse.result, path: ["thread", "id"])
        let turnResponse = try await transport.request(
            method: CodexAppServerMethod.turnStart,
            params: .object([
                "threadId": .string(threadID),
                "approvalPolicy": .string("never"),
                "input": .array([
                    .object(["type": .string("text"), "text": .string(prompt.user)])
                ])
            ]),
            timeout: 15
        )
        let turnID = try nestedString(turnResponse.result, path: ["turn", "id"])

        let rawContent: String
        do {
            rawContent = try await collectTurn(
                events: events,
                threadID: threadID,
                turnID: turnID,
                onTextDelta: onTextDelta
            )
        } catch {
            try? await interrupt(threadID: threadID, turnID: turnID)
            throw error
        }
        return responseParser.parse(
            rawContent: rawContent,
            providerID: providerID,
            model: ExecutionReceiptModel(provider: providerID, name: modelID)
        )
    }

    private func validateAccount() async throws {
        let snapshot = try await prerequisites.readAccount(refresh: false)
        switch snapshot.readiness {
        case .ready:
            return
        case .usageLimited:
            throw LLMProviderError.rateLimited
        case .signedOut, .authenticating:
            throw LLMProviderError.authenticationFailed
        case .workspaceDisabled:
            throw LLMProviderError.executionNotApproved("Codex is disabled by the workspace administrator.")
        case .notInstalled, .unsupportedVersion, .unavailable:
            throw LLMProviderError.network("Codex local account is unavailable.")
        }
    }

    private func selectedModelID() async throws -> String {
        let models = try await prerequisites.listModels().filter { !$0.id.isEmpty }
        if let requested = configuration.modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requested.isEmpty {
            guard models.contains(where: { $0.id == requested }) else {
                throw LLMProviderError.invalidResponse("The selected Codex model is unavailable.")
            }
            return requested
        }
        guard let selected = models.first(where: \.isDefault) ?? models.first else {
            throw LLMProviderError.invalidResponse("Codex returned no available models.")
        }
        return selected.id
    }

    private func validatedScratchPath() throws -> String {
        let path = configuration.scratchDirectory.standardizedFileURL.path
        guard configuration.scratchDirectory.isFileURL, path.hasPrefix("/") else {
            throw LLMProviderError.executionNotApproved("Codex scratch directory must be an absolute local path.")
        }
        return path
    }

    private func collectTurn(
        events: AsyncStream<CodexJSONRPCNotification>,
        threadID: String,
        turnID: String,
        onTextDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await collectTurnEvents(
                    events: events,
                    transport: transport,
                    threadID: threadID,
                    turnID: turnID,
                    onTextDelta: onTextDelta
                )
            }
            group.addTask {
                let nanoseconds = UInt64(max(0, configuration.turnTimeout) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw LLMProviderError.network("Codex planning turn timed out.")
            }
            guard let result = try await group.next() else {
                throw LLMProviderError.network("Codex planning event stream closed.")
            }
            group.cancelAll()
            return result
        }
    }

    private func interrupt(threadID: String, turnID: String) async throws {
        try await transport.notify(
            method: CodexAppServerMethod.turnInterrupt,
            params: .object(["threadId": .string(threadID), "turnId": .string(turnID)])
        )
    }

    private func nestedString(_ value: JSONValue, path: [String]) throws -> String {
        var current = value
        for component in path {
            guard case let .object(object) = current, let next = object[component] else {
                throw LLMProviderError.invalidResponse("Codex App Server response is missing \(path.joined(separator: ".")).")
            }
            current = next
        }
        guard case let .string(result) = current, !result.isEmpty else {
            throw LLMProviderError.invalidResponse("Codex App Server returned an invalid identifier.")
        }
        return result
    }
}

private func collectTurnEvents(
    events: AsyncStream<CodexJSONRPCNotification>,
    transport: any CodexAppServerTransport,
    threadID: String,
    turnID: String,
    onTextDelta: @escaping @Sendable (String) -> Void
) async throws -> String {
    let forbiddenItemTypes: Set<String> = [
        "commandExecution", "fileChange", "webSearch", "mcpToolCall", "dynamicToolCall"
    ]
    var finalText = ""

    for await event in events {
        if event.isServerRequest,
           [CodexAppServerMethod.commandExecutionRequestApproval,
            CodexAppServerMethod.fileChangeRequestApproval,
            CodexAppServerMethod.permissionsRequestApproval].contains(event.method) {
            if let id = event.id,
               event.method != CodexAppServerMethod.permissionsRequestApproval {
                try? await transport.respond(id: id, result: .object(["decision": .string("cancel")]))
            }
            throw LLMProviderError.executionNotApproved("Codex requested a forbidden local tool operation.")
        }

        guard eventMatches(event.params, threadID: threadID, turnID: turnID) else { continue }
        let params = event.params?.providerObjectValue
        let item = params?["item"]?.providerObjectValue
        if let itemType = item?.providerStringValue(for: "type"), forbiddenItemTypes.contains(itemType) {
            throw LLMProviderError.executionNotApproved("Codex started a forbidden \(itemType) operation.")
        }

        switch event.method {
        case "item/agentMessage/delta":
            if let delta = params?.providerStringValue(for: "delta") {
                finalText += delta
                onTextDelta(delta)
            }
        case "item/completed":
            if item?.providerStringValue(for: "type") == "agentMessage",
               let text = item?.providerStringValue(for: "text") {
                finalText = text
            }
        case "turn/completed":
            let status = params?["turn"]?.providerObjectValue?.providerStringValue(for: "status")
            guard status == nil || status == "completed" else {
                throw LLMProviderError.network("Codex planning turn failed.")
            }
            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMProviderError.invalidResponse("Codex returned no Action Plan content.")
            }
            return finalText
        default:
            continue
        }
    }
    throw LLMProviderError.network("Codex planning event stream closed.")
}

private func eventMatches(_ params: JSONValue?, threadID: String, turnID: String) -> Bool {
    guard let object = params?.providerObjectValue else { return true }
    if let eventThreadID = object.providerStringValue(for: "threadId"), eventThreadID != threadID { return false }
    if let eventTurnID = object.providerStringValue(for: "turnId"), eventTurnID != turnID { return false }
    return true
}

private extension JSONValue {
    var providerObjectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func providerStringValue(for key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }
}
