import Foundation
import XCTest

final class UIGateScriptsTests: XCTestCase {
    func testRunnerCapabilityGateDefinesFailClosedModeSpecificContract() throws {
        let script = try readPackageFile("script/check_macos_ui_runner_capabilities.sh")
        let probe = try readPackageFile("script/macos_ui_runner_capability_probe.swift")

        XCTAssertTrue(script.contains("SUISUI_UI_RUNNER_CAPABILITY_ARTIFACT_DIR"))
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
        XCTAssertTrue(script.contains("SUISUI_UI_EVIDENCE_ALLOW_DESKTOP_BACKGROUND=1"))
        XCTAssertTrue(script.contains("SCREEN_RECORDING=\"not-required\""))
        XCTAssertTrue(script.contains("VISIBLE_PIXELS=\"not-required\""))
        XCTAssertTrue(script.contains("trap finalize EXIT"))
        XCTAssertFalse(script.contains("pkill"))
        XCTAssertFalse(script.contains("SUISUI_LAUNCH_RECOVERY_MODE"))

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
        XCTAssertTrue(ci.contains("SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH"))
        XCTAssertTrue(ci.contains("SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT"))
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
                "SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH": "1024",
                "SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT": "724"
            ]
        )

        XCTAssertEqual(result.exitCode, 1, result.output)
        XCTAssertTrue(result.output.contains("failure_category=runner-capability"), result.output)
        XCTAssertTrue(result.output.contains("failure_reason=layout-visible-frame-too-small"), result.output)
        XCTAssertTrue(result.output.contains("standard=1180x760"), result.output)
        XCTAssertTrue(result.output.contains("wide=1420x860"), result.output)
        XCTAssertTrue(result.output.contains("product contract was not downgraded"), result.output)
    }

    func testCIRuntimeTreatsOnlyKnownDisplayCapacityLimitsAsTruthfulNonExecution() throws {
        let ci = try readPackageFile("scripts/ci.sh")
        let runtimeStart = try XCTUnwrap(ci.range(of: "run_layout_stability_gate()"))
        let runtimeEnd = try XCTUnwrap(
            ci.range(of: "\nrun_runtime_gates()", range: runtimeStart.upperBound..<ci.endIndex)
        )
        let source = String(ci[runtimeStart.lowerBound..<runtimeEnd.lowerBound])

        XCTAssertTrue(source.contains("--check-display-capacity"))
        XCTAssertTrue(source.contains("failure_category=runner-capability"))
        XCTAssertTrue(source.contains("failure_reason=layout-visible-frame-too-small"))
        XCTAssertTrue(source.contains("status=not-exercised"))
        XCTAssertTrue(source.contains("product_contract=unchanged"))
        XCTAssertTrue(source.contains("gate_notice_category=runner-capability"))
        XCTAssertTrue(source.contains("layout_capacity_is_known_limitation"))
        XCTAssertTrue(source.contains("return 0"))
        XCTAssertTrue(source.contains("return \"$capacity_status\""))
        XCTAssertFalse(source.contains("SUISUI_LAYOUT_STABILITY_WINDOW_WIDE_WIDTH="))

        XCTAssertTrue(ci.contains("run_layout_stability_gate \"$artifact_dir\" \"$visible_frame_width\" \"$visible_frame_height\""))
        XCTAssertTrue(ci.contains("status_label=\"passed-with-limitation\""))
        XCTAssertTrue(ci.contains("failure_category=runner-capability"))
    }

    func testCILayoutCapacityNoticeCannotClassifyLaterRuntimeFailures() throws {
        let knownLimitation = """
        failure_category=runner-capability
        failure_reason=layout-visible-frame-too-small
        """

        let limitationOnly = try runCILayoutLaneFixture(
            capacityOutput: knownLimitation,
            capacityStatus: 1
        )
        XCTAssertEqual(limitationOnly.exitCode, 0, limitationOnly.output)
        XCTAssertTrue(limitationOnly.output.contains("status=passed-with-limitation"), limitationOnly.output)
        XCTAssertTrue(limitationOnly.output.contains("failure_category=runner-capability"), limitationOnly.output)

        let laterUnclassifiedFailure = try runCILayoutLaneFixture(
            capacityOutput: knownLimitation,
            capacityStatus: 1,
            postLayoutStatus: 1
        )
        XCTAssertEqual(laterUnclassifiedFailure.exitCode, 1, laterUnclassifiedFailure.output)
        XCTAssertTrue(laterUnclassifiedFailure.output.contains("status=failed"), laterUnclassifiedFailure.output)
        XCTAssertTrue(laterUnclassifiedFailure.output.contains("failure_category=app-regression"), laterUnclassifiedFailure.output)

        let invalidCapacityConfiguration = try runCILayoutLaneFixture(
            capacityOutput: "failure_category=configuration\nfailure_reason=invalid-capacity-fixture\n",
            capacityStatus: 2
        )
        XCTAssertEqual(invalidCapacityConfiguration.exitCode, 2, invalidCapacityConfiguration.output)
        XCTAssertTrue(invalidCapacityConfiguration.output.contains("status=failed"), invalidCapacityConfiguration.output)
        XCTAssertTrue(invalidCapacityConfiguration.output.contains("failure_category=configuration"), invalidCapacityConfiguration.output)

        let capableRuntimeFailure = try runCILayoutLaneFixture(
            capacityOutput: "display capacity is sufficient\n",
            capacityStatus: 0,
            runtimeStatus: 1
        )
        XCTAssertEqual(capableRuntimeFailure.exitCode, 1, capableRuntimeFailure.output)
        XCTAssertTrue(capableRuntimeFailure.output.contains("status=failed"), capableRuntimeFailure.output)
        XCTAssertTrue(capableRuntimeFailure.output.contains("failure_category=app-regression"), capableRuntimeFailure.output)

        let mixedClassification = try runCILayoutLaneFixture(
            capacityOutput: """
            failure_category=runner-capability
            failure_category=configuration
            failure_reason=layout-visible-frame-too-small
            """,
            capacityStatus: 1
        )
        XCTAssertEqual(mixedClassification.exitCode, 1, mixedClassification.output)
        XCTAssertTrue(mixedClassification.output.contains("status=failed"), mixedClassification.output)
        XCTAssertFalse(mixedClassification.output.contains("status=passed-with-limitation"), mixedClassification.output)
    }

    func testLayoutDisplayCapacityAcceptsSufficientVisibleFrame() throws {
        let result = try runTool(
            [
                "/bin/bash",
                packageRoot().appendingPathComponent("script/check_layout_stability_smoke.sh").path,
                "--check-display-capacity"
            ],
            environment: [
                "SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH": "1512",
                "SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT": "900"
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("visible frame 1512x900 can exercise required layout windows"), result.output)
    }

    func testLayoutDisplayCapacityRejectsWindowContractOverridesBelowImmutableProductFloor() throws {
        let baseEnvironment = [
            "SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH": "1512",
            "SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT": "900"
        ]
        for (override, belowFloor) in [
            ("SUISUI_LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH", "1179"),
            ("SUISUI_LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT", "759"),
            ("SUISUI_LAYOUT_STABILITY_WINDOW_WIDE_WIDTH", "1419"),
            ("SUISUI_LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT", "859")
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
        // `process appName` lookups to inspect a stale Suisui window from a
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
            environment: ["SUISUI_UI_RUNNER_CAPABILITY_ARTIFACT_DIR": outputDirectory.path]
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

    func testCaptureUsesLocaleSpecificManifestOverrideWithoutMixingArtifacts() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let japaneseManifest = packageRoot()
            .appendingPathComponent("docs/quality/visual-baseline-manifest-ja.json")
        let japaneseScreenshots = packageRoot()
            .appendingPathComponent("docs/release/evidence/ui-screenshots-ja", isDirectory: true)

        XCTAssertTrue(
            script.contains(
                #"VISUAL_BASELINE_MANIFEST="${SUISUI_VISUAL_BASELINE_MANIFEST:-$ROOT_DIR/docs/quality/visual-baseline-manifest.json}""#
            )
        )

        let result = try runTool(
            ["/bin/bash", packageRoot().appendingPathComponent("script/capture_ui_evidence.sh").path, "--dry-run"],
            environment: [
                "SUISUI_UI_EVIDENCE_LOCALE": "japanese",
                "SUISUI_VISUAL_BASELINE_MANIFEST": japaneseManifest.path,
                "SUISUI_UI_EVIDENCE_DIR": japaneseScreenshots.path
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("visual baseline manifest: \(japaneseManifest.path)\n"), result.output)
        XCTAssertTrue(result.output.contains("screenshots: \(japaneseScreenshots.path)\n"), result.output)
        XCTAssertFalse(
            result.output.contains(
                "visual baseline manifest: \(packageRoot().appendingPathComponent("docs/quality/visual-baseline-manifest.json").path)\n"
            ),
            result.output
        )
        XCTAssertFalse(
            result.output.contains(
                "screenshots: \(packageRoot().appendingPathComponent("docs/release/evidence/ui-screenshots").path)\n"
            ),
            result.output
        )
    }

    func testCaptureRejectsSymlinkManifestBeforeInvalidatingReceipt() throws {
        let fixtureDirectory = packageRoot()
            .appendingPathComponent(".build/test-visual-manifest-symlink-\(UUID().uuidString)", isDirectory: true)
        let manifest = fixtureDirectory.appendingPathComponent("manifest.json")
        let manifestSymlink = fixtureDirectory.appendingPathComponent("manifest-link.json")
        let screenshotDirectory = fixtureDirectory.appendingPathComponent("screenshots", isDirectory: true)
        let receipt = fixtureDirectory.appendingPathComponent("receipt.json")
        let missingAXHelpers = fixtureDirectory.appendingPathComponent("missing-ax-helpers.sh")
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let artifactRoot = screenshotDirectory.path
            .replacingOccurrences(of: packageRoot().path + "/", with: "")
        try """
        {
          "schemaVersion": 2,
          "artifactRoot": "\(artifactRoot)",
          "baselineRoot": "docs/quality/visual-baselines",
          "baselineContext": {
            "sourceCommit": "fixture",
            "normalRoute": "normal",
            "locale": "en-US",
            "timeZoneIdentifier": "UTC",
            "referenceInstant": "2026-07-10T12:00:00Z"
          },
          "screens": []
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: manifestSymlink,
            withDestinationURL: manifest
        )
        try "sentinel\n".write(to: receipt, atomically: true, encoding: .utf8)

        let result = try runTool(
            ["/bin/bash", packageRoot().appendingPathComponent("script/capture_ui_evidence.sh").path],
            environment: [
                "AX_HELPERS": missingAXHelpers.path,
                "SUISUI_UI_EVIDENCE_DIR": screenshotDirectory.path,
                "SUISUI_UI_EVIDENCE_HOME": fixtureDirectory.appendingPathComponent("home").path,
                "SUISUI_UI_EVIDENCE_TMPDIR": fixtureDirectory.appendingPathComponent("tmp").path,
                "SUISUI_VISUAL_AX_AUDIT_RESULT": receipt.path,
                "SUISUI_VISUAL_BASELINE_MANIFEST": manifestSymlink.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("BLOCKER"), result.output)
        XCTAssertTrue(result.output.localizedCaseInsensitiveContains("symbolic link"), result.output)
        XCTAssertEqual(try String(contentsOf: receipt, encoding: .utf8), "sentinel\n")
    }

    func testCaptureRejectsExternalAXReceiptBeforeInvalidatingIt() throws {
        let fixtureDirectory = packageRoot()
            .appendingPathComponent(".build/test-visual-external-receipt-\(UUID().uuidString)", isDirectory: true)
        let screenshotDirectory = fixtureDirectory.appendingPathComponent("screenshots", isDirectory: true)
        let manifest = fixtureDirectory.appendingPathComponent("manifest.json")
        let externalReceipt = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-external-receipt-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: fixtureDirectory)
            try? FileManager.default.removeItem(at: externalReceipt)
        }
        try writeVisualManifest(manifest, screenshotDirectory: screenshotDirectory)
        try "external-sentinel\n".write(to: externalReceipt, atomically: true, encoding: .utf8)

        let result = try runCaptureReceiptValidation(
            fixtureDirectory: fixtureDirectory,
            screenshotDirectory: screenshotDirectory,
            manifest: manifest,
            receipt: externalReceipt
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("BLOCKER"), result.output)
        XCTAssertTrue(result.output.contains("receipt parent must resolve under the repository .tmp or .build directory"), result.output)
        XCTAssertEqual(try String(contentsOf: externalReceipt, encoding: .utf8), "external-sentinel\n")
    }

    func testCaptureRejectsSymlinkAXReceiptBeforeInvalidatingTarget() throws {
        let fixtureDirectory = packageRoot()
            .appendingPathComponent(".build/test-visual-symlink-receipt-\(UUID().uuidString)", isDirectory: true)
        let screenshotDirectory = fixtureDirectory.appendingPathComponent("screenshots", isDirectory: true)
        let manifest = fixtureDirectory.appendingPathComponent("manifest.json")
        let receiptTarget = fixtureDirectory.appendingPathComponent("receipt-target.json")
        let receiptSymlink = fixtureDirectory.appendingPathComponent("receipt.json")
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        try writeVisualManifest(manifest, screenshotDirectory: screenshotDirectory)
        try "symlink-sentinel\n".write(to: receiptTarget, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: receiptSymlink, withDestinationURL: receiptTarget)

        let result = try runCaptureReceiptValidation(
            fixtureDirectory: fixtureDirectory,
            screenshotDirectory: screenshotDirectory,
            manifest: manifest,
            receipt: receiptSymlink
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("BLOCKER"), result.output)
        XCTAssertTrue(result.output.localizedCaseInsensitiveContains("symbolic link"), result.output)
        XCTAssertEqual(try String(contentsOf: receiptTarget, encoding: .utf8), "symlink-sentinel\n")
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: receiptSymlink.path),
            receiptTarget.path
        )
    }

    func testVisualGateStagesArtifactMatchedPrivateManifestForCaptureAndCompare() throws {
        let fixtureDirectory = packageRoot()
            .appendingPathComponent(".build/test-ci-visual-private-manifest-\(UUID().uuidString)", isDirectory: true)
        let scriptDirectory = fixtureDirectory.appendingPathComponent("script", isDirectory: true)
        let qualityDirectory = fixtureDirectory.appendingPathComponent("docs/quality", isDirectory: true)
        let baselineDirectory = qualityDirectory.appendingPathComponent("visual-baselines", isDirectory: true)
        let manifest = qualityDirectory.appendingPathComponent("visual-baseline-manifest.json")
        let outputDirectory = fixtureDirectory.appendingPathComponent(".build/output", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: baselineDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let checkedInGate = packageRoot().appendingPathComponent("script/check_ci_visual_gate.sh")
        let fixtureGate = scriptDirectory.appendingPathComponent("check_ci_visual_gate.sh")
        try FileManager.default.copyItem(at: checkedInGate, to: fixtureGate)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixtureGate.path)
        try writeVisualGateManifest(manifest)
        try writeExecutable(
            """
            #!/usr/bin/env bash
            set -euo pipefail
            exit 0
            """,
            to: scriptDirectory.appendingPathComponent("check_macos_ui_runner_capabilities.sh")
        )
        try writeExecutable(
            visualGateManifestVerifyingStub(mode: "capture"),
            to: scriptDirectory.appendingPathComponent("capture_ui_evidence.sh")
        )
        try writeExecutable(
            visualGateManifestVerifyingStub(mode: "compare"),
            to: scriptDirectory.appendingPathComponent("check_visual_regression_smoke.sh")
        )
        let gitInit = try runTool(["/usr/bin/git", "init", "-q", fixtureDirectory.path])
        XCTAssertEqual(gitInit.exitCode, 0, gitInit.output)

        let result = try runTool(
            ["/bin/bash", fixtureGate.path],
            environment: ["SUISUI_CI_VISUAL_GATE_OUTPUT_DIR": outputDirectory.path]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("status=passed"), result.output)
        let privateManifest = outputDirectory
            .appendingPathComponent("current/visual-baseline-manifest.json")
        let values = try JSONSerialization.jsonObject(with: Data(contentsOf: privateManifest)) as? [String: Any]
        XCTAssertEqual(values?["artifactRoot"] as? String, ".build/output/current/screenshots")
        let resourceValues = try privateManifest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        XCTAssertEqual(resourceValues.isRegularFile, true)
        XCTAssertEqual(resourceValues.isSymbolicLink, false)
    }

    func testVisualGateCapturesAllBaselinesBeforeFreshReceiptComparison() throws {
        let script = try readPackageFile("script/check_ci_visual_gate.sh")

        XCTAssertTrue(script.contains("SUISUI_CI_VISUAL_GATE_OUTPUT_DIR"))
        XCTAssertTrue(script.contains("EXPECTED_SCREENSHOT_COUNT=39"))
        XCTAssertFalse(script.contains("EXPECTED_SCREENSHOT_COUNT=33"))
        XCTAssertTrue(script.contains("39-artifact capture"))
        XCTAssertFalse(script.contains("33-screen capture"))
        XCTAssertTrue(script.contains("printf 'expected_screenshot_count=%s\\n' \"$EXPECTED_SCREENSHOT_COUNT\""))
        XCTAssertTrue(script.contains("if [[ \"$MANIFEST_SCREENSHOT_COUNT\" != \"$EXPECTED_SCREENSHOT_COUNT\" ]]"))
        XCTAssertTrue(script.contains("if [[ \"$SCREENSHOT_COUNT\" != \"$EXPECTED_SCREENSHOT_COUNT\" ]]"))
        XCTAssertTrue(script.contains("SUISUI_UI_EVIDENCE_DIR=\"$SCREENSHOT_DIR\""))
        XCTAssertTrue(script.contains("SUISUI_UI_EVIDENCE_FILE=\"$CAPTURE_EVIDENCE_FILE\""))
        XCTAssertTrue(script.contains("SUISUI_UI_EVIDENCE_HOME=\"$PRIVATE_HOME\""))
        XCTAssertTrue(script.contains("SUISUI_VISUAL_AX_AUDIT_RESULT=\"$AX_RECEIPT\""))
        XCTAssertTrue(script.contains("SUISUI_VISUAL_SCREENSHOT_DIR=\"$SCREENSHOT_DIR\""))
        XCTAssertTrue(script.contains("SUISUI_VISUAL_ARTIFACT_DIR=\"$DIFF_DIR\""))
        XCTAssertTrue(script.contains("ui-visual-gate-summary.env"))
        XCTAssertTrue(script.contains("tracked-evidence-before"))
        XCTAssertTrue(script.contains("tracked-evidence-after"))
        XCTAssertTrue(script.contains("block \"visual-diff\""))
        XCTAssertTrue(script.contains("s#/(Users|Volumes)/[^[:space:]]+#<path>#g"))
        XCTAssertTrue(script.contains("/tmp/suisui-ci-visual-gate.XXXXXX"))
        XCTAssertFalse(script.contains("pkill"))
        XCTAssertFalse(script.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
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
            environment: ["SUISUI_CI_VISUAL_GATE_OUTPUT_DIR": outputDirectory.path]
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
        XCTAssertTrue(script.contains("SUISUI_REQUIRE_SINGLE_WINDOW=\"$require_single_window\""))
        XCTAssertTrue(script.contains("read_window_metadata 1"), "a recreated successor is valid only when it is the sole visible PID/name match")
        XCTAssertTrue(script.contains("if [[ \"$window_width\" -eq \"$expected_width\" ]]; then"))
        XCTAssertTrue(script.contains("INFO: reapplying owned window size"))
        XCTAssertTrue(metadataHelper.contains("environment[\"SUISUI_REQUIRE_SINGLE_WINDOW\"] == \"1\""))
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

    func testLayoutResizeMovesWindowAwayFromRightEdgeBeforeGrowing() throws {
        let script = try readPackageFile("script/check_layout_stability_smoke.sh")

        XCTAssertTrue(script.contains("set normalizedPosition to {40, expectedY}"))
        XCTAssertTrue(script.contains("set position of targetWindow to normalizedPosition"))
        let positionChange = try XCTUnwrap(script.range(of: "set position of targetWindow to normalizedPosition"))
        let sizeChange = try XCTUnwrap(script.range(of: "set size of targetWindow to {targetWidth, targetHeight}"))
        XCTAssertLessThan(positionChange.lowerBound, sizeChange.lowerBound)
    }

    func testVisualPositioningRewaitsForOwnedWindowAfterRouteRecreation() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")

        XCTAssertTrue(script.contains("wait_for_owned_evidence_window()"))
        XCTAssertTrue(script.contains("ax_wait_for_pid_owned_window \"$APP_NAME\" \"$EVIDENCE_APP_PID\" \"$window_name\""))
        XCTAssertTrue(script.contains("if ! wait_for_owned_evidence_window \"$window_name\" \"$diagnostic_file\"; then"))
        XCTAssertTrue(script.contains("INFO: waiting for recreated owned evidence window before positioning"))
        XCTAssertTrue(script.contains("wait_for_window_capture_metadata \"$window_name\""))
    }

    func testVisualPositioningRejectsAppKitViewportClampingBeforeCapture() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let positioningStart = try XCTUnwrap(script.range(of: "position_window_for_capture()"))
        let nextFunction = try XCTUnwrap(
            script.range(of: "\nassert_screenshot_has_visible_content()", range: positioningStart.upperBound..<script.endIndex)
        )
        let positioningSource = String(script[positioningStart.lowerBound..<nextFunction.lowerBound])

        XCTAssertTrue(positioningSource.contains("set actualSize to size of targetWindow"))
        XCTAssertTrue(positioningSource.contains("read -r observed_width observed_height <<<\"$ax_window_size\""))
        XCTAssertTrue(positioningSource.contains("POSITIONED_WINDOW_WIDTH=\"$observed_width\""))
        XCTAssertTrue(positioningSource.contains("[[ \"$observed_width\" == \"$width\" && \"$observed_height\" == \"$height\" ]]"))
        XCTAssertTrue(positioningSource.contains("failure_message=visual-window-viewport-mismatch"))
        XCTAssertTrue(positioningSource.contains("requested=${width}x${height}"))
        XCTAssertTrue(positioningSource.contains("observed=${observed_width}x${observed_height}"))
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
        XCTAssertTrue(retrySource.contains("successful_window_width=\"$POSITIONED_WINDOW_WIDTH\""))
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

    private func writeVisualManifest(_ manifest: URL, screenshotDirectory: URL) throws {
        let artifactRoot = screenshotDirectory.path
            .replacingOccurrences(of: packageRoot().path + "/", with: "")
        try """
        {
          "schemaVersion": 2,
          "artifactRoot": "\(artifactRoot)",
          "baselineRoot": "docs/quality/visual-baselines",
          "baselineContext": {
            "sourceCommit": "fixture",
            "normalRoute": "normal",
            "locale": "en-US",
            "timeZoneIdentifier": "UTC",
            "referenceInstant": "2026-07-10T12:00:00Z"
          },
          "screens": []
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)
    }

    private func runCaptureReceiptValidation(
        fixtureDirectory: URL,
        screenshotDirectory: URL,
        manifest: URL,
        receipt: URL
    ) throws -> (exitCode: Int32, output: String) {
        try runTool(
            ["/bin/bash", packageRoot().appendingPathComponent("script/capture_ui_evidence.sh").path],
            environment: [
                "AX_HELPERS": fixtureDirectory.appendingPathComponent("missing-ax-helpers.sh").path,
                "SUISUI_UI_EVIDENCE_DIR": screenshotDirectory.path,
                "SUISUI_UI_EVIDENCE_HOME": fixtureDirectory.appendingPathComponent("home").path,
                "SUISUI_UI_EVIDENCE_TMPDIR": fixtureDirectory.appendingPathComponent("tmp").path,
                "SUISUI_VISUAL_AX_AUDIT_RESULT": receipt.path,
                "SUISUI_VISUAL_BASELINE_MANIFEST": manifest.path
            ]
        )
    }

    private func writeVisualGateManifest(_ manifest: URL) throws {
        let screens = (0..<39).map { index in
            [
                "id": "screen-\(index)",
                "artifacts": ["light": "screen-\(index).png"]
            ] as [String: Any]
        }
        let value: [String: Any] = [
            "schemaVersion": 2,
            "artifactRoot": "docs/release/evidence/ui-screenshots",
            "baselineRoot": "docs/quality/visual-baselines",
            "baselineContext": [
                "sourceCommit": "fixture",
                "normalRoute": "normal",
                "locale": "en-US",
                "timeZoneIdentifier": "UTC",
                "referenceInstant": "2026-07-10T12:00:00Z"
            ],
            "screens": screens
        ]
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: manifest)
    }

    private func visualGateManifestVerifyingStub(mode: String) -> String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
        : "${SUISUI_VISUAL_BASELINE_MANIFEST:?private visual manifest is required}"
        if [[ ! -f "$SUISUI_VISUAL_BASELINE_MANIFEST" || -L "$SUISUI_VISUAL_BASELINE_MANIFEST" ]]; then
          printf 'private manifest must be a regular non-symlink file\\n' >&2
          exit 91
        fi
        MANIFEST_PARENT="$(cd "$(dirname "$SUISUI_VISUAL_BASELINE_MANIFEST")" && pwd -P)"
        case "$MANIFEST_PARENT/" in
          "$ROOT_DIR/.tmp/"*|"$ROOT_DIR/.build/"*) ;;
          *)
            printf 'private manifest escaped the repository output roots\\n' >&2
            exit 92
            ;;
        esac
        ARTIFACT_ROOT="$(/usr/bin/plutil -extract artifactRoot raw -o - "$SUISUI_VISUAL_BASELINE_MANIFEST")"
        if [[ "\(mode)" == "capture" ]]; then
          EXPECTED_ROOT="${SUISUI_UI_EVIDENCE_DIR#"$ROOT_DIR/"}"
          [[ "$ARTIFACT_ROOT" == "$EXPECTED_ROOT" ]] || {
            printf 'capture artifactRoot mismatch: %s != %s\\n' "$ARTIFACT_ROOT" "$EXPECTED_ROOT" >&2
            exit 93
          }
          for index in $(seq 0 38); do
            : >"$SUISUI_UI_EVIDENCE_DIR/screen-$index.png"
          done
          printf '{"status":"passed"}\\n' >"$SUISUI_VISUAL_AX_AUDIT_RESULT"
        else
          EXPECTED_ROOT="${SUISUI_VISUAL_SCREENSHOT_DIR#"$ROOT_DIR/"}"
          [[ "$ARTIFACT_ROOT" == "$EXPECTED_ROOT" ]] || {
            printf 'compare artifactRoot mismatch: %s != %s\\n' "$ARTIFACT_ROOT" "$EXPECTED_ROOT" >&2
            exit 94
          }
        fi
        """
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
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

    private func runCILayoutLaneFixture(
        capacityOutput: String,
        capacityStatus: Int32,
        runtimeStatus: Int32 = 0,
        postLayoutStatus: Int32 = 0
    ) throws -> (exitCode: Int32, output: String) {
        let ci = try readPackageFile("scripts/ci.sh")
        let layoutStart = try XCTUnwrap(ci.range(of: "layout_capacity_is_known_limitation() {"))
        let layoutEnd = try XCTUnwrap(
            ci.range(of: "\n\nrun_runtime_gates() {", range: layoutStart.upperBound..<ci.endIndex)
        )
        let sanitizerStart = try XCTUnwrap(ci.range(of: "sanitize_gate_log() {"))
        let laneEnd = try XCTUnwrap(
            ci.range(of: "\n\nvalidate_ci_flag ", range: sanitizerStart.upperBound..<ci.endIndex)
        )
        let functionSource = String(ci[layoutStart.lowerBound..<layoutEnd.lowerBound]) + "\n\n" +
            String(ci[sanitizerStart.lowerBound..<laneEnd.lowerBound])

        let fixtureDirectory = packageRoot()
            .appendingPathComponent(".build/test-ci-layout-lane-\(UUID().uuidString)", isDirectory: true)
        let scriptDirectory = fixtureDirectory.appendingPathComponent("script", isDirectory: true)
        let outputURL = fixtureDirectory.appendingPathComponent("capacity-output.txt")
        let smokeURL = scriptDirectory.appendingPathComponent("check_layout_stability_smoke.sh")
        let harnessURL = fixtureDirectory.appendingPathComponent("harness.sh")
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let normalizedCapacityOutput = capacityOutput.hasSuffix("\n") ? capacityOutput : capacityOutput + "\n"
        try normalizedCapacityOutput.write(to: outputURL, atomically: true, encoding: .utf8)
        let smoke = """
        #!/usr/bin/env bash
        set -euo pipefail
        if [[ "${1:-}" == "--check-display-capacity" ]]; then
          cat "$SUISUI_TEST_CAPACITY_OUTPUT"
          exit "$SUISUI_TEST_CAPACITY_STATUS"
        fi
        printf 'runtime layout fixture\n'
        exit "$SUISUI_TEST_RUNTIME_STATUS"
        """
        try smoke.write(to: smokeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: smokeURL.path)

        let harness = """
        #!/usr/bin/env bash
        set -euo pipefail
        CI_ARTIFACT_ROOT="$1/artifacts"
        CI_TMPDIR="$1/tmp"
        mkdir -p "$CI_ARTIFACT_ROOT" "$CI_TMPDIR"
        cd "$1"
        \(functionSource)
        runtime_fixture() {
          local layout_status=0
          run_layout_stability_gate "$CI_ARTIFACT_ROOT/ui-runtime" 1024 724 || layout_status=$?
          if [[ "$layout_status" -ne 0 ]]; then
            return "$layout_status"
          fi
          if [[ "$SUISUI_TEST_POST_LAYOUT_STATUS" -ne 0 ]]; then
            printf 'later unclassified runtime failure\n'
            return "$SUISUI_TEST_POST_LAYOUT_STATUS"
          fi
        }
        if run_lane_with_artifacts ui-runtime runtime_fixture; then
          lane_status=0
        else
          lane_status=$?
        fi
        cat "$CI_ARTIFACT_ROOT/ui-runtime/gate-summary.txt"
        exit "$lane_status"
        """
        try harness.write(to: harnessURL, atomically: true, encoding: .utf8)

        return try runTool(
            ["/bin/bash", harnessURL.path, fixtureDirectory.path],
            environment: [
                "SUISUI_TEST_CAPACITY_OUTPUT": outputURL.path,
                "SUISUI_TEST_CAPACITY_STATUS": String(capacityStatus),
                "SUISUI_TEST_RUNTIME_STATUS": String(runtimeStatus),
                "SUISUI_TEST_POST_LAYOUT_STATUS": String(postLayoutStatus)
            ]
        )
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
