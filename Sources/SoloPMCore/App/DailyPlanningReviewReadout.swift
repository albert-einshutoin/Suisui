import Foundation

public enum DailyPlanningReviewReadoutBuilder {
    private static let maxPromptLength = 280
    private static let maxFocusTitleLength = 72

    public static func makeRequest(
        review: DailyPlanningReview,
        languageCode: String,
        voiceID: String
    ) -> TextToSpeechRequest {
        let normalizedLanguage = AppSettings.normalizedTTSLanguageCode(languageCode)
        let normalizedVoice = AppSettings.normalizedTTSVoiceID(voiceID, languageCode: normalizedLanguage)
        let text = normalizedLanguage == "ja"
            ? japaneseReadout(for: review)
            : englishReadout(for: review)
        return TextToSpeechRequest(
            text: limitedPrompt(text),
            languageCode: normalizedLanguage,
            voiceID: normalizedVoice
        )
    }

    private static func englishReadout(for review: DailyPlanningReview) -> String {
        let phase = switch review.phase {
        case .morning:
            "Morning"
        case .midday:
            "Midday"
        case .evening:
            "Evening"
        }
        let inboxLabel = review.inboxUntriagedCount == 1 ? "Inbox item" : "Inbox items"
        return [
            "\(phase) planning review.",
            "\(review.overdueCount) overdue, \(review.dueTodayCount) due today, \(review.inboxUntriagedCount) \(inboxLabel).",
            "Start with \(focusTitle(for: review, fallback: "capture the next task"))."
        ].joined(separator: " ")
    }

    private static func japaneseReadout(for review: DailyPlanningReview) -> String {
        let phase = switch review.phase {
        case .morning:
            "朝"
        case .midday:
            "昼"
        case .evening:
            "夕方"
        }
        return [
            "\(phase)の計画レビューです。",
            "期限切れは\(review.overdueCount)件、今日の期限は\(review.dueTodayCount)件、Inbox未整理は\(review.inboxUntriagedCount)件です。",
            japaneseFocusSentence(for: review)
        ].joined(separator: " ")
    }

    private static func japaneseFocusSentence(for review: DailyPlanningReview) -> String {
        guard review.focusItems.first != nil else {
            return "次のタスクを登録しましょう。"
        }
        return "最初は\(focusTitle(for: review, fallback: "次のタスク"))から始めましょう。"
    }

    private static func focusTitle(
        for review: DailyPlanningReview,
        fallback: String
    ) -> String {
        guard let title = review.focusItems.first?.title else {
            return fallback
        }
        let redacted = LocalPathRedactor.redact(DeveloperSecretRedactor().redact(title).text)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !redacted.isEmpty else {
            return fallback
        }
        if redacted.count <= maxFocusTitleLength {
            return redacted
        }
        return "\(redacted.prefix(maxFocusTitleLength))..."
    }

    private static func limitedPrompt(_ text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > maxPromptLength else {
            return flattened
        }
        return "\(flattened.prefix(maxPromptLength - 3))..."
    }
}
