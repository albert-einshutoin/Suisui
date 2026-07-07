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

    public static func openAICompatible(
        model: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        timeoutInterval: TimeInterval = 60
    ) -> ChatCompletionsCompatibleConfiguration {
        ChatCompletionsCompatibleConfiguration(
            providerID: "openai.chat_completions",
            baseURL: baseURL,
            model: model,
            apiKeySecretKey: .openAIAPIKey,
            requiresAPIKey: true,
            timeoutInterval: timeoutInterval
        )
    }

    public static func groq(
        model: String,
        baseURL: URL = URL(string: "https://api.groq.com/openai/v1")!,
        timeoutInterval: TimeInterval = 60
    ) -> ChatCompletionsCompatibleConfiguration {
        ChatCompletionsCompatibleConfiguration(
            providerID: "groq.chat",
            baseURL: baseURL,
            model: model,
            apiKeySecretKey: .groqAPIKey,
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

    public func makeRequest(apiKey: String?, prompt: PlanningPrompt, stream: Bool = false) throws -> URLRequest {
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
            stream: stream
        )
        request.httpBody = try JSONEncoder().encode(body)

        return request
    }
}

public struct ChatCompletionsOutputTextExtractor: Sendable {
    public init() {}

    public func extractText(from data: Data) throws -> String {
        let response: ChatCompletionsResponseBody
        do {
            response = try JSONDecoder().decode(ChatCompletionsResponseBody.self, from: data)
        } catch {
            throw LLMProviderError.invalidResponse("Chat completion response could not be decoded.")
        }

        let contents = try response.choices.map { choice in
            let content = choice.message.content
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMProviderError.invalidResponse("Chat completion choice did not contain message content.")
            }
            return content
        }
        let content = contents
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            throw LLMProviderError.invalidResponse("Chat completion did not contain message content.")
        }

        return content
    }
}

public struct ChatCompletionsResponseMetadataExtractor: Sendable {
    public init() {}

    public func extractMetadata(
        from data: Data,
        providerID: String,
        fallbackModelName: String
    ) -> PlanningResponseMetadata {
        guard let response = try? JSONDecoder().decode(ChatCompletionsResponseBody.self, from: data) else {
            return PlanningResponseMetadata(
                model: redactedModel(providerID: providerID, name: fallbackModelName),
                usage: .unknown
            )
        }

        return PlanningResponseMetadata(
            model: redactedModel(providerID: providerID, name: response.model ?? fallbackModelName),
            usage: response.usage?.executionReceiptUsage ?? .unknown
        )
    }

    private func redactedModel(providerID: String, name: String) -> ExecutionReceiptModel {
        let provider = AssistantQueueCostPreview.redactedMetadataText(providerID)
        let model = AssistantQueueCostPreview.redactedMetadataText(name)
        return ExecutionReceiptModel(
            provider: provider.isEmpty ? "unknown" : provider,
            name: model.isEmpty ? "unknown" : model
        )
    }
}

public struct ChatCompletionsCompatibleProvider: StreamingLLMProvider {
    public var providerID: String {
        configuration.providerID
    }

    private let configuration: ChatCompletionsCompatibleConfiguration
    private let secretStore: any SecretStore
    private let httpClient: any HTTPDataClient
    private let byteStreamClient: any HTTPByteStreamClient
    private let promptBuilder: PlanningPromptBuilder?
    private let requestBuilder: ChatCompletionsCompatibleRequestBuilder
    private let outputTextExtractor: ChatCompletionsOutputTextExtractor
    private let metadataExtractor: ChatCompletionsResponseMetadataExtractor
    private let responseParser: ActionPlanResponseParser

    public init(
        configuration: ChatCompletionsCompatibleConfiguration,
        secretStore: any SecretStore,
        httpClient: any HTTPDataClient = URLSessionHTTPDataClient(),
        byteStreamClient: any HTTPByteStreamClient = URLSessionHTTPByteStreamClient(),
        promptBuilder: PlanningPromptBuilder? = nil,
        outputTextExtractor: ChatCompletionsOutputTextExtractor = ChatCompletionsOutputTextExtractor(),
        metadataExtractor: ChatCompletionsResponseMetadataExtractor = ChatCompletionsResponseMetadataExtractor(),
        responseParser: ActionPlanResponseParser = ActionPlanResponseParser()
    ) {
        self.configuration = configuration
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.byteStreamClient = byteStreamClient
        self.promptBuilder = promptBuilder
        self.requestBuilder = ChatCompletionsCompatibleRequestBuilder(configuration: configuration)
        self.outputTextExtractor = outputTextExtractor
        self.metadataExtractor = metadataExtractor
        self.responseParser = responseParser
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        let apiKey = try readAPIKey()
        let prompt = try (promptBuilder ?? PlanningPromptBuilder.loadDefault()).buildPrompt(for: request)
        let httpRequest = try requestBuilder.makeRequest(apiKey: apiKey, prompt: prompt)
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

        let rawContent = try outputTextExtractor.extractText(from: data)
        let metadata = metadataExtractor.extractMetadata(
            from: data,
            providerID: providerID,
            fallbackModelName: configuration.model
        )
        return responseParser.parse(
            rawContent: rawContent,
            providerID: providerID,
            model: metadata.model,
            usage: metadata.usage
        )
    }

