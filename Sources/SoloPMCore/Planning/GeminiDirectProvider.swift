import Foundation

public struct GeminiDirectConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var maxOutputTokens: Int
    public var timeoutInterval: TimeInterval

    public init(
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        model: String = "gemini-3.5-flash",
        maxOutputTokens: Int = 16_000,
        timeoutInterval: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.timeoutInterval = timeoutInterval
    }
}

public struct GeminiDirectRequestBuilder: Sendable {
    private let configuration: GeminiDirectConfiguration

    public init(configuration: GeminiDirectConfiguration = GeminiDirectConfiguration()) {
        self.configuration = configuration
    }

    public func makeRequest(
        apiKey: String,
        prompt: PlanningPrompt,
        availableTools: [ActionTool] = []
    ) throws -> URLRequest {
        var request = URLRequest(url: makeURL(), timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let functionDeclarations = GeminiDirectFunctionDeclarationCatalog.declarations(for: availableTools)
        let body = GeminiDirectRequestBody(
            systemInstruction: GeminiDirectContent(parts: [GeminiDirectPart(text: prompt.system)]),
            contents: [
                GeminiDirectContent(role: "user", parts: [GeminiDirectPart(text: prompt.user)])
            ],
            generationConfig: GeminiDirectGenerationConfig(
                maxOutputTokens: configuration.maxOutputTokens,
                responseMimeType: functionDeclarations.isEmpty ? "application/json" : nil
            ),
            tools: functionDeclarations.isEmpty
                ? nil
                : [GeminiDirectTool(functionDeclarations: functionDeclarations)],
            toolConfig: functionDeclarations.isEmpty
                ? nil
                : GeminiDirectToolConfig(
                    functionCallingConfig: GeminiDirectFunctionCallingConfig(
                        mode: "ANY",
                        allowedFunctionNames: functionDeclarations.map(\.name)
                    )
                )
        )
        request.httpBody = try JSONEncoder().encode(body)

        return request
    }

    private func makeURL() -> URL {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var allowedModelCharacters = CharacterSet.urlPathAllowed
        allowedModelCharacters.remove(charactersIn: "/:")
        let model = configuration.model.addingPercentEncoding(withAllowedCharacters: allowedModelCharacters)
            ?? configuration.model
        components.percentEncodedPath = "/\(basePath)/models/\(model):generateContent"
        return components.url!
    }
}

public struct GeminiDirectOutputTextExtractor: Sendable {
    public init() {}

    public func extractPlanningContent(from data: Data, request: PlanningRequest) throws -> String {
        let response = try decodeResponse(from: data)
        try validateSafety(response)

        var textParts: [String] = []
        var functionCalls: [GeminiDirectFunctionCall] = []
        for candidate in try candidates(from: response) {
            guard let parts = candidate.content?.parts else {
                throw LLMProviderError.invalidResponse("Gemini Direct candidate did not contain content parts.")
            }
            for part in parts {
                if let functionCall = part.functionCall {
                    functionCalls.append(functionCall)
                }
                if let text = part.text {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw LLMProviderError.invalidResponse("Gemini Direct text content part was empty.")
                    }
                    textParts.append(text)
                }
            }
        }

        if !functionCalls.isEmpty {
            return try GeminiDirectFunctionCallActionPlanMapper().rawActionPlan(
                from: functionCalls,
                request: request
            )
        }

        return try joinedTextContent(textParts)
    }

    public func extractText(from data: Data) throws -> String {
        let response = try decodeResponse(from: data)
        try validateSafety(response)

        var textParts: [String] = []
        for candidate in try candidates(from: response) {
            guard let parts = candidate.content?.parts else {
                throw LLMProviderError.invalidResponse("Gemini Direct candidate did not contain content parts.")
            }
            for part in parts {
                guard let text = part.text else {
                    continue
                }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LLMProviderError.invalidResponse("Gemini Direct text content part was empty.")
                }
                textParts.append(text)
            }
        }

