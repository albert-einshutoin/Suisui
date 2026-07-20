import XCTest
@testable import SuisuiCore

final class VoiceCommandRouterTests: XCTestCase {
    private let router = VoiceCommandRouter()

    func testIntentDisplayNamesAreUserFacingLabels() {
        XCTAssertEqual(VoiceCommandIntentKind.taskCreate.displayName, "Create task")
        XCTAssertEqual(VoiceCommandIntentKind.developmentPRWorkflow.displayName, "Prepare PR workflow")
        XCTAssertEqual(VoiceCommandIntentKind.connectorSendGate.displayName, "Review connector send")
        XCTAssertFalse(VoiceCommandIntentKind.taskCreate.displayName.contains("."))
        XCTAssertFalse(VoiceCommandIntentKind.developmentPRWorkflow.displayName.contains("_"))
    }

    func testRoutesJapaneseDailyPlanningReviewCommand() {
        let result = router.route(transcript: "今から90分で今日やることを3つに絞って")

        XCTAssertEqual(result.intent, .dailyPlanningReview)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
        XCTAssertEqual(result.decision, .reviewOnly)
        XCTAssertTrue(result.reviewOnly)
    }

    func testRoutesEnglishDailyPlanningReviewCommand() {
        let result = router.route(transcript: "What should I focus on today for the next 90 minutes?")

        XCTAssertEqual(result.intent, .dailyPlanningReview)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
        XCTAssertEqual(result.decision, .reviewOnly)
    }

    func testRoutesNaturalTodayReviewCommandsToDailyPlanningReview() {
        let transcripts = [
            "Open Today Review",
            "today review",
            "日次計画レビューを開いて",
            "今日のレビューを開いて"
        ]

        for transcript in transcripts {
            let result = router.route(transcript: transcript)

            XCTAssertEqual(result.intent, .dailyPlanningReview, transcript)
            XCTAssertGreaterThanOrEqual(result.confidence, 0.7, transcript)
            XCTAssertEqual(result.decision, .reviewOnly, transcript)
        }
    }

    func testRoutesDailyPlanningAcceptanceExamples() {
        let transcripts = [
            "今日やることを3つに絞って",
            "遅れてるものだけ教えて",
            "今から90分でできる順に並べて",
            "夕方にもう一回確認して",
            "Tell me only the overdue work",
            "Check in this evening about today's next actions"
        ]

        for transcript in transcripts {
            let result = router.route(transcript: transcript)

            XCTAssertEqual(result.intent, .dailyPlanningReview, transcript)
            XCTAssertGreaterThanOrEqual(result.confidence, 0.7, transcript)
            XCTAssertEqual(result.decision, .reviewOnly, transcript)
        }
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

    func testRoutesCommitWorkflowCommandAsDevelopmentReviewOnly() {
        let result = router.route(transcript: "この変更をコミットしてPRにしたい")

        XCTAssertEqual(result.intent, .developmentPRWorkflow)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
        XCTAssertEqual(result.decision, .reviewOnly)
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

    func testDailyPlanningOverdueSignalsDoNotStealExplicitCountStatusQuestion() {
        for transcript in [
            "今日の遅れてるタスクは何件で進捗はどう?",
            "遅れてるタスクは何件?",
            "How many overdue tasks today?",
            "Show overdue progress today"
        ] {
            let result = router.route(transcript: transcript)

            XCTAssertEqual(result.intent, .statusAsk, transcript)
            XCTAssertGreaterThanOrEqual(result.confidence, 0.7, transcript)
        }
    }

    func testDailyPlanningOverdueSignalsDoNotStealExplicitScheduleOrCreateCommands() {
        let schedule = router.route(transcript: "Schedule overdue work for tomorrow")
        let japaneseSchedule = router.route(transcript: "今日の予定をできる順に並べて")
        let taskCreate = router.route(transcript: "Create an overdue task for today")

        XCTAssertEqual(schedule.intent, .schedulePlan)
        XCTAssertGreaterThanOrEqual(schedule.confidence, 0.7)
        XCTAssertEqual(japaneseSchedule.intent, .schedulePlan)
        XCTAssertGreaterThanOrEqual(japaneseSchedule.confidence, 0.7)
        XCTAssertEqual(taskCreate.intent, .taskCreate)
        XCTAssertGreaterThanOrEqual(taskCreate.confidence, 0.7)
    }

    func testAmbiguousTranscriptRequiresClarification() {
        let result = router.route(transcript: "いい感じにして")

        XCTAssertEqual(result.intent, .clarify)
        XCTAssertTrue(result.needsClarification)
        XCTAssertEqual(result.decision, .clarifyRequired)
        XCTAssertLessThan(result.confidence, 0.7)
        XCTAssertNotNil(result.clarificationReason)
    }

    func testExplicitExternalSendRoutesToConnectorSendGate() {
        let result = router.route(transcript: "Slackに今すぐ送信して")

        XCTAssertEqual(result.intent, .connectorSendGate)
        XCTAssertEqual(result.decision, .reviewOnly)
        XCTAssertFalse(result.needsClarification)
        XCTAssertTrue(result.reviewOnly)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
        XCTAssertTrue(result.interpretationSummary.contains("connector.send_gate"))
        XCTAssertTrue(result.matchedSignals.contains("今すぐ送信"))
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
