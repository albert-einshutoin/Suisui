import XCTest
@testable import SoloPMCore

final class VoiceCommandRouterTests: XCTestCase {
    private let router = VoiceCommandRouter()

    func testIntentDisplayNamesAreUserFacingLabels() {
        XCTAssertEqual(VoiceCommandIntentKind.taskCreate.displayName, "Create task")
        XCTAssertEqual(VoiceCommandIntentKind.developmentPRWorkflow.displayName, "Prepare PR workflow")
        XCTAssertFalse(VoiceCommandIntentKind.taskCreate.displayName.contains("."))
        XCTAssertFalse(VoiceCommandIntentKind.developmentPRWorkflow.displayName.contains("_"))
    }

    func testRoutesJapaneseTaskCreateCommand() {
        let result = router.route(transcript: "リリースメモのタスクを作成して")

        XCTAssertEqual(result.intent, .taskCreate)
        XCTAssertEqual(result.originalTranscript, "リリースメモのタスクを作成して")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
        XCTAssertFalse(result.needsClarification)
        XCTAssertTrue(result.interpretationSummary.contains("task.create"))
    }

    func testRoutesEnglishScheduleCommand() {
        let result = router.route(transcript: "Plan my schedule for tomorrow morning")

        XCTAssertEqual(result.intent, .schedulePlan)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
        XCTAssertEqual(result.decision, .reviewOnly)
    }

    func testRoutesTaskTriageCommand() {
        let result = router.route(transcript: "Inboxのタスクを優先順位で整理して")

        XCTAssertEqual(result.intent, .taskTriage)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
        XCTAssertEqual(result.decision, .reviewOnly)
    }

    func testRoutesMixedLanguageDocumentBriefCommand() {
        let result = router.route(transcript: "明日の meeting brief を作って")

        XCTAssertEqual(result.intent, .documentBrief)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
    }

    func testShortEnglishSignalsDoNotMatchInsideLongerWords() {
        let documentResult = router.route(transcript: "Prepare the meeting brief")
        let deadlineResult = router.route(transcript: "Create a deadline task for tomorrow")

        XCTAssertEqual(documentResult.intent, .documentBrief)
        XCTAssertFalse(documentResult.matchedSignals.contains("pr"))
        XCTAssertEqual(deadlineResult.intent, .taskCreate)
        XCTAssertFalse(deadlineResult.matchedSignals.contains("line"))
    }

    func testRoutesDevelopmentPRWorkflowCommand() {
        let result = router.route(transcript: "このプロジェクトで branch を作って PR workflow の準備をして")

        XCTAssertEqual(result.intent, .developmentPRWorkflow)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
        XCTAssertTrue(result.reviewOnly)
    }

    func testRoutesNotificationDraftWithoutSending() {
        let result = router.route(transcript: "Slack notification draft for the release delay")

        XCTAssertEqual(result.intent, .notificationDraft)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
        XCTAssertTrue(result.reviewOnly)
    }

    func testRoutesStatusQuestion() {
        let result = router.route(transcript: "今日のタスクは何件で進捗はどう?")

        XCTAssertEqual(result.intent, .statusAsk)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
    }

    func testAmbiguousTranscriptRequiresClarification() {
        let result = router.route(transcript: "いい感じにして")

        XCTAssertEqual(result.intent, .clarify)
        XCTAssertTrue(result.needsClarification)
        XCTAssertEqual(result.decision, .clarifyRequired)
        XCTAssertLessThan(result.confidence, 0.7)
        XCTAssertNotNil(result.clarificationReason)
    }

    func testUnsafeExternalSendRequiresClarification() {
        let result = router.route(transcript: "Slackに今すぐ送信して")

        XCTAssertEqual(result.intent, .clarify)
        XCTAssertTrue(result.needsClarification)
        XCTAssertLessThan(result.confidence, 0.7)
        XCTAssertTrue(result.clarificationReason?.contains("external") ?? false)
    }

    func testUnsafeExecutionBypassingReviewRequiresClarification() {
        let result = router.route(transcript: "Run this without approval and push the workflow")

        XCTAssertEqual(result.intent, .clarify)
        XCTAssertEqual(result.decision, .clarifyRequired)
        XCTAssertTrue(result.needsClarification)
        XCTAssertLessThan(result.confidence, 0.7)
        XCTAssertTrue(result.clarificationReason?.contains("approval") ?? false)
    }
}