    public func generatePlanStream(
        for request: PlanningRequest,
        onTextDelta: @escaping @Sendable (String) -> Void
    ) async throws -> PlanningResponse {
        let apiKey = try readAPIKey()
        let prompt = try (promptBuilder ?? PlanningPromptBuilder.loadDefault()).buildPrompt(for: request)
        let httpRequest = try requestBuilder.makeRequest(apiKey: apiKey, prompt: prompt, stream: true)

        let lines: AsyncThrowingStream<String, Error>
        let response: HTTPURLResponse
        do {
            (lines, response) = try await byteStreamClient.lines(for: httpRequest)
        } catch let error as LLMProviderError {
            throw error
        } catch {
            throw LLMProviderError.network(ProviderErrorMessageSanitizer.message(from: error))
        }

        guard (200..<300).contains(response.statusCode) else {
            let body = try await collectBody(from: lines)
            throw mapHTTPError(statusCode: response.statusCode, data: body)
        }

        var accumulated = ""
        do {
            deltaLoop: for try await line in lines {
                guard let payload = ChatCompletionsSSEParser.dataPayload(from: line) else {
                    continue
                }
                switch try ChatCompletionsSSEParser.parse(payload) {
                case .textDelta(let text):
                    accumulated += text
                    onTextDelta(text)
                case .error(let message):
                    throw LLMProviderError.invalidResponse(message)
                case .done:
                    break deltaLoop
                case .ignored:
                    continue
                }
            }
        } catch let error as LLMProviderError {
            throw error
        } catch {
            throw LLMProviderError.network(ProviderErrorMessageSanitizer.message(from: error))
        }

        let rawContent = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawContent.isEmpty else {
            throw LLMProviderError.invalidResponse("Chat completion stream did not contain text content.")
        }
        // Streaming chunks do not carry a reliable usage envelope, so the
        // receipt falls back to the configured model with unknown usage.
        let metadata = metadataExtractor.extractMetadata(
            from: Data(),
            providerID: providerID,
            fallbackModelName: configuration.model
        )
        return responseParser.parse(
            rawContent: rawContent,
            providerID: providerID,
            model: metadata.model,
            usage: metadata.usage
        )
    }

    private func collectBody(from lines: AsyncThrowingStream<String, Error>) async throws -> Data {
        var body = ""
        do {
            for try await line in lines {
                body += line
                body += "\n"
            }
        } catch {
            // The error payload is best effort; status mapping proceeds with
            // whatever body arrived before the connection failed.
        }
        return Data(body.utf8)
    }

    private func readAPIKey() throws -> String? {
        guard let apiKeySecretKey = configuration.apiKeySecretKey else {
            return nil
        }

        let storedAPIKey = try secretStore.read(apiKeySecretKey)
        do {
            return try APIKeyValidator.normalize(storedAPIKey)
        } catch APIKeyValidationError.empty, APIKeyValidationError.containsWhitespace {
            if configuration.requiresAPIKey {
                throw LLMProviderError.authenticationFailed
            }
            return nil
        }
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> LLMProviderError {
        switch statusCode {
        case 401, 403:
            .authenticationFailed
        case 429:
            .rateLimited
        default:
            .network("HTTP \(statusCode): \(LLMHTTPErrorMessageExtractor.message(from: data) ?? "Empty error body.")")
        }
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

enum ChatCompletionsSSEEvent: Equatable {
    case textDelta(String)
    case error(String)
    case done
    case ignored
}

enum ChatCompletionsSSEParser {
    static func dataPayload(from line: String) -> String? {
        guard line.hasPrefix("data:") else {
            return nil
        }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else {
            return nil
        }
        return payload
    }

    static func parse(_ payload: String) throws -> ChatCompletionsSSEEvent {
        // The terminal marker is not JSON, so it must short-circuit decoding.
        guard payload != "[DONE]" else {
            return .done
        }

        guard let data = payload.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ChatCompletionsSSEEnvelope.self, from: data) else {
            throw LLMProviderError.invalidResponse("Chat completion stream event could not be decoded.")
        }

        if let error = envelope.error {
            let message = error.message ?? "Chat completion stream reported an error."
            return .error(DeveloperSecretRedactor().redact(message).text)
        }

        guard let content = envelope.choices?.first?.delta?.content, !content.isEmpty else {
            return .ignored
        }
        return .textDelta(content)
    }
}

private struct ChatCompletionsSSEEnvelope: Decodable {
    var choices: [ChatCompletionsSSEChoice]?
    var error: ChatCompletionsSSEError?
}

private struct ChatCompletionsSSEChoice: Decodable {
    var delta: ChatCompletionsSSEDelta?
}

private struct ChatCompletionsSSEDelta: Decodable {
    var content: String?
}

private struct ChatCompletionsSSEError: Decodable {
    var message: String?
}

private struct ChatCompletionsResponseBody: Decodable {
    var model: String?
    var choices: [ChatCompletionsChoice]
    var usage: ChatCompletionsUsage?
}

private struct ChatCompletionsChoice: Decodable {
    var message: ChatCompletionsMessage
}

private struct ChatCompletionsUsage: Decodable {
    var promptTokens: Int?
    var completionTokens: Int?
    var inputTokens: Int?
    var outputTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    var executionReceiptUsage: ExecutionReceiptUsage {
        let input = Self.nonNegative(promptTokens ?? inputTokens)
        let output = Self.nonNegative(completionTokens ?? outputTokens)
        guard input != nil || output != nil else {
            return .unknown
        }
        return ExecutionReceiptUsage(
            inputTokens: input,
            outputTokens: output,
            isEstimated: false
        )
    }

    private static func nonNegative(_ value: Int?) -> Int? {
        value.map { max(0, $0) }
    }
}