        return try joinedTextContent(textParts)
    }

    private func decodeResponse(from data: Data) throws -> GeminiDirectResponseBody {
        do {
            return try JSONDecoder().decode(GeminiDirectResponseBody.self, from: data)
        } catch {
            throw LLMProviderError.invalidResponse("Gemini Direct payload could not be decoded.")
        }
    }

    private func validateSafety(_ response: GeminiDirectResponseBody) throws {
        if let blockReason = response.promptFeedback?.blockReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !blockReason.isEmpty {
            throw LLMProviderError.invalidResponse("Gemini Direct blocked the prompt: \(blockReason).")
        }

        for candidate in response.candidates ?? [] where candidate.finishReason == "SAFETY" {
            throw LLMProviderError.invalidResponse("Gemini Direct blocked the response for safety.")
        }
    }

    private func candidates(from response: GeminiDirectResponseBody) throws -> [GeminiDirectCandidate] {
        guard let candidates = response.candidates, !candidates.isEmpty else {
            throw LLMProviderError.invalidResponse("Gemini Direct response did not contain candidates.")
        }
        return candidates
    }

    private func joinedTextContent(_ textParts: [String]) throws -> String {
        let outputText = textParts
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !outputText.isEmpty else {
            throw LLMProviderError.invalidResponse("Gemini Direct response did not contain text content.")
        }

        return outputText
    }
}

public struct GeminiDirectProvider: LLMProvider {
    public let providerID = "gemini.direct"

    private let secretStore: any SecretStore
    private let httpClient: any HTTPDataClient
    private let promptBuilder: PlanningPromptBuilder?
    private let requestBuilder: GeminiDirectRequestBuilder
    private let outputTextExtractor: GeminiDirectOutputTextExtractor
    private let responseParser: ActionPlanResponseParser

    public init(
        secretStore: any SecretStore,
        httpClient: any HTTPDataClient = URLSessionHTTPDataClient(),
        promptBuilder: PlanningPromptBuilder? = nil,
        configuration: GeminiDirectConfiguration = GeminiDirectConfiguration(),
        outputTextExtractor: GeminiDirectOutputTextExtractor = GeminiDirectOutputTextExtractor(),
        responseParser: ActionPlanResponseParser = ActionPlanResponseParser()
    ) {
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.promptBuilder = promptBuilder
        self.requestBuilder = GeminiDirectRequestBuilder(configuration: configuration)
        self.outputTextExtractor = outputTextExtractor
        self.responseParser = responseParser
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        let apiKey: String
        let storedAPIKey = try secretStore.read(.geminiAPIKey)
        do {
            apiKey = try APIKeyValidator.normalize(storedAPIKey)
        } catch APIKeyValidationError.empty, APIKeyValidationError.containsWhitespace {
            throw LLMProviderError.authenticationFailed
        }

        let prompt = try (promptBuilder ?? PlanningPromptBuilder.loadDefault()).buildPrompt(for: request)
        let httpRequest = try requestBuilder.makeRequest(
            apiKey: apiKey,
            prompt: prompt,
            availableTools: request.availableTools
        )
        let data: Data
        let response: HTTPURLResponse

        do {
            (data, response) = try await httpClient.data(for: httpRequest)
        } catch let error as LLMProviderError {
            throw error
        } catch {
            throw LLMProviderError.network(ProviderErrorMessageSanitizer.message(from: error))
        }

        guard (200..<300).contains(response.statusCode) else {
            throw mapHTTPError(statusCode: response.statusCode, data: data)
        }

        let rawContent = try outputTextExtractor.extractPlanningContent(from: data, request: request)
        return responseParser.parse(rawContent: rawContent, providerID: providerID)
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> LLMProviderError {
        switch statusCode {
        case 401, 403:
            .authenticationFailed
        case 400 where isAPIKeyError(data: data):
            .authenticationFailed
        case 429:
            .rateLimited
        default:
            .network("Gemini Direct HTTP \(statusCode): \(LLMHTTPErrorMessageExtractor.message(from: data) ?? "Empty error body.")")
        }
    }

    private func isAPIKeyError(data: Data) -> Bool {
        LLMHTTPErrorMessageExtractor.message(from: data)?
            .localizedCaseInsensitiveContains("api key") == true
    }
}

private struct GeminiDirectRequestBody: Encodable {
    var systemInstruction: GeminiDirectContent
    var contents: [GeminiDirectContent]
    var generationConfig: GeminiDirectGenerationConfig
    var tools: [GeminiDirectTool]?
    var toolConfig: GeminiDirectToolConfig?

