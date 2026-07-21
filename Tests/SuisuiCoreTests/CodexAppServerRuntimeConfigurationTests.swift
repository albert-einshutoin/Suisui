import Foundation
import XCTest
@testable import SuisuiCore

final class CodexAppServerRuntimeConfigurationTests: XCTestCase {
    func testRejectsRelativeOldMissingAndNonExecutablePaths() throws {
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.validate(
            executablePath: "codex",
            reportedVersion: "codex-cli 0.144.1"
        ))
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.validate(
            executablePath: "/usr/bin/true",
            reportedVersion: "codex-cli 0.120.0"
        ))
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.validate(
            executablePath: "/definitely/missing/codex",
            reportedVersion: "codex-cli 0.144.1"
        ))

        let file = try temporaryFile(executable: false)
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.validate(
            executablePath: file.path,
            reportedVersion: "codex-cli 0.144.1"
        ))
    }

    func testAcceptsMinimumAndNewerSemanticVersions() throws {
        let minimum = try CodexAppServerRuntimeConfiguration.validate(
            executablePath: "/usr/bin/true",
            reportedVersion: "codex-cli 0.144.1"
        )
        XCTAssertEqual(minimum.version, CodexAppServerVersion(major: 0, minor: 144, patch: 1))
        XCTAssertEqual(minimum.executablePath, "/usr/bin/true")

        XCTAssertNoThrow(try CodexAppServerRuntimeConfiguration.validate(
            executablePath: "/usr/bin/true",
            reportedVersion: "codex-cli 1.0.0"
        ))
    }

    func testVersionParserRejectsAmbiguousOrIncompleteOutput() {
        XCTAssertNil(CodexAppServerVersion.parse("0.144"))
        XCTAssertNil(CodexAppServerVersion.parse("codex-cli unknown"))
        XCTAssertNil(CodexAppServerVersion.parse("0.144.1 and 0.145.0"))
    }

    func testLaunchConfigurationNeverTargetsAuthStore() throws {
        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.validate(
            executablePath: "/Users/example/.codex/auth.json",
            reportedVersion: "codex-cli 0.144.1",
            fileManager: PermissiveRuntimeFileManager()
        ))
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

private struct PermissiveRuntimeFileManager: CodexRuntimeFileInspecting {
    func codexFileState(atPath _: String) -> (exists: Bool, isDirectory: Bool, isExecutable: Bool) {
        (true, false, true)
    }
}
