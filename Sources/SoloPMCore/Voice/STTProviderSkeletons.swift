import Foundation

public struct AppleSpeechAnalyzerProvider: SpeechToTextProvider {
    public let id: STTProviderID = .appleSpeechAnalyzer
    public var availability: STTProviderAvailability

    public init(
        availability: STTProviderAvailability = STTProviderAvailability(
            providerID: .appleSpeechAnalyzer,
            isAvailable: false,
            reason: "Apple SpeechAnalyzer adapter is not implemented yet."
        )
    ) {
        self.availability = availability
    }

    public func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript {
        throw STTProviderError.unavailable(availability.reason ?? "Apple SpeechAnalyzer is unavailable.")
    }
}

public struct WhisperKitProvider: SpeechToTextProvider {
    public let id: STTProviderID = .whisperKit
    public var availability: STTProviderAvailability

    public init(
        availability: STTProviderAvailability = STTProviderAvailability(
            providerID: .whisperKit,
            isAvailable: false,
            reason: "WhisperKit adapter is not implemented yet.",
            requiresModelDownload: true
        )
    ) {
        self.availability = availability
    }

    public func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript {
        throw STTProviderError.modelMissing(availability.reason ?? "WhisperKit model is unavailable.")
    }
}

public struct WhisperCppProvider: SpeechToTextProvider {
    public let id: STTProviderID = .whisperCpp
    public var availability: STTProviderAvailability

    public init(
        availability: STTProviderAvailability = STTProviderAvailability(
            providerID: .whisperCpp,
            isAvailable: false,
            reason: "whisper.cpp adapter is not implemented yet.",
            requiresModelDownload: true
        )
    ) {
        self.availability = availability
    }

    public func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript {
        throw STTProviderError.modelMissing(availability.reason ?? "whisper.cpp model is unavailable.")
    }
}

public struct OpenAITranscribeProvider: SpeechToTextProvider {
    public static let defaultAvailability = STTProviderAvailability(
        providerID: .openAITranscribe,
        isAvailable: true,
        requiresAPIKey: true
    )

    public let id: STTProviderID = .openAITranscribe
    public var availability: STTProviderAvailability
    private let secretStore: any SecretStore
    private let httpClient: any HTTPDataClient
    private let requestBuilder: OpenAITranscriptionRequestBuilder
    private let responseParser: OpenAITranscriptionResponseParser

    public init(
        availability: STTProviderAvailability = Self.defaultAvailability,
        secretStore: any SecretStore,
        httpClient: any HTTPDataClient = URLSessionHTTPDataClient(),
        configuration: OpenAITranscriptionConfiguration = OpenAITranscriptionConfiguration(),
        responseParser: OpenAITranscriptionResponseParser = OpenAITranscriptionResponseParser()
    ) {
        self.availability = availability
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.requestBuilder = OpenAITranscriptionRequestBuilder(configuration: configuration)
        self.responseParser = responseParser
    }

    public func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript {
        guard availability.isAvailable else {
            throw STTProviderError.unavailable(availability.reason ?? "OpenAI transcription is unavailable.")
        }

        let apiKey = try secretStore.read(.openAIAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey, !apiKey.isEmpty else {
            throw STTProviderError.unavailable("OpenAI API key is not configured.")
        }

        let request = try requestBuilder.makeRequest(apiKey: apiKey, audio: audio)
        let data: Data
        let response: HTTPURLResponse

        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw STTProviderError.transcriptionFailed(error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw STTProviderError.transcriptionFailed("OpenAI transcription failed with HTTP \(response.statusCode).")
        }

        return try responseParser.parse(data: data, audio: audio)
    }
}

public struct OpenAITranscriptionConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var timeoutInterval: TimeInterval

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "gpt-4o-mini-transcribe",
        timeoutInterval: TimeInterval = 120
    ) {
        self.baseURL = baseURL
        self.model = model
        self.timeoutInterval = timeoutInterval
    }
}

public struct OpenAITranscriptionRequestBuilder: Sendable {
    private let configuration: OpenAITranscriptionConfiguration

    public init(configuration: OpenAITranscriptionConfiguration = OpenAITranscriptionConfiguration()) {
        self.configuration = configuration
    }

    public func makeRequest(apiKey: String, audio: RecordedAudio) throws -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(
            url: configuration.baseURL.appendingPathComponent("audio/transcriptions"),
            timeoutInterval: configuration.timeoutInterval
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeMultipartBody(boundary: boundary, audio: audio)
        return request
    }

    private func makeMultipartBody(boundary: String, audio: RecordedAudio) throws -> Data {
        var body = Data()
        body.appendMultipartField(name: "model", value: configuration.model, boundary: boundary)
        body.appendMultipartField(name: "response_format", value: "json", boundary: boundary)

        let fileData = try Data(contentsOf: audio.fileURL)
        let filename = audio.fileURL.lastPathComponent.isEmpty ? "audio.\(audio.format.rawValue)" : audio.fileURL.lastPathComponent
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(audio.format.mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }
}

public struct OpenAITranscriptionResponseParser: Sendable {
    public init() {}

    public func parse(data: Data, audio: RecordedAudio) throws -> STTTranscript {
        do {
            let response = try JSONDecoder().decode(OpenAITranscriptionResponseBody.self, from: data)
            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw STTProviderError.transcriptionFailed("Transcription response did not contain text.")
            }

            return STTTranscript(text: text, languageCode: response.language, duration: response.duration ?? audio.duration)
        } catch let error as STTProviderError {
            throw error
        } catch {
            throw STTProviderError.transcriptionFailed("Transcription response was invalid.")
        }
    }
}

private struct OpenAITranscriptionResponseBody: Decodable {
    var text: String
    var language: String?
    var duration: TimeInterval?
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
}

private extension AudioFileFormat {
    var mimeType: String {
        switch self {
        case .wav:
            "audio/wav"
        case .m4a:
            "audio/mp4"
        case .caf:
            "audio/x-caf"
        }
    }
}

public extension STTProviderCatalog {
    static let phase1Default = STTProviderCatalog(
        availabilities: [
            AppleSpeechAnalyzerProvider().availability,
            WhisperKitProvider().availability,
            WhisperCppProvider().availability,
            OpenAITranscribeProvider.defaultAvailability
        ]
    )
}
