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
    }

    func testAccessibilitySmokeCapturesPIDForOpenLaunchedInstance() throws {
        // Regression for the P2 review that left the `open -n -F` branch
        // without an `APP_LAUNCH_PID`. The cleanup trap and PID-scoped AX
        // scans depend on the captured PID, so the open branch must
        // resolve a fresh $APP_BINARY PID via pgrep + diff.
        let script = try readPackageFile("script/check_accessibility_preflight.sh")

        // Find the open branch by locating the `open -n -F` call and reading
        // up to the closing `fi activate_app` boundary.
        let openCallRange = try XCTUnwrap(
            script.range(of: "/usr/bin/open -n -F \"$APP_BUNDLE\"")
        )
        let openBranchEnd = try XCTUnwrap(
            script.range(of: "activate_app\nfi", range: openCallRange.upperBound..<script.endIndex)
        )
        let openBranch = String(script[openCallRange.lowerBound..<openBranchEnd.upperBound])

        XCTAssertTrue(
            openBranch.contains("pre_open_pids"),
            "The `open` launch branch must snapshot existing $APP_BINARY PIDs so the diff identifies the new instance"
        )
        XCTAssertTrue(
            openBranch.contains("/usr/bin/pgrep -f \"$APP_BINARY/Contents/MacOS/\""),
            "The `open` launch branch must use pgrep to discover the just-opened instance"
        )
        XCTAssertTrue(
            openBranch.contains("launched_app_matches_binary"),
            "The `open` launch branch must validate the candidate PID against $APP_BINARY before assigning APP_LAUNCH_PID"
        )
        XCTAssertTrue(
            openBranch.contains("APP_LAUNCH_PID=\"$candidate_pid\""),
            "The `open` launch branch must assign APP_LAUNCH_PID from the validated candidate"
        )
        XCTAssertFalse(
            openBranch.contains("/usr/bin/open -n -F \"$APP_BUNDLE\"\n    activate_app"),
            "The `open` launch branch must not return without assigning APP_LAUNCH_PID; that re-introduces the stale-window bug"
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

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot().appendingPathComponent(relativePath), encoding: .utf8)
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
