import Foundation

public struct OpenAIResponsesConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var timeoutInterval: TimeInterval

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "gpt-5.5",
        timeoutInterval: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.model = model
        self.timeoutInterval = timeoutInterval
    }
}

public protocol HTTPDataClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPDataClient: HTTPDataClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse("Response was not HTTP.")
        }

        return (data, httpResponse)
    }
}

public struct OpenAIResponsesRequestBuilder: Sendable {
    private let configuration: OpenAIResponsesConfiguration

    public init(configuration: OpenAIResponsesConfiguration = OpenAIResponsesConfiguration()) {
        self.configuration = configuration
    }

    public func makeRequest(apiKey: String, prompt: PlanningPrompt, stream: Bool = false) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent("responses")
        var request = URLRequest(url: url, timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = OpenAIResponsesRequestBody(
            model: configuration.model,
            input: [
                .message(role: "system", text: prompt.system),
                .message(role: "user", text: prompt.user)
            ],
            toolChoice: "none",
            stream: stream
        )
        request.httpBody = try JSONEncoder().encode(body)

        return request
    }
}

public struct OpenAIResponsesOutputTextExtractor: Sendable {
    public init() {}

    public func extractText(from data: Data) throws -> String {
        let response: OpenAIResponsesResponseBody
        do {
            response = try JSONDecoder().decode(OpenAIResponsesResponseBody.self, from: data)
        } catch {
            throw LLMProviderError.invalidResponse("OpenAI Responses payload could not be decoded.")
        }

        if let outputText = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outputText.isEmpty {
            return outputText
        }

        let outputText = try response.output?
            .reduce(into: [String]()) { texts, item in
                guard item.type == "message" else {
                    return
                }
                guard let contentItems = item.content else {
                    throw LLMProviderError.invalidResponse("Response message item did not contain content.")
                }
                for content in contentItems {
                    guard content.type == "output_text" else {
                        continue
                    }
                    guard let text = content.text else {
                        throw LLMProviderError.invalidResponse("Response output_text item did not contain text.")
                    }
                    texts.append(text)
                }
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let outputText, !outputText.isEmpty else {
            throw LLMProviderError.invalidResponse("Response did not contain output text.")
        }

        return outputText
    }
}

public struct OpenAIResponsesMetadataExtractor: Sendable {
    public init() {}

