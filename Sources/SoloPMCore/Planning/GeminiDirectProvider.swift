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

    public func makeRequest(apiKey: String, prompt: PlanningPrompt) throws -> URLRequest {
        var request = URLRequest(url: makeURL(), timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body = GeminiDirectRequestBody(
            systemInstruction: GeminiDirectContent(parts: [GeminiDirectPart(text: prompt.system)]),
            contents: [
                GeminiDirectContent(role: "user", parts: [GeminiDirectPart(text: prompt.user)])
            ],
            generationConfig: GeminiDirectGenerationConfig(
                maxOutputTokens: configuration.maxOutputTokens,
                responseFormat: GeminiDirectResponseFormat(
                    text: GeminiDirectTextResponseFormat(mimeType: "application/json")
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

    public func extractText(from data: Data) throws -> String {
        let response: GeminiDirectResponseBody
        do {
            response = try JSONDecoder().decode(GeminiDirectResponseBody.self, from: data)
        } catch {
            throw LLMProviderError.invalidResponse("Gemini Direct payload could not be decoded.")
        }

        if let blockReason = response.promptFeedback?.blockReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !blockReason.isEmpty {
            throw LLMProviderError.invalidResponse("Gemini Direct blocked the prompt: \(blockReason).")
        }

        guard let candidates = response.candidates, !candidates.isEmpty else {
            throw LLMProviderError.invalidResponse("Gemini Direct response did not contain candidates.")
        }

        var textParts: [String] = []
        for candidate in candidates {
            if candidate.finishReason == "SAFETY" {
                throw LLMProviderError.invalidResponse("Gemini Direct blocked the response for safety.")
            }
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

    private enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig
    }
}

private struct GeminiDirectContent: Codable {
    var role: String?
    var parts: [GeminiDirectPart]
}

private struct GeminiDirectPart: Codable {
    var text: String?
}

private struct GeminiDirectGenerationConfig: Encodable {
    var maxOutputTokens: Int
    var responseFormat: GeminiDirectResponseFormat
}

private struct GeminiDirectResponseFormat: Encodable {
    var text: GeminiDirectTextResponseFormat
}

private struct GeminiDirectTextResponseFormat: Encodable {
    var mimeType: String
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
