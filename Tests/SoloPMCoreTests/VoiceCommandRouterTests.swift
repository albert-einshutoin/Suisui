import XCTest
@testable import SoloPMCore

final class VoiceCommandRouterTests: XCTestCase {
    func testRouterClassifiesRepresentativeJapaneseAndEnglishUtterances() {
        let router = VoiceCommandRouter()

        XCTAssertEqual(router.route("明日のリリース確認タスクを作って").intent, .task)
        XCTAssertEqual(router.route("Create a task to review release notes tomorrow").intent, .task)

        XCTAssertEqual(router.route("明日の午後3時に1on1を予定して").intent, .schedule)
        XCTAssertEqual(router.route("Schedule a work block for Friday afternoon").intent, .schedule)

        XCTAssertEqual(router.route("今週の進捗メモをまとめて").intent, .document)
        XCTAssertEqual(router.route("Draft release notes from the selected documents").intent, .document)

        XCTAssertEqual(router.route("承認済みの実行プランを走らせて").intent, .execution)
        XCTAssertEqual(router.route("Run the approved plan in this workspace").intent, .execution)
    }

    func testRouterMarksStronglyAmbiguousUtterancesForClarification() {
        let router = VoiceCommandRouter()

        let mixedIntent = router.route("明日の会議メモを作って")
        XCTAssertEqual(mixedIntent.intent, .unknown)
        XCTAssertEqual(mixedIntent.disposition, .needsClarification)
        XCTAssertEqual(mixedIntent.confidence, .low)

        let unsupported = router.route("Please handle it")
        XCTAssertEqual(unsupported.intent, .unknown)
        XCTAssertEqual(unsupported.disposition, .needsClarification)
        XCTAssertEqual(unsupported.confidence, .low)
    }

    func testRouterKeepsUnknownCommandsOutOfExecution() {
        let router = VoiceCommandRouter()

        let route = router.route("やっておいて")

        XCTAssertEqual(route.intent, .unknown)
        XCTAssertEqual(route.disposition, .needsClarification)
        XCTAssertNotEqual(route.intent, .execution)
    }

    func testRouterRejectsExplicitlyUnapprovedExecutionRequests() {
        let router = VoiceCommandRouter()

        for utterance in [
            "Run the unapproved plan in this workspace",
            "Run without approval in this workspace",
            "Run the not reviewed plan",
            "未承認のプランを実行して"
        ] {
            let route = router.route(utterance)

            XCTAssertEqual(route.intent, .unknown, utterance)
            XCTAssertEqual(route.disposition, .needsClarification, utterance)
            XCTAssertNotEqual(route.intent, .execution, utterance)
        }
    }

    func testRouterRequiresApprovalOrPlanSignalsBeforeExecution() {
        let router = VoiceCommandRouter()

        for utterance in ["Run it", "実行して"] {
            let route = router.route(utterance)

            XCTAssertEqual(route.intent, .unknown)
            XCTAssertEqual(route.disposition, .needsClarification)
            XCTAssertNotEqual(route.intent, .execution)
        }
    }

    func testRouterReturnsConfidenceAndInterpretationSummary() {
        let router = VoiceCommandRouter()

        let routed = router.route("Create a task to review release notes tomorrow")
        XCTAssertEqual(routed.confidence, .high)
        XCTAssertTrue(routed.interpretationSummary.contains("task"))

        let unclear = router.route("明日の会議メモを作って")
        XCTAssertEqual(unclear.confidence, .low)
        XCTAssertTrue(unclear.interpretationSummary.contains("clarification"))
    }
}
