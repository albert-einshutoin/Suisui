import Foundation
import XCTest

final class SelectiveCIWorkflowTests: XCTestCase {
    func testWorkflowSeparatesPRSelectionFromFullValidationEvents() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")

        XCTAssertTrue(workflow.contains("pull_request:"))
        XCTAssertTrue(workflow.contains("branches:\n      - main\n      - develop\n      - 'release/**'"))
        XCTAssertTrue(workflow.contains("tags:\n      - 'v*'"))
        XCTAssertTrue(workflow.contains("release:\n    types: [published]"))
        XCTAssertTrue(workflow.contains("github.event_name }}-${{ github.event.pull_request.number || github.ref"))
        XCTAssertTrue(workflow.contains("schedule:"))
        XCTAssertTrue(workflow.contains("cron: '17 18 * * *'"))
        XCTAssertTrue(workflow.contains("./ci/run-pr-ci.sh"))
        XCTAssertTrue(workflow.contains("name: Complete validation"))
        XCTAssertTrue(workflow.contains("run: ./ci/run-full.sh"))
        XCTAssertFalse(workflow.contains("Shadow full SwiftPM"))
        XCTAssertFalse(workflow.contains("Compare selective and full results"))
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
        XCTAssertTrue(workflow.contains("needs.test_strategy.outputs.ui_visual_state != '0'"))
        XCTAssertTrue(workflow.contains("failure_reason=visual-selection-result-invalid"))
        XCTAssertTrue(workflow.contains("needs.test_strategy.outputs.ui_performance == 'true'"))
        XCTAssertFalse(workflow.contains("./ci/compare-runs.py"))
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
        XCTAssertTrue(fullRunner.contains("./script/check_pseudo_voiceover_paths.sh"))
        XCTAssertFalse(fullRunner.contains("check_pseudo_voiceover_paths.sh --swift-test"))
        XCTAssertFalse(fullRunner.contains("./scripts/ci.sh source-contracts"))
        XCTAssertTrue(fullRunner.contains("./script/check_security_regressions.sh"))
        XCTAssertFalse(fullRunner.contains("impact/analyze"))
        XCTAssertFalse(fullRunner.contains("ci/config"))
        XCTAssertTrue(orchestrator.contains("selected test runner setup failed"))
        XCTAssertTrue(orchestrator.contains("escalate-plan.py"))
        XCTAssertTrue(orchestrator.contains("\"$ROOT_DIR/ci/run-full.sh\""))
    }

    func testFullAndHostedValidationShareFailClosedRustBoundaryRunner() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")
        let fullRunner = try readRepositoryFile("ci/run-full.sh")
        let rustRunner = try readRepositoryFile("ci/verify-rust-boundaries.sh")

        XCTAssertTrue(fullRunner.contains("./ci/verify-rust-boundaries.sh --require-cargo"))
        XCTAssertFalse(fullRunner.contains("SUISUI_REQUIRE_RUST_BOUNDARIES"))
        XCTAssertTrue(workflow.contains("./ci/verify-rust-boundaries.sh --require-cargo"))
        XCTAssertFalse(workflow.contains("SUISUI_REQUIRE_RUST_BOUNDARIES"))
        XCTAssertFalse(workflow.contains("cargo fmt --manifest-path rust/kokoro-helper/Cargo.toml --check"))
        XCTAssertTrue(rustRunner.contains("rust/kokoro-helper/Cargo.toml"))
        XCTAssertTrue(rustRunner.contains("rust/embedding-helper/Cargo.toml"))
        XCTAssertTrue(rustRunner.contains("cargo fmt --manifest-path"))
        XCTAssertTrue(rustRunner.contains("cargo test --manifest-path"))
        XCTAssertTrue(rustRunner.contains("cargo clippy --manifest-path"))
        XCTAssertTrue(rustRunner.contains("--require-cargo"))
    }

    func testDedicatedRustJobRunsOnlyForSelectivePullRequestValidation() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")
        let rustStart = try XCTUnwrap(workflow.range(of: "\n  kokoro-rust-poc:"))
        let visualStart = try XCTUnwrap(workflow.range(of: "\n  ui-runtime:", range: rustStart.upperBound..<workflow.endIndex))
        let rustJob = String(workflow[rustStart.lowerBound..<visualStart.lowerBound])

        XCTAssertTrue(rustJob.contains("needs:\n      - test_strategy"))
        XCTAssertTrue(rustJob.contains("if: ${{ always() && github.event_name == 'pull_request' && needs.test_strategy.outputs.strategy != 'full' }}"))

        XCTAssertTrue(workflow.contains("TEST_STRATEGY_RESULT: ${{ needs.test_strategy.result }}"))
        XCTAssertTrue(workflow.contains("TEST_STRATEGY: ${{ needs.test_strategy.outputs.strategy }}"))
        XCTAssertTrue(workflow.contains("FULL_VALIDATION_RESULT: ${{ needs.full_validation.result }}"))
        XCTAssertTrue(workflow.contains("rust_result=\"$FULL_VALIDATION_RESULT\""))
        XCTAssertTrue(workflow.contains("$TEST_STRATEGY_RESULT\" != \"success\""))
        XCTAssertTrue(workflow.contains("rust_result=\"$TEST_STRATEGY_RESULT\""))
        XCTAssertTrue(workflow.contains("rust_result=\"$RUST_BOUNDARY_RESULT\""))
    }

    func testCompleteValidationRoutesRestoreBothRustBoundaryCaches() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")
        let selectedStart = try XCTUnwrap(workflow.range(of: "\n  test_strategy:"))
        let fullStart = try XCTUnwrap(workflow.range(of: "\n  full_validation:"))
        let rustStart = try XCTUnwrap(workflow.range(of: "\n  kokoro-rust-poc:"))
        let completeValidationJobs = [
            String(workflow[selectedStart.lowerBound..<fullStart.lowerBound]),
            String(workflow[fullStart.lowerBound..<rustStart.lowerBound])
        ]

        for job in completeValidationJobs {
            XCTAssertTrue(job.contains("name: Restore bounded Cargo cache"))
            XCTAssertTrue(job.contains("rust/kokoro-helper/target"))
            XCTAssertTrue(job.contains("rust/embedding-helper/target"))
            XCTAssertTrue(job.contains("~/.cargo/registry"))
            XCTAssertTrue(job.contains("~/.cargo/git"))
            XCTAssertTrue(job.contains("hashFiles('rust/kokoro-helper/Cargo.lock', 'rust/embedding-helper/Cargo.lock')"))
        }
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
            "誤判定",
            "キャッシュ",
            "毎日 03:17 JST",
            "release tag",
            "GitHub Release",
            "oldPath",
            "executedTestCount",
            "filterが実行0件"
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
