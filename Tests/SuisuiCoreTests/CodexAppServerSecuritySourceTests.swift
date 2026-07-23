import Foundation
import XCTest

final class CodexAppServerSecuritySourceTests: XCTestCase {
    func testProductionSessionCodeCannotReadOrInjectCodexCredentials() throws {
        let root = repositoryRoot()
        let relativePaths = [
            "Sources/SuisuiCore/Planning/CodexAppServerAccountClient.swift",
            "Sources/SuisuiCore/Planning/CodexAppServerProvider.swift",
            "Sources/SuisuiCore/Planning/CodexLocalRuntimeProvider.swift",
            "Sources/SuisuiApp/Views/CodexAccountSettingsView.swift"
        ]
        let source = try relativePaths.map { path in
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }.joined(separator: "\n")

        // These session owners may ask Codex to authenticate, but credential
        // location and token injection must remain impossible from this layer.
        XCTAssertFalse(source.contains("homeDirectoryForCurrentUser"))
        XCTAssertFalse(source.contains("chatgptAuthTokens"))
        XCTAssertFalse(source.contains("accessToken"))
        XCTAssertFalse(source.contains("refreshToken"))
        XCTAssertFalse(source.contains("Data(contentsOf:"))
        XCTAssertFalse(source.contains("FileHandle(forReadingFrom:"))
    }

