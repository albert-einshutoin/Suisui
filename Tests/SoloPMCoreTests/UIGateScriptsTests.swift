import Foundation
import XCTest

final class UIGateScriptsTests: XCTestCase {
    func testRunnerCapabilityGateDefinesFailClosedModeSpecificContract() throws {
        let script = try readPackageFile("script/check_macos_ui_runner_capabilities.sh")
        let probe = try readPackageFile("script/macos_ui_runner_capability_probe.swift")

        XCTAssertTrue(script.contains("SOLOPM_UI_RUNNER_CAPABILITY_ARTIFACT_DIR"))
        XCTAssertTrue(script.contains("runtime|performance|visual"))
        XCTAssertTrue(script.contains("block \"runner-capability\""))
        XCTAssertTrue(script.contains("ui-runner-capability-summary.env"))
        XCTAssertTrue(script.contains("launchctl print \"gui/$UID_VALUE\""))
        XCTAssertTrue(script.contains("pgrep -x WindowServer"))
        XCTAssertTrue(script.contains("required_commands=(id launchctl pgrep swift swiftc osascript)"))
        XCTAssertTrue(script.contains("required_commands+=(sqlite3 screencapture)"))
        XCTAssertTrue(script.contains("performance)\n    required_commands+=(sqlite3)"))
        XCTAssertTrue(script.contains("required_commands+=(sqlite3 sips screencapture)"))
        XCTAssertTrue(script.contains("system-events-automation-unavailable"))
        XCTAssertTrue(script.contains("get unix id of first application process"))
        XCTAssertTrue(script.contains("ui_evidence_content_check.swift"))
        XCTAssertTrue(script.contains("screencapture -x"))
        XCTAssertTrue(script.contains("VISIBLE_PIXEL_PROBE_ATTEMPTS=3"))
        XCTAssertTrue(script.contains("while (( visible_pixel_probe_attempt <= VISIBLE_PIXEL_PROBE_ATTEMPTS ))"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_ALLOW_DESKTOP_BACKGROUND=1"))
        XCTAssertTrue(script.contains("SCREEN_RECORDING=\"not-required\""))
        XCTAssertTrue(script.contains("VISIBLE_PIXELS=\"not-required\""))
        XCTAssertTrue(script.contains("trap finalize EXIT"))
        XCTAssertFalse(script.contains("pkill"))
        XCTAssertFalse(script.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))

        XCTAssertTrue(probe.contains("AXIsProcessTrusted()"))
        XCTAssertTrue(probe.contains("CGPreflightScreenCaptureAccess()"))
        XCTAssertTrue(probe.contains("CGGetActiveDisplayList"))
        XCTAssertTrue(probe.contains("active_display="))
        XCTAssertTrue(probe.contains("accessibility="))
        XCTAssertTrue(probe.contains("screen_recording="))
    }

    func testRunnerCapabilityGateRecordsSanitizedDisplayFrameAndVisibleFrameGeometry() throws {
        let script = try readPackageFile("script/check_macos_ui_runner_capabilities.sh")
        let probe = try readPackageFile("script/macos_ui_runner_capability_probe.swift")
        let ci = try readPackageFile("scripts/ci.sh")

        for key in [
            "display_frame_x",
            "display_frame_y",
            "display_frame_width",
            "display_frame_height",
            "display_visible_frame_x",
            "display_visible_frame_y",
            "display_visible_frame_width",
            "display_visible_frame_height"
        ] {
            XCTAssertTrue(probe.contains("\(key)="), "probe must emit \(key)")
            XCTAssertTrue(script.contains("\(key)="), "summary must retain \(key)")
        }
        XCTAssertTrue(probe.contains("NSScreen.screens"))
        XCTAssertTrue(script.contains("probe_integer_value()"))
        XCTAssertTrue(script.contains("probe_positive_integer_value()"))
        XCTAssertTrue(ci.contains("read_capability_positive_dimension()"))
        XCTAssertTrue(ci.contains("display_visible_frame_width"))
        XCTAssertTrue(ci.contains("display_visible_frame_height"))
        XCTAssertTrue(ci.contains("SOLOPM_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH"))
        XCTAssertTrue(ci.contains("SOLOPM_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT"))
        XCTAssertFalse(probe.contains("hostName"))
        XCTAssertFalse(probe.contains("userName"))
    }

    func testLayoutDisplayCapacityFailureKeepsStandardAndWideContractsAndUsesRunnerCapabilityTaxonomy() throws {
        let result = try runTool(
            [
                "/bin/bash",
                packageRoot().appendingPathComponent("script/check_layout_stability_smoke.sh").path,
                "--check-display-capacity"
            ],
            environment: [
                "SOLOPM_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH": "1024",
                "SOLOPM_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT": "724"
            ]
        )

        XCTAssertEqual(result.exitCode, 1, result.output)
        XCTAssertTrue(result.output.contains("failure_category=runner-capability"), result.output)
        XCTAssertTrue(result.output.contains("failure_reason=layout-visible-frame-too-small"), result.output)
        XCTAssertTrue(result.output.contains("standard=1180x760"), result.output)
        XCTAssertTrue(result.output.contains("wide=1420x860"), result.output)
        XCTAssertTrue(result.output.contains("product contract was not downgraded"), result.output)
    }

    func testLayoutDisplayCapacityAcceptsSufficientVisibleFrame() throws {
        let result = try runTool(
            [
                "/bin/bash",
                packageRoot().appendingPathComponent("script/check_layout_stability_smoke.sh").path,
                "--check-display-capacity"
            ],
            environment: [
                "SOLOPM_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH": "1512",
                "SOLOPM_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT": "900"
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("visible frame 1512x900 can exercise required layout windows"), result.output)
    }

    func testLayoutDisplayCapacityRejectsWindowContractOverridesBelowImmutableProductFloor() throws {
        let baseEnvironment = [
            "SOLOPM_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH": "1512",
            "SOLOPM_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT": "900"
        ]
        for (override, belowFloor) in [
            ("SOLOPM_LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH", "1179"),
            ("SOLOPM_LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT", "759"),
            ("SOLOPM_LAYOUT_STABILITY_WINDOW_WIDE_WIDTH", "1419"),
            ("SOLOPM_LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT", "859")
        ] {
            let result = try runTool(
                [
                    "/bin/bash",
                    packageRoot().appendingPathComponent("script/check_layout_stability_smoke.sh").path,
                    "--check-display-capacity"
                ],
                environment: baseEnvironment.merging([override: belowFloor]) { _, new in new }
            )

            XCTAssertEqual(result.exitCode, 2, "\(override): \(result.output)")
            XCTAssertTrue(result.output.contains("failure_category=configuration"), result.output)
            XCTAssertTrue(result.output.contains("failure_reason=layout-window-contract-below-product-floor"), result.output)
            XCTAssertTrue(result.output.contains("standard floor=1180x760"), result.output)
            XCTAssertTrue(result.output.contains("wide floor=1420x860"), result.output)
        }
    }

    func testCICapabilityDimensionParserFailsClosedForMalformedDuplicateOrNonPositiveValues() throws {
        let valid = try runCapabilityDimensionParser(summary: "display_visible_frame_width=1024\n")
        XCTAssertEqual(valid.exitCode, 0, valid.output)
        XCTAssertEqual(valid.output.trimmingCharacters(in: .whitespacesAndNewlines), "1024")

        for invalidSummary in [
            "",
            "display_visible_frame_height=724\n",
            "display_visible_frame_width=1024\ndisplay_visible_frame_width=1024\n",
            "display_visible_frame_width=1024=unexpected\n",
            "display_visible_frame_width=0\n",
            "display_visible_frame_width=-1\n",
            "display_visible_frame_width= 1024\n",
            "display_visible_frame_width=1024 \n"
        ] {
            let result = try runCapabilityDimensionParser(summary: invalidSummary)
            XCTAssertNotEqual(result.exitCode, 0, "fixture must fail closed: \(invalidSummary.debugDescription)")
        }

        let classifiedFailure = try runCapabilityGeometryReader(summary: "display_visible_frame_width=1024\n")
        XCTAssertNotEqual(classifiedFailure.exitCode, 0)
        XCTAssertTrue(classifiedFailure.output.contains("failure_category=runner-capability"), classifiedFailure.output)
        XCTAssertTrue(classifiedFailure.output.contains("failure_reason=invalid-display-geometry-summary"), classifiedFailure.output)
    }

    func testRunnerCapabilityProbeParserRequiresExactlyOneExactKeyValue() throws {
        let valid = try runCapabilityProbeParser(
            probeOutput: "display_frame_width=1420\n",
            function: "probe_positive_integer_value",
            key: "display_frame_width"
        )
        XCTAssertEqual(valid.exitCode, 0, valid.output)
        XCTAssertEqual(valid.output.trimmingCharacters(in: .whitespacesAndNewlines), "1420")

        for invalidProbeOutput in [
            "",
            "display_frame_height=1420\n",
            "display_frame_width=1420=garbage\n",
            "display_frame_width=1420\ndisplay_frame_width=garbage\n",
            "display_frame_width=0\n",
            "display_frame_width=-1\n",
            "display_frame_width= 1420\n",
            "display_frame_width=1420 \n"
        ] {
            let result = try runCapabilityProbeParser(
                probeOutput: invalidProbeOutput,
                function: "probe_positive_integer_value",
                key: "display_frame_width"
            )
            XCTAssertNotEqual(result.exitCode, 0, "fixture must fail closed: \(invalidProbeOutput.debugDescription)")
        }

        let duplicateBoolean = try runCapabilityProbeParser(
            probeOutput: "active_display=1\nactive_display=0\n",
            function: "probe_value",
            key: "active_display"
        )
        XCTAssertNotEqual(duplicateBoolean.exitCode, 0, duplicateBoolean.output)
    }

    func testRequiredUIGatesKeepStableLaunchAndResolvedProcessIdentitiesForCleanup() throws {
        let helpers = try readPackageFile("script/ui_accessibility_smoke_helpers.sh")
        XCTAssertTrue(helpers.contains("ax_owned_process_identity()"))
        XCTAssertTrue(helpers.contains("-o lstart="))
        XCTAssertTrue(helpers.contains("ax_terminate_owned_process()"))
        XCTAssertTrue(helpers.contains("ax_process_matches_identity"))

        for path in [
            "script/check_release_launch_performance_smoke.sh",
            "script/check_runtime_accessible_crud_smoke.sh",
            "script/check_layout_stability_smoke.sh",
            "script/check_runtime_today_production_route_smoke.sh",
            "script/capture_ui_evidence.sh"
        ] {
            let script = try readPackageFile(path)
            XCTAssertTrue(script.contains("ax_terminate_owned_process"), "\(path) must use identity-safe cleanup")
            XCTAssertTrue(script.contains("LAUNCH_IDENTITY") || script.contains("launch_identity"), "\(path) must retain launch identity")
        }
    }

    func testRuntimeRoutePropagatesPostRouteDatabaseWriteLockFailure() throws {
        // Regression for the P2 review that allowed `run_route` and
        // `navigate_to_seed_project` to swallow a `wait_for_database_write_access`
        // failure. Both code paths are called under `|| return 1` which would
        // otherwise turn the failed write-lock probe into a passed route.
        let script = try readPackageFile("script/check_runtime_today_production_route_smoke.sh")
        let databaseLockPropagationCount = script.components(separatedBy: "if ! wait_for_database_write_access; then")
            .count - 1
        XCTAssertGreaterThanOrEqual(
            databaseLockPropagationCount,
            2,
            "run_route and navigate_to_seed_project must both propagate the post-route write-lock probe"
        )
        // The unconditional `wait_for_database_write_access` followed by
        // `return 0` is the specific anti-pattern the review flagged.
        XCTAssertFalse(
            script.contains("wait_for_database_write_access\n  return 0"),
            "An unwrapped `wait_for_database_write_access; return 0` would mask a write-lock failure as a passed route"
        )
    }

    func testAccessibilitySmokeScopesAppleScriptToLaunchedPID() throws {
        // Regression for the P2 review that allowed name-based
        // `process appName` lookups to inspect a stale SoloPM window from a
        // developer or prior step. The AX scans must prefer the launched PID
        // and fall back to name only when the PID is unknown.
        let script = try readPackageFile("script/check_accessibility_preflight.sh")

        XCTAssertTrue(
            script.contains("first process whose unix id is (appLaunchPidText as integer)"),
            "All AX scans must select the launched PID via `first process whose unix id is`"
        )
        let pidLookupCount = script.components(separatedBy: "first process whose unix id is")
            .count - 1
        XCTAssertGreaterThanOrEqual(
            pidLookupCount,
            4,
            "activate_app, open_task_inspector_for_runtime_focus_path, and the two scanners must each select the PID"
        )
        // Confirm the legacy name-only path is gone. A bare
        // `tell process appName` immediately inside `tell application "System Events"`
        // is the anti-pattern.
        XCTAssertFalse(
            script.contains("tell process appName"),
            "AX scans must not address `process appName` directly; that lets a stray window satisfy the smoke"
        )
        XCTAssertTrue(
            script.contains("APP_LAUNCH_PID:-"),
            "Each AppleScript call must forward the launched PID (empty when the script did not launch the app)"
        )
        let nameFallbackCount = script.components(separatedBy: "if appLaunchPidText is \"\" then")
            .count - 1
        XCTAssertGreaterThanOrEqual(
            nameFallbackCount,
            4,
            "Name-based lookup is allowed only when no launched PID was supplied"
        )
        XCTAssertFalse(
            script.contains("if targetProcess is missing value then\n      try\n        set targetProcess to first process whose name is appName"),
            "A missing PID-owned process must fail closed instead of selecting a stray process by name"
        )
    }

    func testAccessibilitySmokeAlwaysDirectLaunchesOwnedCandidate() throws {
        // Runtime mode prepares a deterministic launch environment before this
        // branch, so LaunchServices is unnecessary. Direct launch gives the
        // preflight an exact PID for AX selection and identity-safe cleanup.
        let script = try readPackageFile("script/check_accessibility_preflight.sh")

        XCTAssertTrue(
            script.contains("if [[ \"$LAUNCH_APP\" -eq 1 && -z \"$LAUNCH_ENV_FILE\" ]]; then"),
            "Runtime launch must prepare the deterministic candidate environment when none was supplied"
        )
        XCTAssertTrue(
            script.contains("\"$APP_BINARY\" >/dev/null 2>&1 &\n  APP_LAUNCH_PID=$!"),
            "Runtime launch must capture the exact direct-launch PID"
        )
        XCTAssertFalse(
            script.contains("/usr/bin/open -n -F \"$APP_BUNDLE\""),
            "LaunchServices cannot provide the exact owned PID required by this preflight"
        )
    }

    func testFailureTaxonomySeparatesRunnerHarnessAndProductRegressions() throws {
        let helpers = try readPackageFile("script/ui_accessibility_smoke_helpers.sh")
        let performance = try readPackageFile("script/check_release_launch_performance_smoke.sh")
        let ci = try readPackageFile("scripts/ci.sh")

        XCTAssertTrue(helpers.contains("harness|performance-budget|app-regression"))
        XCTAssertTrue(performance.contains("failure_category=performance-budget"))
        XCTAssertTrue(ci.contains("ui-runtime|ui-performance) category=\"app-regression\""))
    }

    func testRunnerCapabilityGateRejectsUnsupportedModeWithMachineReadableArtifact() throws {
        let outputDirectory = packageRoot()
            .appendingPathComponent(".build/test-ui-runner-capability-invalid", isDirectory: true)
        try? FileManager.default.removeItem(at: outputDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let result = try runTool(
            ["/bin/bash", packageRoot().appendingPathComponent("script/check_macos_ui_runner_capabilities.sh").path, "unsupported"],
            environment: ["SOLOPM_UI_RUNNER_CAPABILITY_ARTIFACT_DIR": outputDirectory.path]
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        let summary = try String(
            contentsOf: outputDirectory.appendingPathComponent("ui-runner-capability-summary.env"),
            encoding: .utf8
        )
        XCTAssertTrue(summary.contains("gate=unsupported"))
        XCTAssertTrue(summary.contains("status=blocked"))
        XCTAssertTrue(summary.contains("failure_category=configuration"))
        XCTAssertTrue(summary.contains("failure_reason=unsupported-mode"))
        XCTAssertFalse(summary.contains(NSHomeDirectory()))
    }

    func testMacOSCapabilityProbeCompiles() throws {
        let outputURL = packageRoot()
            .appendingPathComponent(".build/test-macos-ui-runner-capability-probe")
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let result = try runTool([
            "/usr/bin/swiftc",
            packageRoot().appendingPathComponent("script/macos_ui_runner_capability_probe.swift").path,
            "-o",
            outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.output)
    }

    func testVisualGateCapturesAllBaselinesBeforeFreshReceiptComparison() throws {
        let script = try readPackageFile("script/check_ci_visual_gate.sh")

        XCTAssertTrue(script.contains("SOLOPM_CI_VISUAL_GATE_OUTPUT_DIR"))
        XCTAssertTrue(script.contains("EXPECTED_SCREENSHOT_COUNT=33"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_DIR=\"$SCREENSHOT_DIR\""))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_FILE=\"$CAPTURE_EVIDENCE_FILE\""))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_HOME=\"$PRIVATE_HOME\""))
        XCTAssertTrue(script.contains("SOLOPM_VISUAL_AX_AUDIT_RESULT=\"$AX_RECEIPT\""))
        XCTAssertTrue(script.contains("SOLOPM_VISUAL_SCREENSHOT_DIR=\"$SCREENSHOT_DIR\""))
        XCTAssertTrue(script.contains("SOLOPM_VISUAL_ARTIFACT_DIR=\"$DIFF_DIR\""))
        XCTAssertTrue(script.contains("ui-visual-gate-summary.env"))
        XCTAssertTrue(script.contains("tracked-evidence-before"))
        XCTAssertTrue(script.contains("tracked-evidence-after"))
        XCTAssertTrue(script.contains("block \"visual-diff\""))
        XCTAssertTrue(script.contains("s#/(Users|Volumes)/[^[:space:]]+#<path>#g"))
        XCTAssertTrue(script.contains("/tmp/solopm-ci-visual-gate.XXXXXX"))
        XCTAssertFalse(script.contains("pkill"))
        XCTAssertFalse(script.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(script.contains("--update-baselines"))
        XCTAssertFalse(script.contains("--allow-update"))

        let capability = try XCTUnwrap(script.range(of: "check_macos_ui_runner_capabilities.sh\" visual"))
        let removeReceipt = try XCTUnwrap(script.range(of: "rm -f \"$AX_RECEIPT\""))
        let capture = try XCTUnwrap(script.range(of: "capture_ui_evidence.sh\""))
        let requireReceipt = try XCTUnwrap(script.range(of: "[[ -s \"$AX_RECEIPT\" ]]"))
        let compare = try XCTUnwrap(script.range(of: "check_visual_regression_smoke.sh\""))
        XCTAssertLessThan(capability.lowerBound, removeReceipt.lowerBound)
        XCTAssertLessThan(removeReceipt.lowerBound, capture.lowerBound)
        XCTAssertLessThan(capture.lowerBound, requireReceipt.lowerBound)
        XCTAssertLessThan(requireReceipt.lowerBound, compare.lowerBound)
    }

    func testVisualGateRejectsArgumentsSoBaselineUpdatesCannotBeRequested() throws {
        let outputDirectory = packageRoot()
            .appendingPathComponent(".build/test-ci-visual-gate-arguments", isDirectory: true)
        try? FileManager.default.removeItem(at: outputDirectory)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let result = try runTool(
            ["/bin/bash", packageRoot().appendingPathComponent("script/check_ci_visual_gate.sh").path, "update"],
            environment: ["SOLOPM_CI_VISUAL_GATE_OUTPUT_DIR": outputDirectory.path]
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        let summary = try String(
            contentsOf: outputDirectory.appendingPathComponent("ui-visual-gate-summary.env"),
            encoding: .utf8
        )
        XCTAssertTrue(summary.contains("status=blocked"))
        XCTAssertTrue(summary.contains("failure_category=configuration"))
        XCTAssertTrue(summary.contains("failure_reason=arguments-not-supported"))
        XCTAssertFalse(summary.contains(NSHomeDirectory()))
    }

    func testLayoutResizeReacquiresNamedOwnedWindowUntilRequestedWidthIsObserved() throws {
        let script = try readPackageFile("script/check_layout_stability_smoke.sh")
        let metadataHelper = try readPackageFile("script/ui_evidence_window_metadata.swift")

        XCTAssertTrue(script.contains("set currentMain to value of attribute \"AXMain\" of currentWindow as boolean"))
        XCTAssertTrue(script.contains("set expectedX to (item 5 of argv) as integer"))
        XCTAssertTrue(script.contains("set expectedY to (item 6 of argv) as integer"))
        XCTAssertTrue(script.contains("set expectedWidth to (item 7 of argv) as integer"))
        XCTAssertTrue(script.contains("set expectedHeight to (item 8 of argv) as integer"))
        XCTAssertTrue(script.contains("set currentPosition to position of currentWindow"))
        XCTAssertTrue(script.contains("set currentSize to size of currentWindow"))
        XCTAssertTrue(script.contains("currentName is requestedName and currentMain and currentPosition is {expectedX, expectedY} and currentSize is {expectedWidth, expectedHeight}"))
        XCTAssertTrue(script.contains("if candidateCount is not 1 then error \"main named pid-owned window matching visible CG frame is not unique\""))
        XCTAssertTrue(script.contains("\"$window_x\" \"$window_y\" \"$window_width\" \"$window_height\""))
        XCTAssertTrue(script.contains("SOLOPM_REQUIRE_SINGLE_WINDOW=\"$require_single_window\""))
        XCTAssertTrue(script.contains("read_window_metadata 1"), "a recreated successor is valid only when it is the sole visible PID/name match")
        XCTAssertTrue(script.contains("if [[ \"$window_width\" -eq \"$expected_width\" ]]; then"))
        XCTAssertTrue(script.contains("INFO: reapplying owned window size"))
        XCTAssertTrue(metadataHelper.contains("environment[\"SOLOPM_REQUIRE_SINGLE_WINDOW\"] == \"1\""))
        XCTAssertTrue(metadataHelper.contains("guard candidates.count == 1"))
    }

    func testLayoutResizeTraceRecordsRequestedExpectedAndBeforeAfterWindowIdentity() throws {
        let script = try readPackageFile("script/check_layout_stability_smoke.sh")

        XCTAssertTrue(script.contains("window-resize-attempts.tsv"))
        XCTAssertTrue(script.contains("requested_width\\trequested_height\\texpected_width"))
        XCTAssertTrue(script.contains("before_window_id\\tbefore_x\\tbefore_y\\tbefore_width\\tbefore_height"))
        XCTAssertTrue(script.contains("ax_status\\tafter_window_id\\tafter_x\\tafter_y\\tafter_width\\tafter_height"))
        XCTAssertTrue(script.contains("$before_window_id"))
        XCTAssertTrue(script.contains("$after_window_id"))
        XCTAssertTrue(script.contains("$ax_status"))
    }

    func testVisualPositioningRewaitsForOwnedWindowAfterRouteRecreation() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")

        XCTAssertTrue(script.contains("wait_for_owned_evidence_window()"))
        XCTAssertTrue(script.contains("ax_wait_for_pid_owned_window \"$APP_NAME\" \"$EVIDENCE_APP_PID\" \"$window_name\""))
        XCTAssertTrue(script.contains("if ! wait_for_owned_evidence_window \"$window_name\"; then"))
        XCTAssertTrue(script.contains("INFO: waiting for recreated owned evidence window before positioning"))
        XCTAssertTrue(script.contains("wait_for_window_capture_metadata \"$window_name\""))
    }

    func testVisualCaptureRefreshesWindowAndAXEvidenceForEveryRetryAttempt() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let captureStart = try XCTUnwrap(script.range(of: "capture_visible_window() {"))
        let nextFunction = try XCTUnwrap(
            script.range(of: "\nopen_mcp_settings_tab() {", range: captureStart.upperBound..<script.endIndex)
        )
        let captureSource = String(script[captureStart.lowerBound..<nextFunction.lowerBound])
        let retryStart = try XCTUnwrap(captureSource.range(of: "for ((capture_attempt = 1;"))
        let retrySource = String(captureSource[retryStart.lowerBound...])

        XCTAssertTrue(retrySource.contains("position_window_for_capture \"$window_name\""))
        XCTAssertTrue(retrySource.contains("window_metadata=\"$(wait_for_window_capture_metadata \"$window_name\")\""))
        XCTAssertTrue(retrySource.contains("target_frame_audit=\"$(wait_for_stable_ax_target_frame \"$target_identifier\" \"$window_name\")\""))
        XCTAssertTrue(retrySource.contains("successful_window_width=\"$window_width\""))
        XCTAssertTrue(retrySource.contains("successful_target_frame_audit=\"$target_frame_audit\""))
        XCTAssertTrue(captureSource.contains("\"$successful_window_width\" \"$successful_window_height\" \"$successful_target_frame_audit\""))
        XCTAssertFalse(captureSource.contains("target_frame_audit=\"$(wait_for_stable_ax_target_frame \"$target_identifier\" \"$window_name\")\"\n\n  local capture_attempt"))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func runCapabilityDimensionParser(summary: String) throws -> (exitCode: Int32, output: String) {
        let ci = try readPackageFile("scripts/ci.sh")
        let functionStart = try XCTUnwrap(ci.range(of: "read_capability_positive_dimension() {"))
        let functionEnd = try XCTUnwrap(
            ci.range(of: "\n}\n", range: functionStart.upperBound..<ci.endIndex)
        )
        let functionSource = String(ci[functionStart.lowerBound..<functionEnd.upperBound])
        let fixtureDirectory = packageRoot().appendingPathComponent(".build/test-capability-summary-parser", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let fixtureID = UUID().uuidString
        let summaryURL = fixtureDirectory.appendingPathComponent("\(fixtureID).env")
        let harnessURL = fixtureDirectory.appendingPathComponent("\(fixtureID).sh")
        defer {
            try? FileManager.default.removeItem(at: summaryURL)
            try? FileManager.default.removeItem(at: harnessURL)
        }
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
        try "set -euo pipefail\n\(functionSource)\nread_capability_positive_dimension \"$1\" display_visible_frame_width\n"
            .write(to: harnessURL, atomically: true, encoding: .utf8)
        return try runTool(["/bin/bash", harnessURL.path, summaryURL.path])
    }

    private func runCapabilityGeometryReader(summary: String) throws -> (exitCode: Int32, output: String) {
        let ci = try readPackageFile("scripts/ci.sh")
        let functionStart = try XCTUnwrap(ci.range(of: "read_capability_positive_dimension() {"))
        let functionEnd = try XCTUnwrap(
            ci.range(of: "\n\nrun_runtime_gates() {", range: functionStart.upperBound..<ci.endIndex)
        )
        let functionSource = String(ci[functionStart.lowerBound..<functionEnd.lowerBound])
        let fixtureDirectory = packageRoot().appendingPathComponent(".build/test-capability-geometry-reader", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let fixtureID = UUID().uuidString
        let summaryURL = fixtureDirectory.appendingPathComponent("\(fixtureID).env")
        let harnessURL = fixtureDirectory.appendingPathComponent("\(fixtureID).sh")
        defer {
            try? FileManager.default.removeItem(at: summaryURL)
            try? FileManager.default.removeItem(at: harnessURL)
        }
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
        try "set -euo pipefail\n\(functionSource)\nread_layout_visible_frame_dimensions \"$1\"\n"
            .write(to: harnessURL, atomically: true, encoding: .utf8)
        return try runTool(["/bin/bash", harnessURL.path, summaryURL.path])
    }

    private func runCapabilityProbeParser(
        probeOutput: String,
        function: String,
        key: String
    ) throws -> (exitCode: Int32, output: String) {
        let capability = try readPackageFile("script/check_macos_ui_runner_capabilities.sh")
        let functionStart = try XCTUnwrap(capability.range(of: "probe_exact_value() {"))
        let functionEnd = try XCTUnwrap(
            capability.range(of: "\n\nif ! ACTIVE_DISPLAY=", range: functionStart.upperBound..<capability.endIndex)
        )
        let functionSource = String(capability[functionStart.lowerBound..<functionEnd.lowerBound])
        let fixtureDirectory = packageRoot().appendingPathComponent(".build/test-capability-probe-parser", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let fixtureID = UUID().uuidString
        let probeURL = fixtureDirectory.appendingPathComponent("\(fixtureID).env")
        let harnessURL = fixtureDirectory.appendingPathComponent("\(fixtureID).sh")
        defer {
            try? FileManager.default.removeItem(at: probeURL)
            try? FileManager.default.removeItem(at: harnessURL)
        }
        try probeOutput.write(to: probeURL, atomically: true, encoding: .utf8)
        let harness = """
        set -euo pipefail
        PROBE_OUTPUT="$(cat "$1")"
        \(functionSource)
        \(function) "\(key)"
        """
        try harness.write(to: harnessURL, atomically: true, encoding: .utf8)
        return try runTool(["/bin/bash", harnessURL.path, probeURL.path])
    }

    private func runTool(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        process.currentDirectoryURL = packageRoot()
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }
}
