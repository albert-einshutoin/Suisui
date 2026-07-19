import Foundation

public struct TranscriptDraft: Equatable, Sendable {
    public var text: String

    public init(text: String = "") {
        self.text = text
    }

    public var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canGeneratePlan: Bool {
        !normalizedText.isEmpty
    }
}

