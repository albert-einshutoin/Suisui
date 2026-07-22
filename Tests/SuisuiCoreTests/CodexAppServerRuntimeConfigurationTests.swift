import Foundation
import XCTest
@testable import SuisuiCore

final class CodexAppServerRuntimeConfigurationTests: XCTestCase {
    func testApprovalRejectsRelativeMissingDirectoryNonRegularAndNonExecutablePaths() throws {
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.approve(executablePath: "codex"))
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/definitely/missing/codex"
        ))
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.approve(executablePath: "/tmp/socket", fileManager: StubRuntimeFileInspector(
            state: makeState(isRegularFile: false)
        )))

        let file = try temporaryFile(executable: false)
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.approve(executablePath: file.path))
    }

    func testVerifiedVersionAndApprovedIdentityAreRequired() throws {
        let approved = try CodexAppServerRuntimeConfiguration.approve(executablePath: "/usr/bin/true")
        let runtime = try CodexAppServerRuntimeConfiguration.validate(
            approvedExecutable: approved,
            reportedVersion: "codex-cli 0.144.1"
        )
        XCTAssertEqual(runtime.version, CodexAppServerVersion(major: 0, minor: 144, patch: 1))
        XCTAssertEqual(runtime.executablePath, approved.resolvedPath)

        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.validate(
            approvedExecutable: approved,
            reportedVersion: "codex-cli 1.0.0"
        )) { error in
            guard case CodexAppServerRuntimeConfigurationError.unverifiedVersion = error else {
                return XCTFail("Expected unverifiedVersion, got \(error)")
            }
        }
    }

    func testChangedResolvedIdentityInvalidatesApproval() throws {
        let original = makeState(inode: 41)
        let changed = makeState(inode: 42)
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/opt/homebrew/bin/codex",
            fileManager: StubRuntimeFileInspector(state: original)
        )

        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.preflight(
            approvedExecutable: approved,
            fileManager: StubRuntimeFileInspector(state: changed)
        )) { error in
            XCTAssertEqual(error as? CodexAppServerRuntimeConfigurationError, .approvedExecutableChanged)
        }
    }

    func testVersionParserRejectsAmbiguousOrIncompleteOutput() {
        XCTAssertNil(CodexAppServerVersion.parse("0.144"))
        XCTAssertNil(CodexAppServerVersion.parse("codex-cli unknown"))
        XCTAssertNil(CodexAppServerVersion.parse("0.144.1 and 0.145.0"))
    }

    func testVersionParserRequiresExactStableCodexCLIOutput() {
        XCTAssertEqual(
            CodexAppServerVersion.parse("codex-cli 0.144.1\n"),
            CodexAppServerVersion(major: 0, minor: 144, patch: 1)
        )
        XCTAssertNil(CodexAppServerVersion.parse("codex-cli 0.144.1-beta"))
        XCTAssertNil(CodexAppServerVersion.parse("codex-cli 0.144.1+local"))
        XCTAssertNil(CodexAppServerVersion.parse("prefix 0.144.1 suffix"))
    }

    func testApprovalNeverTargetsAuthStoreDirectlyOrThroughResolvedTarget() throws {
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/Users/example/.codex/auth.json",
            fileManager: StubRuntimeFileInspector(state: makeState())
        ))

        let identity = CodexExecutableIdentity(
            resolvedPath: "/Users/example/.codex/auth.json",
            deviceID: 1,
            inode: 2,
            modificationTime: 3,
            fileSize: 4
        )
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/opt/homebrew/bin/codex",
            fileManager: StubRuntimeFileInspector(state: CodexRuntimeFileState(
                exists: true,
                isDirectory: false,
                isExecutable: true,
                isRegularFile: true,
                identity: identity
            ))
        ))
    }

    private func makeState(isRegularFile: Bool = true, inode: UInt64 = 2) -> CodexRuntimeFileState {
        CodexRuntimeFileState(
            exists: true,
            isDirectory: false,
            isExecutable: true,
            isRegularFile: isRegularFile,
            identity: CodexExecutableIdentity(
                resolvedPath: "/opt/homebrew/Cellar/codex/0.144.1/bin/codex",
                deviceID: 1,
                inode: inode,
                modificationTime: 3,
                fileSize: 4
            )
        )
    }

    private func temporaryFile(executable: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("codex")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data()))
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return file
    }
}

private struct StubRuntimeFileInspector: CodexRuntimeFileInspecting {
    let state: CodexRuntimeFileState

    func codexFileState(atPath _: String) -> CodexRuntimeFileState { state }
}
