import Foundation
import XCTest

final class CIGateWorkflowTests: XCTestCase {
    func testWorkflowDefinesStableProductionUIGatesOnPinnedMacOSRunner() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")
        let fullRunner = try readRepositoryFile("ci/run-full.sh")

        XCTAssertTrue(workflow.contains("pull_request:"))
        XCTAssertTrue(workflow.contains("push:"))
        XCTAssertTrue(workflow.contains("merge_group:"))
        XCTAssertFalse(workflow.contains("pull_request_target:"))
        XCTAssertTrue(workflow.contains("permissions:\n  contents: read"))

        XCTAssertTrue(workflow.contains("name: SwiftPM macOS"))
        XCTAssertTrue(workflow.contains("name: UI Runtime (production route)"))
        XCTAssertTrue(workflow.contains("name: UI Visual (live baseline)"))
        XCTAssertTrue(workflow.contains("name: UI Performance Build (release artifact)"))
        XCTAssertTrue(workflow.contains("name: UI Performance (production route)"))
        XCTAssertGreaterThanOrEqual(workflow.components(separatedBy: "runs-on: macos-26").count - 1, 5)

        XCTAssertTrue(workflow.contains("run: ./ci/run-full.sh"))
        XCTAssertTrue(fullRunner.contains("./scripts/ci.sh swiftpm"))
        XCTAssertGreaterThanOrEqual(
            workflow.components(separatedBy: "fetch-depth: 0").count - 1,
            2,
            "Both the complete SwiftPM suite and visual provenance checks need full history"
        )
        XCTAssertTrue(workflow.contains("brew install ripgrep"))
        XCTAssertTrue(workflow.contains("command -v rg"))
        XCTAssertTrue(workflow.contains("./scripts/ci.sh ui-runtime"))
        XCTAssertTrue(workflow.contains("./scripts/ci.sh ui-visual"))
        XCTAssertTrue(workflow.contains("SUISUI_VISUAL_SOURCE_REF: ${{ github.event.pull_request.head.sha || github.sha }}"))
        XCTAssertTrue(workflow.contains("locale: [en-US, ja-JP]"))
        XCTAssertTrue(workflow.contains("SUISUI_CI_VISUAL_GATE_LOCALE: ${{ matrix.locale }}"))
        XCTAssertTrue(workflow.contains("UI Visual (live baseline) (${{ matrix.locale }})"))
        XCTAssertTrue(workflow.contains("ui-visual-locales:"))
        XCTAssertTrue(workflow.contains("needs.ui-visual-locales.result"))
        XCTAssertTrue(workflow.contains("name: UI Visual (live baseline)\n"))
        XCTAssertTrue(workflow.contains("failure_reason=locale-visual-gate-did-not-succeed"))
        XCTAssertTrue(
            workflow.contains(
                "github.event_name != 'pull_request' || needs.test_strategy.outputs.ui_visual_state != '0'"
            ),
            "Only the normalized numeric skip state may omit the bilingual visual matrix"
        )
        XCTAssertTrue(workflow.contains("ui_visual_state: ${{ steps.normalize_visual_selection.outputs.state }}"))
        XCTAssertTrue(workflow.contains("id: normalize_visual_selection"))
        XCTAssertTrue(workflow.contains("failure_reason=visual-selection-result-invalid"))
        XCTAssertTrue(workflow.contains("fetch-depth: 0"))
        XCTAssertTrue(workflow.contains("./scripts/ci.sh ui-performance"))
        XCTAssertTrue(workflow.contains("SUISUI_PERFORMANCE_PROFILE: release"))
        XCTAssertTrue(workflow.contains("SUISUI_PERFORMANCE_BUILD_CONFIGURATION: release"))
        XCTAssertTrue(workflow.contains("SUISUI_PERFORMANCE_MAX_COLD_LAUNCH_MS: 1000"))
        XCTAssertTrue(workflow.contains("SUISUI_PERFORMANCE_MAX_DESTINATION_SWITCH_MS: 3000"))
        XCTAssertTrue(workflow.contains("SUISUI_PERFORMANCE_USE_PREBUILT_APP: 1"))
        XCTAssertFalse(workflow.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
    }

