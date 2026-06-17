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
    public let id: STTProviderID = .openAITranscribe
    public var availability: STTProviderAvailability

    public init(
        availability: STTProviderAvailability = STTProviderAvailability(
            providerID: .openAITranscribe,
            isAvailable: false,
            reason: "OpenAI transcription adapter is not implemented yet.",
            requiresAPIKey: true
        )
    ) {
        self.availability = availability
    }

    public func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript {
        throw STTProviderError.unavailable(availability.reason ?? "OpenAI transcription is unavailable.")
    }
}

public extension STTProviderCatalog {
    static let phase1Default = STTProviderCatalog(
        availabilities: [
            AppleSpeechAnalyzerProvider().availability,
            WhisperKitProvider().availability,
            WhisperCppProvider().availability,
            OpenAITranscribeProvider().availability
        ]
    )
}
