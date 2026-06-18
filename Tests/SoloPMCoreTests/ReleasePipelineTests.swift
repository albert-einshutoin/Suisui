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

    func testNotarizationRequiresDeveloperIDAndHardenedRuntimeBeforeSubmit() throws {
        let script = try readPackageFile("script/notarize_app.sh")

        XCTAssertTrue(script.contains("codesign -dv --verbose=4"))
        XCTAssertTrue(script.contains("Authority=Developer ID Application:"))
        XCTAssertTrue(script.contains("flags=.*runtime"))
        XCTAssertTrue(script.contains("not signed with a Developer ID Application identity"))
        XCTAssertTrue(script.contains("signature is missing hardened runtime"))
    }

    func testNotarizationSetupVerifierChecksProfileWithoutSecrets() throws {
        let script = try readPackageFile("script/verify_notarization_setup.sh")

        XCTAssertTrue(script.contains("SOLOPM_NOTARY_PROFILE"))
        XCTAssertTrue(script.contains("SOLOPM_RELEASE_PREFLIGHT_ONLINE"))
        XCTAssertTrue(script.contains("xcrun notarytool history"))
        XCTAssertTrue(script.contains("--keychain-profile"))
        XCTAssertFalse(script.contains("APPLE_ID_PASSWORD"))
        XCTAssertFalse(script.contains("AC_PASSWORD"))
        XCTAssertFalse(script.contains("PASSWORD="))
        XCTAssertFalse(script.contains("TOKEN="))
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

    func testReleasePreflightRequiresAppBundleStructure() throws {
        let script = try readPackageFile("script/verify_release_environment.sh")

        XCTAssertTrue(script.contains("release app bundle is missing executable"))
        XCTAssertTrue(script.contains("release app bundle executable is not executable"))
        XCTAssertTrue(script.contains("release app bundle is missing resources directory"))
        XCTAssertTrue(script.contains("release app bundle is missing action plan schema resource"))
        XCTAssertTrue(script.contains("release app bundle is missing Sparkle framework"))
        XCTAssertTrue(script.contains("release app bundle is missing Sparkle updater app"))
    }

    func testReleasePreflightRequiresProductionSparkleFeedMetadata() throws {
        let script = try readPackageFile("script/verify_release_environment.sh")

        XCTAssertTrue(script.contains("SPARKLE_ENV_FILE"))
        XCTAssertTrue(script.contains("validate_sparkle_release_config.sh"))
        XCTAssertTrue(script.contains("release Sparkle config is invalid"))
        XCTAssertTrue(script.contains("SUFeedURL"))
        XCTAssertTrue(script.contains("SUPublicEDKey"))
        XCTAssertTrue(script.contains("release app is missing Sparkle feed URL"))
        XCTAssertTrue(script.contains("release app is missing Sparkle public EdDSA key"))
        XCTAssertTrue(script.contains("release app Sparkle feed URL must use https"))
        XCTAssertTrue(script.contains("release app Sparkle feed URL must not use placeholder or local domains"))
        XCTAssertTrue(script.contains("release app Sparkle public EdDSA key must not use a placeholder key"))
        XCTAssertTrue(script.contains("release app Sparkle public EdDSA key must be a base64 public key"))
        XCTAssertTrue(script.contains("release app Sparkle feed URL does not match configured SOLOPM_SPARKLE_FEED_URL"))
        XCTAssertTrue(script.contains("release app Sparkle public EdDSA key does not match configured SOLOPM_SPARKLE_PUBLIC_ED_KEY"))
    }

    func testReleasePreflightRejectsInvalidSparkleReleaseConfiguration() throws {
        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: [
                "SOLOPM_SPARKLE_FEED_URL": "http://updates.example.invalid/solopm/appcast.xml",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release Sparkle config is invalid"))
        XCTAssertTrue(result.output.contains("SOLOPM_SPARKLE_FEED_URL must use https for release builds"))
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
        XCTAssertTrue(script.contains("release.sparkleFeedURL"))
        XCTAssertTrue(script.contains("release.appcastPath"))
        XCTAssertTrue(script.contains("create_release_evidence.sh"))
        XCTAssertTrue(script.contains("MARKETING_VERSION"))
        XCTAssertTrue(script.contains("CURRENT_PROJECT_VERSION"))
        XCTAssertTrue(script.contains("missing release artifact file"))
        XCTAssertTrue(script.contains("release artifact SHA-256 does not match checksum file"))
        XCTAssertTrue(script.contains("shasum -a 256"))
        XCTAssertTrue(script.contains("manualChecks.releaseMachineLaunch"))
        XCTAssertTrue(script.contains("manualChecks.checksumVerification"))
        XCTAssertTrue(script.contains("manualChecks.cleanDmgInstall"))
        XCTAssertTrue(script.contains("manualChecks.applicationsFolderInstall"))
        XCTAssertTrue(script.contains("manualChecks.gatekeeperAccepted"))
        XCTAssertTrue(script.contains("manualChecks.cleanEnvironmentLaunch"))
        XCTAssertTrue(script.contains("manualChecks.loginItemToggle"))
        XCTAssertTrue(script.contains("manualChecks.sparkleAppcastMetadata"))
        XCTAssertTrue(script.contains("plutil -extract"))
        XCTAssertTrue(script.contains("plutil -convert json"))
        XCTAssertFalse(script.contains("plutil -lint"))
        XCTAssertFalse(script.contains("SOLOPM_CLEAN_ENV_LAUNCH_CONFIRMED"))
        XCTAssertFalse(script.contains("SOLOPM_LOGIN_ITEM_TOGGLE_CONFIRMED"))
    }

    func testReleasePreflightRequiresGeneratedReleaseAppcast() throws {
        let script = try readPackageFile("script/verify_release_environment.sh")

        XCTAssertTrue(script.contains("RELEASE_APPCAST_FILE"))
        XCTAssertTrue(script.contains("dist/releases/appcast.xml"))
        XCTAssertTrue(script.contains("SOLOPM_REQUIRE_RELEASE_APPCAST=1"))
        XCTAssertTrue(script.contains("verify_appcast.sh"))
        XCTAssertTrue(script.contains("release appcast verification failed"))
    }

    func testReleasePreflightIncludesAppcastVerifierFailureReason() throws {
        let appcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-preflight-reason.xml")
        try FileManager.default.createDirectory(
            at: appcastURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <title>SoloPM</title>
            <item>
              <title>0.1.0</title>
              <sparkle:version>1</sparkle:version>
              <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
              <enclosure url="https://example.com/releases/SoloPM-0.1.0+1.zip" length="12345" type="application/octet-stream" sparkle:edSignature="release-signature-smoke-value"/>
            </item>
          </channel>
        </rss>
        """.write(to: appcastURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: appcastURL) }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: ["SOLOPM_RELEASE_APPCAST_FILE": appcastURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release appcast verification failed: \(appcastURL.path): release appcast enclosure URL must not use placeholder or local domains"))
    }

    func testReleaseEvidenceExampleContainsNoSecretsAndIsIgnored() throws {
        let gitignore = try readPackageFile(".gitignore")
        let example = try readPackageFile("packaging/release-evidence.example.json")

        XCTAssertTrue(gitignore.contains("/packaging/release-evidence.json"))
        XCTAssertTrue(example.contains("\"manualChecks\""))
        XCTAssertTrue(example.contains("\"releaseMachineLaunch\": false"))
        XCTAssertTrue(example.contains("\"checksumVerification\": false"))
        XCTAssertTrue(example.contains("\"cleanDmgInstall\": false"))
        XCTAssertTrue(example.contains("\"applicationsFolderInstall\": false"))
        XCTAssertTrue(example.contains("\"gatekeeperAccepted\": false"))
        XCTAssertTrue(example.contains("\"cleanEnvironmentLaunch\": false"))
        XCTAssertTrue(example.contains("\"loginItemToggle\": false"))
        XCTAssertTrue(example.contains("\"sparkleAppcastMetadata\": false"))
        XCTAssertTrue(example.contains("\"version\": \"0.1.0\""))
        XCTAssertTrue(example.contains("\"buildNumber\": \"1\""))
        XCTAssertTrue(example.contains("\"appBundlePath\": \"dist/SoloPM.app\""))
        XCTAssertTrue(example.contains("\"signingIdentity\""))
        XCTAssertTrue(example.contains("\"notaryProfile\""))
        XCTAssertTrue(example.contains("\"sparkleFeedURL\""))
        XCTAssertTrue(example.contains("\"appcastPath\": \"dist/releases/appcast.xml\""))
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
        let artifactPath = ".build/test-release-artifact.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        let appcastURL = try writeReleaseAppcastFixture(
            at: packageRoot().appendingPathComponent(".build/test-release-appcast.xml")
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
            try? FileManager.default.removeItem(at: appcastURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--force",
                "--release-machine-launch",
                "--checksum-verification",
                "--clean-dmg-install",
                "--applications-folder-install",
                "--gatekeeper-accepted",
                "--clean-environment-launch",
                "--login-item-toggle",
                "--sparkle-appcast-metadata",
                "--manual-environment", "macOS 15.5 clean user on arm64",
                "--checked-by", "release-owner",
                "--note", "Verified launch, Gatekeeper, clean DMG install, Applications install, login item toggle, checksum, and Sparkle appcast on macOS 15.5 arm64 signed build."
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path,
                "SOLOPM_RELEASE_APPCAST_FILE": appcastURL.path,
                "SOLOPM_SIGNING_IDENTITY": "Developer ID Application: SoloPM Test (TEAMID)",
                "SOLOPM_NOTARY_PROFILE": "SoloPMNotaryProfile",
                "SOLOPM_SPARKLE_FEED_URL": "https://updates.solopm.app/releases/appcast.xml",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.solopm.app/releases/",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let evidence = try String(contentsOf: evidenceURL, encoding: .utf8)
        XCTAssertTrue(evidence.contains("\"version\": \"0.1.0\""))
        XCTAssertTrue(evidence.contains("\"buildNumber\": \"1\""))
        XCTAssertTrue(evidence.contains("\"appBundlePath\": \"dist/SoloPM.app\""))
        XCTAssertTrue(evidence.contains("\"artifactPath\": \"\(artifactPath)\""))
        XCTAssertTrue(evidence.contains("\"artifactSha256\": \"42bd420cc2f99e68e60005fa7c28fc2f60e4e04ee160d9dd3b98e72fc2954f98\""))
        XCTAssertTrue(evidence.contains("\"signingIdentity\": \"Developer ID Application: SoloPM Test (TEAMID)\""))
        XCTAssertTrue(evidence.contains("\"notaryProfile\": \"SoloPMNotaryProfile\""))
        XCTAssertTrue(evidence.contains("\"sparkleFeedURL\": \"https://updates.solopm.app/releases/appcast.xml\""))
        XCTAssertTrue(evidence.contains("\"appcastPath\": \".build/test-release-appcast.xml\""))
        XCTAssertTrue(evidence.contains("\"source\""))
        XCTAssertTrue(evidence.contains("\"gitCommit\": \"\(try currentGitCommit())\""))
        XCTAssertTrue(evidence.contains("\"releaseMachineLaunch\": true"))
        XCTAssertTrue(evidence.contains("\"checksumVerification\": true"))
        XCTAssertTrue(evidence.contains("\"cleanDmgInstall\": true"))
        XCTAssertTrue(evidence.contains("\"applicationsFolderInstall\": true"))
        XCTAssertTrue(evidence.contains("\"gatekeeperAccepted\": true"))
        XCTAssertTrue(evidence.contains("\"cleanEnvironmentLaunch\": true"))
        XCTAssertTrue(evidence.contains("\"loginItemToggle\": true"))
        XCTAssertTrue(evidence.contains("\"sparkleAppcastMetadata\": true"))
        XCTAssertTrue(evidence.contains("\"environment\": \"macOS 15.5 clean user on arm64\""))
        XCTAssertTrue(evidence.contains("\"checkedBy\": \"release-owner\""))
        XCTAssertTrue(evidence.contains("Verified launch, Gatekeeper, clean DMG install, Applications install, login item toggle, checksum, and Sparkle appcast on macOS 15.5 arm64 signed build."))
        XCTAssertFalse(evidence.contains("PASSWORD"))
        XCTAssertFalse(evidence.contains("TOKEN"))
        XCTAssertFalse(evidence.contains("SECRET"))
    }

    func testReleaseEvidenceScriptAcceptsRelativePackageEvidencePathForAbsoluteChecksum() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-absolute-checksum.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-absolute-checksum.dmg.sha256")
        let relativeArtifactPath = ".build/test-release-artifact-absolute-checksum.dmg"
        let absoluteArtifactPath = packageRoot()
            .appendingPathComponent(relativeArtifactPath)
            .path
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: absoluteArtifactPath)
        let packageEvidenceURL = try writePackageEvidence(
            for: checksumURL,
            artifactPath: relativeArtifactPath
        )
        let appcastURL = try writeReleaseAppcastFixture(
            at: packageRoot().appendingPathComponent(".build/test-release-appcast-absolute-checksum.xml")
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
            try? FileManager.default.removeItem(at: appcastURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: ["--force"],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path,
                "SOLOPM_RELEASE_APPCAST_FILE": appcastURL.path,
                "SOLOPM_SIGNING_IDENTITY": "Developer ID Application: SoloPM Test (TEAMID)",
                "SOLOPM_NOTARY_PROFILE": "SoloPMNotaryProfile",
                "SOLOPM_SPARKLE_FEED_URL": "https://updates.solopm.app/releases/appcast.xml",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.solopm.app/releases/",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let evidence = try String(contentsOf: evidenceURL, encoding: .utf8)
        XCTAssertTrue(evidence.contains("\"artifactPath\": \"\(absoluteArtifactPath)\""))
    }

    func testReleaseEvidenceScriptRejectsPackageEvidenceFromDifferentSourceCommit() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-stale-source.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-stale-source.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-stale-source.dmg"
        let appcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-stale-source.xml")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(
            for: checksumURL,
            artifactPath: artifactPath,
            gitCommit: "0000000000000000000000000000000000000000"
        )
        try writeReleaseAppcastFixture(at: appcastURL)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
            try? FileManager.default.removeItem(at: appcastURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: ["--force"],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path,
                "SOLOPM_RELEASE_APPCAST_FILE": appcastURL.path,
                "SOLOPM_SIGNING_IDENTITY": "Developer ID Application: SoloPM Test (TEAMID)",
                "SOLOPM_NOTARY_PROFILE": "SoloPMNotaryProfile",
                "SOLOPM_SPARKLE_FEED_URL": "https://updates.solopm.app/releases/appcast.xml",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.solopm.app/releases/",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("package evidence source commit does not match current git commit"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsInvalidReleaseAppcast() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-invalid-appcast.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-invalid-appcast.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-invalid-appcast.dmg"
        let appcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-invalid.xml")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        try writeReleaseAppcastFixture(at: appcastURL, includeSignature: false)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
            try? FileManager.default.removeItem(at: appcastURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: ["--force"],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path,
                "SOLOPM_RELEASE_APPCAST_FILE": appcastURL.path,
                "SOLOPM_SIGNING_IDENTITY": "Developer ID Application: SoloPM Test (TEAMID)",
                "SOLOPM_NOTARY_PROFILE": "SoloPMNotaryProfile",
                "SOLOPM_SPARKLE_FEED_URL": "https://updates.solopm.app/releases/appcast.xml",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.solopm.app/releases/",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence appcast verification failed"))
        XCTAssertTrue(result.output.contains("release appcast is missing Sparkle edSignature"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRequiresSparkleContextForSuccessfulEvidence() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-sparkle-context.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-missing-sparkle-context.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-missing-sparkle-context.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: ["--force"],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path,
                "SOLOPM_SIGNING_IDENTITY": "Developer ID Application: SoloPM Test (TEAMID)",
                "SOLOPM_NOTARY_PROFILE": "SoloPMNotaryProfile"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence Sparkle config is invalid"))
        XCTAssertTrue(result.output.contains("SOLOPM_SPARKLE_FEED_URL is required for release builds"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRequiresSigningContextForSuccessfulEvidence() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-signing-context.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-missing-signing-context.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-missing-signing-context.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
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
        XCTAssertTrue(result.output.contains("release evidence requires SOLOPM_SIGNING_IDENTITY and SOLOPM_NOTARY_PROFILE"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
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

    func testReleaseEvidenceScriptRejectsMissingArtifactFileReferencedByChecksum() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-artifact-file.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-evidence-missing-file.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-evidence-missing-file.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "42bd420cc2f99e68e60005fa7c28fc2f60e4e04ee160d9dd3b98e72fc2954f98  \(artifactPath)\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
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
        XCTAssertTrue(result.output.contains("missing release artifact file"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsArtifactFileHashMismatch() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-artifact-file-hash.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-evidence-file-hash.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-evidence-file-hash.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(
            to: checksumURL,
            artifactPath: artifactPath,
            sha256: "actual-sha"
        )
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
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
        XCTAssertTrue(result.output.contains("release artifact SHA-256 does not match checksum file"))
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
        let artifactPath = ".build/test-release-artifact-missing-manual-environment.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
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
        XCTAssertTrue(result.output.contains("manual release evidence requires a concrete --manual-environment"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsBlankManualEnvironment() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-blank-manual-environment.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-blank-manual-environment.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-blank-manual-environment.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--force",
                "--clean-environment-launch",
                "--login-item-toggle",
                "--manual-environment", "   "
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("manual release evidence requires a concrete --manual-environment"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsBoilerplateManualReviewNote() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-boilerplate-review-note.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-boilerplate-review-note.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-boilerplate-review-note.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        let appcastURL = try writeReleaseAppcastFixture(
            at: packageRoot().appendingPathComponent(".build/test-release-appcast-boilerplate-review-note.xml")
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
            try? FileManager.default.removeItem(at: appcastURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--force",
                "--clean-environment-launch",
                "--login-item-toggle",
                "--manual-environment", "macOS 15.5 clean user on arm64",
                "--checked-by", "release-owner",
                "--note", "Manual checks completed."
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path,
                "SOLOPM_RELEASE_APPCAST_FILE": appcastURL.path,
                "SOLOPM_SIGNING_IDENTITY": "Developer ID Application: SoloPM Test (TEAMID)",
                "SOLOPM_NOTARY_PROFILE": "SoloPMNotaryProfile",
                "SOLOPM_SPARKLE_FEED_URL": "https://updates.solopm.app/releases/appcast.xml",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.solopm.app/releases/",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence review notes must include concrete verification details"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsTemplateManualEnvironment() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-template-manual-environment.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-template-manual-environment.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-template-manual-environment.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--force",
                "--clean-environment-launch",
                "--login-item-toggle",
                "--manual-environment", "macOS version, hardware, clean user/install notes"
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("manual release evidence requires a concrete --manual-environment"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRequiresExplicitReviewNoteForManualChecks() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-manual-without-note.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-manual-without-note.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-manual-without-note.dmg"
        let appcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-manual-without-note.xml")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        try writeReleaseAppcastFixture(at: appcastURL)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
            try? FileManager.default.removeItem(at: appcastURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--force",
                "--release-machine-launch",
                "--checksum-verification",
                "--clean-dmg-install",
                "--applications-folder-install",
                "--gatekeeper-accepted",
                "--clean-environment-launch",
                "--login-item-toggle",
                "--sparkle-appcast-metadata",
                "--manual-environment", "macOS 15.5 clean user on arm64",
                "--checked-by", "release-owner"
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path,
                "SOLOPM_RELEASE_APPCAST_FILE": appcastURL.path,
                "SOLOPM_SIGNING_IDENTITY": "Developer ID Application: SoloPM Test (TEAMID)",
                "SOLOPM_NOTARY_PROFILE": "SoloPMNotaryProfile",
                "SOLOPM_SPARKLE_FEED_URL": "https://updates.solopm.app/releases/appcast.xml",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.solopm.app/releases/",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("manual release evidence requires at least one explicit --note"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsBlankReviewer() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-blank-reviewer.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-blank-reviewer.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-blank-reviewer.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--force",
                "--checked-by", "   "
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence requires --checked-by"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
    }

    func testReleaseEvidenceScriptRejectsBlankReviewNote() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-blank-review-note.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-blank-review-note.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-blank-review-note.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--force",
                "--note", "   "
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence review notes cannot be blank"))
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

    func testReleasePreflightRejectsMissingArtifactFileReferencedByChecksum() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-artifact-file.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-missing-file.dmg.sha256")
        let artifactPath = "dist/releases/SoloPM-0.1.0+1.missing-file.dmg"
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
            "artifactPath": "\(artifactPath)",
            "artifactSha256": "actual-sha"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "environment": "macOS 15.5 clean user on arm64"
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try "actual-sha  \(artifactPath)\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
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
        XCTAssertTrue(result.output.contains("missing release artifact file"))
    }

    func testReleasePreflightRejectsArtifactFileHashMismatch() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-artifact-file-hash.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-file-hash.dmg.sha256")
        let artifactURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-file-hash.dmg")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "artifact content".write(to: artifactURL, atomically: true, encoding: .utf8)
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "\(artifactURL.path)",
            "artifactSha256": "actual-sha"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "environment": "macOS 15.5 clean user on arm64"
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try "actual-sha  \(artifactURL.path)\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactURL.path)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
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
        XCTAssertTrue(result.output.contains("release artifact SHA-256 does not match checksum file"))
    }

    func testReleasePreflightRejectsEvidenceForDifferentSigningContext() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-signing-context.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-signing-context.dmg.sha256")
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
            "artifactSha256": "actual-sha",
            "signingIdentity": "Developer ID Application: Other Release Owner (TEAMID)",
            "notaryProfile": "OtherNotaryProfile"
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
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path,
                "SOLOPM_SIGNING_IDENTITY": "Developer ID Application: SoloPM Release Owner (TEAMID)",
                "SOLOPM_NOTARY_PROFILE": "SoloPMNotaryProfile"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence signing identity does not match metadata"))
        XCTAssertTrue(result.output.contains("release evidence notary profile does not match metadata"))
    }

    func testReleasePreflightRejectsEvidenceForDifferentSparkleContext() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-sparkle-context.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-sparkle-context.dmg.sha256")
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
            "artifactSha256": "actual-sha",
            "signingIdentity": "Developer ID Application: SoloPM Release Owner (TEAMID)",
            "notaryProfile": "SoloPMNotaryProfile",
            "sparkleFeedURL": "https://updates-old.solopm.app/releases/appcast.xml",
            "appcastPath": "dist/releases/old-appcast.xml"
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
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
        }

        let result = try runScript(
            "script/verify_release_environment.sh",
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path,
                "SOLOPM_SIGNING_IDENTITY": "Developer ID Application: SoloPM Release Owner (TEAMID)",
                "SOLOPM_NOTARY_PROFILE": "SoloPMNotaryProfile",
                "SOLOPM_SPARKLE_FEED_URL": "https://updates.solopm.app/releases/appcast.xml",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence Sparkle feed URL does not match metadata"))
        XCTAssertTrue(result.output.contains("release evidence appcast path does not match metadata"))
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
            .appendingPathComponent(".build/test-release-artifact-preflight-absolute-checksum.dmg")
            .path
        let relativeArtifactPath = ".build/test-release-artifact-preflight-absolute-checksum.dmg"
        let artifactSha = "42bd420cc2f99e68e60005fa7c28fc2f60e4e04ee160d9dd3b98e72fc2954f98"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "artifact content".write(
            to: URL(fileURLWithPath: absoluteArtifactPath),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "\(absoluteArtifactPath)",
            "artifactSha256": "\(artifactSha)"
          },
          "manualChecks": {
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "environment": "macOS 15.5 clean user on arm64"
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try "\(artifactSha)  \(absoluteArtifactPath)\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        let packageEvidenceURL = try writePackageEvidence(
            for: checksumURL,
            artifactPath: relativeArtifactPath
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(atPath: absoluteArtifactPath)
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
        XCTAssertFalse(result.output.contains("missing release artifact file"))
        XCTAssertFalse(result.output.contains("release artifact SHA-256 does not match checksum file"))
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

    func testReleasePreflightRejectsTemplateManualEnvironment() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-template-environment.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-template-environment.dmg.sha256")
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
            "artifactSha256": "actual-sha",
            "signingIdentity": "Developer ID Application: SoloPM Test (TEAMID)",
            "notaryProfile": "SoloPMNotaryProfile",
            "sparkleFeedURL": "https://updates.solopm.app/releases/appcast.xml",
            "appcastPath": "dist/releases/appcast.xml"
          },
          "manualChecks": {
            "releaseMachineLaunch": true,
            "checksumVerification": true,
            "cleanDmgInstall": true,
            "applicationsFolderInstall": true,
            "gatekeeperAccepted": true,
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "sparkleAppcastMetadata": true,
            "environment": "macOS version, hardware, clean user/install notes"
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
        XCTAssertTrue(result.output.contains("release evidence manual check environment is not concrete"))
    }

    func testReleasePreflightRejectsEvidenceWithoutReviewMetadata() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-review.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-missing-review.dmg.sha256")
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
            "artifactSha256": "actual-sha",
            "signingIdentity": "Developer ID Application: SoloPM Test (TEAMID)",
            "notaryProfile": "SoloPMNotaryProfile",
            "sparkleFeedURL": "https://updates.solopm.app/releases/appcast.xml",
            "appcastPath": "dist/releases/appcast.xml"
          },
          "manualChecks": {
            "releaseMachineLaunch": true,
            "checksumVerification": true,
            "cleanDmgInstall": true,
            "applicationsFolderInstall": true,
            "gatekeeperAccepted": true,
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "sparkleAppcastMetadata": true,
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
        XCTAssertTrue(result.output.contains("release evidence missing reviewer"))
        XCTAssertTrue(result.output.contains("release evidence missing review timestamp"))
    }

    func testReleasePreflightRejectsEvidenceWithoutReviewNotes() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-review-notes.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-missing-review-notes.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-missing-review-notes.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        let gitCommit = try currentGitCommit()
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "\(artifactPath)",
            "artifactSha256": "42bd420cc2f99e68e60005fa7c28fc2f60e4e04ee160d9dd3b98e72fc2954f98",
            "signingIdentity": "Developer ID Application: SoloPM Test (TEAMID)",
            "notaryProfile": "SoloPMNotaryProfile",
            "sparkleFeedURL": "https://updates.solopm.app/releases/appcast.xml",
            "appcastPath": "dist/releases/appcast.xml"
          },
          "source": {
            "gitCommit": "\(gitCommit)"
          },
          "manualChecks": {
            "releaseMachineLaunch": true,
            "checksumVerification": true,
            "cleanDmgInstall": true,
            "applicationsFolderInstall": true,
            "gatekeeperAccepted": true,
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "sparkleAppcastMetadata": true,
            "environment": "macOS 15.5 clean user on arm64"
          },
          "review": {
            "checkedBy": "release-owner",
            "checkedAt": "2026-06-18T00:00:00Z"
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
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
        XCTAssertTrue(result.output.contains("release evidence missing review notes"))
    }

    func testReleasePreflightRejectsBoilerplateReviewNotes() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-boilerplate-review-notes.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-boilerplate-review-notes.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-boilerplate-review-notes.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        let gitCommit = try currentGitCommit()
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "\(artifactPath)",
            "artifactSha256": "42bd420cc2f99e68e60005fa7c28fc2f60e4e04ee160d9dd3b98e72fc2954f98",
            "signingIdentity": "Developer ID Application: SoloPM Test (TEAMID)",
            "notaryProfile": "SoloPMNotaryProfile",
            "sparkleFeedURL": "https://updates.solopm.app/releases/appcast.xml",
            "appcastPath": "dist/releases/appcast.xml"
          },
          "source": {
            "gitCommit": "\(gitCommit)"
          },
          "manualChecks": {
            "releaseMachineLaunch": true,
            "checksumVerification": true,
            "cleanDmgInstall": true,
            "applicationsFolderInstall": true,
            "gatekeeperAccepted": true,
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "sparkleAppcastMetadata": true,
            "environment": "macOS 15.5 clean user on arm64"
          },
          "review": {
            "checkedBy": "release-owner",
            "checkedAt": "2026-06-18T00:00:00Z",
            "notes": ["Manual checks completed."]
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
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
        XCTAssertTrue(result.output.contains("release evidence review notes must include concrete verification details"))
    }

    func testReleasePreflightRejectsEvidenceForDifferentSourceCommit() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-source-commit.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-source-commit.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-source-commit.dmg"
        let staleCommit = "1111111111111111111111111111111111111111"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(
            for: checksumURL,
            artifactPath: artifactPath,
            gitCommit: staleCommit
        )
        try """
        {
          "release": {
            "version": "0.1.0",
            "buildNumber": "1",
            "appBundlePath": "dist/SoloPM.app",
            "artifactPath": "\(artifactPath)",
            "artifactSha256": "42bd420cc2f99e68e60005fa7c28fc2f60e4e04ee160d9dd3b98e72fc2954f98",
            "signingIdentity": "Developer ID Application: SoloPM Test (TEAMID)",
            "notaryProfile": "SoloPMNotaryProfile",
            "sparkleFeedURL": "https://updates.solopm.app/releases/appcast.xml",
            "appcastPath": "dist/releases/appcast.xml"
          },
          "source": {
            "gitCommit": "\(staleCommit)"
          },
          "manualChecks": {
            "releaseMachineLaunch": true,
            "checksumVerification": true,
            "cleanDmgInstall": true,
            "applicationsFolderInstall": true,
            "gatekeeperAccepted": true,
            "cleanEnvironmentLaunch": true,
            "loginItemToggle": true,
            "sparkleAppcastMetadata": true,
            "environment": "macOS 15.5 clean user on arm64"
          },
          "review": {
            "checkedBy": "release-owner",
            "checkedAt": "2026-06-18T00:00:00Z",
            "notes": ["Verified launch, Gatekeeper, clean DMG install, Applications install, login item toggle, checksum, and Sparkle appcast on macOS 15.5 arm64 signed build."]
          }
        }
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
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
        XCTAssertTrue(result.output.contains("release evidence source commit does not match current git commit"))
        XCTAssertTrue(result.output.contains("release package evidence source commit does not match current git commit"))
    }

    func testReleaseChecklistRequiresEvidenceBeforeFinalReport() throws {
        let checklist = try readPackageFile("docs/release/checklist.md")

        XCTAssertTrue(checklist.contains("packaging/release-evidence.example.json"))
        XCTAssertTrue(checklist.contains("SOLOPM_PACKAGE_FORMAT=all ./script/package_release.sh"))
        XCTAssertTrue(checklist.contains("SOLOPM_RELEASE_ARTIFACT_SHA256_FILE"))
        XCTAssertTrue(checklist.contains("SoloPM-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"))
        XCTAssertTrue(checklist.contains("./script/create_release_evidence.sh"))
        XCTAssertTrue(checklist.contains("packaging/release-evidence.json"))
        XCTAssertTrue(checklist.contains("manual release evidence"))
        XCTAssertTrue(checklist.contains("reject blank, placeholder, sample, example, todo, or replace-style environment descriptions"))
        XCTAssertTrue(checklist.contains("blank reviewer names, blank review notes, and boilerplate notes"))
        XCTAssertTrue(checklist.contains("manual release flags require an explicit review note"))
        XCTAssertTrue(checklist.contains("source git commit is recorded in release evidence"))
        XCTAssertTrue(checklist.contains("SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/verify_appcast.sh dist/releases/appcast.xml"))
        XCTAssertFalse(checklist.contains("./script/verify_appcast.sh packaging/appcast.sample.xml"))
        XCTAssertTrue(checklist.contains("./script/verify_notarization_setup.sh"))
        XCTAssertTrue(checklist.contains("./script/verify_release_environment.sh"))
        XCTAssertTrue(checklist.contains("script/capture_ui_evidence.sh"))
        XCTAssertTrue(checklist.contains("docs/release/evidence/accessibility-voiceover.md"))
        XCTAssertTrue(checklist.contains("Project navigation -> Project board detail -> Open task -> Status controls -> Task inspector"))
        XCTAssertTrue(checklist.contains("./script/release_readiness_report.sh"))
    }

    func testReleaseReadinessReportAggregatesRuntimeMockScanTasksAndPreflight() throws {
        let script = try readPackageFile("script/release_readiness_report.sh")

        XCTAssertTrue(script.contains("Sources/SoloPMCore"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp"))
        XCTAssertTrue(script.contains("Sources/SoloPMCLI"))
        XCTAssertTrue(script.contains("(?i:fake|mock|canned|stub|skeleton|todo|fixme"))
        XCTAssertTrue(script.contains("not[[:space:]_-]*implemented"))
        XCTAssertTrue(script.contains("(?i:(^|[^[:alnum:]_])(demo|sample|placeholder)([^[:alnum:]_]|$))"))
        XCTAssertTrue(script.contains("Static[A-Za-z0-9_]*"))
        XCTAssertFalse(script.contains("Fake|Mock|InMemory|Static|Demo|sample|canned|stub"))
        XCTAssertTrue(script.contains("Phase0-Phase10"))
        XCTAssertTrue(script.contains("Phase10-*.md"))
        XCTAssertTrue(script.contains("find \"$ROOT_DIR/tasks\""))
        XCTAssertTrue(script.contains("--with-filename"))
        XCTAssertTrue(script.contains("tasks/README.md"))
        XCTAssertTrue(script.contains("verify_release_environment.sh"))
        XCTAssertTrue(script.contains("missing runtime source directory"))
        XCTAssertTrue(script.contains("runtime mock/fake scan failed"))
        XCTAssertTrue(script.contains("section \"UI screenshot evidence\""))
        XCTAssertTrue(script.contains("docs/release/evidence/ui-screenshots.md"))
        XCTAssertTrue(script.contains("project-board-light.png"))
        XCTAssertTrue(script.contains("sips -g pixelWidth -g pixelHeight"))
        XCTAssertTrue(script.contains("missing UI screenshot file"))
        XCTAssertTrue(script.contains("UI screenshot is unexpectedly small"))
        XCTAssertTrue(script.contains("section \"VoiceOver accessibility evidence\""))
        XCTAssertTrue(script.contains("docs/release/evidence/accessibility-voiceover.md"))
        XCTAssertTrue(script.contains("Status: passed"))
        XCTAssertTrue(script.contains("grep -Fx \"Status: passed\""))
        XCTAssertTrue(script.contains("Project navigation"))
        XCTAssertTrue(script.contains("Task inspector"))
        XCTAssertTrue(script.contains("missing VoiceOver accessibility evidence file"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence is not marked passed"))
        XCTAssertTrue(script.contains("BLOCKER"))
    }

    func testReleaseReadinessReportFailsWhenRuntimeSourceDirectoryIsMissing() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-missing-runtime-source", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let coreDirectory = fixtureRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("SoloPMCore", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coreDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try "final class RuntimeSource {}\n"
            .write(to: coreDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("missing runtime source directory: Sources/SoloPMApp"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsClosedWhenRuntimeScanCommandErrors() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-runtime-scan-error", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let fakeBinDirectory = fixtureRoot.appendingPathComponent("bin", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let fakeRgURL = fakeBinDirectory.appendingPathComponent("rg")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeBinDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        printf "rg exploded\\n" >&2
        exit 2
        """.write(to: fakeRgURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeRgURL.path)

        let path = "\(fakeBinDirectory.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        let result = try runTool(["bash", reportURL.path], environment: ["PATH": path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("rg exploded"))
        XCTAssertTrue(result.output.contains("runtime mock/fake scan failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenUIScreenshotEvidenceFilesAreMissing() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-missing-ui-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try """
        # UI Screenshot Evidence

        Generated with `script/capture_ui_evidence.sh`.

        - Generated at: `2026-06-19T00:00:00Z`

        ## Screenshots

        - Light: `docs/release/evidence/ui-screenshots/project-board-light.png`
        - Dark: `docs/release/evidence/ui-screenshots/project-board-dark.png`
        - System: `docs/release/evidence/ui-screenshots/project-board-system.png`
        """.write(to: evidenceDirectory.appendingPathComponent("ui-screenshots.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("== UI screenshot evidence =="))
        XCTAssertTrue(result.output.contains("missing UI screenshot file: docs/release/evidence/ui-screenshots/project-board-light.png"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenVoiceOverEvidenceIsMissing() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-missing-voiceover-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("== VoiceOver accessibility evidence =="))
        XCTAssertTrue(result.output.contains("missing VoiceOver accessibility evidence file: docs/release/evidence/accessibility-voiceover.md"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenVoiceOverEvidenceIsPendingTemplate() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-pending-voiceover-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: pending. This template mentions `Status: passed` only as an instruction.

        - Project navigation
        - Project board detail
        - Open task
        - Status controls
        - Task inspector
        - Save Changes
        - Delete Task confirmation
        - No keyboard trap
        - No unlabeled primary CRUD controls
        """.write(to: evidenceDirectory.appendingPathComponent("accessibility-voiceover.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence is not marked passed"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence still contains placeholder text"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, and release environment gates passed."))
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
        let demoProvider = "demo"
        let future = "Not_Implemented"
        let memoryDatabase = ":memory:"
        """.write(to: markerFile, atomically: true, encoding: .utf8)
        try """
        let settings = [AVSampleRateKey: 44_100]
        let openCodeModelID = "opencode-model"
        private struct ArchivedProjectPlaceholder {}
        static func buildProductionValue() {}
        """.write(to: benignFile, atomically: true, encoding: .utf8)

        let markerResult = try runTool(["rg", "-n", pattern, markerFile.path])
        XCTAssertEqual(markerResult.exitCode, 0, markerResult.output)
        XCTAssertTrue(markerResult.output.contains("LocalmockExecutor"))
        XCTAssertTrue(markerResult.output.contains("StaticPlanningProvider"))
        XCTAssertTrue(markerResult.output.contains("demoProvider"))
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
        notarizedPackageRequired: Bool = true,
        gitCommit: String? = nil
    ) throws -> URL {
        let manifestPath = checksumURL.path.replacingOccurrences(of: ".sha256", with: ".package-evidence.json")
        let manifestURL = URL(fileURLWithPath: manifestPath)
        let sourceCommit = try gitCommit ?? currentGitCommit()
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
            "  },",
            "  \"source\": {",
            "    \"gitCommit\": \"\(sourceCommit)\"",
            "  }",
            "}"
        ]
        try (jsonLines.joined(separator: "\n") + "\n")
            .write(to: manifestURL, atomically: true, encoding: .utf8)
        return manifestURL
    }

    private func currentGitCommit() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", packageRoot().path, "rev-parse", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        return output
    }

    private func writeArtifactChecksum(
        to checksumURL: URL,
        artifactPath: String,
        content: String = "artifact content",
        sha256: String = "42bd420cc2f99e68e60005fa7c28fc2f60e4e04ee160d9dd3b98e72fc2954f98"
    ) throws -> URL {
        let artifactURL = artifactPath.hasPrefix("/")
            ? URL(fileURLWithPath: artifactPath)
            : packageRoot().appendingPathComponent(artifactPath)
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: artifactURL, atomically: true, encoding: .utf8)
        try "\(sha256)  \(artifactPath)\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        return artifactURL
    }

    @discardableResult
    private func writeReleaseAppcastFixture(at appcastURL: URL, includeSignature: Bool = true) throws -> URL {
        let signatureAttribute = includeSignature
            ? " sparkle:edSignature=\"release-signature-smoke-value\""
            : ""
        let artifactURL = appcastURL.deletingLastPathComponent()
            .appendingPathComponent("SoloPM-0.1.0+1.zip")
        let checksumURL = appcastURL.deletingLastPathComponent()
            .appendingPathComponent("SoloPM-0.1.0+1.zip.sha256")
        let packageEvidenceURL = appcastURL.deletingLastPathComponent()
            .appendingPathComponent("SoloPM-0.1.0+1.zip.package-evidence.json")
        let artifactSha = "554f3f497395d59fc12389d51b5fb7208248425e0dbad975db3f08132f58dbed"
        try FileManager.default.createDirectory(
            at: appcastURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "zip content".write(to: artifactURL, atomically: true, encoding: .utf8)
        try "\(artifactSha)  \(artifactURL.path)\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        try """
        {
          "package": {
            "artifactPath": "\(artifactURL.path)",
            "format": "zip",
            "createdAt": "2026-06-18T00:00:00Z",
            "signedPackageRequired": true,
            "notarizedPackageRequired": true
          },
          "source": {
            "gitCommit": "test-fixture"
          }
        }
        """.write(to: packageEvidenceURL, atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>SoloPM Releases</title>
            <item>
              <title>SoloPM 0.1.0</title>
              <sparkle:version>1</sparkle:version>
              <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
              <enclosure url="https://updates.solopm.app/releases/SoloPM-0.1.0+1.zip" length="12345" type="application/octet-stream"\(signatureAttribute)/>
            </item>
          </channel>
        </rss>
        """.write(to: appcastURL, atomically: true, encoding: .utf8)
        return appcastURL
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

    private func runTool(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
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

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
