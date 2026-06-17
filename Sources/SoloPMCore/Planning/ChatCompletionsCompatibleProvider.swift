import Foundation

public struct ChatCompletionsCompatibleConfiguration: Equatable, Sendable {
    public var providerID: String
    public var baseURL: URL
    public var model: String
    public var apiKeySecretKey: SecretKey?
    public var requiresAPIKey: Bool
    public var timeoutInterval: TimeInterval

    public init(
        providerID: String,
        baseURL: URL,
        model: String,
        apiKeySecretKey: SecretKey?,
        requiresAPIKey: Bool,
        timeoutInterval: TimeInterval = 60
    ) {
        self.providerID = providerID
        self.baseURL = baseURL
        self.model = model
        self.apiKeySecretKey = apiKeySecretKey
        self.requiresAPIKey = requiresAPIKey
        self.timeoutInterval = timeoutInterval
    }

    public static func openRouter(
        model: String,
        timeoutInterval: TimeInterval = 60
    ) -> ChatCompletionsCompatibleConfiguration {
        ChatCompletionsCompatibleConfiguration(
            providerID: "openrouter.chat",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            model: model,
            apiKeySecretKey: .openRouterAPIKey,
            requiresAPIKey: true,
            timeoutInterval: timeoutInterval
        )
    }

    public static func ollama(
        model: String,
        baseURL: URL = URL(string: "http://localhost:11434/v1")!,
        timeoutInterval: TimeInterval = 60
    ) -> ChatCompletionsCompatibleConfiguration {
        ChatCompletionsCompatibleConfiguration(
            providerID: "ollama.chat",
            baseURL: baseURL,
            model: model,
            apiKeySecretKey: nil,
            requiresAPIKey: false,
            timeoutInterval: timeoutInterval
        )
    }
}

public struct ChatCompletionsCompatibleRequestBuilder: Sendable {
    private let configuration: ChatCompletionsCompatibleConfiguration

    public init(configuration: ChatCompletionsCompatibleConfiguration) {
        self.configuration = configuration
    }

    public func makeRequest(apiKey: String?, prompt: PlanningPrompt) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url, timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatCompletionsRequestBody(
            model: configuration.model,
            messages: [
                ChatCompletionsMessage(role: "system", content: prompt.system),
                ChatCompletionsMessage(role: "user", content: prompt.user)
            ],
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        return request
    }
}

public struct ChatCompletionsOutputTextExtractor: Sendable {
    public init() {}

    public func extractText(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(ChatCompletionsResponseBody.self, from: data)
        let content = response.choices
            .compactMap(\.message.content)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            throw LLMProviderError.invalidResponse("Chat completion did not contain message content.")
        }

        return content
    }
}

public struct ChatCompletionsCompatibleProvider: LLMProvider {
    public var providerID: String {
        configuration.providerID
    }

    private let configuration: ChatCompletionsCompatibleConfiguration
    private let secretStore: any SecretStore
    private let httpClient: any HTTPDataClient
    private let promptBuilder: PlanningPromptBuilder
    private let requestBuilder: ChatCompletionsCompatibleRequestBuilder
    private let outputTextExtractor: ChatCompletionsOutputTextExtractor
    private let responseParser: ActionPlanResponseParser

    public init(
        configuration: ChatCompletionsCompatibleConfiguration,
        secretStore: any SecretStore = InMemorySecretStore(),
        httpClient: any HTTPDataClient = URLSessionHTTPDataClient(),
        promptBuilder: PlanningPromptBuilder = PlanningPromptBuilder(),
        outputTextExtractor: ChatCompletionsOutputTextExtractor = ChatCompletionsOutputTextExtractor(),
        responseParser: ActionPlanResponseParser = ActionPlanResponseParser()
    ) {
        self.configuration = configuration
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.promptBuilder = promptBuilder
        self.requestBuilder = ChatCompletionsCompatibleRequestBuilder(configuration: configuration)
        self.outputTextExtractor = outputTextExtractor
        self.responseParser = responseParser
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        let apiKey = try readAPIKey()
        let prompt = promptBuilder.buildPrompt(for: request)
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

    private func readAPIKey() throws -> String? {
        guard let apiKeySecretKey = configuration.apiKeySecretKey else {
            return nil
        }

        let apiKey = try secretStore.read(apiKeySecretKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if configuration.requiresAPIKey && (apiKey?.isEmpty ?? true) {
            throw LLMProviderError.authenticationFailed
        }

        return apiKey
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> LLMProviderError {
        switch statusCode {
        case 401, 403:
            .authenticationFailed
        case 429:
            .rateLimited
        default:
            .network("HTTP \(statusCode): \(errorMessage(from: data) ?? "No error message.")")
        }
    }

    private func errorMessage(from data: Data) -> String? {
        guard let errorBody = try? JSONDecoder().decode(ChatCompletionsErrorResponseBody.self, from: data) else {
            return nil
        }

        return errorBody.error.message
    }
}

private struct ChatCompletionsRequestBody: Encodable {
    var model: String
    var messages: [ChatCompletionsMessage]
    var stream: Bool
}

private struct ChatCompletionsMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionsResponseBody: Decodable {
    var choices: [ChatCompletionsChoice]
}

private struct ChatCompletionsChoice: Decodable {
    var message: ChatCompletionsMessage
}

private struct ChatCompletionsErrorResponseBody: Decodable {
    var error: ChatCompletionsErrorBody
}

private struct ChatCompletionsErrorBody: Decodable {
    var message: String
}
