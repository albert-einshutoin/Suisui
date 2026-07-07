import Foundation

public struct ClaudeMessagesConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var maxTokens: Int
    public var timeoutInterval: TimeInterval
    public var anthropicVersion: String

    public init(
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        model: String = "claude-fable-5",
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

    public func makeRequest(apiKey: String, prompt: PlanningPrompt, stream: Bool = false) throws -> URLRequest {
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
            stream: stream
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

public struct ClaudeMessagesProvider: StreamingLLMProvider {
    public let providerID = "claude.messages"

    private let secretStore: any SecretStore
    private let httpClient: any HTTPDataClient
    private let byteStreamClient: any HTTPByteStreamClient
    private let promptBuilder: PlanningPromptBuilder?
    private let requestBuilder: ClaudeMessagesRequestBuilder
    private let outputTextExtractor: ClaudeMessagesOutputTextExtractor
    private let responseParser: ActionPlanResponseParser

    public init(
        secretStore: any SecretStore,
        httpClient: any HTTPDataClient = URLSessionHTTPDataClient(),
        byteStreamClient: any HTTPByteStreamClient = URLSessionHTTPByteStreamClient(),
        promptBuilder: PlanningPromptBuilder? = nil,
        configuration: ClaudeMessagesConfiguration = ClaudeMessagesConfiguration(),
        outputTextExtractor: ClaudeMessagesOutputTextExtractor = ClaudeMessagesOutputTextExtractor(),
        responseParser: ActionPlanResponseParser = ActionPlanResponseParser()
    ) {
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.byteStreamClient = byteStreamClient
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
            throw LLMProviderError.network(ProviderErrorMessageSanitizer.message(from: error))
        }

        guard (200..<300).contains(response.statusCode) else {
            throw mapHTTPError(statusCode: response.statusCode, data: data)
        }

        let rawContent = try outputTextExtractor.extractText(from: data)
        return responseParser.parse(rawContent: rawContent, providerID: providerID)
    }

    public func generatePlanStream(
        for request: PlanningRequest,
        onTextDelta: @escaping @Sendable (String) -> Void
    ) async throws -> PlanningResponse {
        let apiKey: String
        let storedAPIKey = try secretStore.read(.anthropicAPIKey)
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
                guard let payload = ClaudeMessagesSSEParser.dataPayload(from: line) else {
                    continue
                }
                switch try ClaudeMessagesSSEParser.parse(payload) {
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
            throw LLMProviderError.invalidResponse("Claude Messages stream did not contain text content.")
        }
        return responseParser.parse(rawContent: rawContent, providerID: providerID)
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
            .network("Claude Messages HTTP \(statusCode): \(LLMHTTPErrorMessageExtractor.message(from: data) ?? "Empty error body.")")
        }
    }
}

extension ClaudeMessagesProvider: AnswerGeneratingLLMProvider {
    public func generateAnswer(for request: WorkspaceAnswerRequest) async throws -> String {
        let apiKey: String
        let storedAPIKey = try secretStore.read(.anthropicAPIKey)
        do {
            apiKey = try APIKeyValidator.normalize(storedAPIKey)
        } catch APIKeyValidationError.empty, APIKeyValidationError.containsWhitespace {
            throw LLMProviderError.authenticationFailed
        }

        let prompt = WorkspaceAnswerPromptBuilder.buildPrompt(for: request)
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

        let answer = try outputTextExtractor.extractText(from: data)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else {
            throw LLMProviderError.invalidResponse("Claude Messages response did not contain answer text.")
        }
        return answer
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

enum ClaudeMessagesSSEEvent: Equatable {
    case textDelta(String)
    case error(String)
    case ignored
}

enum ClaudeMessagesSSEParser {
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

    static func parse(_ payload: String) throws -> ClaudeMessagesSSEEvent {
        guard let data = payload.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ClaudeMessagesSSEEnvelope.self, from: data) else {
            throw LLMProviderError.invalidResponse("Claude Messages stream event could not be decoded.")
        }

        switch envelope.type {
        case "content_block_delta":
            guard envelope.delta?.type == "text_delta" else {
                return .ignored
            }
            guard let text = envelope.delta?.text else {
                throw LLMProviderError.invalidResponse("Claude Messages text delta did not contain text.")
            }
            return .textDelta(text)
        case "error":
            let message = envelope.error?.message ?? "Claude Messages stream reported an error."
            return .error(DeveloperSecretRedactor().redact(message).text)
        default:
            return .ignored
        }
    }
}

private struct ClaudeMessagesSSEEnvelope: Decodable {
    var type: String
    var delta: ClaudeMessagesSSEDelta?
    var error: ClaudeMessagesSSEError?
}

private struct ClaudeMessagesSSEDelta: Decodable {
    var type: String?
    var text: String?
}

private struct ClaudeMessagesSSEError: Decodable {
    var message: String?
}