    func testAuthAccessEvidenceScriptRequiresPIDClassifiedRootTraceAndFailsClosed() throws {
        let root = repositoryRoot()
        let script = try String(
            contentsOf: root.appendingPathComponent("script/check_codex_auth_access_evidence.sh"),
            encoding: .utf8
        )
        let wrapperSource = try String(
            contentsOf: root.appendingPathComponent("script/codex_auth_access_audit_wrapper.c"),
            encoding: .utf8
        )
        let auditTestSource = try String(
            contentsOf: root.appendingPathComponent(
                "Tests/SuisuiCoreTests/CodexLocalRuntimeProviderTests.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("SUISUI_CODEX_RUN_AUTH_ACCESS_EVIDENCE"))
        XCTAssertTrue(script.contains("/usr/bin/ktrace dump"))
        XCTAssertTrue(script.contains("C3,S0x040c,S0x040e,S0x040f"))
        XCTAssertTrue(script.contains("--notify-tracing-started"))
        XCTAssertTrue(script.contains("/usr/bin/notifyutil -1"))
        XCTAssertTrue(script.contains("-l fast"))
        XCTAssertTrue(script.contains("max_raw_trace_bytes"))
        XCTAssertTrue(script.contains("/usr/bin/fs_usage -w -f pathname -R"))
        XCTAssertTrue(auditTestSource.contains("initializationTimeout: 60"))
        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertTrue(script.contains("--run-root-capture"))
        XCTAssertTrue(script.contains("root_trace_command=("))
        XCTAssertTrue(script.contains("declare -f run_root_capture"))
        XCTAssertTrue(script.contains("/bin/bash"))
        XCTAssertTrue(script.contains("\n    -c\n"))
        XCTAssertTrue(script.contains("validate_capture_channel"))
        XCTAssertTrue(script.contains("stat -f %u"))
        XCTAssertTrue(script.contains("stat -f %g"))
        XCTAssertTrue(script.contains("stat -f %z"))
        XCTAssertTrue(script.contains(": >\"$trace_ready\""))
        XCTAssertTrue(script.contains(": >\"$trace_stop\""))
        XCTAssertTrue(script.contains("chmod 0600 \"$trace_ready\" \"$trace_stop\""))
        let rootProgramDeclaration = try XCTUnwrap(
            script.range(of: "printf -v root_trace_program")
        )
        let rootCommandDeclaration = try XCTUnwrap(
            script.range(of: "root_trace_command=(")
        )
        let rootPipefail = try XCTUnwrap(
            script.range(
                of: "set -euo pipefail",
                range: rootProgramDeclaration.lowerBound..<rootCommandDeclaration.lowerBound
            )
        )
        XCTAssertLessThan(rootProgramDeclaration.lowerBound, rootPipefail.lowerBound)
        XCTAssertLessThan(rootPipefail.lowerBound, rootCommandDeclaration.lowerBound)
        XCTAssertEqual(script.components(separatedBy: "/usr/bin/ktrace dump").count - 1, 1)
        XCTAssertFalse(script.contains("run_filtered_trace"))
        XCTAssertFalse(script.contains("system_trace_ready"))
        XCTAssertFalse(script.contains("child_trace_ready"))
        XCTAssertTrue(script.contains("/usr/bin/clang"))
        XCTAssertTrue(script.contains("parent_pid"))
        XCTAssertTrue(script.contains("child_pid"))
        XCTAssertTrue(script.contains("calibration_sentinel"))
        XCTAssertTrue(script.contains("calibration_parent_pid"))
        XCTAssertTrue(script.contains("calibration_child_pid"))
        XCTAssertTrue(script.contains("calibration_unexpected_pid"))
        XCTAssertTrue(script.contains("calibration_before_pid"))
        XCTAssertTrue(script.contains("calibration_after_pid"))
        XCTAssertTrue(script.contains("calibration_parent_count"))
        XCTAssertTrue(script.contains("calibration_child_count"))
        XCTAssertTrue(script.contains("calibration_unexpected_count"))
        XCTAssertTrue(script.contains("calibration_before_count"))
        XCTAssertTrue(script.contains("calibration_after_count"))
        XCTAssertTrue(script.contains(
            "calibration_expected_total=$((\n  calibration_parent_count"
        ))
        XCTAssertTrue(script.contains("harness_parent_auth_access_count"))
        XCTAssertTrue(script.contains("codex_child_auth_access_count"))
        XCTAssertTrue(script.contains("codex_process_pids=(\"$child_pid\")"))
        XCTAssertTrue(script.contains("monitor_codex_process_tree"))
        XCTAssertTrue(script.contains("/usr/bin/pgrep -P \"$ancestor_pid\""))
        XCTAssertTrue(script.contains("for codex_process_pid in \"${codex_process_pids[@]}\""))
        XCTAssertTrue(script.contains("kill \"$codex_process_monitor_pid\""))
        XCTAssertTrue(script.contains("unexpected_auth_access_count"))
        XCTAssertTrue(script.contains(
            "unexpected_auth_access_count=$((\n  total_auth_access_count"
        ))
        XCTAssertFalse(script.contains("calibration_expected_total=$(\n"))
        XCTAssertFalse(script.contains("unexpected_auth_access_count=$(\n"))
        XCTAssertTrue(script.contains(
            "total_auth_access_count - harness_parent_auth_access_count - codex_child_auth_access_count"
        ))
        XCTAssertTrue(script.contains("sanitized_counts=parent:%s,child:%s,unexpected:%s"))
        XCTAssertTrue(script.contains("auth_path_suffix=\".codex/auth.json\""))
        XCTAssertTrue(script.contains("product_source_commit"))
        XCTAssertTrue(script.contains("audit_harness_commit"))
        XCTAssertTrue(script.contains("Tests/SuisuiCoreTests/CodexLocalRuntimeProviderTests.swift"))
        XCTAssertTrue(script.contains("audit_harness_sha256"))
        XCTAssertTrue(script.contains("codex_version"))
        XCTAssertTrue(script.contains("\"$codex_executable\" --version"))
        XCTAssertTrue(script.contains("trace_status"))
        let parentPIDPublish = try XCTUnwrap(
            auditTestSource.range(of: "wrapperPath + \".parent-pid\"")
        )
        let parentRouteWait = try XCTUnwrap(
            auditTestSource.range(of: "wrapperPath + \".parent-route-ready\"")
        )
        let transportCreation = try XCTUnwrap(
            auditTestSource.range(of: "let transport = CodexAppServerStdioTransport")
        )
        let accountCreation = try XCTUnwrap(
            auditTestSource.range(of: "let account = CodexAppServerAccountClient")
        )
        let initializeCall = try XCTUnwrap(
            auditTestSource.range(of: "try await account.initialize(clientVersion: \"auth-access-audit\")")
        )
        XCTAssertLessThan(parentPIDPublish.lowerBound, parentRouteWait.lowerBound)
        XCTAssertLessThan(parentRouteWait.lowerBound, transportCreation.lowerBound)
        XCTAssertLessThan(transportCreation.lowerBound, accountCreation.lowerBound)
        XCTAssertLessThan(accountCreation.lowerBound, initializeCall.lowerBound)

        let parentPIDWait = try XCTUnwrap(
            script.range(of: "while [[ ! -s \"${wrapper_path}.parent-pid\" ]]")
        )
        let authTraceLaunch = try XCTUnwrap(
            script.range(
                of: "launch_capture \"$auth_raw_trace\"",
                range: parentPIDWait.upperBound..<script.endIndex
            )
        )
        let authTraceStarted = try XCTUnwrap(
            script.range(
                of: "wait_for_capture_ready \"$auth_trace_ready\" \"auth-access\"",
                range: authTraceLaunch.upperBound..<script.endIndex
            )
        )
        let parentRouteRelease = try XCTUnwrap(
            script.range(
                of: "touch \"${wrapper_path}.parent-route-ready\"",
                range: authTraceStarted.upperBound..<script.endIndex
            )
        )
        let childPIDWait = try XCTUnwrap(
            script.range(
                of: "while [[ ! -s \"${wrapper_path}.child-pid\" ]]",
                range: parentRouteRelease.upperBound..<script.endIndex
            )
        )
        let processTreeMonitor = try XCTUnwrap(
            script.range(
                of: "monitor_codex_process_tree",
                range: childPIDWait.upperBound..<script.endIndex
            )
        )
        let wrapperRelease = try XCTUnwrap(
            script.range(
                of: "touch \"${wrapper_path}.ready\"",
                range: processTreeMonitor.upperBound..<script.endIndex
            )
        )
        XCTAssertLessThan(parentPIDWait.lowerBound, authTraceLaunch.lowerBound)
        XCTAssertLessThan(authTraceLaunch.lowerBound, authTraceStarted.lowerBound)
        XCTAssertLessThan(authTraceStarted.lowerBound, parentRouteRelease.lowerBound)
        XCTAssertLessThan(parentRouteRelease.lowerBound, childPIDWait.lowerBound)
        XCTAssertLessThan(childPIDWait.lowerBound, processTreeMonitor.lowerBound)
        XCTAssertLessThan(processTreeMonitor.lowerBound, wrapperRelease.lowerBound)

        let testWait = try XCTUnwrap(script.range(of: "wait \"$test_pid\""))
        let traceStopPublish = try XCTUnwrap(
            script.range(of: "printf 'stop\\n' >\"$auth_trace_stop\"")
        )
        let traceWait = try XCTUnwrap(
            script.range(
                of: "wait \"$trace_pid\"",
                range: traceStopPublish.upperBound..<script.endIndex
            )
        )
        let authPathDeclaration = try XCTUnwrap(script.range(of: "auth_path_suffix=\".codex/auth.json\""))
        let traceLaunch = try XCTUnwrap(script.range(of: "/usr/bin/ktrace dump"))
        let traceReadinessCheck = try XCTUnwrap(script.range(of: "wait_for_capture_ready"))
        XCTAssertLessThan(authPathDeclaration.lowerBound, traceLaunch.lowerBound)
        XCTAssertLessThan(traceLaunch.lowerBound, traceReadinessCheck.lowerBound)
        XCTAssertLessThan(traceReadinessCheck.lowerBound, wrapperRelease.lowerBound)
        XCTAssertLessThan(wrapperRelease.lowerBound, testWait.lowerBound)
        XCTAssertLessThan(testWait.lowerBound, traceStopPublish.lowerBound)
        XCTAssertLessThan(traceStopPublish.lowerBound, traceWait.lowerBound)
        XCTAssertTrue(script.contains("status --porcelain=v1"))
        XCTAssertTrue(script.contains("trace_loss_marker_count"))
        XCTAssertTrue(script.contains("chmod 0600"))
        XCTAssertFalse(script.contains("touch \"$auth_trace_stop\""))
        XCTAssertTrue(script.contains("/bin/unlink \"$calibration_raw_trace\""))
        XCTAssertTrue(script.contains("/bin/unlink \"$calibration_trace_diagnostic\""))
        XCTAssertTrue(script.contains("/bin/unlink \"$auth_raw_trace\""))
        XCTAssertTrue(script.contains("/bin/unlink \"$auth_trace_diagnostic\""))
        XCTAssertFalse(script.contains("/usr/bin/unlink"))
        XCTAssertTrue(script.contains("mv \"$evidence_temp\" \"$evidence_output\""))
        XCTAssertTrue(script.contains("\"schemaVersion\": 4"))
        XCTAssertTrue(script.contains("\"productSourceCommit\""))
        XCTAssertTrue(script.contains("\"auditHarnessCommit\""))
        XCTAssertTrue(script.contains("\"auditHarnessSHA256\""))
        XCTAssertTrue(script.contains("\"codexVersion\""))
        XCTAssertTrue(script.contains("\"harnessParentPID\""))
        XCTAssertTrue(script.contains("\"codexChildPID\""))
        XCTAssertTrue(script.contains("\"codexProcessPIDs\""))
        XCTAssertFalse(script.contains("\"sourceCommit\""))
        XCTAssertFalse(script.contains("cat \"$auth_path\""))
        XCTAssertTrue(wrapperSource.contains("getpid()"))
        XCTAssertTrue(wrapperSource.contains("execv("))
        XCTAssertFalse(wrapperSource.contains("auth.json"))
    }

    func testAccountSettingsCancelsActiveLoginWhenApprovalChangesOrViewCloses() throws {
        let root = repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/SuisuiApp/Views/CodexAccountSettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("activeTask"))
        XCTAssertTrue(source.contains("activeLoginID"))
        XCTAssertTrue(source.contains("activeAccountClient"))
        XCTAssertTrue(source.contains("operationGeneration"))
        XCTAssertTrue(source.contains("account.cancelLogin(id: loginID)"))
        XCTAssertTrue(source.contains("await transport.shutdown()"))
        XCTAssertTrue(source.contains("suisuiCodexExecutionApprovalDidChange"))
        XCTAssertTrue(source.contains(".onDisappear"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
