import Foundation
import XCTest

final class ReleasePipelineTests: XCTestCase {
    func testNotarizationScriptUsesStoredCredentialsStaplingAndLogRecovery() throws {
        let script = try readPackageFile("script/notarize_app.sh")

        XCTAssertTrue(script.contains("xcrun notarytool submit"))
        XCTAssertTrue(script.contains("--keychain-profile"))
        XCTAssertTrue(script.contains("--wait"))
        XCTAssertTrue(script.contains("xcrun stapler staple"))
        XCTAssertTrue(script.contains("xcrun stapler validate"))
        XCTAssertTrue(script.contains("notarytool log"))
        XCTAssertFalse(script.contains("APPLE_ID_PASSWORD"))
        XCTAssertFalse(script.contains("AC_PASSWORD"))
    }

    func testReleasePreflightReportsExternalReleaseBlockersWithoutSecrets() throws {
        let script = try readPackageFile("script/verify_release_environment.sh")

        XCTAssertTrue(script.contains("SOLOPM_SIGNING_IDENTITY"))
        XCTAssertTrue(script.contains("security find-identity -p codesigning -v"))
        XCTAssertTrue(script.contains("SOLOPM_NOTARY_PROFILE"))
        XCTAssertTrue(script.contains("SOLOPM_RELEASE_PREFLIGHT_ONLINE"))
        XCTAssertTrue(script.contains("xcrun notarytool history"))
        XCTAssertTrue(script.contains("codesign --verify --strict --deep"))
        XCTAssertTrue(script.contains("spctl -a -vv"))
        XCTAssertTrue(script.contains("BLOCKER"))
        XCTAssertFalse(script.contains("APPLE_ID_PASSWORD"))
        XCTAssertFalse(script.contains("AC_PASSWORD"))
    }

