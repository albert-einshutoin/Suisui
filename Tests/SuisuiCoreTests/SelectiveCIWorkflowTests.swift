import Foundation
import XCTest

final class SelectiveCIWorkflowTests: XCTestCase {
    func testWorkflowSeparatesPRSelectionFromFullValidationEvents() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")

        XCTAssertTrue(workflow.contains("pull_request:"))
        XCTAssertTrue(workflow.contains("branches:\n      - main\n      - develop\n      - 'release/**'"))
        XCTAssertTrue(workflow.contains("schedule:"))
        XCTAssertTrue(workflow.contains("cron: '17 18 * * *'"))
        XCTAssertTrue(workflow.contains("./ci/run-pr-ci.sh"))
        XCTAssertTrue(workflow.contains("force-full-reason"))
        XCTAssertTrue(workflow.contains("Shadow full SwiftPM (rollout comparison)"))
        XCTAssertTrue(workflow.contains("needs.test_strategy.outputs.shadow_full == 'true'"))
        XCTAssertTrue(workflow.contains("synthesized pull-request merge revision"))
        XCTAssertFalse(workflow.contains("ref: ${{ github.event.pull_request.head.sha"))
        XCTAssertFalse(workflow.contains("pull_request_target:"))
    }

    func testWorkflowUsesBoundedCacheAndPlanDrivenE2EGates() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")

        XCTAssertTrue(workflow.contains("uses: actions/cache@v4"))
        XCTAssertTrue(workflow.contains("uses: actions/cache/restore@v4"))
        XCTAssertTrue(workflow.contains("${{ runner.os }}-${{ runner.arch }}-swift-6-"))
        XCTAssertTrue(workflow.contains("hashFiles('Package.resolved', 'Package.swift')"))
        XCTAssertTrue(workflow.contains("needs.test_strategy.outputs.ui_runtime == 'true'"))
        XCTAssertTrue(workflow.contains("needs.test_strategy.outputs.ui_visual == 'true'"))
        XCTAssertTrue(workflow.contains("needs.test_strategy.outputs.ui_performance == 'true'"))
        XCTAssertTrue(workflow.contains("name: Compare selective and full results"))
        XCTAssertTrue(workflow.contains("./ci/compare-runs.py"))
    }

    func testImpactPolicyAndIndependentFullRunnerAreSourceControlledContracts() throws {
        let config = try readRepositoryFile("ci/config/impact.json")
        let fullRunner = try readRepositoryFile("ci/run-full.sh")
        let orchestrator = try readRepositoryFile("ci/run-pr-ci.sh")

        for marker in [
            "\"forceFullRules\"",
            "\"smokeTestTargets\"",
            "\"integrationRules\"",
            "\"e2eRules\"",
            "\"Package.resolved\"",
            "\"Sources/SuisuiCore/Database/**\"",
            "\"Sources/SuisuiCore/Security/**\"",
            "\"pattern\": \"Sources/SuisuiCore/**\""
        ] {
            XCTAssertTrue(config.contains(marker), "impact policy must include \(marker)")
        }
        XCTAssertTrue(fullRunner.contains("./scripts/ci.sh swiftpm"))
        XCTAssertTrue(fullRunner.contains("./scripts/ci.sh source-contracts"))
        XCTAssertTrue(fullRunner.contains("./script/check_security_regressions.sh"))
        XCTAssertFalse(fullRunner.contains("impact/analyze"))
        XCTAssertFalse(fullRunner.contains("ci/config"))
        XCTAssertTrue(orchestrator.contains("selected test runner setup failed"))
        XCTAssertTrue(orchestrator.contains("\"$ROOT_DIR/ci/run-full.sh\""))
    }

    func testContributorDocumentationExplainsSafeOperationAndExtensionPoints() throws {
        let documentation = try readRepositoryFile("docs/quality/selective-ci.md")

        for marker in [
            "目的",
            "判定できない場合は全テスト",
            "対応プロジェクト",
            "アダプターの追加",
            "./ci/run-pr-ci.sh",
            "./ci/run-full.sh",
            "ci/config/impact.json",
            "shadow full",
            "誤判定",
            "キャッシュ",
            "毎日 03:17 JST",
            "比較指標",
            "fullOnlyFailure"
        ] {
            XCTAssertTrue(documentation.contains(marker), "selective CI guide must include \(marker)")
        }
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let fileURL = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
