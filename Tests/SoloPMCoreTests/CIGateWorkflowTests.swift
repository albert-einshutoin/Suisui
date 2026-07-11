import Foundation
import XCTest

final class CIGateWorkflowTests: XCTestCase {
    func testWorkflowDefinesStableProductionUIGatesOnPinnedMacOSRunner() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")

        XCTAssertTrue(workflow.contains("pull_request:"))
        XCTAssertTrue(workflow.contains("push:"))
        XCTAssertTrue(workflow.contains("merge_group:"))
        XCTAssertFalse(workflow.contains("pull_request_target:"))
        XCTAssertTrue(workflow.contains("permissions:\n  contents: read"))

        XCTAssertTrue(workflow.contains("name: SwiftPM macOS"))
        XCTAssertTrue(workflow.contains("name: UI Runtime (production route)"))
        XCTAssertTrue(workflow.contains("name: UI Visual (live baseline)"))
        XCTAssertTrue(workflow.contains("name: UI Performance (production route)"))
        XCTAssertGreaterThanOrEqual(workflow.components(separatedBy: "runs-on: macos-26").count - 1, 4)

        XCTAssertTrue(workflow.contains("./scripts/ci.sh swiftpm"))
        XCTAssertTrue(workflow.contains("./scripts/ci.sh ui-runtime"))
        XCTAssertTrue(workflow.contains("./scripts/ci.sh ui-visual"))
        XCTAssertTrue(workflow.contains("./scripts/ci.sh ui-performance"))
        XCTAssertFalse(workflow.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))
    }

    func testWorkflowAlwaysUploadsShortLivedSanitizedArtifactsForEveryUIGate() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")

        XCTAssertGreaterThanOrEqual(workflow.components(separatedBy: "uses: actions/upload-artifact@v4").count - 1, 3)
        XCTAssertGreaterThanOrEqual(workflow.components(separatedBy: "if: always()").count - 1, 3)
        XCTAssertGreaterThanOrEqual(workflow.components(separatedBy: "retention-days: 7").count - 1, 3)
        XCTAssertGreaterThanOrEqual(workflow.components(separatedBy: "include-hidden-files: true").count - 1, 3)
        XCTAssertTrue(workflow.contains(".tmp/ci-artifacts/ui-runtime"))
        XCTAssertTrue(workflow.contains(".tmp/ci-artifacts/ui-visual"))
        XCTAssertTrue(workflow.contains(".tmp/ci-artifacts/ui-performance"))
    }

    func testCIScriptRoutesIndependentLanesWithoutOptionalFlags() throws {
        let script = try readRepositoryFile("scripts/ci.sh")

        XCTAssertTrue(script.contains("CI_LANE=\"${1:-${SOLOPM_CI_LANE:-swiftpm}}\""))
        XCTAssertTrue(script.contains("swiftpm|ui-runtime|ui-visual|ui-performance"))
        XCTAssertTrue(script.contains("run_lane_with_artifacts"))
        XCTAssertTrue(script.contains("check_macos_ui_runner_capabilities.sh runtime"))
        XCTAssertTrue(script.contains("./script/build_and_run.sh --verify"))
        XCTAssertTrue(script.contains("run_build_and_run_verify \"$artifact_dir\""))
        XCTAssertTrue(script.contains("Only copy the path-free AX/window diagnostics"))
        XCTAssertTrue(script.contains("$verify_tmp\"/verify/*.txt"))
        XCTAssertTrue(script.contains("$verify_tmp\"/verify/*.err"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_ACCESSIBLE_CRUD_ARTIFACT_DIR=\"$artifact_dir/runtime-accessible-crud\""))
        XCTAssertTrue(script.contains("check_runtime_today_production_route_smoke.sh"))
        XCTAssertTrue(script.contains("check_runtime_accessible_crud_smoke.sh"))
        XCTAssertTrue(script.contains("check_layout_stability_smoke.sh"))
        XCTAssertTrue(script.contains("check_ci_visual_gate.sh"))
        XCTAssertTrue(script.contains("check_macos_ui_runner_capabilities.sh performance"))
        XCTAssertTrue(script.contains("check_release_launch_performance_smoke.sh"))
        XCTAssertFalse(script.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))

        let layoutGate = try readRepositoryFile("script/check_layout_stability_smoke.sh")
        XCTAssertFalse(layoutGate.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(layoutGate.contains("prepare_voiceover_review_candidate.sh"))
        XCTAssertFalse(layoutGate.contains("/usr/bin/osascript - \"$APP_NAME\""))
    }

    func testCILaneLogSanitizesBeforeTeeExposesItToPublicLog() throws {
        // Regression for the P2 review that let raw lane stdout/stderr reach
        // the GitHub Actions job log before the post-tee sanitizer ran.
        // The sanitizer must sit between the lane function and `tee` so
        // secrets and runner-local paths never appear in the public log.
        let script = try readRepositoryFile("scripts/ci.sh")

        XCTAssertTrue(
            script.contains("| sanitize_gate_log - | tee \"$raw_log\""),
            "Lane output must be piped through the sanitizer before `tee` writes the public Actions log"
        )
        XCTAssertFalse(
            script.contains("2>&1 | tee \"$raw_log\"\n  status=${PIPESTATUS[0]}"),
            "Lane output must not be tee'd raw; the previous post-tee sanitization let secrets reach the job log"
        )
        XCTAssertTrue(
            script.contains("[[ \"$input\" == \"-\" ]]"),
            "sanitize_gate_log must support a stdin/stdout mode (`-`) so it can sit in the lane pipeline"
        )
    }

    func testAutomatedReleasePreflightRequiresTheSameProductionUIGates() throws {
        let preflight = try readRepositoryFile("script/check_automated_release_preflight.sh")
        let readiness = try readRepositoryFile("script/release_readiness_report.sh")
        let accessibilityPreflight = try readRepositoryFile("script/check_accessibility_preflight.sh")
        let buildAndRun = try readRepositoryFile("script/build_and_run.sh")

        XCTAssertTrue(preflight.contains("./scripts/ci.sh ui-runtime"))
        XCTAssertTrue(preflight.contains("./scripts/ci.sh ui-visual"))
        XCTAssertTrue(preflight.contains("./scripts/ci.sh ui-performance"))
        XCTAssertTrue(preflight.contains("Real visual regression: passed"))
        XCTAssertTrue(readiness.contains("\"Real visual regression\""))
        XCTAssertFalse(preflight.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(preflight.contains("pkill -x \"$APP_NAME\""))
        XCTAssertFalse(accessibilityPreflight.contains("pkill -x \"$APP_NAME\""))
        XCTAssertFalse(buildAndRun.contains("pkill -x \"$APP_NAME\""))
    }

    func testContributorDocsPublishExactLocalReproductionCommandsAndTrustBoundary() throws {
        let documentation = try readRepositoryFile("docs/quality/ci-ui-gates.md")

        XCTAssertTrue(documentation.contains("./scripts/ci.sh swiftpm"))
        XCTAssertTrue(documentation.contains("./scripts/ci.sh ui-runtime"))
        XCTAssertTrue(documentation.contains("./scripts/ci.sh ui-visual"))
        XCTAssertTrue(documentation.contains("./scripts/ci.sh ui-performance"))
        XCTAssertTrue(documentation.contains("pull_request_target"))
        XCTAssertTrue(documentation.contains("ephemeral"))
        XCTAssertTrue(documentation.contains("runner-capability"))
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
