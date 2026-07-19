import XCTest
@testable import SuisuiCore

final class DailyPlanningReviewReadoutTests: XCTestCase {
    func testBuildsEnglishReadoutWithoutRawTranscript() {
        let review = dailyReview(
            sourceTranscript: "今日やることを確認して sk-proj-secret123",
            phase: .morning,
            overdueCount: 2,
            dueTodayCount: 3,
            inboxUntriagedCount: 1,
            focusItems: [
                DailyPlanningFocusItem(
                    taskID: 42,
                    title: "Clear billing blocker",
                    reason: "Overdue work should move first."
                )
            ]
        )

        let request = DailyPlanningReviewReadoutBuilder.makeRequest(
            review: review,
            languageCode: "en",
            voiceID: "af_heart"
        )

        XCTAssertEqual(request.languageCode, "en")
        XCTAssertEqual(request.voiceID, "af_heart")
        XCTAssertTrue(request.text.contains("Morning planning review."))
        XCTAssertTrue(request.text.contains("2 overdue"))
        XCTAssertTrue(request.text.contains("3 due today"))
        XCTAssertTrue(request.text.contains("1 Inbox item"))
        XCTAssertTrue(request.text.contains("Start with Clear billing blocker."))
        XCTAssertFalse(request.text.contains("今日やることを確認して"))
        XCTAssertFalse(request.text.contains("sk-proj-secret123"))
        XCTAssertLessThanOrEqual(request.text.count, 280)
    }

    func testBuildsJapaneseReadoutWithLocalizedCountsAndVoiceFallback() {
        let review = dailyReview(
            sourceTranscript: "Plan my day",
            phase: .midday,
            overdueCount: 0,
            dueTodayCount: 1,
            inboxUntriagedCount: 0,
            focusItems: [
                DailyPlanningFocusItem(
                    taskID: 43,
                    title: "顧客向けアップデートを確認",
                    reason: "High-priority work protects today's plan."
                )
            ]
        )

        let request = DailyPlanningReviewReadoutBuilder.makeRequest(
            review: review,
            languageCode: "ja",
            voiceID: "af_heart"
        )

        XCTAssertEqual(request.languageCode, "ja")
        XCTAssertEqual(request.voiceID, "jf_alpha")
        XCTAssertTrue(request.text.contains("昼の計画レビューです。"))
        XCTAssertTrue(request.text.contains("期限切れは0件"))
        XCTAssertTrue(request.text.contains("今日の期限は1件"))
        XCTAssertTrue(request.text.contains("Inbox未整理は0件"))
        XCTAssertTrue(request.text.contains("最初は顧客向けアップデートを確認から始めましょう。"))
        XCTAssertLessThanOrEqual(request.text.count, 280)
    }

    func testReadoutRedactsSecretsAndShortensLongFocusTitle() {
        let secret = "sk-proj-verysecret123"
        let longTitle = "Prepare \(secret) launch summary with customer evidence, decision history, status, next action, and risk notes"
        let review = dailyReview(
            sourceTranscript: "Read this aloud",
            phase: .evening,
            overdueCount: 1,
            dueTodayCount: 4,
            inboxUntriagedCount: 2,
            focusItems: [
                DailyPlanningFocusItem(taskID: 44, title: longTitle, reason: "Keep moving.")
            ]
        )

        let request = DailyPlanningReviewReadoutBuilder.makeRequest(
            review: review,
            languageCode: "en",
            voiceID: "af_heart"
        )

        XCTAssertTrue(request.text.contains("Evening planning review."))
        XCTAssertTrue(request.text.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(request.text.contains(secret))
        XCTAssertFalse(request.text.contains("risk notes"))
        XCTAssertLessThanOrEqual(request.text.count, 280)
    }

    func testReadoutRedactsLocalPathsFromFocusTitle() {
        let localPath = "/Users/example/Library/Application Support/Suisui/Voice/speech.wav"
        let review = dailyReview(
            sourceTranscript: "Read this aloud",
            phase: .morning,
            overdueCount: 0,
            dueTodayCount: 1,
            inboxUntriagedCount: 0,
            focusItems: [
                DailyPlanningFocusItem(
                    taskID: 45,
                    title: "Review \(localPath) before standup",
                    reason: "Keep local paths out of speech prompts."
                )
            ]
        )

        let request = DailyPlanningReviewReadoutBuilder.makeRequest(
            review: review,
            languageCode: "en",
            voiceID: "af_heart"
        )

        XCTAssertTrue(request.text.contains("[REDACTED_PATH]"))
        XCTAssertFalse(request.text.contains(localPath))
        XCTAssertFalse(request.text.contains("Application Support"))
        XCTAssertFalse(request.text.contains("speech.wav"))
    }

    func testReadoutUsesCaptureFallbackWhenNoFocusItemsExist() {
        let review = dailyReview(
            sourceTranscript: "今日の計画を読んで",
            phase: .evening,
            overdueCount: 0,
            dueTodayCount: 0,
            inboxUntriagedCount: 0,
            focusItems: []
        )

        let request = DailyPlanningReviewReadoutBuilder.makeRequest(
            review: review,
            languageCode: "ja",
            voiceID: "jf_alpha"
        )

        XCTAssertTrue(request.text.contains("次のタスクを登録しましょう。"))
        XCTAssertFalse(request.text.contains("今日の計画を読んで"))
    }

    private func dailyReview(
        sourceTranscript: String,
        phase: DailyPlanningReviewPhase,
        overdueCount: Int,
        dueTodayCount: Int,
        inboxUntriagedCount: Int,
        focusItems: [DailyPlanningFocusItem]
    ) -> DailyPlanningReview {
        DailyPlanningReview(
            sourceTranscript: sourceTranscript,
            phase: phase,
            requestedMinutes: nil,
            headline: "Daily planning",
            spokenSummary: "Existing English summary should not be reused blindly.",
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            inboxUntriagedCount: inboxUntriagedCount,
            recommendedTaskID: focusItems.first?.taskID,
            focusItems: focusItems,
            scheduleBlocks: []
        )
    }
}