    public func extractMetadata(
        from data: Data,
        providerID: String,
        fallbackModelName: String
    ) -> PlanningResponseMetadata {
        guard let response = try? JSONDecoder().decode(OpenAIResponsesResponseBody.self, from: data) else {
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

public struct OpenAIResponsesProvider: StreamingLLMProvider {
    public let providerID = "openai.responses"

    private let secretStore: any SecretStore
    private let httpClient: any HTTPDataClient
    private let byteStreamClient: any HTTPByteStreamClient
    private let promptBuilder: PlanningPromptBuilder?
    private let configuration: OpenAIResponsesConfiguration
    private let requestBuilder: OpenAIResponsesRequestBuilder
    private let outputTextExtractor: OpenAIResponsesOutputTextExtractor
    private let metadataExtractor: OpenAIResponsesMetadataExtractor
    private let responseParser: ActionPlanResponseParser

    public init(
        secretStore: any SecretStore,
        httpClient: any HTTPDataClient = URLSessionHTTPDataClient(),
        byteStreamClient: any HTTPByteStreamClient = URLSessionHTTPByteStreamClient(),
        promptBuilder: PlanningPromptBuilder? = nil,
        configuration: OpenAIResponsesConfiguration = OpenAIResponsesConfiguration(),
        outputTextExtractor: OpenAIResponsesOutputTextExtractor = OpenAIResponsesOutputTextExtractor(),
        metadataExtractor: OpenAIResponsesMetadataExtractor = OpenAIResponsesMetadataExtractor(),
        responseParser: ActionPlanResponseParser = ActionPlanResponseParser()
    ) {
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.byteStreamClient = byteStreamClient
        self.promptBuilder = promptBuilder
        self.configuration = configuration
        self.requestBuilder = OpenAIResponsesRequestBuilder(configuration: configuration)
        self.outputTextExtractor = outputTextExtractor
        self.metadataExtractor = metadataExtractor
        self.responseParser = responseParser
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        let apiKey: String
        let storedAPIKey = try secretStore.read(.openAIAPIKey)
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
        let apiKey: String
        let storedAPIKey = try secretStore.read(.openAIAPIKey)
        do {
            apiKey = try APIKeyValidator.normalize(storedAPIKey)
        } catch APIKeyValidationError.empty, APIKeyValidationError.containsWhitespace {
            throw LLMProviderError.authenticationFailed
        }

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
            for try await line in lines {
                guard let payload = OpenAIResponsesSSEParser.dataPayload(from: line) else {
                    continue
                }
                switch try OpenAIResponsesSSEParser.parse(payload) {
                case .textDelta(let text):
                    accumulated += text
                    onTextDelta(text)
                case .error(let message):
                    throw LLMProviderError.invalidResponse(message)
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
            throw LLMProviderError.invalidResponse("OpenAI Responses stream did not contain text content.")
        }
        // Streaming deltas do not carry a reliable usage envelope, so the
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

enum OpenAIResponsesSSEEvent: Equatable {
    case textDelta(String)
    case error(String)
    case ignored
}

enum OpenAIResponsesSSEParser {
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

    static func parse(_ payload: String) throws -> OpenAIResponsesSSEEvent {
        guard let data = payload.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(OpenAIResponsesSSEEnvelope.self, from: data) else {
            throw LLMProviderError.invalidResponse("OpenAI Responses stream event could not be decoded.")
        }

        switch envelope.type {
        case "response.output_text.delta":
            guard let text = envelope.delta else {
                throw LLMProviderError.invalidResponse("OpenAI Responses text delta did not contain text.")
            }
            return .textDelta(text)
        case "response.failed", "error":
            let message = envelope.message
                ?? envelope.error?.message
                ?? envelope.response?.error?.message
                ?? "OpenAI Responses stream reported an error."
            return .error(DeveloperSecretRedactor().redact(message).text)
        default:
            return .ignored
        }
    }
}

private struct OpenAIResponsesSSEEnvelope: Decodable {
    var type: String
    var delta: String?
    var message: String?
    var error: OpenAIResponsesSSEError?
    var response: OpenAIResponsesSSEResponse?
}

private struct OpenAIResponsesSSEResponse: Decodable {
    var error: OpenAIResponsesSSEError?
}

private struct OpenAIResponsesSSEError: Decodable {
    var message: String?
}

private struct OpenAIResponsesRequestBody: Encodable {
    var model: String
    var input: [OpenAIResponsesInputMessage]
    var toolChoice: String
    var stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case toolChoice = "tool_choice"
        case stream
    }
}

private struct OpenAIResponsesInputMessage: Encodable {
    var role: String
    var content: [OpenAIResponsesInputContent]

    static func message(role: String, text: String) -> OpenAIResponsesInputMessage {
        OpenAIResponsesInputMessage(
            role: role,
            content: [
                OpenAIResponsesInputContent(text: text)
            ]
        )
    }
}

private struct OpenAIResponsesInputContent: Encodable {
    var text: String
    let type = "input_text"
}

private struct OpenAIResponsesResponseBody: Decodable {
    var model: String?
    var outputText: String?
    var output: [OpenAIResponsesOutputItem]?
    var usage: OpenAIResponsesUsage?

    private enum CodingKeys: String, CodingKey {
        case model
        case outputText = "output_text"
        case output
        case usage
    }
}

private struct OpenAIResponsesOutputItem: Decodable {
    var type: String
    var content: [OpenAIResponsesOutputContent]?
}

private struct OpenAIResponsesOutputContent: Decodable {
    var type: String
    var text: String?
}

private struct OpenAIResponsesUsage: Decodable {
    var inputTokens: Int?
    var outputTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    var executionReceiptUsage: ExecutionReceiptUsage {
        let input = Self.nonNegative(inputTokens)
        let output = Self.nonNegative(outputTokens)
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
