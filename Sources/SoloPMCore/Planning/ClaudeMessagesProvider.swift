import Foundation

public struct ClaudeMessagesConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var maxTokens: Int
    public var timeoutInterval: TimeInterval
    public var anthropicVersion: String

    public init(
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        model: String = "claude-opus-4-6",
        maxTokens: Int = 16_000,
        timeoutInterval: TimeInterval = 60,
        anthropicVersion: String = "2023-06-01"
    ) {
        self.baseURL = baseURL
        self.model = model
        self.maxTokens = maxTokens
        self.timeoutInterval = timeoutInterval
        self.anthropicVersion = anthropicVersion
    }
}

public struct ClaudeMessagesRequestBuilder: Sendable {
    private let configuration: ClaudeMessagesConfiguration

    public init(configuration: ClaudeMessagesConfiguration = ClaudeMessagesConfiguration()) {
        self.configuration = configuration
    }

    public func makeRequest(apiKey: String, prompt: PlanningPrompt) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent("messages")
        var request = URLRequest(url: url, timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(configuration.anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let body = ClaudeMessagesRequestBody(
            model: configuration.model,
            maxTokens: configuration.maxTokens,
            system: prompt.system,
            messages: [
                ClaudeMessagesRequestMessage(role: "user", content: prompt.user)
            ],
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        return request
    }
}

public struct ClaudeMessagesOutputTextExtractor: Sendable {
    public init() {}

    public func extractText(from data: Data) throws -> String {
        let response: ClaudeMessagesResponseBody
        do {
            response = try JSONDecoder().decode(ClaudeMessagesResponseBody.self, from: data)
        } catch {
            throw LLMProviderError.invalidResponse("Claude Messages payload could not be decoded.")
        }

        var textBlocks: [String] = []
        for block in response.content {
            guard block.type == "text" else {
                continue
            }
            guard let text = block.text else {
                throw LLMProviderError.invalidResponse("Claude Messages text content block did not contain text.")
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw LLMProviderError.invalidResponse("Claude Messages text content block was empty.")
            }
            textBlocks.append(text)
        }

        let outputText = textBlocks
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !outputText.isEmpty else {
            throw LLMProviderError.invalidResponse("Claude Messages response did not contain text content.")
        }

        return outputText
    }
}

public struct ClaudeMessagesProvider: LLMProvider {
    public let providerID = "claude.messages"

    private let secretStore: any SecretStore
    private let httpClient: any HTTPDataClient
    private let promptBuilder: PlanningPromptBuilder?
    private let requestBuilder: ClaudeMessagesRequestBuilder
    private let outputTextExtractor: ClaudeMessagesOutputTextExtractor
    private let responseParser: ActionPlanResponseParser

    public init(
        secretStore: any SecretStore,
        httpClient: any HTTPDataClient = URLSessionHTTPDataClient(),
        promptBuilder: PlanningPromptBuilder? = nil,
        configuration: ClaudeMessagesConfiguration = ClaudeMessagesConfiguration(),
        outputTextExtractor: ClaudeMessagesOutputTextExtractor = ClaudeMessagesOutputTextExtractor(),
        responseParser: ActionPlanResponseParser = ActionPlanResponseParser()
    ) {
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.promptBuilder = promptBuilder
        self.requestBuilder = ClaudeMessagesRequestBuilder(configuration: configuration)
        self.outputTextExtractor = outputTextExtractor
        self.responseParser = responseParser
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        let apiKey: String
        let storedAPIKey = try secretStore.read(.anthropicAPIKey)
        do {
            apiKey = try APIKeyValidator.normalize(storedAPIKey)
        } catch APIKeyValidationError.empty, APIKeyValidationError.containsWhitespace {
            throw LLMProviderError.authenticationFailed
        }

        let prompt = try (promptBuilder ?? PlanningPromptBuilder.loadDefault()).buildPrompt(for: request)
        let httpRequest = try requestBuilder.makeRequest(apiKey: apiKey, prompt: prompt)
        let data: Data
        let response: HTTPURLResponse

        do {
            (data, response) = try await httpClient.data(for: httpRequest)
        } catch let error as LLMProviderError {
            throw error
        } catch {
            throw LLMProviderError.network(error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw mapHTTPError(statusCode: response.statusCode, data: data)
        }

        let rawContent = try outputTextExtractor.extractText(from: data)
        return responseParser.parse(rawContent: rawContent, providerID: providerID)
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> LLMProviderError {
        switch statusCode {
        case 401, 403:
            .authenticationFailed
        case 429:
            .rateLimited
        default:
            .network("Claude Messages HTTP \(statusCode): \(LLMHTTPErrorMessageExtractor.message(from: data) ?? "Empty error body.")")
        }
    }
}

private struct ClaudeMessagesRequestBody: Encodable {
    var model: String
    var maxTokens: Int
    var system: String
    var messages: [ClaudeMessagesRequestMessage]
    var stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
    }
}

private struct ClaudeMessagesRequestMessage: Encodable {
    var role: String
    var content: String
}

private struct ClaudeMessagesResponseBody: Decodable {
    var content: [ClaudeMessagesResponseContentBlock]
}

private struct ClaudeMessagesResponseContentBlock: Decodable {
    var type: String
    var text: String?
}
