import Foundation
import XCTest
@testable import SuisuiCore

final class CodexAppServerRuntimeConfigurationTests: XCTestCase {
    func testSystemSignedExecutableExposesIdentityAndIsRejectedByProductionPolicy() throws {
        let fileState = FileManager.default.codexFileState(atPath: "/usr/bin/true")
        let signature = try XCTUnwrap(fileState.identity?.codeSignature)

        XCTAssertFalse(signature.signingIdentifier.isEmpty)
        XCTAssertFalse(signature.designatedRequirement.isEmpty)
        XCTAssertFalse(signature.isProductionRequirementSatisfied)
        XCTAssertThrowsError(
            try CodexAppServerRuntimeConfiguration.approve(executablePath: "/usr/bin/true")
        ) { error in
            XCTAssertEqual(
                error as? CodexAppServerRuntimeConfigurationError,
                .unexpectedCodeSignature
            )
        }
    }

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
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/usr/bin/true",
            trustPolicy: .developerUnsignedAllowed
        )
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

    func testContentDigestInvalidatesApprovalWhenMetadataIsUnchanged() throws {
        let original = makeState(contentSHA256: String(repeating: "a", count: 64))
        let changed = makeState(contentSHA256: String(repeating: "b", count: 64))
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

    func testSameSizeEditWithRestoredModificationTimeInvalidatesApproval() throws {
        let executable = try temporaryFile(executable: true, contents: Data("first\n".utf8))
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: executable.path,
            trustPolicy: .developerUnsignedAllowed
        )
        let originalDate = Date(timeIntervalSince1970: approved.identity.modificationTime)

        try Data("other\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: executable.path)

        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.preflight(
            approvedExecutable: approved
        )) { error in
            XCTAssertEqual(error as? CodexAppServerRuntimeConfigurationError, .approvedExecutableChanged)
        }
    }

    func testSymlinkTargetChangeInvalidatesApproval() throws {
        let directory = try temporaryDirectory()
        let first = directory.appendingPathComponent("codex-first")
        let second = directory.appendingPathComponent("codex-second")
        let selected = directory.appendingPathComponent("codex")
        try Data("first\n".utf8).write(to: first)
        try Data("other\n".utf8).write(to: second)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: first.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: second.path)
        try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: first)
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: selected.path,
            trustPolicy: .developerUnsignedAllowed
        )

        try FileManager.default.removeItem(at: selected)
        try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: second)

        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.preflight(
            approvedExecutable: approved
        )) { error in
            XCTAssertEqual(error as? CodexAppServerRuntimeConfigurationError, .approvedExecutableChanged)
        }
    }

    func testProductionRejectsUnsignedExecutableAndDeveloperPolicyRecordsException() throws {
        let executable = try temporaryFile(executable: true, contents: Data("#!/bin/sh\n".utf8))

        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.approve(
            executablePath: executable.path
        )) { error in
            XCTAssertEqual(error as? CodexAppServerRuntimeConfigurationError, .validCodeSignatureRequired)
        }

        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: executable.path,
            trustPolicy: .developerUnsignedAllowed
        )
        XCTAssertEqual(approved.trustPolicy, .developerUnsignedAllowed)
        XCTAssertNil(approved.identity.codeSignature)
        XCTAssertEqual(approved.identity.contentSHA256.count, 64)

        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/Applications/Other.app/Contents/MacOS/other",
            fileManager: StubRuntimeFileInspector(
                state: makeState(signature: makeSignature(teamIdentifier: "OTHERTEAM"))
            )
        )) { error in
            XCTAssertEqual(
                error as? CodexAppServerRuntimeConfigurationError,
                .unexpectedCodeSignature
            )
        }
    }

    func testProductionRejectsMatchingTextIdentityWithoutAppleAnchoredRequirement() throws {
        let spoofedIdentity = makeSignature(
            signingIdentifier: "codex",
            teamIdentifier: "2DC432GLL2",
            isProductionRequirementSatisfied: false
        )

        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/Applications/Codex.app/Contents/MacOS/codex",
            fileManager: StubRuntimeFileInspector(
                state: makeState(signature: spoofedIdentity)
            )
        )) { error in
            XCTAssertEqual(
                error as? CodexAppServerRuntimeConfigurationError,
                .unexpectedCodeSignature
            )
        }
    }

    func testPackageManagerUpdateRequiresExplicitReapproval() throws {
        let directory = try temporaryDirectory()
        let executable = directory.appendingPathComponent("codex")
        try Data("version-one\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: executable.path,
            trustPolicy: .developerUnsignedAllowed
        )

        let replacement = directory.appendingPathComponent("codex.new")
        try Data("version-two\n".utf8).write(to: replacement)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: replacement.path)
        _ = try FileManager.default.replaceItemAt(executable, withItemAt: replacement)

        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.preflight(
            approvedExecutable: approved
        )) { error in
            XCTAssertEqual(error as? CodexAppServerRuntimeConfigurationError, .approvedExecutableChanged)
        }
        XCTAssertNoThrow(try CodexAppServerRuntimeConfiguration.approve(
            executablePath: executable.path,
            trustPolicy: .developerUnsignedAllowed
        ))
    }

    func testSigningIdentifierTeamAndRequirementChangesInvalidateApproval() throws {
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/opt/homebrew/bin/codex",
            fileManager: StubRuntimeFileInspector(state: makeState())
        )
        let changedSignatures = [
            makeState(signature: makeSignature(signingIdentifier: "com.example.other")),
            makeState(signature: makeSignature(teamIdentifier: "OTHERTEAM")),
            makeState(signature: makeSignature(designatedRequirement: "identifier \"com.example.codex\"")),
        ]

        for changed in changedSignatures {
            XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.preflight(
                approvedExecutable: approved,
                fileManager: StubRuntimeFileInspector(state: changed)
            )) { error in
                XCTAssertEqual(error as? CodexAppServerRuntimeConfigurationError, .approvedExecutableChanged)
            }
        }
    }

    func testLegacyMetadataOnlyApprovalRequiresFreshApproval() throws {
        let legacy = """
        {
          "path": "/usr/bin/true",
          "identity": {
            "resolvedPath": "/usr/bin/true",
            "deviceID": 1,
            "inode": 2,
            "modificationTime": 3,
            "fileSize": 4
          },
          "approvedAt": 0
        }
        """
        let approved = try JSONDecoder().decode(ApprovedCodexExecutable.self, from: Data(legacy.utf8))

        XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.preflight(
            approvedExecutable: approved
        )) { error in
            XCTAssertEqual(error as? CodexAppServerRuntimeConfigurationError, .executionApprovalRequired)
        }
    }

    func testLegacySignatureIdentityRequiresFreshAppleAnchoredVerification() throws {
        let legacy = """
        {
          "signingIdentifier": "codex",
          "teamIdentifier": "2DC432GLL2",
          "designatedRequirement": "identifier codex"
        }
        """

        let signature = try JSONDecoder().decode(
            CodexCodeSignatureIdentity.self,
            from: Data(legacy.utf8)
        )

        XCTAssertFalse(signature.isProductionRequirementSatisfied)
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
        XCTAssertNil(CodexAppServerVersion.parse("codex-cli 00.144.1"))
        XCTAssertNil(CodexAppServerVersion.parse("codex-cli 0.0144.1"))
        XCTAssertNil(CodexAppServerVersion.parse("codex-cli 0.144.01"))
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
            fileSize: 4,
            contentSHA256: String(repeating: "a", count: 64),
            codeSignature: makeSignature()
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

    private func makeState(
        isRegularFile: Bool = true,
        inode: UInt64 = 2,
        contentSHA256: String = String(repeating: "a", count: 64),
        signature: CodexCodeSignatureIdentity? = nil
    ) -> CodexRuntimeFileState {
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
                fileSize: 4,
                contentSHA256: contentSHA256,
                codeSignature: signature ?? makeSignature()
            )
        )
    }

    private func makeSignature(
        signingIdentifier: String = "codex",
        teamIdentifier: String? = "2DC432GLL2",
        designatedRequirement: String = "identifier \"codex\" and anchor apple generic and certificate leaf[subject.OU] = \"2DC432GLL2\"",
        isProductionRequirementSatisfied: Bool = true
    ) -> CodexCodeSignatureIdentity {
        CodexCodeSignatureIdentity(
            signingIdentifier: signingIdentifier,
            teamIdentifier: teamIdentifier,
            designatedRequirement: designatedRequirement,
            isProductionRequirementSatisfied: isProductionRequirementSatisfied
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func temporaryFile(executable: Bool, contents: Data = Data()) throws -> URL {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("codex")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: contents))
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        return file
    }
}

private struct StubRuntimeFileInspector: CodexRuntimeFileInspecting {
    let state: CodexRuntimeFileState

    func codexFileState(atPath _: String) -> CodexRuntimeFileState { state }
}
