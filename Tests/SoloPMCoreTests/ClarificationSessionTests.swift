import XCTest
@testable import SoloPMCore

final class ClarificationSessionTests: XCTestCase {
    func testEnglishFlowFillsMissingSlotsOneByOneAndResolves() {
        var session = ClarificationSession(
            originalUtterance: "Create a task and run it after approval",
            requiredSlots: [.project, .dueDate, .executionApproval]
        )

        guard case .needsClarification(let question1, let remaining1) = session.state else {
            return XCTFail("Expected needs clarification for the first slot.")
        }
        XCTAssertEqual(question1.slot, .project)
        XCTAssertEqual(remaining1, [.project, .dueDate, .executionApproval])

        let stateAfterProject = session.answer("Alpha Team")
        guard case .needsClarification(let question2, let remaining2) = stateAfterProject else {
            return XCTFail("Expected needs clarification after answering project.")
        }
        XCTAssertEqual(question2.slot, .dueDate)
        XCTAssertEqual(remaining2, [.dueDate, .executionApproval])

        let stateAfterDueDate = session.answer("tomorrow")
        guard case .needsClarification(let question3, let remaining3) = stateAfterDueDate else {
            return XCTFail("Expected needs clarification after answering due date.")
        }
        XCTAssertEqual(question3.slot, .executionApproval)
        XCTAssertEqual(remaining3, [.executionApproval])

        let finalState = session.answer("yes")
        guard case .resolved(let result) = finalState else {
            return XCTFail("Expected resolved state after all slots are answered.")
        }
        XCTAssertEqual(result.originalUtterance, "Create a task and run it after approval")

        guard case .text(let project) = result.answers[.project] else {
            return XCTFail("Project should be stored as text.")
        }
        XCTAssertEqual(project, "Alpha Team")

        guard case .text(let dueDate) = result.answers[.dueDate] else {
            return XCTFail("Due date should be stored as text.")
        }
        XCTAssertEqual(dueDate, "tomorrow")

        guard case .approval(let approval) = result.answers[.executionApproval] else {
            return XCTFail("Execution approval should be stored as approval value.")
        }
        XCTAssertTrue(approval)
    }

    func testJapaneseFlowHandlesProjectDueDateAndDestinationWithClarification() {
        var session = ClarificationSession(
            originalUtterance: "明日のリリースタスクを作って",
            requiredSlots: [.project, .dueDate, .destination]
        )

        guard case .needsClarification(let question1, let remaining1) = session.state else {
            return XCTFail("Expected needs clarification for project.")
        }
        XCTAssertEqual(question1.slot, .project)
        XCTAssertEqual(remaining1, [.project, .dueDate, .destination])

        let stateAfterEmpty = session.answer("   ")
        guard case .needsClarification(_, let remainingAfterEmpty) = stateAfterEmpty else {
            return XCTFail("Expected needs clarification when empty answer is given.")
        }
        XCTAssertEqual(remainingAfterEmpty, [.project, .dueDate, .destination])

        XCTAssertEqual(
            session.answer("   "),
            .needsClarification(
                question: ClarificationQuestion(slot: .project, prompt: "Which project should this request belong to?"),
                remainingSlots: [.project, .dueDate, .destination]
            )
        )

        _ = session.answer("営業プロジェクト")
        guard case .needsClarification(let question2, let remaining2) = session.state else {
            return XCTFail("Expected needs clarification for due date.")
        }
        XCTAssertEqual(question2.slot, .dueDate)
        XCTAssertEqual(remaining2, [.dueDate, .destination])

        let stateAfterDueDate = session.answer("明日")
        guard case .needsClarification(let question3, let remaining3) = stateAfterDueDate else {
            return XCTFail("Expected needs clarification for destination.")
        }
        XCTAssertEqual(question3.slot, .destination)
        XCTAssertEqual(remaining3, [.destination])

        let finalState = session.answer("Slack")
        guard case .resolved(let result) = finalState else {
            return XCTFail("Expected resolved after filling destination.")
        }
        XCTAssertEqual(result.answers[.project], .text("営業プロジェクト"))
        guard case .text(let dueDate) = result.answers[.dueDate] else {
            return XCTFail("Due date should be resolved.")
        }
        XCTAssertEqual(dueDate, "明日")
        XCTAssertEqual(result.answers[.destination], .text("Slack"))
    }

    func testUnknownAnswersDoNotResolveAndKeepClarificationState() {
        var session = ClarificationSession(
            originalUtterance: "Create a task",
            requiredSlots: [.dueDate]
        )

        XCTAssertEqual(
            session.answer("not sure"),
            .needsClarification(
                question: ClarificationQuestion(
                    slot: .dueDate,
                    prompt: "When is the due date for this request?"
                ),
                remainingSlots: [.dueDate]
            )
        )
        XCTAssertEqual(
            session.state,
            .needsClarification(
                question: ClarificationQuestion(
                    slot: .dueDate,
                    prompt: "When is the due date for this request?"
                ),
                remainingSlots: [.dueDate]
            )
        )
    }

    func testNegativeApprovalAnswersAreNotTreatedAsApprovedBySubstringMatch() {
        for answer in ["not approved", "not ok", "not okay", "承認しない", "承認はしない"] {
            var session = ClarificationSession(
                originalUtterance: "Run the approved plan",
                requiredSlots: [.executionApproval]
            )

            let state = session.answer(answer)

            guard case .resolved(let result) = state else {
                return XCTFail("Expected explicit negative approval to resolve as rejected.")
            }
            XCTAssertEqual(result.answers[.executionApproval], .approval(false))
        }
    }

    func testSessionRecordsClarificationTurnsForQueueReview() {
        var session = ClarificationSession(
            originalUtterance: "Run the approved plan",
            resolvedRoute: VoiceCommandRoute(
                utterance: "Run the approved plan",
                intent: .execution,
                disposition: .routed,
                confidence: .high,
                interpretationSummary: "Routed as execution intent."
            ),
            requiredSlots: [.repository, .executionScope, .executionApproval]
        )

        _ = session.answer("soloPM")
        _ = session.answer("only run tests")
        let finalState = session.answer("approved")

        guard case .resolved(let result) = finalState else {
            return XCTFail("Expected resolved state after all execution slots are answered.")
        }
        XCTAssertEqual(result.resolvedRoute?.intent, .execution)
        XCTAssertEqual(result.answers[.repository], .text("soloPM"))
        XCTAssertEqual(result.answers[.executionScope], .text("only run tests"))
        XCTAssertEqual(result.turns.map(\.slot), [.repository, .executionScope, .executionApproval])
        XCTAssertEqual(result.turns.first?.question.prompt, "Which repository or project directory should this use?")
        XCTAssertEqual(result.turns.last?.answer, .approval(true))
    }
}
