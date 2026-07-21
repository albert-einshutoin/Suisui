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

        XCTAssertTrue(script.contains("SUISUI_CODEX_RUN_AUTH_ACCESS_EVIDENCE"))
        XCTAssertTrue(script.contains("/usr/bin/fs_usage"))
        XCTAssertTrue(script.contains("fs_usage -e -w -f pathname -t 12"))
        XCTAssertTrue(script.contains("/usr/bin/clang"))
        XCTAssertTrue(script.contains("parent_pid"))
        XCTAssertTrue(script.contains("child_pid"))
        XCTAssertTrue(script.contains("parent_auth_access_count"))
        XCTAssertTrue(script.contains("child_auth_access_count"))
        XCTAssertTrue(script.contains("unexpected_auth_access_count"))
        XCTAssertTrue(script.contains("auth_path_suffix=\".codex/auth.json\""))
        XCTAssertTrue(script.contains("product_source_commit"))
        XCTAssertTrue(script.contains("audit_harness_commit"))
        XCTAssertTrue(script.contains("codex_version"))
        XCTAssertTrue(script.contains("\"$codex_executable\" --version"))
        XCTAssertTrue(script.contains("\"schemaVersion\": 2"))
        XCTAssertTrue(script.contains("\"productSourceCommit\""))
        XCTAssertTrue(script.contains("\"auditHarnessCommit\""))
        XCTAssertTrue(script.contains("\"codexVersion\""))
        XCTAssertFalse(script.contains("\"sourceCommit\""))
        XCTAssertFalse(script.contains("cat \"$auth_path\""))
        XCTAssertTrue(wrapperSource.contains("getpid()"))
        XCTAssertTrue(wrapperSource.contains("execv("))
        XCTAssertFalse(wrapperSource.contains("auth.json"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