    private enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig
        case tools
        case toolConfig
    }
}

private struct GeminiDirectContent: Codable {
    var role: String?
    var parts: [GeminiDirectPart]
}

private struct GeminiDirectPart: Codable {
    var text: String?
    var functionCall: GeminiDirectFunctionCall?
}

private struct GeminiDirectGenerationConfig: Encodable {
    var maxOutputTokens: Int
    var responseMimeType: String?
}

private struct GeminiDirectResponseBody: Decodable {
    var promptFeedback: GeminiDirectPromptFeedback?
    var candidates: [GeminiDirectCandidate]?
}

private struct GeminiDirectPromptFeedback: Decodable {
    var blockReason: String?
}

private struct GeminiDirectCandidate: Decodable {
    var content: GeminiDirectContent?
    var finishReason: String?
}

private struct GeminiDirectFunctionCall: Codable {
    var id: String?
    var name: String
    var args: [String: JSONValue]?
}

private struct GeminiDirectTool: Encodable {
    var functionDeclarations: [GeminiDirectFunctionDeclaration]
}

private struct GeminiDirectToolConfig: Encodable {
    var functionCallingConfig: GeminiDirectFunctionCallingConfig
}

private struct GeminiDirectFunctionCallingConfig: Encodable {
    var mode: String
    var allowedFunctionNames: [String]
}

private struct GeminiDirectFunctionDeclaration: Encodable {
    var name: String
    var description: String
    var parameters: GeminiDirectSchema
}

private final class GeminiDirectSchema: Encodable {
    var type: String
    var description: String?
    var properties: [String: GeminiDirectSchema]?
    var items: GeminiDirectSchema?
    var required: [String]?

    init(
        type: String,
        description: String? = nil,
        properties: [String: GeminiDirectSchema]? = nil,
        items: GeminiDirectSchema? = nil,
        required: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.items = items
        self.required = required
    }
}

private enum GeminiDirectFunctionDeclarationCatalog {
    static func declarations(for tools: [ActionTool]) -> [GeminiDirectFunctionDeclaration] {
        let requestedTools = Set(tools)
        return supportedTools
            .filter { requestedTools.contains($0) }
            .map(declaration)
    }

    static func actionTool(named functionName: String, availableTools: [ActionTool]) -> ActionTool? {
        availableTools.first { tool in
            supportedTools.contains(tool) && self.functionName(for: tool) == functionName
        }
    }

