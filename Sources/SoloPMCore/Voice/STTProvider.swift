import Foundation

public enum STTProviderID: String, CaseIterable, Equatable, Sendable {
    case appleSpeechAnalyzer
    case whisperKit
    case whisperCpp
    case openAITranscribe

    public var displayName: String {
        switch self {
        case .appleSpeechAnalyzer:
            "Apple SpeechAnalyzer"
        case .whisperKit:
            "WhisperKit"
        case .whisperCpp:
            "whisper.cpp"
        case .openAITranscribe:
            "OpenAI Transcribe"
        }
    }
}

public struct STTProviderAvailability: Equatable, Sendable {
    public var providerID: STTProviderID
    public var isAvailable: Bool
    public var reason: String?
    public var requiresAPIKey: Bool
    public var requiresModelDownload: Bool

    public init(
        providerID: STTProviderID,
        isAvailable: Bool,
        reason: String? = nil,
        requiresAPIKey: Bool = false,
        requiresModelDownload: Bool = false
    ) {
        self.providerID = providerID
        self.isAvailable = isAvailable
        self.reason = reason
        self.requiresAPIKey = requiresAPIKey
        self.requiresModelDownload = requiresModelDownload
    }
}

public struct RecordedAudio: Equatable, Sendable {
    public var fileURL: URL
    public var format: AudioFileFormat
    public var duration: TimeInterval?

    public init(fileURL: URL, format: AudioFileFormat, duration: TimeInterval? = nil) {
        self.fileURL = fileURL
        self.format = format
        self.duration = duration
    }
}

public enum AudioFileFormat: String, Equatable, Sendable {
    case wav
    case m4a
    case caf
}

public struct STTTranscript: Equatable, Sendable {
    public var text: String
    public var languageCode: String?
    public var duration: TimeInterval?

    public init(text: String, languageCode: String? = nil, duration: TimeInterval? = nil) {
        self.text = text
        self.languageCode = languageCode
        self.duration = duration
    }
}

public protocol SpeechToTextProvider: Sendable {
    var id: STTProviderID { get }
    var availability: STTProviderAvailability { get }

    func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript
}

public enum STTProviderError: Error, Equatable, Sendable {
    case unavailable(String)
    case permissionDenied
    case modelMissing(String)
    case transcriptionFailed(String)
}

public struct FakeSTTProvider: SpeechToTextProvider {
    public var id: STTProviderID
    public var availability: STTProviderAvailability
    private var transcript: STTTranscript

    public init(
        id: STTProviderID = .whisperKit,
        availability: STTProviderAvailability? = nil,
        transcript: STTTranscript
    ) {
        self.id = id
        self.availability = availability ?? STTProviderAvailability(providerID: id, isAvailable: true)
        self.transcript = transcript
    }

    public func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript {
        guard availability.isAvailable else {
            throw STTProviderError.unavailable(availability.reason ?? "STT provider is unavailable.")
        }
        return transcript
    }
}

public struct STTProviderCatalog: Sendable {
    public var availabilities: [STTProviderAvailability]

    public init(availabilities: [STTProviderAvailability]) {
        self.availabilities = availabilities
    }

    public var availableProviders: [STTProviderAvailability] {
        availabilities.filter(\.isAvailable)
    }

    public func availability(for providerID: STTProviderID) -> STTProviderAvailability {
        availabilities.first { $0.providerID == providerID } ?? STTProviderAvailability(
            providerID: providerID,
            isAvailable: false,
            reason: "Provider is not registered."
        )
    }
}

