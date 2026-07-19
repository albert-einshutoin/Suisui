import XCTest
@testable import SuisuiCore

final class SuisuiCLIParserTests: XCTestCase {
    func testParsesReadOnlyCommands() throws {
        XCTAssertEqual(try SuisuiCLIParser().parse(["status"]).command, .status)
        XCTAssertEqual(try SuisuiCLIParser().parse(["tasks", "due"]).command, .tasksDue)
        XCTAssertEqual(try SuisuiCLIParser().parse(["plan", "validate", "plan.json"]).command, .planValidate(path: "plan.json"))
        XCTAssertEqual(try SuisuiCLIParser().parse(["frames", "search", "deadline watcher"]).command, .framesSearch(query: "deadline watcher"))
    }

    func testParsesHelpCommand() throws {
        XCTAssertEqual(try SuisuiCLIParser().parse([]).command, .help)
        XCTAssertEqual(try SuisuiCLIParser().parse(["help"]).command, .help)
        XCTAssertEqual(try SuisuiCLIParser().parse(["--help"]).command, .help)
        XCTAssertEqual(try SuisuiCLIParser().parse(["-h"]).command, .help)
    }

    func testUsageNamesCollisionSafeCLIProduct() {
        XCTAssertTrue(SuisuiCLIUsage.text.contains("suisui-cli status"))
        XCTAssertTrue(SuisuiCLIUsage.text.contains("suisui-cli plan validate <path>"))
    }

    func testSwiftPMExecutableProductNamesDoNotCollideOnCaseInsensitiveFilesystems() throws {
        let manifest = try String(
            contentsOf: packageRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(manifest.contains("name: \"Suisui\""))
        XCTAssertTrue(manifest.contains("name: \"suisui-cli\""))
        XCTAssertFalse(manifest.contains("name: \"suisui\","))
    }

    func testRejectsWriteOrUnknownCommandsWithUsageExitCode() {
        XCTAssertThrowsError(try SuisuiCLIParser().parse(["github", "issue", "create"])) { error in
            XCTAssertEqual((error as? SuisuiCLIParseError)?.exitCode, .usage)
        }

        XCTAssertThrowsError(try SuisuiCLIParser().parse(["tasks", "create"])) { error in
            XCTAssertEqual((error as? SuisuiCLIParseError)?.exitCode, .usage)
        }
    }

    func testPlanValidationExitCodeReflectsValidationResult() {
        let valid = ActionPlanValidationResult(issues: [])
        let invalid = ActionPlanValidationResult(
            issues: [.blocking(path: "actions", message: "ActionPlan must contain at least one action.")]
        )

        XCTAssertEqual(SuisuiCLIExitCode.planValidation(valid), .success)
        XCTAssertEqual(SuisuiCLIExitCode.planValidation(invalid), .validationFailed)
        XCTAssertEqual(SuisuiCLIExitCode.validationFailed.rawValue, 65)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
