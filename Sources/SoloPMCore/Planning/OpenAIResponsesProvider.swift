import Foundation

public struct OpenAIResponsesConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var timeoutInterval: TimeInterval

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "gpt-5.2",
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

    public func makeRequest(apiKey: String, prompt: PlanningPrompt) throws -> URLRequest {
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
            toolChoice: "none"
        )
        request.httpBody = try JSONEncoder().encode(body)

        return request
    }
}

public struct OpenAIResponsesOutputTextExtractor: Sendable {
    public init() {}

    public func extractText(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(OpenAIResponsesResponseBody.self, from: data)

        if let outputText = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outputText.isEmpty {
            return outputText
        }

        let outputText = response.output?
            .flatMap { $0.content ?? [] }
            .compactMap { content -> String? in
                guard content.type == "output_text" else {
                    return nil
                }
                return content.text
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let outputText, !outputText.isEmpty else {
            throw LLMProviderError.invalidResponse("Response did not contain output text.")
        }

        return outputText
    }
}

public struct OpenAIResponsesProvider: LLMProvider {
    public let providerID = "openai.responses"

    private let secretStore: any SecretStore
    private let httpClient: any HTTPDataClient
    private let promptBuilder: PlanningPromptBuilder?
    private let requestBuilder: OpenAIResponsesRequestBuilder
    private let outputTextExtractor: OpenAIResponsesOutputTextExtractor
    private let responseParser: ActionPlanResponseParser

    public init(
        secretStore: any SecretStore,
        httpClient: any HTTPDataClient = URLSessionHTTPDataClient(),
        promptBuilder: PlanningPromptBuilder? = nil,
        configuration: OpenAIResponsesConfiguration = OpenAIResponsesConfiguration(),
        outputTextExtractor: OpenAIResponsesOutputTextExtractor = OpenAIResponsesOutputTextExtractor(),
        responseParser: ActionPlanResponseParser = ActionPlanResponseParser()
    ) {
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.promptBuilder = promptBuilder
        self.requestBuilder = OpenAIResponsesRequestBuilder(configuration: configuration)
        self.outputTextExtractor = outputTextExtractor
        self.responseParser = responseParser
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        let apiKey = try secretStore.read(.openAIAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey, !apiKey.isEmpty else {
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
            .network("HTTP \(statusCode): \(errorMessage(from: data) ?? "No error message.")")
        }
    }

    private func errorMessage(from data: Data) -> String? {
        guard let errorBody = try? JSONDecoder().decode(OpenAIErrorResponseBody.self, from: data) else {
            return nil
        }

        return errorBody.error.message
    }
}

private struct OpenAIResponsesRequestBody: Encodable {
    var model: String
    var input: [OpenAIResponsesInputMessage]
    var toolChoice: String

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case toolChoice = "tool_choice"
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
    var outputText: String?
    var output: [OpenAIResponsesOutputItem]?

    private enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct OpenAIResponsesOutputItem: Decodable {
    var content: [OpenAIResponsesOutputContent]?
}

private struct OpenAIResponsesOutputContent: Decodable {
    var type: String
    var text: String?
}

private struct OpenAIErrorResponseBody: Decodable {
    var error: OpenAIErrorBody
}

private struct OpenAIErrorBody: Decodable {
    var message: String
}
