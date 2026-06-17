import XCTest
@testable import SoloPMCore

final class PlanningPromptBuilderTests: XCTestCase {
    func testPromptContainsCurrentDateTimezoneToolsAndUserInput() {
        let request = PlanningRequest(
            userInput: "Create a task for next Friday",
            currentDate: Date(timeIntervalSince1970: 1_783_200_000),
            timeZoneIdentifier: "Asia/Tokyo",
            availableTools: [.taskCreate, .projectCreate],
            knowledgeFrameCandidates: []
        )

        let prompt = PlanningPromptBuilder().buildPrompt(for: request)

        XCTAssertTrue(prompt.user.contains("Time zone: Asia/Tokyo"))
        XCTAssertTrue(prompt.user.contains("project.create"))
        XCTAssertTrue(prompt.user.contains("task.create"))
        XCTAssertTrue(prompt.user.contains("Create a task for next Friday"))
    }

    func testPromptForbidsDangerousOperations() {
        let prompt = PlanningPromptBuilder().buildPrompt(
            for: PlanningRequest(userInput: "Delete this file")
        )

        XCTAssertTrue(prompt.system.contains("Dangerous operations are forbidden"))
        XCTAssertTrue(prompt.system.contains("Git push"))
        XCTAssertTrue(prompt.system.contains("file delete"))
    }
}