    func testWorkflowAlwaysUploadsShortLivedSanitizedArtifactsForEveryUIGate() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")

        XCTAssertGreaterThanOrEqual(workflow.components(separatedBy: "uses: actions/upload-artifact@v4").count - 1, 3)
        XCTAssertGreaterThanOrEqual(workflow.components(separatedBy: "if: always()").count - 1, 3)
        XCTAssertGreaterThanOrEqual(workflow.components(separatedBy: "retention-days: 7").count - 1, 3)
        XCTAssertGreaterThanOrEqual(workflow.components(separatedBy: "include-hidden-files: true").count - 1, 3)
        XCTAssertTrue(workflow.contains(".tmp/ci-artifacts/ui-runtime"))
        XCTAssertTrue(workflow.contains(".tmp/ci-artifacts/ui-visual"))
        XCTAssertTrue(workflow.contains("ui-visual-${{ matrix.locale }}-${{ github.run_id }}-${{ github.run_attempt }}"))
        XCTAssertTrue(workflow.contains(".tmp/ci-artifacts/ui-performance"))
    }

    func testPerformanceGateWaitsForOtherMacOSUIGatesBeforeMeasuring() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")
        let performanceStart = try XCTUnwrap(workflow.range(of: "\n  ui-performance:"))
        let performanceJob = String(workflow[performanceStart.lowerBound...])
        let needsStart = try XCTUnwrap(performanceJob.range(of: "    needs:\n"))
        let conditionStart = try XCTUnwrap(
            performanceJob.range(
                of: "    if: ${{ always() && (github.event_name != 'pull_request' || needs.test_strategy.outputs.ui_performance == 'true') }}",
                range: needsStart.upperBound..<performanceJob.endIndex
            )
        )
        let dependencies = String(
            performanceJob[needsStart.upperBound..<conditionStart.lowerBound]
        )

        XCTAssertTrue(dependencies.contains("      - test_strategy\n"))
        XCTAssertTrue(dependencies.contains("      - full_validation\n"))
        XCTAssertTrue(dependencies.contains("      - ui-runtime\n"))
        XCTAssertTrue(dependencies.contains("      - ui-visual\n"))
        XCTAssertTrue(dependencies.contains("      - ui-performance-build\n"))
    }

    func testPerformanceMeasurementUsesVerifiedReleaseArtifactOnAFreshRunner() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")
        let buildStart = try XCTUnwrap(workflow.range(of: "\n  ui-performance-build:"))
        let measureStart = try XCTUnwrap(
            workflow.range(of: "\n  ui-performance:", range: buildStart.upperBound..<workflow.endIndex)
        )
        let buildJob = String(workflow[buildStart.lowerBound..<measureStart.lowerBound])
        let measureJob = String(workflow[measureStart.lowerBound...])

        XCTAssertTrue(buildJob.contains("SUISUI_RELEASE_BUILD_PURPOSE=performance"))
        XCTAssertTrue(buildJob.contains("SUISUI_BUILD_CONFIGURATION=release ./script/build_and_run.sh --build-only"))
        XCTAssertTrue(buildJob.contains("COPYFILE_DISABLE=1 /usr/bin/tar -czf"))
        XCTAssertTrue(buildJob.contains("archive_sha256="))
        XCTAssertTrue(buildJob.contains("source_commit="))
        XCTAssertTrue(buildJob.contains("build_configuration=release"))
        XCTAssertTrue(buildJob.contains("uses: actions/upload-artifact@v4"))
        XCTAssertTrue(buildJob.contains("name: ui-performance-app-${{ github.run_id }}-${{ github.run_attempt }}"))

        XCTAssertTrue(measureJob.contains("uses: actions/download-artifact@v4"))
        XCTAssertTrue(measureJob.contains("name: ui-performance-app-${{ github.run_id }}-${{ github.run_attempt }}"))
        XCTAssertTrue(measureJob.contains("SUISUI_PERFORMANCE_ARTIFACT_DIR:"))
        XCTAssertTrue(measureJob.contains("SUISUI_PERFORMANCE_USE_PREBUILT_APP: 1"))
        XCTAssertFalse(measureJob.contains("Restore Swift build cache"))
    }

    func testVisualRequiredCheckAggregatorFailsClosedForUnknownSelectorResults() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")
        let script = try visualAggregatorScript(from: workflow)

        let cases: [(
            eventName: String,
            selectionState: String,
            matrixResult: String,
            expectedExitCode: Int32,
            expectedOutput: String
        )] = [
            ("pull_request", "0", "skipped", 0, "status=not-required"),
            ("pull_request", "1", "success", 0, "status=passed"),
            ("pull_request", "1", "failure", 1, "locale-visual-gate-did-not-succeed"),
            ("pull_request", "", "success", 1, "visual-selection-result-invalid"),
            ("pull_request", "2", "success", 1, "visual-selection-result-invalid"),
            ("push", "", "success", 0, "status=passed")
        ]

        for testCase in cases {
            let result = try runBash(
                script,
                environment: [
                    "EVENT_NAME": testCase.eventName,
                    "VISUAL_SELECTION_STATE": testCase.selectionState,
                    "LOCALE_VISUAL_RESULT": testCase.matrixResult
                ]
            )
            XCTAssertEqual(
                result.exitCode,
                testCase.expectedExitCode,
                "unexpected result for \(testCase): \(result.output)"
            )
            XCTAssertTrue(
                result.output.contains(testCase.expectedOutput),
                "missing \(testCase.expectedOutput) for \(testCase): \(result.output)"
            )
        }
    }

    func testVisualSelectionNormalizerTreatsOnlyExactLowercaseFalseAsSkip() throws {
        let workflow = try readRepositoryFile(".github/workflows/ci.yml")
        let script = try visualSelectionNormalizerScript(from: workflow)
        let cases: [(raw: String, expectedState: String)] = [
            ("false", "0"),
            ("true", "1"),
            ("FALSE", "2"),
            ("False", "2"),
            ("unknown", "2"),
            ("", "2")
        ]

        for testCase in cases {
            let result = try runBash(
                script,
                environment: [
                    "RAW_VISUAL_SELECTION": testCase.raw,
                    "GITHUB_OUTPUT": "/dev/null"
                ]
            )
            XCTAssertEqual(result.exitCode, 0, "unexpected normalizer failure for \(testCase): \(result.output)")
            XCTAssertTrue(
                result.output.contains("visual_selection_state=\(testCase.expectedState)"),
                "unexpected normalized state for \(testCase): \(result.output)"
            )
        }
    }

    func testCIScriptRoutesIndependentLanesWithoutOptionalFlags() throws {
        let script = try readRepositoryFile("scripts/ci.sh")

        XCTAssertTrue(script.contains("CI_LANE=\"${1:-${SUISUI_CI_LANE:-swiftpm}}\""))
        XCTAssertTrue(script.contains("swiftpm|source-contracts|ui-runtime|ui-visual|ui-performance"))
        XCTAssertTrue(script.contains("run_lane_with_artifacts"))
        XCTAssertTrue(script.contains("check_macos_ui_runner_capabilities.sh runtime"))
        XCTAssertTrue(script.contains("./script/build_and_run.sh --verify"))
        XCTAssertTrue(script.contains("run_build_and_run_verify \"$artifact_dir\""))
        XCTAssertTrue(script.contains("Only copy the path-free AX/window diagnostics"))
        XCTAssertTrue(script.contains("$verify_tmp\"/verify/*.txt"))
        XCTAssertTrue(script.contains("$verify_tmp\"/verify/*.err"))
        XCTAssertTrue(script.contains("SUISUI_RUNTIME_ACCESSIBLE_CRUD_ARTIFACT_DIR=\"$artifact_dir/runtime-accessible-crud\""))
        XCTAssertTrue(script.contains("check_runtime_today_production_route_smoke.sh"))
        XCTAssertTrue(script.contains("check_runtime_accessible_crud_smoke.sh"))
        XCTAssertTrue(script.contains("check_layout_stability_smoke.sh"))
        XCTAssertTrue(script.contains("check_ci_visual_gate.sh"))
        XCTAssertTrue(script.contains("check_macos_ui_runner_capabilities.sh performance"))
        XCTAssertTrue(script.contains("check_release_launch_performance_smoke.sh"))
        XCTAssertTrue(script.contains("SUISUI_PERFORMANCE_PROFILE=\"${SUISUI_PERFORMANCE_PROFILE:-release}\""))
        XCTAssertTrue(script.contains("SUISUI_PERFORMANCE_BUILD_CONFIGURATION=\"${SUISUI_PERFORMANCE_BUILD_CONFIGURATION:-release}\""))
        XCTAssertFalse(script.contains("SUISUI_LAUNCH_RECOVERY_MODE"))

        let layoutGate = try readRepositoryFile("script/check_layout_stability_smoke.sh")
        XCTAssertFalse(layoutGate.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(layoutGate.contains("prepare_voiceover_review_candidate.sh"))
        XCTAssertFalse(layoutGate.contains("/usr/bin/osascript - \"$APP_NAME\""))
    }

    func testCILaneLogSanitizesBeforeTeeExposesItToPublicLog() throws {
        // Regression for the P2 review that let raw lane stdout/stderr reach
        // the GitHub Actions job log before the post-tee sanitizer ran.
        // The sanitizer must sit between the lane function and `tee` so
        // secrets and runner-local paths never appear in the public log.
        let script = try readRepositoryFile("scripts/ci.sh")
        let redactionHelper = try readRepositoryFile("script/ci_redact_stream.sh")

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
        XCTAssertTrue(
            script.contains("local output=\"${2:-}\""),
            "stdin mode passes only one argument, so the optional output path must be safe under `set -u`"
        )
        XCTAssertTrue(script.contains("pipeline_statuses=(\"${PIPESTATUS[@]}\")"))
        XCTAssertTrue(script.contains("pipeline_statuses[1]"))
        XCTAssertTrue(script.contains("pipeline_statuses[2]"))
        XCTAssertTrue(script.contains("source \"$CI_REDACT_HELPER\""))
        XCTAssertTrue(script.contains("ci_redact_stream"))
        XCTAssertTrue(redactionHelper.contains("Authorization"))
        XCTAssertTrue(redactionHelper.contains("github_pat_"))
        XCTAssertTrue(redactionHelper.contains("glpat-"))
        XCTAssertTrue(redactionHelper.contains("AIza"))

        let sensitiveFixture = """
        public-marker=keep-me
        path="/Users/alice/My Private App/config.json" volume='/Volumes/Secret Disk/work'
        Authorization: Bearer bearer-provider-value Authorization: Basic basic-provider-value
        PASSWORD="alpha beta" 'api_key': 'quoted secret value'
        sk_live_providerfixture1234 glpat-providerfixture1234 AIzaProviderFixture1234567890
        https://alice:password-value@example.test/path
        escaped=/Users/alice/My\\ Project/private.txt
        {"token":"abc\\\"leaked-tail"}
        -----BEGIN PRIVATE KEY-----
        private-key-body-value
        -----END PRIVATE KEY-----
        """
        let helperPath = repositoryRoot.appendingPathComponent("script/ci_redact_stream.sh").path
        let sanitized = try runBash(
            "source \"$REDACTION_HELPER\"; printf '%s' \"$SENSITIVE_FIXTURE\" | ci_redact_stream",
            environment: [
                "REDACTION_HELPER": helperPath,
                "SENSITIVE_FIXTURE": sensitiveFixture
            ]
        )
        XCTAssertEqual(sanitized.exitCode, 0, sanitized.output)
        for privateValue in [
            "alice", "My Private App", "Secret Disk", "bearer-provider-value",
            "basic-provider-value", "alpha beta", "quoted secret value",
            "sk_live_providerfixture1234", "glpat-providerfixture1234",
            "AIzaProviderFixture1234567890", "password-value", "Project/private.txt",
            "leaked-tail", "private-key-body-value"
        ] {
            XCTAssertFalse(sanitized.output.contains(privateValue), sanitized.output)
        }
        XCTAssertTrue(sanitized.output.contains("public-marker=keep-me"), sanitized.output)
    }

    func testCompleteSwiftPMRunnerWritesFailedEvidenceWhenDiscoveryFails() throws {
        let script = try readRepositoryFile("script/run_complete_swiftpm_tests.sh")

        XCTAssertTrue(
            script.contains(
                """
                if [[ "$discovery_status" -ne 0 ]]; then
                  write_failed_evidence "$baseline_test_count" 0 "$max_skipped_test_count"
                """
            ),
            "A discovery/compiler failure must publish failed evidence with every configured count boundary"
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
        XCTAssertFalse(preflight.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(preflight.contains("pkill -x \"$APP_NAME\""))
        XCTAssertFalse(accessibilityPreflight.contains("pkill -x \"$APP_NAME\""))
        XCTAssertFalse(buildAndRun.contains("pkill -x \"$APP_NAME\""))
    }

    func testContributorDocsPublishExactLocalReproductionCommandsAndTrustBoundary() throws {
        let documentation = try readRepositoryFile("docs/quality/ci-ui-gates.md")

        XCTAssertTrue(documentation.contains("./scripts/ci.sh swiftpm"))
        XCTAssertTrue(documentation.contains("./scripts/ci.sh source-contracts"))
        XCTAssertTrue(documentation.contains("全SwiftPM behavioral test"))
        XCTAssertTrue(documentation.contains("xUnit"))
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

    private func visualAggregatorScript(from workflow: String) throws -> String {
        let step = try XCTUnwrap(workflow.range(of: "      - name: Aggregate locale visual gates\n"))
        let runMarker = try XCTUnwrap(
            workflow.range(
                of: "        run: |\n",
                range: step.upperBound..<workflow.endIndex
            )
        )
        let jobEnd = try XCTUnwrap(
            workflow.range(
                of: "\n\n  ui-performance-build:",
                range: runMarker.upperBound..<workflow.endIndex
            )
        )
        let body = workflow[runMarker.upperBound..<jobEnd.lowerBound]
        let normalizedLines = body.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { line -> String in
            let value = String(line)
            return value.hasPrefix("          ") ? String(value.dropFirst(10)) : value
        }
        return "#!/usr/bin/env bash\nset -euo pipefail\n" + normalizedLines.joined(separator: "\n") + "\n"
    }

    private func visualSelectionNormalizerScript(from workflow: String) throws -> String {
        let step = try XCTUnwrap(workflow.range(of: "      - name: Normalize visual selection\n"))
        let runMarker = try XCTUnwrap(
            workflow.range(
                of: "        run: |\n",
                range: step.upperBound..<workflow.endIndex
            )
        )
        let stepEnd = try XCTUnwrap(
            workflow.range(
                of: "\n\n      - name: Upload strategy and execution history",
                range: runMarker.upperBound..<workflow.endIndex
            )
        )
        let body = workflow[runMarker.upperBound..<stepEnd.lowerBound]
        let normalizedLines = body.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { line -> String in
            let value = String(line)
            return value.hasPrefix("          ") ? String(value.dropFirst(10)) : value
        }
        return "#!/usr/bin/env bash\nset -euo pipefail\n" + normalizedLines.joined(separator: "\n") + "\n"
    }

    private func runBash(
        _ script: String,
        environment: [String: String]
    ) throws -> (exitCode: Int32, output: String) {
        let fixtureDirectory = repositoryRoot.appendingPathComponent(
            ".build/test-visual-aggregator-\(UUID().uuidString)",
            isDirectory: true
        )
        let scriptURL = fixtureDirectory.appendingPathComponent("aggregate.sh")
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(
            environment,
            uniquingKeysWith: { _, replacement in replacement }
        )
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (process.terminationStatus, output)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
