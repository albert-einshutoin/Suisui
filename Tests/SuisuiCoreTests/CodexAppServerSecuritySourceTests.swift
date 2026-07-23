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
        XCTAssertTrue(script.contains("/usr/bin/fs_usage"))
        XCTAssertTrue(script.contains("fs_usage -w -f pathname -t 120"))
        XCTAssertTrue(auditTestSource.contains("initializationTimeout: 60"))
        XCTAssertTrue(script.contains("/usr/bin/awk"))
        XCTAssertTrue(script.contains("-v needle="))
        XCTAssertTrue(script.contains("-v ready_path="))
        XCTAssertTrue(script.contains("index($0, needle) { print; fflush() }"))
        XCTAssertTrue(script.contains("trace_event_pattern="))
        XCTAssertTrue(script.contains("system_trace_ready"))
        XCTAssertTrue(script.contains("child_trace_ready"))
        XCTAssertTrue(script.contains("print \"ready\" > ready_path"))
        XCTAssertTrue(script.contains("close(ready_path)"))
        XCTAssertTrue(script.contains(
            "while [[ ! -s \"$system_trace_ready\" || ! -s \"$child_trace_ready\" ]]"
        ))
        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertTrue(script.contains("--run-root-traces"))
        XCTAssertTrue(script.contains("root_trace_command=("))
        XCTAssertTrue(script.contains("declare -f run_root_traces"))
        XCTAssertTrue(script.contains("/bin/bash\n  -c"))
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
        XCTAssertTrue(script.contains("child_trace_log"))
        XCTAssertTrue(script.contains(
            "run_filtered_trace \"$child_trace_output\" \"$child_trace_ready\" \"$audited_child_pid\""
        ))
        XCTAssertFalse(script.contains("parent_trace_log"))
        XCTAssertFalse(script.contains("parent_trace_output"))
        XCTAssertTrue(script.contains("/usr/bin/clang"))
        XCTAssertTrue(script.contains("parent_pid"))
        XCTAssertTrue(script.contains("child_pid"))
        XCTAssertTrue(script.contains("harness_parent_auth_access_count"))
        XCTAssertTrue(script.contains("codex_child_auth_access_count"))
        XCTAssertTrue(script.contains("unexpected_auth_access_count"))
        XCTAssertTrue(script.contains("wc -l <\"$child_trace_log\""))
        XCTAssertTrue(script.contains(
            "total_auth_access_count - codex_child_auth_access_count"
        ))
        XCTAssertTrue(script.contains("sanitized_counts=parent:%s,child:%s,unexpected:%s"))
        XCTAssertFalse(script.contains("grep -Ec \"\\\\.${parent_pid}"))
        XCTAssertFalse(script.contains("grep -Ec \"\\\\.${child_pid}"))
        XCTAssertTrue(script.contains("auth_path_suffix=\".codex/auth.json\""))
        XCTAssertTrue(script.contains("product_source_commit"))
        XCTAssertTrue(script.contains("audit_harness_commit"))
        XCTAssertTrue(script.contains("Tests/SuisuiCoreTests/CodexLocalRuntimeProviderTests.swift"))
        XCTAssertTrue(script.contains("audit_harness_sha256"))
        XCTAssertTrue(script.contains("codex_version"))
        XCTAssertTrue(script.contains("\"$codex_executable\" --version"))
        XCTAssertTrue(script.contains("trace_status"))
        XCTAssertTrue(script.contains(
            """
            if ! kill -0 "$trace_pid" >/dev/null 2>&1; then
              trace_pid=""
              echo "BLOCKER: filesystem trace ended before the audited test completed." >&2
              exit 1
            fi
            """
        ))
        let testWait = try XCTUnwrap(script.range(of: "wait \"$test_pid\""))
        let coverageCheck = try XCTUnwrap(
            script.range(of: "BLOCKER: filesystem trace ended before the audited test completed.")
        )
        let traceWait = try XCTUnwrap(script.range(of: "wait \"$trace_pid\""))
        let authPathDeclaration = try XCTUnwrap(script.range(of: "auth_path_suffix=\".codex/auth.json\""))
        let traceLaunch = try XCTUnwrap(script.range(of: "/usr/bin/fs_usage"))
        let traceReadinessCheck = try XCTUnwrap(
            script.range(
                of: "while [[ ! -s \"$system_trace_ready\" || ! -s \"$child_trace_ready\" ]]"
            )
        )
        let wrapperRelease = try XCTUnwrap(script.range(of: "touch \"${wrapper_path}.ready\""))
        XCTAssertLessThan(authPathDeclaration.lowerBound, traceLaunch.lowerBound)
        XCTAssertLessThan(traceLaunch.lowerBound, traceReadinessCheck.lowerBound)
        XCTAssertLessThan(traceReadinessCheck.lowerBound, wrapperRelease.lowerBound)
        XCTAssertLessThan(testWait.lowerBound, coverageCheck.lowerBound)
        XCTAssertLessThan(coverageCheck.lowerBound, traceWait.lowerBound)
        XCTAssertTrue(script.contains("status --porcelain=v1"))
        XCTAssertTrue(script.contains("mv \"$evidence_temp\" \"$evidence_output\""))
        XCTAssertTrue(script.contains("\"schemaVersion\": 4"))
        XCTAssertTrue(script.contains("\"productSourceCommit\""))
        XCTAssertTrue(script.contains("\"auditHarnessCommit\""))
        XCTAssertTrue(script.contains("\"auditHarnessSHA256\""))
        XCTAssertTrue(script.contains("\"codexVersion\""))
        XCTAssertTrue(script.contains("\"harnessParentPID\""))
        XCTAssertTrue(script.contains("\"codexChildPID\""))
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
