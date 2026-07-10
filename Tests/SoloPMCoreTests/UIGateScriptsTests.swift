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