    static func functionName(for tool: ActionTool) -> String {
        tool.rawValue
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    private static let supportedTools: [ActionTool] = [.taskCreate, .taskBulkCreate, .taskUpdate, .taskComplete]

    private static func declaration(for tool: ActionTool) -> GeminiDirectFunctionDeclaration {
        switch tool {
        case .taskCreate:
            GeminiDirectFunctionDeclaration(
                name: functionName(for: tool),
                description: "Create one local SoloPM task. SoloPM will require local user approval before writing.",
                parameters: GeminiDirectSchema(
                    type: "object",
                    properties: taskProperties(),
                    required: ["title"]
                )
            )
        case .taskBulkCreate:
            GeminiDirectFunctionDeclaration(
                name: functionName(for: tool),
                description: "Create multiple local SoloPM tasks. SoloPM will require local user approval before writing.",
                parameters: GeminiDirectSchema(
                    type: "object",
                    properties: [
                        "tasks": GeminiDirectSchema(
                            type: "array",
                            description: "Tasks to create.",
                            items: GeminiDirectSchema(
                                type: "object",
                                properties: taskProperties(),
                                required: ["title"]
                            )
                        )
                    ],
                    required: ["tasks"]
                )
            )
        case .taskUpdate:
            GeminiDirectFunctionDeclaration(
                name: functionName(for: tool),
                description: "Update one local SoloPM task, including status, project, due date, detail, title, or priority. SoloPM will require local user approval before writing.",
                parameters: GeminiDirectSchema(
                    type: "object",
                    properties: taskUpdateProperties(),
                    required: ["id"]
                )
            )
        case .taskComplete:
            GeminiDirectFunctionDeclaration(
                name: functionName(for: tool),
                description: "Mark one local SoloPM task as completed. SoloPM will require local user approval before writing.",
                parameters: GeminiDirectSchema(
                    type: "object",
                    properties: [
                        "id": GeminiDirectSchema(type: "integer", description: "Required local SoloPM task id.")
                    ],
                    required: ["id"]
                )
            )
        default:
            preconditionFailure("Unsupported Gemini Direct function declaration.")
        }
    }

    private static func taskProperties() -> [String: GeminiDirectSchema] {
        [
            "title": GeminiDirectSchema(type: "string", description: "Required task title."),
            "projectId": GeminiDirectSchema(type: "integer", description: "Optional local SoloPM project id."),
            "detail": GeminiDirectSchema(type: "string", description: "Optional task detail."),
            "dueAt": GeminiDirectSchema(type: "string", description: "Optional ISO-8601 due date or timestamp."),
            "priority": GeminiDirectSchema(type: "string", description: "Optional priority label."),
            "sourceCommand": GeminiDirectSchema(type: "string", description: "Optional original user command.")
        ]
    }

    private static func taskUpdateProperties() -> [String: GeminiDirectSchema] {
        [
            "id": GeminiDirectSchema(type: "integer", description: "Required local SoloPM task id."),
            "title": GeminiDirectSchema(type: "string", description: "Optional replacement task title."),
            "projectId": GeminiDirectSchema(type: "integer", description: "Optional local SoloPM project id to move the task into."),
            "status": GeminiDirectSchema(type: "string", description: "Optional task status: open, backlog, planned, in_progress, blocked, or completed."),
            "detail": GeminiDirectSchema(type: "string", description: "Optional task detail."),
            "dueAt": GeminiDirectSchema(type: "string", description: "Optional ISO-8601 due date or timestamp."),
            "priority": GeminiDirectSchema(type: "string", description: "Optional priority label.")
        ]
    }
}

private struct GeminiDirectFunctionCallActionPlanMapper {
    private let validator = ActionPlanValidator()

    func rawActionPlan(from functionCalls: [GeminiDirectFunctionCall], request: PlanningRequest) throws -> String {
        let actions = try functionCalls.enumerated().map { index, call in
            try action(from: call, index: index, request: request)
        }
        let highestRisk = actions.map(\.riskLevel).max() ?? .read
        let plan = ActionPlan(
            id: "gemini-function-plan",
            userInput: request.userInput,
            summary: summary(for: actions),
            actions: actions,
            riskLevel: highestRisk,
            requiresApproval: actions.contains { $0.riskLevel >= .write }
        )

        let validationResult = validator.validate(plan)
        guard validationResult.isValid else {
            let message = validationResult.issues.map(\.message).joined(separator: " ")
            throw LLMProviderError.invalidResponse("Gemini Direct function call could not be converted to a valid ActionPlan: \(message)")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(plan)
        guard let rawContent = String(data: data, encoding: .utf8) else {
            throw LLMProviderError.invalidResponse("Gemini Direct function call ActionPlan was not UTF-8.")
        }
        return rawContent
    }

    private func action(
        from functionCall: GeminiDirectFunctionCall,
        index: Int,
        request: PlanningRequest
    ) throws -> PlanAction {
        guard let tool = GeminiDirectFunctionDeclarationCatalog.actionTool(
            named: functionCall.name,
            availableTools: request.availableTools
        ) else {
            throw LLMProviderError.invalidResponse("Gemini Direct requested unsupported function '\(functionCall.name)'.")
        }

        // Provider-native function calls are only planning intents here; SoloPM keeps writes behind the existing review approval path.
        return PlanAction(
            id: nonBlank(functionCall.id) ?? "function-call-\(index + 1)",
            tool: tool,
            arguments: functionCall.args ?? [:],
            riskLevel: tool.defaultRiskLevel,
            requiresUserConfirmation: false
        )
    }

    private func summary(for actions: [PlanAction]) -> String {
        if actions.count == 1,
           actions[0].tool == .taskCreate,
           case .string(let title)? = actions[0].arguments["title"] {
            return "Create task: \(title)"
        }
        return "Prepare \(actions.count) SoloPM task action\(actions.count == 1 ? "" : "s") from Gemini function call."
    }

    private func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
