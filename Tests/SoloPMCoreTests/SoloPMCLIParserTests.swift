import XCTest
@testable import SoloPMCore

final class SoloPMCLIParserTests: XCTestCase {
    func testParsesReadOnlyCommands() throws {
        XCTAssertEqual(try SoloPMCLIParser().parse(["status"]).command, .status)
        XCTAssertEqual(try SoloPMCLIParser().parse(["tasks", "due"]).command, .tasksDue)
        XCTAssertEqual(try SoloPMCLIParser().parse(["plan", "validate", "plan.json"]).command, .planValidate(path: "plan.json"))
        XCTAssertEqual(try SoloPMCLIParser().parse(["frames", "search", "deadline watcher"]).command, .framesSearch(query: "deadline watcher"))
    }

    func testRejectsWriteOrUnknownCommandsWithUsageExitCode() {
        XCTAssertThrowsError(try SoloPMCLIParser().parse(["github", "issue", "create"])) { error in
            XCTAssertEqual((error as? SoloPMCLIParseError)?.exitCode, .usage)
        }

        XCTAssertThrowsError(try SoloPMCLIParser().parse(["tasks", "create"])) { error in
            XCTAssertEqual((error as? SoloPMCLIParseError)?.exitCode, .usage)
        }
    }

    func testPlanValidationExitCodeReflectsValidationResult() {
        let valid = ActionPlanValidationResult(issues: [])
        let invalid = ActionPlanValidationResult(
            issues: [.blocking(path: "actions", message: "ActionPlan must contain at least one action.")]
        )

        XCTAssertEqual(SoloPMCLIExitCode.planValidation(valid), .success)
        XCTAssertEqual(SoloPMCLIExitCode.planValidation(invalid), .validationFailed)
        XCTAssertEqual(SoloPMCLIExitCode.validationFailed.rawValue, 65)
    }
}
