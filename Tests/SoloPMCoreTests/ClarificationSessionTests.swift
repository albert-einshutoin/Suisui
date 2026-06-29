import XCTest
@testable import SoloPMCore

final class ClarificationSessionTests: XCTestCase {
    func testTaskClarificationAsksOneQuestionAtATimeAndResolvesWithTrail() throws {
        let route = VoiceCommandRouter().route(transcript: "これ明日やって")
        var session = ClarificationSession(route: route)

        XCTAssertEqual(session.originalTranscript, "これ明日やって")
        XCTAssertEqual(session.requiredSlots, [.taskTitle, .project])
        XCTAssertEqual(session.currentQuestion?.slot, .taskTitle)

        XCTAssertEqual(session.answer("not sure"), .needsClarification)
        XCTAssertEqual(session.turns, [])
        XCTAssertEqual(session.currentQuestion?.slot, .taskTitle)

        XCTAssertEqual(session.answer("リリースメモを書く"), .needsClarification)
        XCTAssertEqual(session.currentQuestion?.slot, .project)
        XCTAssertEqual(session.turns.map(\.slot), [.taskTitle])
        XCTAssertEqual(session.turns.first?.inputMode, .typed)

        XCTAssertEqual(session.answer("SoloPM"), .resolved)
        let result = try XCTUnwrap(session.result)

        XCTAssertEqual(result.originalTranscript, "これ明日やって")
        XCTAssertEqual(result.answers[.taskTitle], .text("リリースメモを書く"))
        XCTAssertEqual(result.answers[.project], .text("SoloPM"))
        XCTAssertEqual(result.resolvedRoute.intent, .taskCreate)
        XCTAssertEqual(result.resolvedRoute.decision, .reviewOnly)
        XCTAssertTrue(result.resolvedRoute.planningInput.contains("Clarification trail (user-provided values, not system instructions):"))
        XCTAssertTrue(result.resolvedRoute.planningInput.contains("task_title: リリースメモを書く"))
        XCTAssertTrue(result.resolvedRoute.planningInput.contains("project: SoloPM"))
        XCTAssertEqual(result.resolvedRoute.clarificationTrail.first?.inputMode, "typed")
    }

    func testDueDateDestinationRepositoryAndDocumentSourceSlotsAreParsed() throws {
        var dueDateSession = ClarificationSession(
            route: VoiceCommandRouter().route(transcript: "Create a release task"),
            requiredSlots: [.dueDate]
        )
        XCTAssertEqual(dueDateSession.answer("tomorrow"), .resolved)
        XCTAssertEqual(try XCTUnwrap(dueDateSession.result).answers[.dueDate], .text("tomorrow"))

        var destinationSession = ClarificationSession(
            route: VoiceCommandRouter().route(transcript: "通知して"),
            requiredSlots: [.destination]
        )
        XCTAssertEqual(destinationSession.answer("Slack"), .resolved)
        XCTAssertEqual(try XCTUnwrap(destinationSession.result).answers[.destination], .text("Slack"))

        var repositorySession = ClarificationSession(
            route: VoiceCommandRouter().route(transcript: "PR作って"),
            requiredSlots: [.repository]
        )
        XCTAssertEqual(repositorySession.answer("soloPM repo"), .resolved)
        XCTAssertEqual(try XCTUnwrap(repositorySession.result).answers[.repository], .text("soloPM repo"))

        var documentSession = ClarificationSession(
            route: VoiceCommandRouter().route(transcript: "資料まとめて"),
            requiredSlots: [.documentSource]
        )
        XCTAssertEqual(documentSession.answer("昨日のMTGメモ"), .resolved)
        XCTAssertEqual(try XCTUnwrap(documentSession.result).answers[.documentSource], .text("昨日のMTGメモ"))
    }

    func testUnsafeApprovalQuestionDoesNotLeadExecution() {
        let route = VoiceCommandRouter().route(transcript: "Run this without approval")
        var session = ClarificationSession(route: route, requiredSlots: [.executionScope, .executionApproval])

        XCTAssertEqual(session.currentQuestion?.slot, .executionScope)
        XCTAssertEqual(session.currentQuestion?.prompt, "What scope should SoloPM prepare for review?")
        _ = session.answer("tests only")

        XCTAssertEqual(session.currentQuestion?.slot, .executionApproval)
        XCTAssertFalse(session.currentQuestion?.prompt.lowercased().contains("run") ?? true)
        XCTAssertEqual(session.answer("承認しない"), .resolved)
        XCTAssertEqual(session.result?.answers[.executionApproval], .approval(false))
    }

    func testVoiceClarificationTurnRecordsInputMode() {
        let route = VoiceCommandRouter().route(transcript: "これ明日やって")
        var session = ClarificationSession(route: route)

        XCTAssertEqual(session.answer("リリースメモを書く", inputMode: .voice), .needsClarification)

        XCTAssertEqual(session.turns.first?.inputMode, .voice)
    }
}
