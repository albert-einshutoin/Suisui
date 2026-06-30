import Foundation

public enum TTSProviderID: String, CaseIterable, Equatable, Sendable {
    case kokoro

    public var displayName: String {
        switch self {
        case .kokoro:
            "Kokoro"
        }
    }
}

public struct TTSProviderAvailability: Equatable, Sendable {
    public var providerID: TTSProviderID
    public var isAvailable: Bool
    public var reason: String?
    public var requiresModelDownload: Bool

    public init(
        providerID: TTSProviderID,
        isAvailable: Bool,
        reason: String? = nil,
        requiresModelDownload: Bool = false
    ) {
        self.providerID = providerID
        self.isAvailable = isAvailable
        self.reason = reason
        self.requiresModelDownload = requiresModelDownload
    }
}

public struct TextToSpeechRequest: Equatable, Sendable {
    public var text: String
    public var languageCode: String
    public var voiceID: String

    public init(text: String, languageCode: String, voiceID: String) {
        self.text = text
        self.languageCode = languageCode
        self.voiceID = voiceID
    }
}

public struct SynthesizedSpeech: Equatable, Sendable {
    public var fileURL: URL
    public var format: AudioFileFormat
    public var languageCode: String
    public var voiceID: String

    public init(fileURL: URL, format: AudioFileFormat, languageCode: String, voiceID: String) {
        self.fileURL = fileURL
        self.format = format
        self.languageCode = languageCode
        self.voiceID = voiceID
    }
}

public protocol TextToSpeechProvider: Sendable {
    var id: TTSProviderID { get }
    var availability: TTSProviderAvailability { get }

    func synthesize(_ request: TextToSpeechRequest) async throws -> SynthesizedSpeech
}

public enum TTSProviderError: Error, Equatable, Sendable {
    case unavailable(String)
    case modelMissing(String)
    case promptRejected(String)
    case synthesisFailed(String)
}

public struct TTSProviderCatalog: Sendable {
    public var availabilities: [TTSProviderAvailability]

    public init(availabilities: [TTSProviderAvailability]) {
        self.availabilities = availabilities
    }

    public var availableProviders: [TTSProviderAvailability] {
        availabilities.filter(\.isAvailable)
    }

    public func availability(for providerID: TTSProviderID) -> TTSProviderAvailability {
        availabilities.first { $0.providerID == providerID } ?? TTSProviderAvailability(
            providerID: providerID,
            isAvailable: false,
            reason: "Provider is not registered."
        )
    }
}

public extension TTSProviderCatalog {
    static let phase1Default = TTSProviderCatalog(
        availabilities: [
            TTSProviderAvailability(
                providerID: .kokoro,
                isAvailable: false,
                reason: "Install the Kokoro model and configure the executable in Settings.",
                requiresModelDownload: true
            )
        ]
    )
}