    func testReleasePreflightRequiresCleanTrackedSourceTree() throws {
        let script = try readPackageFile("script/verify_release_environment.sh")

        XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" status --porcelain --untracked-files=no"))
        XCTAssertTrue(script.contains("source tree has uncommitted tracked changes"))
    }

    func testReleasePreflightRequiresConfiguredDeveloperIDSignature() throws {
        let script = try readPackageFile("script/verify_release_environment.sh")

        XCTAssertTrue(script.contains("Developer ID Application:"))
        XCTAssertTrue(script.contains("SOLOPM_SIGNING_IDENTITY must be a Developer ID Application identity"))
        XCTAssertTrue(script.contains("codesign -dv --verbose=4"))
        XCTAssertTrue(script.contains("Authority="))
        XCTAssertTrue(script.contains("release app signature does not include configured Developer ID identity"))
    }

    func testSigningSetupRejectsNonDeveloperIDIdentity() throws {
        let script = try readPackageFile("script/verify_signing_setup.sh")

        XCTAssertTrue(script.contains("Developer ID Application:"))
        XCTAssertTrue(script.contains("SOLOPM_SIGNING_IDENTITY must be a Developer ID Application identity"))
        XCTAssertTrue(script.contains("security find-identity -p codesigning -v"))
    }

    func testReleasePreflightRequiresHardenedRuntimeSignatureFlag() throws {
        let script = try readPackageFile("script/verify_release_environment.sh")

        XCTAssertTrue(script.contains("flags=.*runtime"))
        XCTAssertTrue(script.contains("release app signature is missing hardened runtime"))
    }

    func testReleasePreflightRequiresSignedEntitlementsToMatchManifest() throws {
        let script = try readPackageFile("script/verify_release_environment.sh")

        XCTAssertTrue(script.contains("packaging/SoloPM.entitlements"))
        XCTAssertTrue(script.contains("codesign -d --entitlements :-"))
        XCTAssertTrue(script.contains("release app entitlements do not match packaging/SoloPM.entitlements"))
    }

    func testReleasePreflightRequiresAppBundleMetadataToMatchReleaseMetadata() throws {
        let script = try readPackageFile("script/verify_release_environment.sh")

        XCTAssertTrue(script.contains("CFBundleShortVersionString"))
        XCTAssertTrue(script.contains("CFBundleVersion"))
        XCTAssertTrue(script.contains("CFBundleIdentifier"))
        XCTAssertTrue(script.contains("release app bundle metadata mismatch"))
    }

    func testReleasePreflightRequiresLocalEvidenceFileForManualChecks() throws {
        let script = try readPackageFile("script/verify_release_environment.sh")

        XCTAssertTrue(script.contains("RELEASE_EVIDENCE_FILE"))
        XCTAssertTrue(script.contains("packaging/release-evidence.json"))
        XCTAssertTrue(script.contains("release.version"))
        XCTAssertTrue(script.contains("release.buildNumber"))
        XCTAssertTrue(script.contains("release.appBundlePath"))
        XCTAssertTrue(script.contains("release.artifactSha256"))
        XCTAssertTrue(script.contains("SOLOPM_RELEASE_ARTIFACT_SHA256_FILE"))
        XCTAssertTrue(script.contains("create_release_evidence.sh"))
        XCTAssertTrue(script.contains("MARKETING_VERSION"))
        XCTAssertTrue(script.contains("CURRENT_PROJECT_VERSION"))
        XCTAssertTrue(script.contains("manualChecks.cleanEnvironmentLaunch"))
        XCTAssertTrue(script.contains("manualChecks.loginItemToggle"))
        XCTAssertTrue(script.contains("plutil -extract"))
        XCTAssertTrue(script.contains("plutil -convert json"))
        XCTAssertFalse(script.contains("plutil -lint"))
        XCTAssertFalse(script.contains("SOLOPM_CLEAN_ENV_LAUNCH_CONFIRMED"))
        XCTAssertFalse(script.contains("SOLOPM_LOGIN_ITEM_TOGGLE_CONFIRMED"))
    }

    func testReleaseEvidenceExampleContainsNoSecretsAndIsIgnored() throws {
        let gitignore = try readPackageFile(".gitignore")
        let example = try readPackageFile("packaging/release-evidence.example.json")

        XCTAssertTrue(gitignore.contains("/packaging/release-evidence.json"))
        XCTAssertTrue(example.contains("\"manualChecks\""))
        XCTAssertTrue(example.contains("\"cleanEnvironmentLaunch\": false"))
        XCTAssertTrue(example.contains("\"loginItemToggle\": false"))
        XCTAssertTrue(example.contains("\"version\": \"0.1.0\""))
        XCTAssertTrue(example.contains("\"buildNumber\": \"1\""))
        XCTAssertTrue(example.contains("\"appBundlePath\": \"dist/SoloPM.app\""))
        XCTAssertFalse(example.contains("PASSWORD"))
        XCTAssertFalse(example.contains("TOKEN"))
        XCTAssertFalse(example.contains("SECRET"))
    }

    func testLocalVisualQAArtifactsAndMacMetadataAreIgnored() throws {
        let gitignore = try readPackageFile(".gitignore")
        let ignoredPaths = gitignore
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        XCTAssertTrue(ignoredPaths.contains(".DS_Store"))
        XCTAssertTrue(ignoredPaths.contains("/ui-samples/"))
    }

    func testReleasePreflightRejectsEvidenceForDifferentBuild() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-mismatch.json")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "release": {
            "version": "9.9.9",
            "buildNumber": "999",
            "appBundlePath": "dist/Other.app",
            "artifactSha256": "not-used-by-preflight"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: evidenceURL) }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: ["SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence version does not match metadata"))
        XCTAssertTrue(result.output.contains("release evidence build number does not match metadata"))
        XCTAssertTrue(result.output.contains("release evidence app bundle path does not match metadata"))
    }

    func testReleaseEvidenceScriptCreatesMetadataBoundEvidenceWithChecksum() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-created.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact.dmg.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "abcdef1234567890  dist/releases/SoloPM-0.1.0+1.dmg\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--force",
                "--clean-environment-launch",
                "--login-item-toggle",
                "--manual-environment", "macOS 15.5 clean user on arm64",
                "--checked-by", "release-owner",
                "--note", "Manual checks completed on signed build."
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let evidence = try String(contentsOf: evidenceURL, encoding: .utf8)
        XCTAssertTrue(evidence.contains("\"version\": \"0.1.0\""))
        XCTAssertTrue(evidence.contains("\"buildNumber\": \"1\""))
        XCTAssertTrue(evidence.contains("\"appBundlePath\": \"dist/SoloPM.app\""))
        XCTAssertTrue(evidence.contains("\"artifactPath\": \"dist/releases/SoloPM-0.1.0+1.dmg\""))
        XCTAssertTrue(evidence.contains("\"artifactSha256\": \"abcdef1234567890\""))
        XCTAssertTrue(evidence.contains("\"cleanEnvironmentLaunch\": true"))
        XCTAssertTrue(evidence.contains("\"loginItemToggle\": true"))
        XCTAssertTrue(evidence.contains("\"environment\": \"macOS 15.5 clean user on arm64\""))
        XCTAssertTrue(evidence.contains("\"checkedBy\": \"release-owner\""))
        XCTAssertTrue(evidence.contains("Manual checks completed on signed build."))
        XCTAssertFalse(evidence.contains("PASSWORD"))
        XCTAssertFalse(evidence.contains("TOKEN"))
        XCTAssertFalse(evidence.contains("SECRET"))
    }

    func testReleaseEvidenceScriptAcceptsRelativePackageEvidencePathForAbsoluteChecksum() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-absolute-checksum.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-absolute-checksum.dmg.sha256")
        let absoluteArtifactPath = packageRoot()
            .appendingPathComponent("dist/releases/SoloPM-0.1.0+1.dmg")
            .path
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "abcdef1234567890  \(absoluteArtifactPath)\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(
            for: checksumURL,
            artifactPath: "dist/releases/SoloPM-0.1.0+1.dmg"
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: ["--force"],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let evidence = try String(contentsOf: evidenceURL, encoding: .utf8)
        XCTAssertTrue(evidence.contains("\"artifactPath\": \"\(absoluteArtifactPath)\""))
    }

    func testReleaseEvidenceScriptRejectsMissingPackagedArtifact() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-packaged-artifact.json")
        let missingChecksumURL = packageRoot()
            .appendingPathComponent(".build/missing-release-artifact.dmg.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: ["--force"],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": missingChecksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence requires a packaged artifact checksum"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsManualChecksWithoutPackagedArtifact() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-artifact.json")
        let missingChecksumURL = packageRoot()
            .appendingPathComponent(".build/missing-release-artifact.dmg.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--force",
                "--clean-environment-launch",
                "--login-item-toggle",
                "--manual-environment", "macOS 15.5 clean user on arm64"
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": missingChecksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence requires a packaged artifact checksum"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsManualChecksWithoutEnvironment() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-manual-environment.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-missing-manual-environment.dmg.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "abcdef1234567890  dist/releases/SoloPM-0.1.0+1.dmg\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--force",
                "--clean-environment-launch",
                "--login-item-toggle"
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("manual release evidence requires --manual-environment"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsSmokePackageEvidence() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-smoke-package.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-smoke.zip.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "abcdef1234567890  dist/package-smoke/SoloPM-0.1.0+1.zip\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(
            for: checksumURL,
            artifactPath: "dist/package-smoke/SoloPM-0.1.0+1.zip",
            signedPackageRequired: false,
            notarizedPackageRequired: false
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: ["--force"],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence requires an artifact packaged with signed and notarized gates enabled"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsPackageEvidenceWithoutArtifactPath() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-package-without-artifact-path.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-package-without-artifact-path.dmg.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "abcdef1234567890  dist/releases/SoloPM-0.1.0+1.dmg\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: nil)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: ["--force"],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("package evidence manifest is missing artifact path"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleasePreflightRejectsEvidenceWithMismatchedArtifactChecksum() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-checksum.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-checksum.dmg.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "dist/releases/SoloPM-0.1.0+1.dmg",
            "artifactSha256": "evidence-sha"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "environment": "macOS 15.5 clean user on arm64"
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try "actual-sha  dist/releases/SoloPM-0.1.0+1.dmg\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
        }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence artifact SHA-256 does not match package checksum"))
    }

    func testReleasePreflightRejectsEvidenceWithoutPackageEvidenceManifest() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-no-package-manifest.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-no-package-manifest.dmg.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "dist/releases/SoloPM-0.1.0+1.dmg",
            "artifactSha256": "actual-sha"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "environment": "macOS 15.5 clean user on arm64"
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try "actual-sha  dist/releases/SoloPM-0.1.0+1.dmg\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
        }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("missing release package evidence manifest"))
    }

    func testReleasePreflightRejectsAmbiguousReleaseArtifactChecksums() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-ambiguous-artifact.json")
        let releaseDirectory = packageRoot()
            .appendingPathComponent("dist/releases", isDirectory: true)
        let dmgChecksumURL = releaseDirectory
            .appendingPathComponent("SoloPM-0.1.0+1.ambiguous-a.dmg.sha256")
        let zipChecksumURL = releaseDirectory
            .appendingPathComponent("SoloPM-0.1.0+1.ambiguous-b.zip.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: releaseDirectory,
            withIntermediateDirectories: true
        )
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "dist/releases/SoloPM-0.1.0+1.ambiguous-a.dmg",
            "artifactSha256": "actual-sha"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "environment": "macOS 15.5 clean user on arm64"
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try "actual-sha  dist/releases/SoloPM-0.1.0+1.ambiguous-a.dmg\n"
            .write(to: dmgChecksumURL, atomically: true, encoding: .utf8)
        try "other-sha  dist/releases/SoloPM-0.1.0+1.ambiguous-b.zip\n"
            .write(to: zipChecksumURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: dmgChecksumURL)
            try? FileManager.default.removeItem(at: zipChecksumURL)
        }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: ["SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("multiple release artifact checksum files found"))
        XCTAssertTrue(result.output.contains("SOLOPM_RELEASE_ARTIFACT_SHA256_FILE"))
    }

    func testReleasePreflightRejectsSmokePackageEvidence() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-preflight-smoke-package.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-preflight-smoke.zip.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "dist/package-smoke/SoloPM-0.1.0+1.zip",
            "artifactSha256": "actual-sha"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "environment": "macOS 15.5 clean user on arm64"
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try "actual-sha  dist/package-smoke/SoloPM-0.1.0+1.zip\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(
            for: checksumURL,
            artifactPath: "dist/package-smoke/SoloPM-0.1.0+1.zip",
            signedPackageRequired: false,
            notarizedPackageRequired: false
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release package evidence requires signed and notarized gates enabled"))
    }

    func testReleasePreflightRejectsPackageEvidenceWithoutArtifactPath() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-preflight-package-without-artifact-path.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-preflight-package-without-artifact-path.dmg.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "dist/releases/SoloPM-0.1.0+1.dmg",
            "artifactSha256": "actual-sha"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "environment": "macOS 15.5 clean user on arm64"
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try "actual-sha  dist/releases/SoloPM-0.1.0+1.dmg\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: nil)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release package evidence manifest is missing artifact path"))
    }

    func testReleasePreflightAcceptsRelativePackageEvidencePathForAbsoluteChecksum() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-preflight-absolute-checksum.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-preflight-absolute-checksum.dmg.sha256")
        let absoluteArtifactPath = packageRoot()
            .appendingPathComponent("dist/releases/SoloPM-0.1.0+1.dmg")
            .path
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "\(absoluteArtifactPath)",
            "artifactSha256": "actual-sha"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "environment": "macOS 15.5 clean user on arm64"
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try "actual-sha  \(absoluteArtifactPath)\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(
            for: checksumURL,
            artifactPath: "dist/releases/SoloPM-0.1.0+1.dmg"
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.output.contains("release package evidence artifact path does not match checksum"))
        XCTAssertFalse(result.output.contains("release package evidence manifest is missing artifact path"))
    }

    func testReleasePreflightRejectsManualEvidenceWithoutEnvironment() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-no-environment.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-no-environment.dmg.sha256")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "dist/releases/SoloPM-0.1.0+1.dmg",
            "artifactSha256": "actual-sha"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try "actual-sha  dist/releases/SoloPM-0.1.0+1.dmg\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
        }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence missing manual check environment"))
    }

    func testReleaseChecklistRequiresEvidenceBeforeFinalReport() throws {
        let checklist = try readPackageFile("docs/release/checklist.md")

        XCTAssertTrue(checklist.contains("packaging/release-evidence.example.json"))
        XCTAssertTrue(checklist.contains("./script/create_release_evidence.sh"))
        XCTAssertTrue(checklist.contains("packaging/release-evidence.json"))
        XCTAssertTrue(checklist.contains("manual release evidence"))
        XCTAssertTrue(checklist.contains("./script/verify_release_environment.sh"))
        XCTAssertTrue(checklist.contains("./script/release_readiness_report.sh"))
    }

    func testReleaseReadinessReportAggregatesRuntimeMockScanTasksAndPreflight() throws {
        let script = try readPackageFile("script/release_readiness_report.sh")

        XCTAssertTrue(script.contains("Sources/SoloPMCore"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp"))
        XCTAssertTrue(script.contains("Sources/SoloPMCLI"))
        XCTAssertTrue(script.contains("(?i:fake|mock|demo|canned|stub|skeleton|todo|fixme"))
        XCTAssertTrue(script.contains("not[[:space:]_-]*implemented"))
        XCTAssertTrue(script.contains("(?i:(^|[^[:alnum:]_])(sample|placeholder)([^[:alnum:]_]|$))"))
        XCTAssertTrue(script.contains("Static[A-Za-z0-9_]*"))
        XCTAssertFalse(script.contains("Fake|Mock|InMemory|Static|Demo|sample|canned|stub"))
        XCTAssertTrue(script.contains("tasks/Phase*.md"))
        XCTAssertTrue(script.contains("tasks/README.md"))
        XCTAssertTrue(script.contains("verify_release_environment.sh"))
        XCTAssertTrue(script.contains("BLOCKER"))
    }

    func testReleaseReadinessRuntimeMarkerPatternCatchesLowercaseMarkersWithoutCommonFalsePositives() throws {
        let availability = try runTool(["rg", "--version"])
        try XCTSkipIf(availability.exitCode != 0, "rg is required to exercise the release marker pattern")

        let script = try readPackageFile("script/release_readiness_report.sh")
        guard let patternLine = script
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("MOCK_PATTERN=\"") }) else {
            return XCTFail("release readiness report must define MOCK_PATTERN")
        }
        let pattern = String(patternLine.dropFirst("MOCK_PATTERN=\"".count).dropLast())

        let scanDirectory = packageRoot()
            .appendingPathComponent(".build/test-runtime-marker-scan", isDirectory: true)
        let markerFile = scanDirectory.appendingPathComponent("RuntimeMarker.swift")
        let benignFile = scanDirectory.appendingPathComponent("BenignRuntimeNames.swift")
        try FileManager.default.createDirectory(at: scanDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scanDirectory) }

        try """
        final class LocalmockExecutor {}
        struct StaticPlanningProvider {}
        let future = "Not_Implemented"
        let memoryDatabase = ":memory:"
        """.write(to: markerFile, atomically: true, encoding: .utf8)
        try """
        let settings = [AVSampleRateKey: 44_100]
        private struct ArchivedProjectPlaceholder {}
        static func buildProductionValue() {}
        """.write(to: benignFile, atomically: true, encoding: .utf8)

        let markerResult = try runTool(["rg", "-n", pattern, markerFile.path])
        XCTAssertEqual(markerResult.exitCode, 0, markerResult.output)
        XCTAssertTrue(markerResult.output.contains("LocalmockExecutor"))
        XCTAssertTrue(markerResult.output.contains("StaticPlanningProvider"))
        XCTAssertTrue(markerResult.output.contains("Not_Implemented"))
        XCTAssertTrue(markerResult.output.contains(":memory:"))

        let benignResult = try runTool(["rg", "-n", pattern, benignFile.path])
        XCTAssertEqual(benignResult.exitCode, 1, benignResult.output)
    }

    func testDistributionPackageScriptBuildsDmgWithApplicationsLinkAndChecksums() throws {
        let script = try readPackageFile("script/package_release.sh")

        XCTAssertTrue(script.contains("hdiutil create"))
        XCTAssertTrue(script.contains("ln -s /Applications"))
        XCTAssertTrue(script.contains("shasum -a 256"))
        XCTAssertTrue(script.contains("SOLOPM_PACKAGE_FORMAT"))
        XCTAssertTrue(script.contains("ditto -c -k --keepParent"))
        XCTAssertTrue(script.contains("SOLOPM_REQUIRE_SIGNED_PACKAGE"))
        XCTAssertTrue(script.contains(".package-evidence.json"))
    }

    func testDistributionPackageScriptRequiresNotarizedAppByDefault() throws {
        let script = try readPackageFile("script/package_release.sh")
        let distribution = try readPackageFile("docs/release/distribution.md")

        XCTAssertTrue(script.contains("SOLOPM_REQUIRE_NOTARIZED_PACKAGE"))
        XCTAssertTrue(script.contains("xcrun stapler validate"))
        XCTAssertTrue(script.contains("spctl -a -vv"))
        XCTAssertTrue(script.contains("package-smoke"))
        XCTAssertTrue(distribution.contains("SOLOPM_REQUIRE_NOTARIZED_PACKAGE=0"))
    }

    func testReleaseDocsCoverNotarizationDistributionAndManualChecks() throws {
        let notarization = try readPackageFile("docs/release/notarization.md")
        let distribution = try readPackageFile("docs/release/distribution.md")

        XCTAssertTrue(notarization.contains("xcrun notarytool"))
        XCTAssertTrue(notarization.contains("staple"))
        XCTAssertTrue(notarization.contains("notarytool log"))
        XCTAssertTrue(distribution.contains("DMG"))
        XCTAssertTrue(distribution.contains("Applications"))
        XCTAssertTrue(distribution.contains("checksum"))
        XCTAssertTrue(distribution.contains("clean 環境"))
    }

    func testNotarizationEnvironmentExampleDoesNotContainSecrets() throws {
        let example = try readPackageFile("packaging/notarization.env.example")

        XCTAssertTrue(example.contains("SOLOPM_NOTARY_PROFILE"))
        XCTAssertFalse(example.contains("PASSWORD="))
        XCTAssertFalse(example.contains("TOKEN="))
        XCTAssertFalse(example.contains("APPLE_ID="))
    }

    func testLocalNotarizationEnvironmentFileIsIgnored() throws {
        let gitignore = try readPackageFile(".gitignore")
        let ignoredPaths = gitignore
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        XCTAssertTrue(ignoredPaths.contains("/packaging/notarization.env"))
    }

    private func writePackageEvidence(
        for checksumURL: URL,
        artifactPath: String? = "dist/releases/SoloPM-0.1.0+1.dmg",
        signedPackageRequired: Bool = true,
        notarizedPackageRequired: Bool = true
    ) throws -> URL {
        let manifestPath = checksumURL.path.replacingOccurrences(of: ".sha256", with: ".package-evidence.json")
        let manifestURL = URL(fileURLWithPath: manifestPath)
        var jsonLines = [
            "{",
            "  \"package\": {"
        ]
        if let artifactPath {
            jsonLines.append("    \"artifactPath\": \"\(artifactPath)\",")
        }
        jsonLines += [
            "    \"format\": \"dmg\",",
            "    \"createdAt\": \"2026-06-18T00:00:00Z\",",
            "    \"signedPackageRequired\": \(signedPackageRequired ? "true" : "false"),",
            "    \"notarizedPackageRequired\": \(notarizedPackageRequired ? "true" : "false")",
            "  }",
            "}"
        ]
        try (jsonLines.joined(separator: "\n") + "\n")
            .write(to: manifestURL, atomically: true, encoding: .utf8)
        return manifestURL
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func runScript(
        _ relativePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", packageRoot().appendingPathComponent(relativePath).path] + arguments
        process.currentDirectoryURL = packageRoot()
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func runTool(_ arguments: [String]) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = packageRoot()

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
