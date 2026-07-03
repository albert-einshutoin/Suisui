import Foundation
import CoreGraphics
import ImageIO
import XCTest

final class ReleasePipelineTests: XCTestCase {
    func testBuildAndRunSerializesDistBundleRebuilds() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("BUILD_AND_RUN_LOCK_DIR=\"$BUILD_AND_RUN_TMP_ROOT/build_and_run.lock\""))
        XCTAssertTrue(script.contains("while ! mkdir \"$BUILD_AND_RUN_LOCK_DIR\""))
        XCTAssertTrue(script.contains("trap cleanup_build_and_run EXIT INT TERM"))
        XCTAssertTrue(script.contains("BLOCKER: timed out waiting for build/run lock"))
        XCTAssertLessThan(
            try XCTUnwrap(script.range(of: "acquire_build_and_run_lock")).lowerBound,
            try XCTUnwrap(script.range(of: "rm -rf \"$APP_BUNDLE\"")).lowerBound
        )
    }

    func testBuildAndRunUsesDedicatedTemporaryRootAndCleansItUp() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("BUILD_AND_RUN_TMP_ROOT=\"${SOLOPM_TMP_ROOT:-$ROOT_DIR/.tmp}\""))
        XCTAssertTrue(script.contains("BUILD_AND_RUN_TMPDIR_CREATED=0"))
        XCTAssertTrue(script.contains("mktemp -d \"$BUILD_AND_RUN_TMP_ROOT/solopm-build-and-run-tmp.XXXXXX\""))
        XCTAssertTrue(script.contains("export TMPDIR=\"$BUILD_AND_RUN_TMPDIR/\""))
        XCTAssertTrue(script.contains("cleanup_build_and_run_tmpdir()"))
        XCTAssertTrue(script.contains("rm -rf \"$BUILD_AND_RUN_TMPDIR\""))
        XCTAssertTrue(script.contains("cleanup_build_and_run()"))
        XCTAssertTrue(script.contains("cleanup_build_and_run_tmpdir"))
        XCTAssertFalse(script.contains("export TMPDIR=\"${SOLOPM_TMPDIR:-$ROOT_DIR/.tmp/}\""))
    }

    func testCIScriptUsesDedicatedTemporaryRootAndCleansItUp() throws {
        let script = try readPackageFile("scripts/ci.sh")

        XCTAssertTrue(script.contains("CI_TMP_ROOT=\"${SOLOPM_CI_TMP_ROOT:-$ROOT_DIR/.tmp}\""))
        XCTAssertTrue(script.contains("CI_TMPDIR_CREATED=0"))
        XCTAssertTrue(script.contains("mktemp -d \"$CI_TMP_ROOT/solopm-ci-tmp.XXXXXX\""))
        XCTAssertTrue(script.contains("export TMPDIR=\"$CI_TMPDIR/\""))
        XCTAssertTrue(script.contains("cleanup_ci_tmpdir()"))
        XCTAssertTrue(script.contains("rm -rf \"$CI_TMPDIR\""))
        XCTAssertTrue(script.contains("trap cleanup_ci EXIT INT TERM"))
        XCTAssertLessThan(
            try XCTUnwrap(script.range(of: "export TMPDIR=\"$CI_TMPDIR/\"")).lowerBound,
            try XCTUnwrap(script.range(of: "swift test")).lowerBound
        )
    }

    func testCIScriptSeparatesLightweightPRGateFromRuntimeAndVisualGates() throws {
        let script = try readPackageFile("scripts/ci.sh")
        let automatedPreflight = try readPackageFile("script/check_automated_release_preflight.sh")
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        XCTAssertTrue(script.contains("CI_RUNTIME_GATES=\"${SOLOPM_CI_RUNTIME_GATES:-0}\""))
        XCTAssertTrue(script.contains("CI_VISUAL_GATES=\"${SOLOPM_CI_VISUAL_GATES:-0}\""))
        XCTAssertTrue(script.contains("CI_RELEASE_GATES=\"${SOLOPM_CI_RELEASE_GATES:-0}\""))
        XCTAssertTrue(script.contains("run_pr_gate()"))
        XCTAssertTrue(script.contains("swift test --filter AppExperienceSourceTests"))
        XCTAssertTrue(script.contains("swift test --filter QualitySourceContractTests"))
        XCTAssertTrue(script.contains("script/check_pseudo_voiceover_paths.sh --swift-test"))
        XCTAssertTrue(script.contains("swift test --filter ProjectBoardStoreTests"))
        XCTAssertTrue(script.contains("run_runtime_gates()"))
        XCTAssertTrue(script.contains("script/check_runtime_accessible_crud_smoke.sh"))
        XCTAssertTrue(script.contains("script/check_layout_stability_smoke.sh"))
        XCTAssertTrue(script.contains("script/check_accessibility_preflight.sh --runtime"))
        XCTAssertTrue(script.contains("run_visual_gates()"))
        XCTAssertTrue(script.contains("script/check_visual_regression_smoke.sh"))
        XCTAssertTrue(script.contains("if [[ \"$CI_RUNTIME_GATES\" == \"1\" ]]; then\n  run_runtime_gates"))
        XCTAssertTrue(script.contains("if [[ \"$CI_VISUAL_GATES\" == \"1\" ]]; then\n  run_visual_gates"))
        XCTAssertLessThan(
            try XCTUnwrap(script.range(of: "run_pr_gate")).lowerBound,
            try XCTUnwrap(script.range(of: "run_runtime_gates")).lowerBound
        )

        XCTAssertTrue(automatedPreflight.contains("SOLOPM_CI_RELEASE_GATES=1 ./scripts/ci.sh"))
        XCTAssertTrue(phase.contains("- [x] `scripts/ci.sh` が軽量PR gateと重いruntime gateを混同しないことをsource testで固定する。"))
        XCTAssertTrue(phase.contains("- [x] `scripts/ci.sh` はunit/sourceを必須、runtime/visualは明示フラグで実行する。"))
    }

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

    func testReleaseMachineLocalDoctorRunsNonSecretDiagnostics() throws {
        let script = try readPackageFile("script/check_release_machine_local_doctor.sh")

        XCTAssertTrue(script.contains("security find-identity -p codesigning -v"))
        XCTAssertTrue(script.contains("packaging/signing.env"))
        XCTAssertTrue(script.contains("packaging/notarization.env"))
        XCTAssertTrue(script.contains("packaging/sparkle.env"))
        XCTAssertTrue(script.contains("./script/verify_signing_setup.sh"))
        XCTAssertTrue(script.contains("SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh"))
        XCTAssertTrue(script.contains("SOLOPM_BUILD_CONFIGURATION=release SOLOPM_SPARKLE_CONFIG_QUIET=1 ./script/validate_sparkle_release_config.sh"))
        XCTAssertTrue(script.contains("./script/verify_release_environment.sh"))
        XCTAssertTrue(script.contains("redact_sensitive_line"))
        XCTAssertTrue(script.contains("Developer ID certificate material, notary credentials, Sparkle private keys, tokens, or passwords"))
        XCTAssertFalse(script.contains("APPLE_ID_PASSWORD"))
        XCTAssertFalse(script.contains("AC_PASSWORD"))
    }

    func testReleaseMachineLocalDoctorRedactsVerifierSecretsAndAggregatesBlockers() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-machine-local-doctor", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let binDirectory = fixtureRoot.appendingPathComponent("bin", isDirectory: true)
        let doctorURL = scriptDirectory.appendingPathComponent("check_release_machine_local_doctor.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try readPackageFile("script/check_release_machine_local_doctor.sh")
            .write(to: doctorURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        printf "     0 valid identities found\\n"
        """.write(to: binDirectory.appendingPathComponent("security"), atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        printf "signing verifier token failed: super-secret-token\\n"
        exit 2
        """.write(to: scriptDirectory.appendingPathComponent("verify_signing_setup.sh"), atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        printf "notary credential failed: hidden-token\\n"
        exit 2
        """.write(to: scriptDirectory.appendingPathComponent("verify_notarization_setup.sh"), atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        printf "Sparkle private key failed: hidden-private-key\\n"
        exit 2
        """.write(to: scriptDirectory.appendingPathComponent("validate_sparkle_release_config.sh"), atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        printf "BLOCKER: missing local release evidence: run ./script/create_release_evidence.sh after packaging and manual checks\\n"
        exit 2
        """.write(to: scriptDirectory.appendingPathComponent("verify_release_environment.sh"), atomically: true, encoding: .utf8)

        for executable in [
            doctorURL,
            binDirectory.appendingPathComponent("security"),
            scriptDirectory.appendingPathComponent("verify_signing_setup.sh"),
            scriptDirectory.appendingPathComponent("verify_notarization_setup.sh"),
            scriptDirectory.appendingPathComponent("validate_sparkle_release_config.sh"),
            scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        ] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }

        let result = try runTool(
            ["bash", doctorURL.path],
            environment: ["PATH": "\(binDirectory.path):/usr/bin:/bin:/usr/sbin:/sbin"]
        )

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.output.contains("BLOCKER: no Developer ID Application identities found"))
        XCTAssertTrue(result.output.contains("BLOCKER: missing local release config: packaging/signing.env"))
        XCTAssertTrue(result.output.contains("BLOCKER: missing local release config: packaging/notarization.env"))
        XCTAssertTrue(result.output.contains("BLOCKER: missing local release config: packaging/sparkle.env"))
        XCTAssertTrue(result.output.contains("BLOCKER: release machine diagnostic failed: ./script/verify_signing_setup.sh"))
        XCTAssertTrue(result.output.contains("BLOCKER: release machine diagnostic failed: SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh"))
        XCTAssertTrue(result.output.contains("BLOCKER: release machine diagnostic failed: SOLOPM_BUILD_CONFIGURATION=release SOLOPM_SPARKLE_CONFIG_QUIET=1 ./script/validate_sparkle_release_config.sh"))
        XCTAssertTrue(result.output.contains("BLOCKER: release machine diagnostic failed: ./script/verify_release_environment.sh"))
        XCTAssertTrue(result.output.contains("[redacted sensitive diagnostic line]"))
        XCTAssertFalse(result.output.contains("super-secret-token"))
        XCTAssertFalse(result.output.contains("hidden-token"))
        XCTAssertFalse(result.output.contains("hidden-private-key"))
        XCTAssertTrue(result.output.contains("Do not paste Developer ID certificate material, notary credentials, Sparkle private keys, tokens, or passwords"))
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
        XCTAssertTrue(script.contains("generator.name"))
        XCTAssertTrue(script.contains("release evidence missing generator provenance"))
        XCTAssertTrue(script.contains("release evidence generator provenance is not canonical"))
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
        XCTAssertTrue(example.contains("\"generator\""))
        XCTAssertTrue(example.contains("\"name\": \"script/create_release_evidence.sh\""))
        XCTAssertFalse(example.contains("PASSWORD"))
        XCTAssertFalse(example.contains("TOKEN"))
        XCTAssertFalse(example.contains("SECRET"))
    }

    func testReleaseManualEvidenceDocsMapEveryFlagToConcreteProof() throws {
        let script = try readPackageFile("script/create_release_evidence.sh")
        let checklist = try readPackageFile("docs/release/checklist.md")
        let example = try readPackageFile("packaging/release-evidence.example.json")

        XCTAssertTrue(script.contains("Manual flag evidence requirements:"))
        XCTAssertTrue(script.contains("--release-machine-launch: signed/notarized app opens from dist/SoloPM.app on the release machine"))
        XCTAssertTrue(script.contains("--checksum-verification: shasum -a 256 matches the generated *.sha256 artifact"))
        XCTAssertTrue(script.contains("--clean-dmg-install: DMG downloads and opens in a clean user or VM"))
        XCTAssertTrue(script.contains("--applications-folder-install: app is dragged to /Applications and launches there"))
        XCTAssertTrue(script.contains("--gatekeeper-accepted: spctl/Gatekeeper accepts the stapled app"))
        XCTAssertTrue(script.contains("--clean-environment-launch: first launch succeeds in the clean user or VM"))
        XCTAssertTrue(script.contains("--login-item-toggle: Settings toggles launch-at-login on and off in the signed app"))
        XCTAssertTrue(script.contains("--sparkle-appcast-metadata: release appcast metadata points to this version/build"))
        XCTAssertTrue(script.contains("require_manual_note_proof_if_checked"))
        XCTAssertTrue(script.contains("manual release evidence note missing proof for %s"))
        XCTAssertTrue(script.contains("\"clean environment launch\""))

        XCTAssertTrue(checklist.contains("Manual flag evidence requirements"))
        XCTAssertTrue(checklist.contains("| `--login-item-toggle` | Settings toggles launch-at-login on and off in the signed app. |"))
        XCTAssertTrue(checklist.contains("The `--note` value must name the observed result for each true manual flag."))
        XCTAssertTrue(checklist.contains("The evidence scripts reject manual flags whose `--note` does not mention the matching observed proof."))

        XCTAssertTrue(example.contains("Manual flag evidence requirements are documented in docs/release/checklist.md."))
        XCTAssertTrue(example.contains("Do not copy this example as final release evidence."))
    }

    func testManualUnblockerRunbookMapsRemainingReleaseBlockersToGeneratedCommands() throws {
        let runbook = try readPackageFile("docs/release/manual-unblockers.md")
        let checklist = try readPackageFile("docs/release/checklist.md")
        let report = try readPackageFile("script/release_readiness_report.sh")
        let phase = try readPackageFile("tasks/Phase10-ReleaseReadinessRuntime.md")

        XCTAssertTrue(runbook.contains("Manual Release Unblockers"))
        XCTAssertTrue(runbook.contains("current_commit=\"$(git rev-parse --short HEAD)\""))
        XCTAssertTrue(runbook.contains("automated_evidence=\".tmp/automated-release-preflight-${current_commit}.md\""))
        XCTAssertTrue(runbook.contains("SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=\"$automated_evidence\" ./script/check_automated_release_preflight.sh"))
        XCTAssertTrue(runbook.contains("Use the latest action summary for the current release-candidate source commit and generated helper paths."))
        XCTAssertTrue(runbook.contains("Use `Release candidate product source commit`, not the action summary `Source commit`, when filling manual VoiceOver or competitor evidence."))
        XCTAssertFalse(runbook.contains("automated-release-preflight-5875b4e.md"))
        XCTAssertFalse(runbook.contains("Current release-candidate source commit: `17880b5`"))
        XCTAssertTrue(runbook.contains("Do not hand-edit passed evidence"))
        XCTAssertTrue(runbook.contains("Run `--validate-only` before writing tracked evidence"))
        XCTAssertTrue(runbook.contains("Do not ask an LLM, automation, or a generated action summary to create passed evidence for manual VoiceOver, competitor hands-on, signing, notarization, Sparkle, Gatekeeper, clean install, or Launch at Login checks without the real pass."))
        XCTAssertTrue(runbook.contains("Generated helpers can route the work, but only concrete observations from the real release-candidate app or signed release artifact can unblock these lanes."))

        for lane in ["VoiceOver", "Competitor hands-on", "Release machine"] {
            XCTAssertTrue(runbook.contains("## \(lane)"), "Missing lane: \(lane)")
        }

        for path in [
            ".tmp/voiceover-review/voiceover-worksheet.md",
            ".tmp/voiceover-review/create-evidence-command.sh",
            ".tmp/competitor-hands-on/hands-on-worksheet.md",
            ".tmp/competitor-hands-on/competitor-benchmark-pending-<release-candidate-source-commit>.md",
            ".tmp/competitor-hands-on/create-evidence-command.sh",
            ".tmp/release-machine/release-machine-worksheet.md",
            ".tmp/release-machine/create-release-evidence-command.sh"
        ] {
            XCTAssertTrue(runbook.contains(path), "Missing generated helper path: \(path)")
        }

        XCTAssertTrue(runbook.contains("script/create_voiceover_evidence.sh"))
        XCTAssertTrue(runbook.contains("script/create_competitor_hands_on_evidence.sh"))
        XCTAssertTrue(runbook.contains("script/create_release_evidence.sh"))
        XCTAssertTrue(runbook.contains("Generated by: script/create_voiceover_evidence.sh"))
        XCTAssertTrue(runbook.contains("Generated by: script/create_competitor_hands_on_evidence.sh"))
        XCTAssertTrue(runbook.contains("generator.name: script/create_release_evidence.sh"))
        XCTAssertTrue(runbook.contains("SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=\"$automated_evidence\" ./script/release_readiness_report.sh"))
        XCTAssertTrue(report.contains("check_manual_unblocker_runbook_freshness()"))
        XCTAssertTrue(report.contains("OK: manual unblocker runbook avoids hardcoded release-candidate paths"))
        XCTAssertTrue(report.contains("manual unblocker runbook hardcodes automated preflight evidence"))
        XCTAssertTrue(report.contains("manual unblocker runbook hardcodes release-candidate source commit"))
        XCTAssertTrue(report.contains("manual unblocker runbook missing automated preflight evidence bootstrap"))
        XCTAssertTrue(report.contains("manual unblocker runbook missing manual-only evidence boundary"))
        XCTAssertTrue(report.contains("SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=\"$automated_evidence\" ./script/check_automated_release_preflight.sh"))

        XCTAssertTrue(checklist.contains("manual-unblockers.md"))
        XCTAssertTrue(phase.contains("[x] release readiness は `docs/release/manual-unblockers.md` が hardcoded automated preflight evidence や release-candidate source commit を含む場合 blocker にする。"))
        XCTAssertTrue(phase.contains("[x] action summary と manual unblocker runbook は LLM / automation / generated summary が実測なしに manual passed evidence を作ってはいけないことを明示する。"))
        XCTAssertTrue(phase.contains("[x] release readiness は `docs/release/manual-unblockers.md` から manual-only evidence boundary が消えた場合 blocker にする。"))
    }

    func testManualEvidenceScriptsRequireCleanTrackedSourceTreeBeforeWritingPassedEvidence() throws {
        let voiceOverScript = try readPackageFile("script/create_voiceover_evidence.sh")
        let competitorScript = try readPackageFile("script/create_competitor_hands_on_evidence.sh")
        let releaseEvidenceScript = try readPackageFile("script/create_release_evidence.sh")
        let checklist = try readPackageFile("docs/release/checklist.md")
        let phase = try readPackageFile("tasks/Phase10-ReleaseReadinessRuntime.md")

        for script in [voiceOverScript, competitorScript, releaseEvidenceScript] {
            XCTAssertTrue(script.contains("require_clean_tracked_source_tree_for_passed_evidence"))
            XCTAssertGreaterThanOrEqual(script.components(separatedBy: "require_clean_tracked_source_tree_for_passed_evidence").count - 1, 2)
            XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" status --porcelain --untracked-files=no"))
            XCTAssertTrue(script.contains("requires a clean tracked source tree"))
            XCTAssertTrue(script.contains("Commit or revert tracked source changes"))
        }

        let voiceOverGuardRange = try XCTUnwrap(voiceOverScript.range(of: "require_clean_tracked_source_tree_for_passed_evidence"))
        let voiceOverWriteRange = try XCTUnwrap(voiceOverScript.range(of: "write_passed_evidence"))
        XCTAssertLessThan(
            voiceOverGuardRange.lowerBound,
            voiceOverWriteRange.lowerBound
        )
        let competitorGuardRange = try XCTUnwrap(competitorScript.range(of: "require_clean_tracked_source_tree_for_passed_evidence"))
        let competitorWriteRange = try XCTUnwrap(competitorScript.range(of: "write_passed_evidence"))
        XCTAssertLessThan(
            competitorGuardRange.lowerBound,
            competitorWriteRange.lowerBound
        )
        let releaseGuardRange = try XCTUnwrap(releaseEvidenceScript.range(of: "require_clean_tracked_source_tree_for_passed_evidence"))
        let releaseWriteRange = try XCTUnwrap(releaseEvidenceScript.range(of: "mv \"$tmp_file\" \"$OUTPUT_FILE\""))
        XCTAssertLessThan(
            releaseGuardRange.lowerBound,
            releaseWriteRange.lowerBound
        )

        XCTAssertTrue(checklist.contains("Direct manual evidence scripts also require a clean tracked source tree before writing passed evidence."))
        XCTAssertTrue(phase.contains("[x] Direct manual evidence scripts reject dirty tracked source trees before writing passed VoiceOver, competitor, or release-machine evidence."))
    }

    func testReleaseMachineEvidencePreparationWritesWorksheetAndCommandWithoutPassingEvidence() throws {
        let worksheetURL = packageRoot()
            .appendingPathComponent(".build/test-release-machine-worksheet.md")
        let commandURL = packageRoot()
            .appendingPathComponent(".build/test-release-machine-create-evidence-command.sh")
        try? FileManager.default.removeItem(at: worksheetURL)
        try? FileManager.default.removeItem(at: commandURL)
        defer {
            try? FileManager.default.removeItem(at: worksheetURL)
            try? FileManager.default.removeItem(at: commandURL)
        }
        let currentShortCommit = try currentShortGitCommit()

        let result = try runScript(
            "script/prepare_release_machine_evidence.sh",
            arguments: [
                "--worksheet-output", worksheetURL.path,
                "--command-output", commandURL.path
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Release machine worksheet written: \(worksheetURL.path)"))
        XCTAssertTrue(result.output.contains("Release evidence command written: \(commandURL.path)"))
        let worksheet = try String(contentsOf: worksheetURL, encoding: .utf8)
        XCTAssertTrue(worksheet.contains("# Release Machine Evidence Worksheet"))
        XCTAssertTrue(worksheet.contains("Status: pending"))
        XCTAssertTrue(worksheet.contains("This worksheet is not release evidence."))
        XCTAssertTrue(worksheet.contains("- Release candidate source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(worksheet.contains("- Evidence output: `packaging/release-evidence.json`"))
        XCTAssertTrue(worksheet.contains("## Prerequisite Checks"))
        XCTAssertTrue(worksheet.contains("- [ ] Developer ID signing identity is configured and verified."))
        XCTAssertTrue(worksheet.contains("- [ ] Notary profile is configured and verified online."))
        XCTAssertTrue(worksheet.contains("- [ ] Production Sparkle feed URL and public EdDSA key are configured."))
        XCTAssertTrue(worksheet.contains("## Manual Release Checks To Perform"))
        XCTAssertTrue(worksheet.contains("- [ ] Release-machine launch"))
        XCTAssertTrue(worksheet.contains("- [ ] Gatekeeper acceptance"))
        XCTAssertTrue(worksheet.contains("- [ ] Launch at Login toggle"))
        XCTAssertTrue(worksheet.contains("- [ ] Sparkle appcast metadata"))
        XCTAssertTrue(worksheet.contains("## Release Evidence Notes To Fill"))
        XCTAssertTrue(worksheet.contains("- Reviewer:"))
        XCTAssertTrue(worksheet.contains("- Manual environment:"))
        XCTAssertTrue(worksheet.contains("- Release-machine launch:"))
        XCTAssertTrue(worksheet.contains("- Checksum verification:"))
        XCTAssertTrue(worksheet.contains("- Gatekeeper acceptance:"))
        XCTAssertTrue(worksheet.contains("- Launch at Login toggle:"))
        XCTAssertTrue(worksheet.contains("## Evidence Command"))
        XCTAssertTrue(worksheet.contains("Run `.build/test-release-machine-create-evidence-command.sh` only after every checked item above is true."))
        XCTAssertTrue(worksheet.contains("The generated command validates the filled evidence, writes `packaging/release-evidence.json`, then reruns the online release environment preflight."))
        XCTAssertFalse(worksheet.contains("Status: passed"))

        let command = try String(contentsOf: commandURL, encoding: .utf8)
        XCTAssertTrue(command.contains("# Generated by script/prepare_release_machine_evidence.sh."))
        XCTAssertTrue(command.contains("# Fill \(worksheetURL.path) while reviewing, then replace every placeholder below."))
        XCTAssertTrue(command.contains("# This command must fail if placeholders are not replaced."))
        XCTAssertTrue(command.contains("REPO_ROOT="))
        XCTAssertTrue(command.contains("cd \"$REPO_ROOT\""))
        XCTAssertTrue(command.contains("EXPECTED_SOURCE_COMMIT=\(currentShortCommit)"))
        XCTAssertTrue(command.contains("CURRENT_SOURCE_COMMIT=\"$(git rev-parse --short HEAD 2>/dev/null || printf unknown)\""))
        XCTAssertTrue(command.contains("TRACKED_SOURCE_STATUS=\"$(git status --porcelain --untracked-files=no)\""))
        XCTAssertTrue(command.contains("release evidence command requires a clean tracked source tree"))
        XCTAssertTrue(command.contains("release evidence command was generated for source commit"))
        XCTAssertTrue(command.contains("Rerun ./script/prepare_release_machine_evidence.sh for this release candidate."))
        XCTAssertTrue(command.contains("RELEASE_MACHINE_WORKSHEET_FILE=\(worksheetURL.path)"))
        XCTAssertTrue(command.contains("verify_release_machine_worksheet_for_evidence()"))
        XCTAssertTrue(command.contains("Status: completed"))
        XCTAssertTrue(command.contains("Release candidate source commit: \\`$EXPECTED_SOURCE_COMMIT\\`"))
        XCTAssertTrue(command.contains("Status:[[:space:]]*pending"))
        XCTAssertTrue(command.contains("^## Closeout$"))
        XCTAssertTrue(command.contains("grep -F -- \"- [ ]\" \"$RELEASE_MACHINE_WORKSHEET_FILE\""))
        XCTAssertTrue(command.contains("release-machine worksheet is missing, stale, or incomplete"))
        XCTAssertTrue(command.contains("release_machine_worksheet_value_is_placeholder_or_boilerplate()"))
        XCTAssertTrue(command.contains("verified|checked|done|passed|ok|okay"))
        XCTAssertTrue(command.contains("\"manual checks completed\"|\"manual release pass completed\""))
        XCTAssertTrue(command.contains("fill %s with concrete release-machine observation."))
        XCTAssertTrue(command.contains("Release-machine launch"))
        XCTAssertTrue(command.contains("Manual environment"))
        let worksheetCheckRange = try XCTUnwrap(command.range(of: "verify_release_machine_worksheet_for_evidence"))
        let metadataSourceRange = try XCTUnwrap(command.range(of: "source packaging/app_metadata.env"))
        XCTAssertLessThan(worksheetCheckRange.lowerBound, metadataSourceRange.lowerBound)
        XCTAssertTrue(command.contains("source packaging/app_metadata.env"))
        XCTAssertTrue(command.contains("for release_config_file in packaging/signing.env packaging/notarization.env packaging/sparkle.env; do"))
        XCTAssertTrue(command.contains("release evidence command requires $release_config_file on the release machine"))
        XCTAssertTrue(command.contains("source \"$release_config_file\""))
        let configGuardRange = try XCTUnwrap(command.range(of: "for release_config_file in packaging/signing.env packaging/notarization.env packaging/sparkle.env; do"))
        XCTAssertLessThan(metadataSourceRange.lowerBound, configGuardRange.lowerBound)
        XCTAssertTrue(command.contains("SOLOPM_RELEASE_ARTIFACT_SHA256_FILE=\"dist/releases/$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256\""))
        XCTAssertFalse(command.contains("SOLOPM_RELEASE_ARTIFACT_SHA256_FILE=\"dist/releases/SoloPM-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256\""))
        XCTAssertTrue(command.contains("Verify release-machine signing, notarization, and Sparkle setup before validating manual evidence."))
        XCTAssertTrue(command.contains("./script/verify_signing_setup.sh"))
        XCTAssertTrue(command.contains("SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh"))
        XCTAssertTrue(command.contains("SOLOPM_BUILD_CONFIGURATION=release SOLOPM_SPARKLE_CONFIG_QUIET=1 ./script/validate_sparkle_release_config.sh"))
        XCTAssertTrue(command.contains("Validate the filled release-machine evidence command before writing tracked evidence."))
        XCTAssertTrue(command.contains("./script/create_release_evidence.sh --validate-only \\"))
        XCTAssertTrue(command.contains("./script/create_release_evidence.sh --force \\"))
        XCTAssertTrue(command.contains("Run final release-machine preflight after evidence is written."))
        XCTAssertTrue(command.contains("SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh"))
        XCTAssertTrue(command.contains("--release-machine-launch \\"))
        XCTAssertTrue(command.contains("--checksum-verification \\"))
        XCTAssertTrue(command.contains("--clean-dmg-install \\"))
        XCTAssertTrue(command.contains("--applications-folder-install \\"))
        XCTAssertTrue(command.contains("--gatekeeper-accepted \\"))
        XCTAssertTrue(command.contains("--clean-environment-launch \\"))
        XCTAssertTrue(command.contains("--login-item-toggle \\"))
        XCTAssertTrue(command.contains("--sparkle-appcast-metadata \\"))
        XCTAssertTrue(command.contains("--manual-environment \"<macOS version, hardware, clean user or VM/install context>\" \\"))
        XCTAssertTrue(command.contains("--checked-by \"<reviewer name>\" \\"))
        XCTAssertTrue(command.contains("Launch at Login toggle on/off"))
        XCTAssertTrue(command.contains("Sparkle appcast metadata"))
        let setupRange = try XCTUnwrap(command.range(of: "Verify release-machine signing, notarization, and Sparkle setup before validating manual evidence."))
        let validateRange = try XCTUnwrap(command.range(of: "./script/create_release_evidence.sh --validate-only \\"))
        let writeRange = try XCTUnwrap(command.range(of: "./script/create_release_evidence.sh --force \\"))
        let preflightRange = try XCTUnwrap(command.range(of: "SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh"))
        XCTAssertLessThan(configGuardRange.lowerBound, setupRange.lowerBound)
        XCTAssertLessThan(setupRange.lowerBound, validateRange.lowerBound)
        XCTAssertLessThan(validateRange.lowerBound, writeRange.lowerBound)
        XCTAssertLessThan(writeRange.lowerBound, preflightRange.lowerBound)

        let checklist = try readPackageFile("docs/release/checklist.md")
        XCTAssertTrue(checklist.contains("The generated release evidence command requires a clean tracked source tree, pins the release evidence source commit it was created for, and exits before writing evidence if the worktree is dirty or has moved to another commit."))
        XCTAssertTrue(checklist.contains("The generated release-machine command also verifies `.tmp/release-machine/release-machine-worksheet.md` is marked completed, pinned to the same source commit, free of unchecked/pending/template markers, and filled before release evidence validation or writing can run."))
        XCTAssertTrue(checklist.contains("The generated release-machine command requires `packaging/signing.env`, `packaging/notarization.env`, and `packaging/sparkle.env` to exist on the release machine and sources them before validating or writing release evidence."))
        XCTAssertTrue(checklist.contains("The generated release-machine command runs signing, online notarization profile, and release Sparkle setup verifiers before `create_release_evidence.sh --validate-only`."))
        XCTAssertTrue(checklist.contains("Run the generated release-machine `--validate-only` command first; it performs the same release evidence validation without writing `packaging/release-evidence.json`."))
        XCTAssertTrue(checklist.contains("The generated release-machine command reruns `SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh` after writing release evidence, so the operator sees the final release-machine gate result before returning to `release_readiness_report.sh`."))

        let phase = try readPackageFile("tasks/Phase10-ReleaseReadinessRuntime.md")
        XCTAssertTrue(phase.contains("[x] `script/prepare_release_machine_evidence.sh` pins `.tmp/release-machine/create-release-evidence-command.sh` to a clean tracked source tree and the source commit it was generated for"))
        XCTAssertTrue(phase.contains("[x] `.tmp/release-machine/create-release-evidence-command.sh` verifies `.tmp/release-machine/release-machine-worksheet.md` is current, marked completed, filled, and free of pending/unchecked markers before release evidence validation or writing."))
        XCTAssertTrue(phase.contains("[x] `.tmp/release-machine/create-release-evidence-command.sh` requires `packaging/signing.env`, `packaging/notarization.env`, and `packaging/sparkle.env` before running release evidence validation."))
        XCTAssertTrue(phase.contains("[x] `.tmp/release-machine/create-release-evidence-command.sh` runs signing, online notarization, and release Sparkle setup verifiers before `create_release_evidence.sh --validate-only`."))
        XCTAssertTrue(phase.contains("[x] `script/create_release_evidence.sh --validate-only` validates the filled release-machine command without writing `packaging/release-evidence.json`."))
        XCTAssertTrue(phase.contains("[x] `.tmp/release-machine/create-release-evidence-command.sh` runs `SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh` after writing release evidence so release-machine operators see the final gate before rerunning the readiness report."))
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
                "--note", completeManualReleaseEvidenceNote
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
        XCTAssertTrue(evidence.contains("\"generator\""))
        XCTAssertTrue(evidence.contains("\"name\": \"script/create_release_evidence.sh\""))
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
        XCTAssertTrue(evidence.contains(completeManualReleaseEvidenceNote))
        XCTAssertFalse(evidence.contains("PASSWORD"))
        XCTAssertFalse(evidence.contains("TOKEN"))
        XCTAssertFalse(evidence.contains("SECRET"))
    }

    func testReleaseEvidenceValidateOnlyRunsFullValidationWithoutWritingEvidence() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-validate-only.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-validate-only.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-validate-only.dmg"
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURL = try writeArtifactChecksum(to: checksumURL, artifactPath: artifactPath)
        let packageEvidenceURL = try writePackageEvidence(for: checksumURL, artifactPath: artifactPath)
        let appcastURL = try writeReleaseAppcastFixture(
            at: packageRoot().appendingPathComponent(".build/test-release-appcast-validate-only.xml")
        )
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
            try? FileManager.default.removeItem(at: checksumURL)
            try? FileManager.default.removeItem(at: artifactURL)
            try? FileManager.default.removeItem(at: packageEvidenceURL)
            try? FileManager.default.removeItem(at: appcastURL)
        }

        try "existing release evidence must not be overwritten\n"
            .write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--validate-only",
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
                "--note", completeManualReleaseEvidenceNote
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
        XCTAssertTrue(result.output.contains("OK: release evidence command is valid for current source commit: \(try currentGitCommit())"))
        XCTAssertEqual(
            try String(contentsOf: evidenceURL, encoding: .utf8),
            "existing release evidence must not be overwritten\n"
        )
    }

    func testReleaseEvidenceValidateOnlyRejectsPlaceholdersWithoutWritingEvidence() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-validate-only-placeholder.json")
        try? FileManager.default.removeItem(at: evidenceURL)
        defer {
            try? FileManager.default.removeItem(at: evidenceURL)
        }

        let result = try runScript(
            "script/create_release_evidence.sh",
            arguments: [
                "--validate-only",
                "--release-machine-launch",
                "--manual-environment", "<macOS version, hardware, clean user or VM/install context>",
                "--checked-by", "<reviewer name>",
                "--note", "<concrete note covering release-machine launch, checksum SHA-256, clean DMG install, /Applications launch, Gatekeeper/spctl acceptance, clean environment first launch, Launch at Login toggle on/off, and Sparkle appcast metadata>"
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence requires --checked-by to name the actual reviewer"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
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

    func testReleaseEvidenceScriptRejectsWeakManualEnvironment() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-weak-manual-environment.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-weak-manual-environment.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-weak-manual-environment.dmg"
        let appcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-weak-manual-environment.xml")
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
                "--manual-environment", "macOS 15.5",
                "--checked-by", "release-owner",
                "--note", completeManualReleaseEvidenceNote
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

    func testReleaseEvidenceScriptRejectsManualFlagWithoutMatchingReviewNoteProof() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-manual-proof-note.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-missing-manual-proof-note.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-missing-manual-proof-note.dmg"
        let appcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-missing-manual-proof-note.xml")
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
                "--checked-by", "release-owner",
                "--note", "Verified release-machine launch from dist/SoloPM.app, checksum SHA-256, clean DMG install, Applications install, Gatekeeper acceptance, login item toggle, and Sparkle appcast metadata on macOS 15.5 arm64 signed build."
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
        XCTAssertTrue(result.output.contains("manual release evidence note missing proof for clean environment launch"))
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

    func testReleaseEvidenceScriptRejectsPlaceholderReviewer() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-placeholder-reviewer.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-placeholder-reviewer.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-placeholder-reviewer.dmg"
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
                "--checked-by", "Release reviewer"
            ],
            environment: [
                "SOLOPM_RELEASE_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ARTIFACT_SHA256_FILE": checksumURL.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release evidence requires --checked-by to name the actual reviewer"))
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

    func testReleasePreflightRejectsReleaseEvidenceWithoutGeneratorProvenance() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-generator.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-missing-generator.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-missing-generator.dmg"
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
            "notes": ["\(completeManualReleaseEvidenceNote)"]
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
        XCTAssertTrue(result.output.contains("release evidence missing generator provenance: generator.name"))
    }

    func testReleasePreflightRejectsReleaseEvidenceWithNonCanonicalGeneratorProvenance() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-wrong-generator.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-wrong-generator.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-wrong-generator.dmg"
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
          "generator": {
            "name": "manual-json-editor"
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
            "notes": ["\(completeManualReleaseEvidenceNote)"]
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
        XCTAssertTrue(result.output.contains("release evidence generator provenance is not canonical"))
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

    func testReleasePreflightRejectsWeakManualEnvironment() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-weak-environment.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-weak-environment.dmg.sha256")
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
          "source": {
            "gitCommit": "\(try currentGitCommit())"
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
            "environment": "macOS 15.5"
          },
          "review": {
            "checkedBy": "release-owner",
            "checkedAt": "2026-06-19T00:00:00Z",
            "notes": ["\(completeManualReleaseEvidenceNote)"]
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

    func testReleasePreflightRejectsPlaceholderReviewer() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-placeholder-reviewer.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-placeholder-reviewer.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-placeholder-reviewer.dmg"
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
            "checkedBy": "Release reviewer",
            "checkedAt": "2026-06-18T00:00:00Z",
            "notes": [
              "Verified release-machine launch from dist/SoloPM.app, checksum SHA-256, clean DMG install, Applications install, Gatekeeper acceptance, clean environment launch, login item toggle, and Sparkle appcast metadata on macOS 15.5 arm64 signed build."
            ]
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
        XCTAssertTrue(result.output.contains("release evidence reviewer is not concrete: review.checkedBy"))
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

    func testReleasePreflightRejectsManualFlagWithoutMatchingReviewNoteProof() throws {
        let evidenceURL = packageRoot()
            .appendingPathComponent(".build/test-release-evidence-missing-manual-proof-note-preflight.json")
        let checksumURL = packageRoot()
            .appendingPathComponent(".build/test-release-artifact-missing-manual-proof-note-preflight.dmg.sha256")
        let artifactPath = ".build/test-release-artifact-missing-manual-proof-note-preflight.dmg"
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
            "notes": ["Verified release-machine launch from dist/SoloPM.app, checksum SHA-256, clean DMG install, Applications install, Gatekeeper acceptance, login item toggle, and Sparkle appcast metadata on macOS 15.5 arm64 signed build."]
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
        XCTAssertTrue(result.output.contains("release evidence review notes missing proof for clean environment launch"))
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
            "notes": ["\(completeManualReleaseEvidenceNote)"]
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
        XCTAssertTrue(checklist.contains("SOLOPM_BUILD_CONFIGURATION=release ./script/build_and_run.sh --verify"))
        XCTAssertTrue(checklist.contains("visible Project Board window"))
        XCTAssertTrue(checklist.contains("SOLOPM_RELEASE_ARTIFACT_SHA256_FILE"))
        XCTAssertTrue(checklist.contains("$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"))
        XCTAssertFalse(checklist.contains("SoloPM-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"))
        XCTAssertTrue(checklist.contains("./script/create_release_evidence.sh"))
        XCTAssertTrue(checklist.contains("packaging/release-evidence.json"))
        XCTAssertTrue(checklist.contains("manual release evidence"))
        XCTAssertTrue(checklist.contains("reject blank, placeholder, sample, example, todo, replace-style, or weak environment descriptions"))
        XCTAssertTrue(checklist.contains("Manual environment must include the macOS version, clean user or VM/install context, and hardware or CPU architecture."))
        XCTAssertTrue(checklist.contains("blank reviewer names, placeholder names such as \"Reviewer Name\""))
        XCTAssertTrue(checklist.contains("placeholder role names such as \"Release reviewer\" or \"Product reviewer\""))
        XCTAssertTrue(checklist.contains("manual release flags require an explicit review note"))
        XCTAssertTrue(checklist.contains("./script/prepare_release_manual_helpers.sh"))
        XCTAssertTrue(checklist.contains("It regenerates the VoiceOver pending preview/launch env/worksheet/command, competitor hands-on pending evidence, competitor benchmark pending worksheet, and competitor hands-on worksheet/command for the release-candidate product source commit; it also regenerates the release-machine worksheet/command for the current release evidence source commit without writing passed evidence."))
        XCTAssertTrue(checklist.contains("The manual helper wrapper itself requires a clean tracked source tree before regenerating pending previews or command files"))
        XCTAssertTrue(checklist.contains("source git commit is recorded in release evidence"))
        XCTAssertTrue(checklist.contains("SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/verify_appcast.sh dist/releases/appcast.xml"))
        XCTAssertFalse(checklist.contains("./script/verify_appcast.sh packaging/appcast.sample.xml"))
        XCTAssertTrue(checklist.contains("./script/verify_notarization_setup.sh"))
        XCTAssertTrue(checklist.contains("./script/verify_release_environment.sh"))
        XCTAssertTrue(checklist.contains("./script/verify_mcp_compliance.sh"))
        XCTAssertTrue(checklist.contains("docs/release/evidence/mcp-inspector.md"))
        XCTAssertTrue(checklist.contains("Stable baseline: `2025-11-25`"))
        XCTAssertTrue(checklist.contains("Official latest source: https://modelcontextprotocol.io/specification"))
        XCTAssertTrue(checklist.contains("Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases"))
        XCTAssertTrue(checklist.contains("Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release."))
        XCTAssertTrue(checklist.contains("Official latest checked: 2026-06-24"))
        XCTAssertTrue(checklist.contains("Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning"))
        XCTAssertTrue(checklist.contains("Official versioning assertion: current protocol version is `2025-11-25`"))
        XCTAssertTrue(checklist.contains("Official stable source: https://modelcontextprotocol.io/specification/2025-11-25"))
        XCTAssertTrue(checklist.contains("Draft watchlist: `2026-07-28`"))
        XCTAssertTrue(checklist.contains("Draft changelog source: https://modelcontextprotocol.io/specification/draft/changelog"))
        XCTAssertTrue(checklist.contains("Draft changelog assertion: changes are listed since `2025-11-25`; it is not the current release baseline."))
        XCTAssertTrue(checklist.contains("script/capture_ui_evidence.sh"))
        XCTAssertTrue(checklist.contains("docs/release/evidence/accessibility-voiceover.md"))
        XCTAssertTrue(checklist.contains("./script/check_accessibility_preflight.sh --source-only"))
        XCTAssertTrue(checklist.contains("./script/check_accessibility_preflight.sh --runtime"))
        XCTAssertTrue(checklist.contains("./script/prepare_voiceover_review_candidate.sh --no-launch"))
        XCTAssertTrue(checklist.contains("VoiceOver Review Project"))
        XCTAssertTrue(checklist.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION"))
        XCTAssertTrue(checklist.contains(".tmp/voiceover-review/create-evidence-command.sh"))
        XCTAssertTrue(checklist.contains("Fill the worksheet with concrete observations from the manual pass before running the generated command."))
        XCTAssertTrue(checklist.contains("The generated VoiceOver evidence command reads reviewer, environment, and focus observations from the completed worksheet, so manual reviewers do not retype VoiceOver notes into shell placeholders."))
        XCTAssertTrue(checklist.contains("./script/create_voiceover_evidence.sh --pending"))
        XCTAssertTrue(checklist.contains("./script/create_voiceover_evidence.sh --passed"))
        XCTAssertTrue(checklist.contains("--capture-runtime-ax-smoke"))
        XCTAssertTrue(checklist.contains("--runtime-ax-smoke-note"))
        XCTAssertTrue(checklist.contains("--accessibility-environment \"VoiceOver/keyboard/device details used for the manual pass\""))
        XCTAssertTrue(checklist.contains("--project-navigation-note"))
        XCTAssertTrue(checklist.contains("--project-board-detail-note"))
        XCTAssertTrue(checklist.contains("--inline-task-composer-note"))
        XCTAssertTrue(checklist.contains("--task-content-execution-note"))
        XCTAssertTrue(checklist.contains("--no-unlabeled-crud-note"))
        XCTAssertTrue(checklist.contains("--confirm-manual-voiceover-pass"))
        XCTAssertTrue(checklist.contains("Project navigation -> Project board detail -> Open task -> Inline Task Composer -> Status controls -> Task inspector"))
        XCTAssertTrue(checklist.contains("docs/release/evidence/competitor-hands-on.md"))
        XCTAssertTrue(checklist.contains("docs/product/competitor-benchmark.md"))
        XCTAssertTrue(checklist.contains("Update the benchmark document from worksheet/desk research to hands-on findings before final release readiness."))
        XCTAssertTrue(checklist.contains("./script/create_competitor_hands_on_evidence.sh --pending"))
        XCTAssertTrue(checklist.contains(".tmp/competitor-hands-on/hands-on-worksheet.md"))
        XCTAssertTrue(checklist.contains(".tmp/competitor-hands-on/create-evidence-command.sh"))
        XCTAssertTrue(checklist.contains("Replace every placeholder in that generated command with concrete observations before running it"))
        XCTAssertTrue(checklist.contains("./script/create_competitor_hands_on_evidence.sh --passed"))
        XCTAssertTrue(checklist.contains("The passed generator writes both `docs/release/evidence/competitor-hands-on.md` and `docs/product/competitor-benchmark.md`"))
        XCTAssertTrue(checklist.contains("Each competitor note and Ship / Defer / Reject delta must identify what was actually observed or decided during the hands-on pass."))
        XCTAssertTrue(checklist.contains("--environment \"macOS/browser versions, competitor app/account tiers, and whether any paid trial was used\""))
        XCTAssertTrue(checklist.contains("--benchmark-output docs/product/competitor-benchmark.md"))
        XCTAssertTrue(checklist.contains("--confirm-manual-hands-on"))
        XCTAssertTrue(checklist.contains("Notion -> Todoist -> Linear -> Motion"))
        XCTAssertTrue(checklist.contains("./script/check_automated_release_preflight.sh"))
        XCTAssertTrue(checklist.contains("A standard run writes `.tmp/automated-release-preflight-$(git rev-parse --short HEAD).md`"))
        XCTAssertTrue(checklist.contains("Override `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE` only when a release operator needs to write or reuse a non-standard evidence path."))
        XCTAssertTrue(checklist.contains("The release readiness report auto-discovers `.tmp/automated-release-preflight-<commit>.md` for the current source commit when the environment variable is omitted."))
        XCTAssertTrue(checklist.contains("requires a clean tracked source tree"))
        XCTAssertTrue(checklist.contains("When the final report reuses this evidence, it verifies the generator identity, UTC timestamp, source commit, clean-tree marker, app name, Xcode workspace/scheme/configuration/destination, every automated proof gate, the runtime AX smoke OK line with `unlabeledButtons=0`, `genericButtons=0`, `crudSignals=8/8`, `focusPathSignals=6/6`, and `destructiveCancelSignals=1/1`, and the manual-evidence boundary text."))
        XCTAssertTrue(checklist.contains("Manual VoiceOver and competitor hands-on evidence record the current release-candidate product `Source commit`"))
        XCTAssertTrue(checklist.contains("rerun `./script/prepare_release_manual_helpers.sh` and then repeat the affected manual passes after product source changes instead of reusing evidence from an older release candidate"))
        XCTAssertTrue(checklist.contains("This automated sweep does not replace manual VoiceOver, competitor hands-on, signing, notarization, Sparkle, or Gatekeeper evidence."))
        XCTAssertTrue(checklist.contains("The final readiness report treats skipped automated proof gates as blockers by default."))
        XCTAssertTrue(checklist.contains("Do not claim release readiness from the default report output if CI, SQLite CRUD, runtime accessible CRUD, layout stability, Xcode build, visible launch, or runtime AX were skipped."))
        XCTAssertTrue(checklist.contains("then writes the captured `Runtime AX smoke: OK: runtime AX smoke visible...` line into the automated preflight evidence"))
        XCTAssertTrue(checklist.contains("./script/release_readiness_report.sh"))
        XCTAssertTrue(checklist.contains("./script/release_readiness_report.sh # auto-discovers .tmp/automated-release-preflight-<commit>.md"))
        XCTAssertTrue(checklist.contains("SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=\".tmp/automated-release-preflight-$(git rev-parse --short HEAD).md\" ./script/release_readiness_report.sh"))
        XCTAssertTrue(checklist.contains("SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh"))
        XCTAssertTrue(checklist.contains("SOLOPM_RELEASE_CI_PREFLIGHT=1 ./script/release_readiness_report.sh"))
        XCTAssertTrue(checklist.contains("SOLOPM_LOCAL_CRUD_SMOKE=1 ./script/release_readiness_report.sh"))
        XCTAssertTrue(checklist.contains("SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT=1 ./script/release_readiness_report.sh"))
        XCTAssertTrue(checklist.contains("SOLOPM_RELEASE_XCODE_PREFLIGHT=1 ./script/release_readiness_report.sh"))
        XCTAssertTrue(checklist.contains("SOLOPM_BUILD_CONFIGURATION=release SOLOPM_RELEASE_LAUNCH_PREFLIGHT=1 ./script/release_readiness_report.sh"))
    }

    func testAutomatedReleasePreflightScriptRunsRealLocalGatesWithoutFakingManualEvidence() throws {
        let script = try readPackageFile("script/check_automated_release_preflight.sh")
        let checklist = try readPackageFile("docs/release/checklist.md")
        let phase = try readPackageFile("tasks/Phase10-ReleaseReadinessRuntime.md")

        XCTAssertTrue(script.contains("./scripts/ci.sh"))
        XCTAssertTrue(script.contains("./script/check_local_crud_smoke.sh"))
        XCTAssertTrue(script.contains("./script/check_runtime_accessible_crud_smoke.sh"))
        XCTAssertTrue(script.contains("./script/check_layout_stability_smoke.sh"))
        XCTAssertTrue(script.contains("xcodebuild"))
        XCTAssertTrue(script.contains(".swiftpm/xcode/package.xcworkspace"))
        XCTAssertTrue(script.contains("-scheme \"$XCODE_SCHEME\""))
        XCTAssertTrue(script.contains("./script/build_and_run.sh --verify"))
        XCTAssertTrue(script.contains("./script/prepare_voiceover_review_candidate.sh --skip-build --no-launch"))
        XCTAssertTrue(script.contains("./script/check_accessibility_preflight.sh --runtime --launch-env .tmp/voiceover-review/launch.env --timeout 30"))
        let launchPreflightRange = try XCTUnwrap(script.range(of: "section \"Launch preflight\""))
        let voiceOverCandidateRange = try XCTUnwrap(script.range(of: "./script/prepare_voiceover_review_candidate.sh --skip-build --no-launch"))
        let runtimeAccessibilityRange = try XCTUnwrap(script.range(of: "section \"Runtime accessibility preflight\""))
        XCTAssertLessThan(launchPreflightRange.lowerBound, voiceOverCandidateRange.lowerBound)
        XCTAssertLessThan(voiceOverCandidateRange.lowerBound, runtimeAccessibilityRange.lowerBound)
        XCTAssertTrue(script.contains("./script/verify_mcp_compliance.sh"))
        XCTAssertTrue(script.contains("section \"Refresh manual release helpers\""))
        XCTAssertTrue(script.contains("./script/prepare_release_manual_helpers.sh"))
        let mcpPreflightRange = try XCTUnwrap(script.range(of: "section \"MCP compliance preflight\""))
        let manualHelperRefreshRange = try XCTUnwrap(script.range(of: "section \"Refresh manual release helpers\""))
        let evidenceWriteRange = try XCTUnwrap(script.range(of: "\nwrite_automated_preflight_evidence\n"))
        XCTAssertLessThan(mcpPreflightRange.lowerBound, manualHelperRefreshRange.lowerBound)
        XCTAssertLessThan(manualHelperRefreshRange.lowerBound, evidenceWriteRange.lowerBound)
        XCTAssertTrue(script.contains("manual VoiceOver"))
        XCTAssertTrue(script.contains("competitor hands-on"))
        XCTAssertTrue(script.contains("signing/notarization/Sparkle/Gatekeeper"))
        XCTAssertTrue(script.contains("automated release preflight passed"))
        XCTAssertTrue(script.contains("This does not mark the release ready."))
        XCTAssertTrue(script.contains("SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh"))
        XCTAssertTrue(script.contains("if [[ -n \"$AUTOMATED_PREFLIGHT_EVIDENCE_FILE\" ]]; then"))
        XCTAssertTrue(script.contains("SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=%q ./script/release_readiness_report.sh"))
        XCTAssertTrue(script.contains("default_automated_preflight_evidence_file()"))
        XCTAssertTrue(script.contains("AUTOMATED_PREFLIGHT_EVIDENCE_FILE=\"$(default_automated_preflight_evidence_file)\""))
        XCTAssertTrue(script.contains(".tmp/automated-release-preflight-${commit}.md"))
        XCTAssertTrue(script.contains("to reuse this evidence with the remaining release blockers"))
        XCTAssertTrue(script.contains("SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE"))
        XCTAssertTrue(script.contains("Automated Release Preflight Evidence"))
        XCTAssertTrue(script.contains("Status: passed"))
        XCTAssertTrue(script.contains("Generated by: script/check_automated_release_preflight.sh"))
        XCTAssertTrue(script.contains("require_clean_source_tree_for_evidence"))
        XCTAssertTrue(script.contains("automated preflight evidence requires a clean tracked source tree"))
        XCTAssertTrue(script.contains("Tracked source tree: clean"))
        XCTAssertTrue(script.contains("Release CI: passed"))
        XCTAssertTrue(script.contains("Local CRUD smoke: passed"))
        XCTAssertTrue(script.contains("Runtime accessible CRUD smoke: passed"))
        XCTAssertTrue(script.contains("Layout stability smoke: passed"))
        XCTAssertTrue(script.contains("Xcode build preflight: passed"))
        XCTAssertTrue(script.contains("Launch preflight: passed"))
        XCTAssertTrue(script.contains("Runtime accessibility preflight: passed"))
        XCTAssertTrue(script.contains("RUNTIME_AX_SMOKE_OUTPUT"))
        XCTAssertTrue(script.contains("Runtime AX smoke: $RUNTIME_AX_SMOKE_OUTPUT"))
        XCTAssertTrue(script.contains("VOICEOVER_CANDIDATE_SOURCE_COMMIT"))
        XCTAssertTrue(script.contains("VOICEOVER_CANDIDATE_PROJECT_ID"))
        XCTAssertTrue(script.contains("VOICEOVER_CANDIDATE_DATABASE"))
        XCTAssertTrue(script.contains("VOICEOVER_CANDIDATE_SELECTED_DESTINATION"))
        XCTAssertTrue(script.contains("VoiceOver candidate source commit: $VOICEOVER_CANDIDATE_SOURCE_COMMIT"))
        XCTAssertTrue(script.contains("VoiceOver candidate project ID: $VOICEOVER_CANDIDATE_PROJECT_ID"))
        XCTAssertTrue(script.contains("VoiceOver candidate database: $VOICEOVER_CANDIDATE_DATABASE"))
        XCTAssertTrue(script.contains("VoiceOver candidate selected destination: $VOICEOVER_CANDIDATE_SELECTED_DESTINATION"))
        XCTAssertTrue(script.contains("runtime accessibility preflight did not emit a runtime AX smoke OK line"))
        XCTAssertTrue(script.contains("MCP compliance preflight: passed"))
        XCTAssertTrue(script.contains("This does not mark the release ready."))
        XCTAssertTrue(script.contains("Automated release preflight evidence written to"))
        XCTAssertTrue(script.contains("terminate_app"))
        XCTAssertFalse(script.contains("create_voiceover_evidence.sh --passed"))
        XCTAssertFalse(script.contains("create_competitor_hands_on_evidence.sh --passed"))
        XCTAssertFalse(script.contains("confirm-manual-voiceover-pass"))
        XCTAssertFalse(script.contains("confirm-manual-hands-on"))
        XCTAssertTrue(checklist.contains("./script/check_automated_release_preflight.sh"))
        XCTAssertTrue(checklist.contains("After automated preflight passes, it refreshes VoiceOver and competitor helper files for the release-candidate product source commit and release-machine helper files for the current release evidence source commit without writing passed evidence."))
        XCTAssertTrue(checklist.contains("The automated preflight evidence also records the seeded VoiceOver candidate source commit, project ID, database path, and selected destination used for runtime AX smoke."))
        XCTAssertTrue(checklist.contains("The seeded runtime AX gate uses `--timeout 30` because macOS accessibility tree updates can lag behind the visible Project Board window after launch."))
        XCTAssertTrue(phase.contains("[x] `script/check_automated_release_preflight.sh` で CI、SQLite CRUD、runtime accessible CRUD、layout stability、Xcode build、visible-window launch、seeded VoiceOver review candidate 上の runtime AX、MCP compliance を一括検証できる。"))
        XCTAssertTrue(phase.contains("[x] 自動proof証跡は seeded runtime AX smoke の `OK: runtime AX smoke visible` 行を保存し、`unlabeledButtons=0`、`genericButtons=0`、`crudSignals=8/8`、`focusPathSignals=6/6`、`destructiveCancelSignals=1/1` が欠ける証跡を release readiness で拒否する。"))
        XCTAssertTrue(phase.contains("[x] 自動proof証跡は runtime AX smoke 対象の VoiceOver candidate source commit / project ID / database / selected destination を保存し、どのseeded candidateで検証したか追跡できる。"))
        XCTAssertTrue(phase.contains("[x] `check_automated_release_preflight.sh` は runtime AX smoke を `.tmp/voiceover-review/launch.env` から直接起動し、既存プロセスの選択状態に依存しない。"))
        XCTAssertTrue(phase.contains("[x] `check_automated_release_preflight.sh` は seeded runtime AX smoke を30秒timeoutで実行し、起動直後のAX tree更新遅延でrelease proofがflakyに落ちないようにする。"))
        XCTAssertTrue(phase.contains("[x] `check_automated_release_preflight.sh` は通過後に VoiceOver / competitor helper を release-candidate product source commit、release-machine helper を current release evidence source commit で再生成し、helper freshness を片寄らせない。"))
    }

    func testAutomatedReleasePreflightBoundsXcodeBuildHang() throws {
        let script = try readPackageFile("script/check_automated_release_preflight.sh")

        XCTAssertTrue(script.contains("XCODE_PREFLIGHT_TIMEOUT_SECONDS=\"${SOLOPM_XCODE_PREFLIGHT_TIMEOUT_SECONDS:-600}\""))
        XCTAssertTrue(script.contains("run_xcodebuild_with_timeout()"))
        XCTAssertTrue(script.contains("BLOCKER: Xcode build preflight timed out after ${XCODE_PREFLIGHT_TIMEOUT_SECONDS}s"))
        XCTAssertTrue(script.contains("printf 'NEXT: reproduce with xcodebuild -workspace %q -scheme %q -configuration %q -destination %q build\\n'"))
        XCTAssertTrue(script.contains("\"$ROOT_DIR/$XCODE_WORKSPACE_RELATIVE\" \"$XCODE_SCHEME\" \"$XCODE_CONFIGURATION\" \"$XCODE_DESTINATION\""))
        XCTAssertTrue(script.contains("NEXT: this is separate from the SwiftPM native build; do not reuse automated preflight evidence until the Xcode build gate passes."))
        XCTAssertTrue(script.contains("kill \"$xcode_pid\""))
        XCTAssertTrue(script.contains("run_xcodebuild_with_timeout"))
        XCTAssertLessThan(
            try XCTUnwrap(script.range(of: "run_xcodebuild_with_timeout()")).lowerBound,
            try XCTUnwrap(script.range(of: "section \"Xcode build preflight\"")).lowerBound
        )

        let checklist = try readPackageFile("docs/release/checklist.md")
        XCTAssertTrue(checklist.contains("If the Xcode watchdog times out, reproduce the exact `xcodebuild -workspace ... -scheme ... -destination ... build` command from the blocker output and keep automated preflight evidence rejected until that Xcode build gate passes."))
    }

    func testReleaseActionSummaryReportsManualHelperFreshnessForCurrentCommit() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-manual-helper-freshness", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let voiceOverDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("voiceover-review", isDirectory: true)
        let competitorDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("competitor-hands-on", isDirectory: true)
        let releaseMachineDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("release-machine", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let actionURL = fixtureRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("release-actions.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: voiceOverDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: competitorDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: releaseMachineDirectory, withIntermediateDirectories: true)
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
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let commit = try runTool(["git", "rev-parse", "--short", "HEAD"])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try "- Source commit: `\(commit)`\n"
            .write(
                to: voiceOverDirectory.appendingPathComponent("accessibility-voiceover-pending-\(commit).md"),
                atomically: true,
                encoding: .utf8
            )
        try "- Source commit: `oldcafe`\n"
            .write(
                to: voiceOverDirectory.appendingPathComponent("accessibility-voiceover-pending-oldcafe.md"),
                atomically: true,
                encoding: .utf8
            )
        try """
        SOLOPM_DATABASE_PATH=/tmp/SoloPM-voiceover-review.sqlite
        SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=project:42
        SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT=\(commit)
        SOLOPM_VOICEOVER_REVIEW_PROJECT_ID=42
        """.write(to: voiceOverDirectory.appendingPathComponent("launch.env"), atomically: true, encoding: .utf8)
        try "- Source commit: `\(commit)`\n"
            .write(to: voiceOverDirectory.appendingPathComponent("voiceover-worksheet.md"), atomically: true, encoding: .utf8)
        try "EXPECTED_SOURCE_COMMIT=\(commit)\n"
            .write(to: voiceOverDirectory.appendingPathComponent("create-evidence-command.sh"), atomically: true, encoding: .utf8)
        try "- Source commit: `\(commit)`\n"
            .write(
                to: competitorDirectory.appendingPathComponent("competitor-hands-on-pending-\(commit).md"),
                atomically: true,
                encoding: .utf8
            )
        try "- Source commit: `\(commit)`\n"
            .write(
                to: competitorDirectory.appendingPathComponent("competitor-benchmark-pending-\(commit).md"),
                atomically: true,
                encoding: .utf8
            )
        try "- Source commit: `oldcafe`\n"
            .write(
                to: competitorDirectory.appendingPathComponent("competitor-hands-on-pending-oldcafe.md"),
                atomically: true,
                encoding: .utf8
            )
        try "- Source commit: `oldcafe`\n"
            .write(
                to: competitorDirectory.appendingPathComponent("competitor-benchmark-pending-oldcafe.md"),
                atomically: true,
                encoding: .utf8
            )
        try "- Source commit: `oldcafe`\n"
            .write(
                to: competitorDirectory.appendingPathComponent("evidence.md"),
                atomically: true,
                encoding: .utf8
            )
        try "- Release candidate source commit: `\(commit)`\n"
            .write(to: competitorDirectory.appendingPathComponent("hands-on-worksheet.md"), atomically: true, encoding: .utf8)
        try "EXPECTED_SOURCE_COMMIT=\(commit)\n"
            .write(to: competitorDirectory.appendingPathComponent("create-evidence-command.sh"), atomically: true, encoding: .utf8)
        try "- Release candidate source commit: `\(commit)`\n"
            .write(to: releaseMachineDirectory.appendingPathComponent("release-machine-worksheet.md"), atomically: true, encoding: .utf8)
        try "EXPECTED_SOURCE_COMMIT=\(commit)\n"
            .write(to: releaseMachineDirectory.appendingPathComponent("create-release-evidence-command.sh"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: releasePreflightURL.path)

        _ = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_RELEASE_ACTIONS_FILE": actionURL.path]
        )
        let actions = try String(contentsOf: actionURL, encoding: .utf8)

        XCTAssertTrue(actions.contains("## Manual Review Helper Freshness"))
        XCTAssertTrue(actions.contains("- [x] VoiceOver pending preview is generated for release-candidate source commit: `.tmp/voiceover-review/accessibility-voiceover-pending-\(commit).md`"))
        XCTAssertTrue(actions.contains("- [x] VoiceOver launch env is pinned to release-candidate source commit: `.tmp/voiceover-review/launch.env`"))
        XCTAssertTrue(actions.contains("- [x] VoiceOver worksheet is generated for release-candidate source commit: `.tmp/voiceover-review/voiceover-worksheet.md`"))
        XCTAssertTrue(actions.contains("- [x] VoiceOver evidence command is pinned to release-candidate source commit: `.tmp/voiceover-review/create-evidence-command.sh`"))
        XCTAssertTrue(actions.contains("- [x] Competitor pending evidence is generated for release-candidate source commit: `.tmp/competitor-hands-on/competitor-hands-on-pending-\(commit).md`"))
        XCTAssertTrue(actions.contains("- [x] Competitor benchmark pending worksheet is generated for release-candidate source commit: `.tmp/competitor-hands-on/competitor-benchmark-pending-\(commit).md`"))
        XCTAssertTrue(actions.contains("- [x] Competitor worksheet is generated for release-candidate source commit: `.tmp/competitor-hands-on/hands-on-worksheet.md`"))
        XCTAssertTrue(actions.contains("- [x] Competitor evidence command is pinned to release-candidate source commit: `.tmp/competitor-hands-on/create-evidence-command.sh`"))
        XCTAssertTrue(actions.contains("- [x] Release machine worksheet is generated for release evidence source commit: `.tmp/release-machine/release-machine-worksheet.md`"))
        XCTAssertTrue(actions.contains("- [x] Release evidence command is pinned to release evidence source commit: `.tmp/release-machine/create-release-evidence-command.sh`"))
        XCTAssertTrue(actions.contains("- [ ] VoiceOver manual pass clears up to"))
        XCTAssertTrue(actions.contains("Next: fill `.tmp/voiceover-review/voiceover-worksheet.md` during the manual pass, run generated `.tmp/voiceover-review/create-evidence-command.sh` validate-only first, then rerun readiness."))
        XCTAssertTrue(actions.contains("- [ ] Competitor hands-on pass clears up to"))
        XCTAssertTrue(actions.contains("Next: fill `.tmp/competitor-hands-on/hands-on-worksheet.md` and `.tmp/competitor-hands-on/competitor-benchmark-pending-\(commit).md` during the 2-4h pass, complete generated `.tmp/competitor-hands-on/create-evidence-command.sh`, run its validate-only path first, then rerun readiness."))
        XCTAssertFalse(actions.contains("Next: run `./script/prepare_release_manual_helpers.sh`, complete `.tmp/voiceover-review/create-evidence-command.sh`, then rerun readiness."))
        XCTAssertFalse(actions.contains("Next: run `./script/prepare_release_manual_helpers.sh`, fill `.tmp/competitor-hands-on/create-evidence-command.sh`, then rerun readiness."))
        XCTAssertTrue(actions.contains("## Ignored Stale Manual Helper Previews"))
        XCTAssertTrue(actions.contains("- [!] `.tmp/voiceover-review/accessibility-voiceover-pending-oldcafe.md` is ignored because the release-candidate source commit is `\(commit)`."))
        XCTAssertTrue(actions.contains("- [!] `.tmp/competitor-hands-on/competitor-hands-on-pending-oldcafe.md` is ignored because the release-candidate source commit is `\(commit)`."))
        XCTAssertTrue(actions.contains("- [!] `.tmp/competitor-hands-on/competitor-benchmark-pending-oldcafe.md` is ignored because the release-candidate source commit is `\(commit)`."))
        XCTAssertTrue(actions.contains("- [!] `.tmp/competitor-hands-on/evidence.md` is ignored because the release-candidate source commit is `\(commit)`."))
        XCTAssertTrue(actions.contains("These stale previews do not unblock readiness; use the release-candidate helper paths above or rerun `./script/prepare_release_manual_helpers.sh`."))
        XCTAssertTrue(actions.contains("Optional cleanup: run `./script/prepare_release_manual_helpers.sh --prune-stale` after committing source changes to remove ignored old pending previews and legacy default previews without writing passed evidence."))
    }

    func testReleaseActionSummaryTellsOperatorsToRegenerateStaleManualHelpers() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-stale-manual-helper-freshness", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let voiceOverDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("voiceover-review", isDirectory: true)
        let competitorDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("competitor-hands-on", isDirectory: true)
        let releaseMachineDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("release-machine", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let actionURL = fixtureRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("release-actions.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: voiceOverDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: competitorDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: releaseMachineDirectory, withIntermediateDirectories: true)
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
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let commit = try runTool(["git", "rev-parse", "--short", "HEAD"])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try """
        SOLOPM_DATABASE_PATH=/tmp/stale-voiceover-review.sqlite
        SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=project:7
        SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT=oldcafe
        SOLOPM_VOICEOVER_REVIEW_PROJECT_ID=7
        """.write(to: voiceOverDirectory.appendingPathComponent("launch.env"), atomically: true, encoding: .utf8)
        try "- Source commit: `oldcafe`\n"
            .write(
                to: competitorDirectory.appendingPathComponent("competitor-hands-on-pending-\(commit).md"),
                atomically: true,
                encoding: .utf8
            )
        try "- Release candidate source commit: `oldcafe`\n"
            .write(to: competitorDirectory.appendingPathComponent("hands-on-worksheet.md"), atomically: true, encoding: .utf8)
        try "EXPECTED_SOURCE_COMMIT=oldcafe\n"
            .write(to: competitorDirectory.appendingPathComponent("create-evidence-command.sh"), atomically: true, encoding: .utf8)
        try "- Release candidate source commit: `oldcafe`\n"
            .write(to: releaseMachineDirectory.appendingPathComponent("release-machine-worksheet.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: releasePreflightURL.path)

        _ = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_RELEASE_ACTIONS_FILE": actionURL.path]
        )
        let actions = try String(contentsOf: actionURL, encoding: .utf8)

        XCTAssertTrue(actions.contains("## Manual Review Helper Freshness"))
        XCTAssertTrue(actions.contains("- [ ] VoiceOver pending preview missing for release-candidate source commit: `.tmp/voiceover-review/accessibility-voiceover-pending-\(commit).md`"))
        XCTAssertTrue(actions.contains("- [ ] VoiceOver launch env is stale or not pinned to release-candidate source commit `\(commit)`: `.tmp/voiceover-review/launch.env`"))
        XCTAssertTrue(actions.contains("- [ ] VoiceOver worksheet missing for release-candidate source commit: `.tmp/voiceover-review/voiceover-worksheet.md`"))
        XCTAssertTrue(actions.contains("- [ ] Competitor pending evidence is stale or not pinned to release-candidate source commit `\(commit)`: `.tmp/competitor-hands-on/competitor-hands-on-pending-\(commit).md`"))
        XCTAssertTrue(actions.contains("- [ ] Release evidence command missing for release evidence source commit: `.tmp/release-machine/create-release-evidence-command.sh`"))
        XCTAssertTrue(actions.contains("NEXT: regenerate manual review helpers for the current release candidate before running any passed-evidence command."))
        XCTAssertTrue(actions.contains("./script/prepare_release_manual_helpers.sh"))
        XCTAssertFalse(actions.contains("./script/prepare_voiceover_review_candidate.sh --no-launch --skip-build"))
        XCTAssertFalse(actions.contains("./script/create_competitor_hands_on_evidence.sh --pending --output \".tmp/competitor-hands-on/competitor-hands-on-pending-\(commit).md\" --benchmark-output \".tmp/competitor-hands-on/competitor-benchmark-pending-\(commit).md\""))
    }

    func testReleaseActionSummaryRejectsCommandHelpersThatOnlyMentionCurrentCommitInComments() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-comment-only-helper-pin", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let voiceOverDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("voiceover-review", isDirectory: true)
        let competitorDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("competitor-hands-on", isDirectory: true)
        let releaseMachineDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("release-machine", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let actionURL = fixtureRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("release-actions.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: voiceOverDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: competitorDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: releaseMachineDirectory, withIntermediateDirectories: true)
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
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let commit = try runTool(["git", "rev-parse", "--short", "HEAD"])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try "- Source commit: `\(commit)`\n"
            .write(
                to: voiceOverDirectory.appendingPathComponent("accessibility-voiceover-pending-\(commit).md"),
                atomically: true,
                encoding: .utf8
            )
        try "- Source commit: `\(commit)`\n"
            .write(
                to: competitorDirectory.appendingPathComponent("competitor-hands-on-pending-\(commit).md"),
                atomically: true,
                encoding: .utf8
            )
        try "- Source commit: `\(commit)`\n"
            .write(
                to: competitorDirectory.appendingPathComponent("competitor-benchmark-pending-\(commit).md"),
                atomically: true,
                encoding: .utf8
            )
        try "- Release candidate source commit: `\(commit)`\n"
            .write(to: competitorDirectory.appendingPathComponent("hands-on-worksheet.md"), atomically: true, encoding: .utf8)
        try "- Release candidate source commit: `\(commit)`\n"
            .write(to: releaseMachineDirectory.appendingPathComponent("release-machine-worksheet.md"), atomically: true, encoding: .utf8)

        let commentOnlyCommand = """
        # Generated for EXPECTED_SOURCE_COMMIT=\(commit), but this line is only a comment.
        EXPECTED_SOURCE_COMMIT=oldcafe
        """
        try commentOnlyCommand.write(to: voiceOverDirectory.appendingPathComponent("create-evidence-command.sh"), atomically: true, encoding: .utf8)
        try commentOnlyCommand.write(to: competitorDirectory.appendingPathComponent("create-evidence-command.sh"), atomically: true, encoding: .utf8)
        try commentOnlyCommand.write(to: releaseMachineDirectory.appendingPathComponent("create-release-evidence-command.sh"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: releasePreflightURL.path)

        _ = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_RELEASE_ACTIONS_FILE": actionURL.path]
        )
        let actions = try String(contentsOf: actionURL, encoding: .utf8)

        XCTAssertTrue(actions.contains("- [ ] VoiceOver evidence command is stale or not pinned to release-candidate source commit `\(commit)`: `.tmp/voiceover-review/create-evidence-command.sh`"))
        XCTAssertTrue(actions.contains("- [ ] Competitor evidence command is stale or not pinned to release-candidate source commit `\(commit)`: `.tmp/competitor-hands-on/create-evidence-command.sh`"))
        XCTAssertTrue(actions.contains("- [ ] Release evidence command is stale or not pinned to release evidence source commit `\(commit)`: `.tmp/release-machine/create-release-evidence-command.sh`"))
        XCTAssertTrue(actions.contains("NEXT: regenerate manual review helpers for the current release candidate before running any passed-evidence command."))
    }

    func testManualReleaseHelperPreparationScriptRegeneratesCurrentCommitHelpers() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-prepare-release-manual-helpers", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let callsDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("calls", isDirectory: true)
        let helperURL = scriptDirectory.appendingPathComponent("prepare_release_manual_helpers.sh")
        let voiceOverURL = scriptDirectory.appendingPathComponent("prepare_voiceover_review_candidate.sh")
        let competitorURL = scriptDirectory.appendingPathComponent("create_competitor_hands_on_evidence.sh")
        let releaseMachineURL = scriptDirectory.appendingPathComponent("prepare_release_machine_evidence.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: callsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("Sources/SoloPMApp", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "let product = \"SoloPM\"\n".write(
            to: fixtureRoot.appendingPathComponent("Sources/SoloPMApp/App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "// swift-tools-version: 6.0\n".write(
            to: fixtureRoot.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "init"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.email", "release-tests@example.invalid"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.name", "Release Tests"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "add", "Sources/SoloPMApp/App.swift", "Package.swift"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "commit", "-m", "product source"]).exitCode, 0)
        let currentShortCommit = try runTool(["git", "-C", fixtureRoot.path, "rev-parse", "--short", "HEAD"])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceOverDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("voiceover-review", isDirectory: true)
        let competitorDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("competitor-hands-on", isDirectory: true)
        try FileManager.default.createDirectory(at: voiceOverDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: competitorDirectory, withIntermediateDirectories: true)
        let staleVoiceOverPreview = voiceOverDirectory
            .appendingPathComponent("accessibility-voiceover-pending-oldcafe.md")
        let staleCompetitorPreview = competitorDirectory
            .appendingPathComponent("competitor-hands-on-pending-oldcafe.md")
        let staleBenchmarkPreview = competitorDirectory
            .appendingPathComponent("competitor-benchmark-pending-oldcafe.md")
        let legacyCompetitorEvidence = competitorDirectory
            .appendingPathComponent("evidence.md")
        let currentVoiceOverPreview = voiceOverDirectory
            .appendingPathComponent("accessibility-voiceover-pending-\(currentShortCommit).md")
        let currentCompetitorPreview = competitorDirectory
            .appendingPathComponent("competitor-hands-on-pending-\(currentShortCommit).md")
        let currentBenchmarkPreview = competitorDirectory
            .appendingPathComponent("competitor-benchmark-pending-\(currentShortCommit).md")
        for stalePreview in [staleVoiceOverPreview, staleCompetitorPreview, staleBenchmarkPreview] {
            try "- Source commit: `oldcafe`\n".write(to: stalePreview, atomically: true, encoding: .utf8)
        }
        try "- Source commit: `oldcafe`\n"
            .write(to: legacyCompetitorEvidence, atomically: true, encoding: .utf8)
        for currentPreview in [currentVoiceOverPreview, currentCompetitorPreview, currentBenchmarkPreview] {
            try "- Source commit: `\(currentShortCommit)`\n".write(to: currentPreview, atomically: true, encoding: .utf8)
        }

        try readPackageFile("script/prepare_release_manual_helpers.sh")
            .write(to: helperURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        mkdir -p "$ROOT_DIR/.tmp/calls"
        printf "%s\\n" "$*" > "$ROOT_DIR/.tmp/calls/voiceover.args"
        """.write(to: voiceOverURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        mkdir -p "$ROOT_DIR/.tmp/calls"
        printf "%s\\n" "$*" > "$ROOT_DIR/.tmp/calls/competitor.args"
        """.write(to: competitorURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        mkdir -p "$ROOT_DIR/.tmp/calls"
        printf "%s\\n" "$*" > "$ROOT_DIR/.tmp/calls/release-machine.args"
        """.write(to: releaseMachineURL, atomically: true, encoding: .utf8)

        for url in [helperURL, voiceOverURL, competitorURL, releaseMachineURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let helpResult = try runTool(["bash", helperURL.path, "--help"])
        XCTAssertEqual(helpResult.exitCode, 0, helpResult.output)
        XCTAssertTrue(helpResult.output.contains("Regenerates release-candidate manual review helpers without writing passed evidence."))
        XCTAssertTrue(helpResult.output.contains("--prune-stale removes ignored pending preview files for older source commits and legacy default preview files after the release-candidate helpers are regenerated."))

        let result = try runTool(["bash", helperURL.path])
        let voiceOverArgs = try String(
            contentsOf: callsDirectory.appendingPathComponent("voiceover.args"),
            encoding: .utf8
        )
        let competitorArgs = try String(
            contentsOf: callsDirectory.appendingPathComponent("competitor.args"),
            encoding: .utf8
        )
        let releaseMachineArgs = try String(
            contentsOf: callsDirectory.appendingPathComponent("release-machine.args"),
            encoding: .utf8
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Preparing manual review helpers for release-candidate product source commit: \(currentShortCommit)"))
        XCTAssertTrue(result.output.contains("Preparing release-machine helper for release evidence source commit: \(currentShortCommit)"))
        XCTAssertTrue(result.output.contains("Manual release helpers prepared."))
        XCTAssertTrue(result.output.contains("- Release-candidate product source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(result.output.contains("- Release evidence source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(result.output.contains(".tmp/voiceover-review/accessibility-voiceover-pending-\(currentShortCommit).md"))
        XCTAssertTrue(result.output.contains(".tmp/voiceover-review/voiceover-worksheet.md"))
        XCTAssertTrue(result.output.contains(".tmp/competitor-hands-on/competitor-hands-on-pending-\(currentShortCommit).md"))
        XCTAssertTrue(result.output.contains(".tmp/competitor-hands-on/competitor-benchmark-pending-\(currentShortCommit).md"))
        XCTAssertTrue(result.output.contains(".tmp/competitor-hands-on/hands-on-worksheet.md"))
        XCTAssertTrue(result.output.contains(".tmp/release-machine/create-release-evidence-command.sh"))
        XCTAssertTrue(voiceOverArgs.contains("--no-launch --skip-build"))
        XCTAssertTrue(competitorArgs.contains("--pending --output .tmp/competitor-hands-on/competitor-hands-on-pending-\(currentShortCommit).md --benchmark-output .tmp/competitor-hands-on/competitor-benchmark-pending-\(currentShortCommit).md"))
        XCTAssertEqual(releaseMachineArgs.trimmingCharacters(in: .whitespacesAndNewlines), "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staleVoiceOverPreview.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staleCompetitorPreview.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staleBenchmarkPreview.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyCompetitorEvidence.path))

        let pruneResult = try runTool(["bash", helperURL.path, "--prune-stale"])
        XCTAssertEqual(pruneResult.exitCode, 0, pruneResult.output)
        XCTAssertTrue(pruneResult.output.contains("Removed stale manual helper preview: .tmp/voiceover-review/accessibility-voiceover-pending-oldcafe.md"))
        XCTAssertTrue(pruneResult.output.contains("Removed stale manual helper preview: .tmp/competitor-hands-on/competitor-hands-on-pending-oldcafe.md"))
        XCTAssertTrue(pruneResult.output.contains("Removed stale manual helper preview: .tmp/competitor-hands-on/competitor-benchmark-pending-oldcafe.md"))
        XCTAssertTrue(pruneResult.output.contains("Removed legacy manual helper preview: .tmp/competitor-hands-on/evidence.md"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleVoiceOverPreview.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleCompetitorPreview.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleBenchmarkPreview.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyCompetitorEvidence.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentVoiceOverPreview.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentCompetitorPreview.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentBenchmarkPreview.path))
    }

    func testManualReleaseHelperPreparationOutputDistinguishesProductAndReleaseEvidenceCommits() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-prepare-release-manual-helpers-commit-split", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let helperURL = scriptDirectory.appendingPathComponent("prepare_release_manual_helpers.sh")
        let voiceOverURL = scriptDirectory.appendingPathComponent("prepare_voiceover_review_candidate.sh")
        let competitorURL = scriptDirectory.appendingPathComponent("create_competitor_hands_on_evidence.sh")
        let releaseMachineURL = scriptDirectory.appendingPathComponent("prepare_release_machine_evidence.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("Sources/SoloPMApp", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("docs/release", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "let product = \"SoloPM\"\n".write(
            to: fixtureRoot.appendingPathComponent("Sources/SoloPMApp/App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "// swift-tools-version: 6.0\n".write(
            to: fixtureRoot.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "init"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.email", "release-tests@example.invalid"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.name", "Release Tests"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "add", "."]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "commit", "-m", "product source"]).exitCode, 0)
        let productSourceCommit = String(
            try runTool(["git", "-C", fixtureRoot.path, "rev-parse", "--short", "HEAD"])
                .output
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )

        try "release helper docs\n".write(
            to: fixtureRoot.appendingPathComponent("docs/release/manual-unblockers.md"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "add", "."]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "commit", "-m", "release helper docs"]).exitCode, 0)
        let releaseEvidenceCommit = String(
            try runTool(["git", "-C", fixtureRoot.path, "rev-parse", "--short", "HEAD"])
                .output
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertNotEqual(productSourceCommit, releaseEvidenceCommit)

        try readPackageFile("script/prepare_release_manual_helpers.sh")
            .write(to: helperURL, atomically: true, encoding: .utf8)
        for helperScriptURL in [voiceOverURL, competitorURL, releaseMachineURL] {
            try """
            #!/usr/bin/env bash
            set -euo pipefail
            :
            """.write(to: helperScriptURL, atomically: true, encoding: .utf8)
        }
        for url in [helperURL, voiceOverURL, competitorURL, releaseMachineURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", helperURL.path])

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Preparing manual review helpers for release-candidate product source commit: \(productSourceCommit)"))
        XCTAssertTrue(result.output.contains("Preparing release-machine helper for release evidence source commit: \(releaseEvidenceCommit)"))
        XCTAssertTrue(result.output.contains("Manual release helpers prepared."))
        XCTAssertTrue(result.output.contains("- Release-candidate product source commit: `\(productSourceCommit)`"))
        XCTAssertTrue(result.output.contains("- Release evidence source commit: `\(releaseEvidenceCommit)`"))
        XCTAssertFalse(result.output.contains("Manual release helpers prepared for release-candidate source commit: \(productSourceCommit)"))
    }

    func testManualReleaseHelperPreparationRejectsDirtyTrackedSourceTreeBeforeCallingHelpers() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-prepare-release-manual-helpers-dirty-tree", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let callsDirectory = fixtureRoot
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("calls", isDirectory: true)
        let helperURL = scriptDirectory.appendingPathComponent("prepare_release_manual_helpers.sh")
        let voiceOverURL = scriptDirectory.appendingPathComponent("prepare_voiceover_review_candidate.sh")
        let competitorURL = scriptDirectory.appendingPathComponent("create_competitor_hands_on_evidence.sh")
        let releaseMachineURL = scriptDirectory.appendingPathComponent("prepare_release_machine_evidence.sh")
        let trackedURL = fixtureRoot.appendingPathComponent("tracked-release-source.txt")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try readPackageFile("script/prepare_release_manual_helpers.sh")
            .write(to: helperURL, atomically: true, encoding: .utf8)
        for helperScriptURL in [voiceOverURL, competitorURL, releaseMachineURL] {
            try """
            #!/usr/bin/env bash
            set -euo pipefail
            ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
            mkdir -p "$ROOT_DIR/.tmp/calls"
            printf "%s\\n" "$*" > "$ROOT_DIR/.tmp/calls/\(helperScriptURL.deletingPathExtension().lastPathComponent).args"
            """.write(to: helperScriptURL, atomically: true, encoding: .utf8)
        }
        try "clean release candidate\n".write(to: trackedURL, atomically: true, encoding: .utf8)

        for url in [helperURL, voiceOverURL, competitorURL, releaseMachineURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "init"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.email", "release-tests@example.invalid"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.name", "Release Tests"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "add", "."]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "commit", "-m", "initial release helper fixture"]).exitCode, 0)

        try "dirty release candidate\n".write(to: trackedURL, atomically: true, encoding: .utf8)

        let result = try runTool(["bash", helperURL.path])

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("BLOCKER: manual release helper preparation requires a clean tracked source tree"))
        XCTAssertTrue(result.output.contains("Commit or revert tracked source changes, then rerun ./script/prepare_release_manual_helpers.sh for this release candidate."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: callsDirectory.path))
    }

    func testVoiceOverEvidenceGeneratorWritesPendingAndPassedEvidence() throws {
        let pendingURL = packageRoot()
            .appendingPathComponent(".build/test-voiceover-evidence-pending.md")
        let passedURL = packageRoot()
            .appendingPathComponent(".build/test-voiceover-evidence-passed.md")
        let validateOnlyURL = packageRoot()
            .appendingPathComponent(".build/test-voiceover-evidence-validate-only.md")
        let runtimeAXSmokeScriptURL = packageRoot()
            .appendingPathComponent(".build/test-capture-runtime-ax-smoke.sh")
        defer {
            try? FileManager.default.removeItem(at: pendingURL)
            try? FileManager.default.removeItem(at: passedURL)
            try? FileManager.default.removeItem(at: validateOnlyURL)
            try? FileManager.default.removeItem(at: runtimeAXSmokeScriptURL)
        }
        let currentShortCommit = try manualReleaseEvidenceSourceCommit()
        let taskContentExecutionNote = "Approved execution announced the reviewed task title and detail, then left a redacted receipt with task identity, reviewed detail, and before/after status."
        let inboxVoiceTriageNote = "Inbox voice capture detail announces transcript, AI interpretation, source metadata, memo field, and make task schedule review later project triage actions."
        let todayRailActionsNote = "Today assistant rail announces next action and task detail before focus schedule draft edit subtask draft and reminder draft controls."
        let unsafeEvidenceSource = "dist/SoloPM.app manual VoiceOver pass using \(packageRoot().path)/.tmp/voiceover-review/SoloPM-voiceover-review.sqlite project:119 file:///Users/alice/private.wav"
        let sanitizedEvidenceSource = "dist/SoloPM.app manual VoiceOver pass using isolated .tmp voiceover review database project:119"
        let localPathMarkers = [packageRoot().path, "/Users/", "/Volumes/", "file://"]

        let pendingResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: ["--pending", "--evidence-source", unsafeEvidenceSource, "--output", pendingURL.path]
        )

        XCTAssertEqual(pendingResult.exitCode, 0, pendingResult.output)
        let pendingEvidence = try String(contentsOf: pendingURL, encoding: .utf8)
        XCTAssertTrue(pendingEvidence.contains("Status: pending"))
        XCTAssertTrue(pendingEvidence.contains("- App build: `0.1.0 (1)`"))
        XCTAssertTrue(pendingEvidence.contains("- Bundle identifier: `dev.solopm.app`"))
        XCTAssertTrue(pendingEvidence.contains("- Source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(pendingEvidence.contains("- Accessibility environment:"))
        XCTAssertTrue(pendingEvidence.contains("- Runtime AX smoke:"))
        XCTAssertTrue(pendingEvidence.contains("- [ ] Project navigation"))
        XCTAssertTrue(pendingEvidence.contains("- [ ] Inline Task Composer"))
        XCTAssertTrue(pendingEvidence.contains("- [ ] Inbox voice triage: confirm the selected voice intake detail announces transcript, interpretation, source metadata, memo, and triage actions."))
        XCTAssertTrue(pendingEvidence.contains("- [ ] Today rail actions: confirm the Today rail announces next action, task detail, focus, schedule draft, edit, subtask draft, and reminder draft controls."))
        XCTAssertTrue(pendingEvidence.contains("- [ ] Task content execution: run the approved plan and confirm the redacted execution receipt includes reviewed title and detail."))
        XCTAssertTrue(pendingEvidence.contains("- [ ] Delete Task confirmation: confirm destructive action opens an inline inspector confirmation panel before local deletion."))
        XCTAssertTrue(pendingEvidence.contains("- [ ] No keyboard trap: confirm focus can leave sidebar, board, card controls, inspector fields, and inline confirmation panels."))
        XCTAssertTrue(pendingEvidence.contains("- [ ] No unlabeled primary CRUD controls: confirm create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help."))
        XCTAssertFalse(pendingEvidence.contains("confirmation dialogs"))
        XCTAssertFalse(pendingEvidence.contains("complete/archive"))
        XCTAssertTrue(pendingEvidence.contains("Do not set `Status: passed` until every item below is verified"))
        XCTAssertTrue(pendingEvidence.contains("- Evidence source: `\(sanitizedEvidenceSource)`"))
        for marker in localPathMarkers {
            XCTAssertFalse(pendingEvidence.contains(marker), "pending VoiceOver evidence must not leak \(marker)")
        }

        let unsafePassedResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: ["--passed", "--checked-by", "SoloPM Release Owner", "--output", passedURL.path]
        )
        XCTAssertNotEqual(unsafePassedResult.exitCode, 0)
        XCTAssertTrue(unsafePassedResult.output.contains("--confirm-manual-voiceover-pass is required with --passed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let missingNotesResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(missingNotesResult.exitCode, 0)
        XCTAssertTrue(missingNotesResult.output.contains("--project-navigation-note is required with --passed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let placeholderEnvironmentResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver/keyboard/device details used for the manual pass",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(placeholderEnvironmentResult.exitCode, 0)
        XCTAssertTrue(placeholderEnvironmentResult.output.contains("--accessibility-environment must describe the actual VoiceOver, keyboard, and device environment"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let placeholderReviewerResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "Reviewer Name",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(placeholderReviewerResult.exitCode, 0)
        XCTAssertTrue(placeholderReviewerResult.output.contains("--checked-by must name the actual reviewer"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let unknownMacOSVersionResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS unknown",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(unknownMacOSVersionResult.exitCode, 0)
        XCTAssertTrue(unknownMacOSVersionResult.output.contains("--macos-version must identify the actual macOS version"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let angleBracketPlaceholderReviewerResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "<reviewer name>",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(angleBracketPlaceholderReviewerResult.exitCode, 0)
        XCTAssertTrue(angleBracketPlaceholderReviewerResult.output.contains("--checked-by must name the actual reviewer"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let invalidDateResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "June 19, 2026",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(invalidDateResult.exitCode, 0)
        XCTAssertTrue(invalidDateResult.output.contains("--check-date must use YYYY-MM-DD"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let invalidCalendarDateResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-02-31",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(invalidCalendarDateResult.exitCode, 0)
        XCTAssertTrue(invalidCalendarDateResult.output.contains("--check-date must use YYYY-MM-DD"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let futureDateResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2099-01-01",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(futureDateResult.exitCode, 0)
        XCTAssertTrue(futureDateResult.output.contains("--check-date must not be in the future"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let boilerplateNoteResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--project-navigation-note", "Verified.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(boilerplateNoteResult.exitCode, 0)
        XCTAssertTrue(boilerplateNoteResult.output.contains("--project-navigation-note must include concrete VoiceOver verification details"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let copiedTemplateNoteResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--project-navigation-note", "Concrete VoiceOver observation for sidebar Inbox, Today, and Project navigation.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(copiedTemplateNoteResult.exitCode, 0)
        XCTAssertTrue(copiedTemplateNoteResult.output.contains("--project-navigation-note must include concrete VoiceOver verification details"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let angleBracketTemplateNoteResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "<VoiceOver observation for sidebar Inbox, Today, Projects, and selected review project navigation>",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(angleBracketTemplateNoteResult.exitCode, 0)
        XCTAssertTrue(angleBracketTemplateNoteResult.output.contains("--project-navigation-note must include concrete VoiceOver verification details"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let missingFocusPathRuntimeAXResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(missingFocusPathRuntimeAXResult.exitCode, 0)
        XCTAssertTrue(missingFocusPathRuntimeAXResult.output.contains("--runtime-ax-smoke-note must include focusPathSignals=6/6"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let missingTaskContentExecutionResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(missingTaskContentExecutionResult.exitCode, 0)
        XCTAssertTrue(missingTaskContentExecutionResult.output.contains("--task-content-execution-note is required with --passed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let weakTaskContentExecutionResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--validate-only",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", "VoiceOver announced Run approved plan and the selected task execution completed.",
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", validateOnlyURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(weakTaskContentExecutionResult.exitCode, 0)
        XCTAssertTrue(weakTaskContentExecutionResult.output.contains("--task-content-execution-note must mention the redacted receipt, reviewed title, and reviewed detail"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: validateOnlyURL.path))

        let weakInboxVoiceTriageResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--validate-only",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", "Inbox voice detail announced transcript and triage actions.",
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", validateOnlyURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(weakInboxVoiceTriageResult.exitCode, 0)
        XCTAssertTrue(weakInboxVoiceTriageResult.output.contains("--inbox-voice-triage-note must mention transcript, interpretation, metadata, memo, and every Inbox triage action"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: validateOnlyURL.path))

        let weakTodayRailActionsResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--validate-only",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", "Today rail announced focus, schedule, and reminder controls.",
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", validateOnlyURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(weakTodayRailActionsResult.exitCode, 0)
        XCTAssertTrue(weakTodayRailActionsResult.output.contains("--today-rail-actions-note must mention next action, task detail, focus, schedule, edit, subtask, and reminder controls"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: validateOnlyURL.path))

        try """
        #!/usr/bin/env bash
        set -euo pipefail
        if [[ "${1:-}" != "--runtime" || "${2:-}" != "--skip-launch" ]]; then
          echo "unexpected arguments: $*" >&2
          exit 2
        fi
        echo "OK: accessibility source anchors are present (47 anchors)"
        echo "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=31, textFields=2, staticTexts=29, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1"
        echo "This is not a substitute for the manual VoiceOver pass."
        """.write(to: runtimeAXSmokeScriptURL, atomically: true, encoding: .utf8)

        let capturedRuntimeAXSmokeResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--capture-runtime-ax-smoke",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ],
            environment: ["SOLOPM_ACCESSIBILITY_PREFLIGHT_SCRIPT": runtimeAXSmokeScriptURL.path]
        )
        XCTAssertEqual(capturedRuntimeAXSmokeResult.exitCode, 0, capturedRuntimeAXSmokeResult.output)
        let capturedRuntimeAXSmokeEvidence = try String(contentsOf: passedURL, encoding: .utf8)
        XCTAssertTrue(capturedRuntimeAXSmokeEvidence.contains("- Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=31, textFields=2, staticTexts=29, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1"))
        XCTAssertFalse(capturedRuntimeAXSmokeEvidence.contains("This is not a substitute for the manual VoiceOver pass."))
        XCTAssertFalse(capturedRuntimeAXSmokeEvidence.localizedCaseInsensitiveContains("pending"))
        try? FileManager.default.removeItem(at: passedURL)

        let capturedWithoutManualPassResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--capture-runtime-ax-smoke",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path
            ],
            environment: ["SOLOPM_ACCESSIBILITY_PREFLIGHT_SCRIPT": runtimeAXSmokeScriptURL.path]
        )
        XCTAssertNotEqual(capturedWithoutManualPassResult.exitCode, 0)
        XCTAssertTrue(capturedWithoutManualPassResult.output.contains("--confirm-manual-voiceover-pass is required with --passed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let validateOnlyResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--validate-only",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", validateOnlyURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertEqual(validateOnlyResult.exitCode, 0, validateOnlyResult.output)
        XCTAssertTrue(validateOnlyResult.output.contains("OK: VoiceOver evidence command is valid for current source commit"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: validateOnlyURL.path))

        let validateOnlyPlaceholderResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--validate-only",
                "--checked-by", "<reviewer name>",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", validateOnlyURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )
        XCTAssertNotEqual(validateOnlyPlaceholderResult.exitCode, 0)
        XCTAssertTrue(validateOnlyPlaceholderResult.output.contains("--checked-by must name the actual reviewer"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: validateOnlyURL.path))

        let passedResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Release Owner",
                "--macos-version", "macOS 15.5",
                "--check-date", "2026-06-19",
                "--accessibility-environment", "VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display",
                "--runtime-ax-smoke-note", "OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1",
                "--project-navigation-note", "Sidebar Inbox, Today, and selected project rows announce destination and counts in order.",
                "--project-board-detail-note", "Selected project board announces project title before card navigation begins.",
                "--open-task-note", "Task card details open from keyboard focus without relying on drag.",
                "--inline-task-composer-note", "Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.",
                "--status-controls-note", "Previous and next status buttons announce the target status before moving the task.",
                "--task-inspector-note", "Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.",
                "--inbox-voice-triage-note", inboxVoiceTriageNote,
                "--today-rail-actions-note", todayRailActionsNote,
                "--evidence-source", unsafeEvidenceSource,
                "--save-changes-note", "Keyboard activation reaches the local task save action and returns without a trap.",
                "--task-content-execution-note", taskContentExecutionNote,
                "--delete-confirmation-note", "Delete opens confirmation before local deletion and exposes cancel.",
                "--no-keyboard-trap-note", "Focus can leave sidebar, board, card controls, inspector fields, and dialogs.",
                "--no-unlabeled-crud-note", "Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.",
                "--output", passedURL.path,
                "--confirm-manual-voiceover-pass"
            ]
        )

        XCTAssertEqual(passedResult.exitCode, 0, passedResult.output)
        let passedEvidence = try String(contentsOf: passedURL, encoding: .utf8)
        XCTAssertTrue(passedEvidence.contains("Status: passed"))
        XCTAssertTrue(passedEvidence.contains("Generated by: script/create_voiceover_evidence.sh"))
        XCTAssertTrue(passedEvidence.contains("- App build: `0.1.0 (1)`"))
        XCTAssertTrue(passedEvidence.contains("- Bundle identifier: `dev.solopm.app`"))
        XCTAssertTrue(passedEvidence.contains("- Source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(passedEvidence.contains("- Checked by: SoloPM Release Owner"))
        XCTAssertTrue(passedEvidence.contains("- Check date: 2026-06-19"))
        XCTAssertTrue(passedEvidence.contains("- Evidence source: `\(sanitizedEvidenceSource)`"))
        XCTAssertTrue(passedEvidence.contains("- Accessibility environment: VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display"))
        XCTAssertTrue(passedEvidence.contains("- Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1"))
        XCTAssertTrue(passedEvidence.contains("- Project navigation: passed - Sidebar Inbox, Today, and selected project rows announce destination and counts in order."))
        XCTAssertTrue(passedEvidence.contains("- Project board detail: passed - Selected project board announces project title before card navigation begins."))
        XCTAssertTrue(passedEvidence.contains("- Open task: passed - Task card details open from keyboard focus without relying on drag."))
        XCTAssertTrue(passedEvidence.contains("- Inline Task Composer: passed - Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable."))
        XCTAssertTrue(passedEvidence.contains("- Status controls: passed - Previous and next status buttons announce the target status before moving the task."))
        XCTAssertTrue(passedEvidence.contains("- Task inspector: passed - Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable."))
        XCTAssertTrue(passedEvidence.contains("- Inbox voice triage: passed - \(inboxVoiceTriageNote)"))
        XCTAssertTrue(passedEvidence.contains("- Today rail actions: passed - \(todayRailActionsNote)"))
        XCTAssertTrue(passedEvidence.contains("- Save Changes: passed - Keyboard activation reaches the local task save action and returns without a trap."))
        XCTAssertTrue(passedEvidence.contains("- Task content execution: passed - \(taskContentExecutionNote)"))
        XCTAssertTrue(passedEvidence.contains("- Delete Task confirmation: passed - Delete opens confirmation before local deletion and exposes cancel."))
        XCTAssertTrue(passedEvidence.contains("- No keyboard trap: passed - Focus can leave sidebar, board, card controls, inspector fields, and dialogs."))
        XCTAssertTrue(passedEvidence.contains("- No unlabeled primary CRUD controls: passed - Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help."))
        XCTAssertFalse(passedEvidence.contains("complete/archive"))
        XCTAssertFalse(passedEvidence.localizedCaseInsensitiveContains("pending"))
        XCTAssertFalse(passedEvidence.contains("- [ ]"))
        XCTAssertFalse(passedEvidence.localizedCaseInsensitiveContains("placeholder"))
        for marker in localPathMarkers {
            XCTAssertFalse(passedEvidence.contains(marker), "passed VoiceOver evidence must not leak \(marker)")
        }
    }

    func testVoiceOverPendingDefaultsUseIgnoredCurrentCommitPreview() throws {
        let root = packageRoot()
        let currentShortCommit = try manualReleaseEvidenceSourceCommit()
        let trackedEvidenceURL = root
            .appendingPathComponent("docs/release/evidence/accessibility-voiceover.md")
        let defaultPendingURL = root
            .appendingPathComponent(".tmp/voiceover-review/accessibility-voiceover-pending-\(currentShortCommit).md")
        let originalTrackedEvidence = try String(contentsOf: trackedEvidenceURL, encoding: .utf8)

        try? FileManager.default.removeItem(at: defaultPendingURL)
        defer {
            try? originalTrackedEvidence.write(to: trackedEvidenceURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: defaultPendingURL)
        }

        let pendingResult = try runScript(
            "script/create_voiceover_evidence.sh",
            arguments: ["--pending"]
        )

        XCTAssertEqual(pendingResult.exitCode, 0, pendingResult.output)
        XCTAssertTrue(
            pendingResult.output.contains(".tmp/voiceover-review/accessibility-voiceover-pending-\(currentShortCommit).md"),
            pendingResult.output
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: defaultPendingURL.path))
        XCTAssertEqual(
            try String(contentsOf: trackedEvidenceURL, encoding: .utf8),
            originalTrackedEvidence,
            "Direct pending generation must not modify tracked VoiceOver release evidence."
        )
    }

    func testAccessibilityPreflightChecksSourceAnchorsAndDocumentsRuntimeBoundary() throws {
        let script = try readPackageFile("script/check_accessibility_preflight.sh")
        let checklist = try readPackageFile("docs/release/checklist.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let phase14 = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        XCTAssertTrue(script.contains("REQUIRED_SOURCE_ANCHORS"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-sidebar"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-detail"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-create"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-show-archived"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-add-project"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-header-add-task"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::task-status-move-controls"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::task-status-move-"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-detail"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-status"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-priority"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-due"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-apply-suggestion"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-save"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-delete"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-delete-confirmation-cancel"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-title"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-apply-suggestion"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-save"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-complete"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-restore"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-archive"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-delete"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-overview-task-open-"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-overview-add-task"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-local-suggestion-open-task"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-local-suggestion-review-action"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-artifact-path"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-artifact-track"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::project-artifact-remove-"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::sidebar-destination-"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-quick-add-button"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-voice-intake-detail"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-voice-transcript"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-voice-interpretation"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-voice-memo-editor"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-voice-memo-save"))
        XCTAssertTrue(script.contains(#"Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"n\", modifiers: [.command])"#))
        XCTAssertTrue(script.contains(#"Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"n\", modifiers: [.command, .shift])"#))
        XCTAssertTrue(script.contains(#"Sources/SoloPMApp/SoloPMApp.swift::.keyboardShortcut(\",\", modifiers: [.command])"#))
        XCTAssertTrue(script.contains(#"Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"s\", modifiers: [.command])"#))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(.delete, modifiers: [.command])"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(.return, modifiers: [.command])"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(.escape, modifiers: [])"))
        XCTAssertTrue(script.contains(#"Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::.keyboardShortcut(\"1\", modifiers: [.command])"#))
        XCTAssertTrue(script.contains(#"Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::.keyboardShortcut(\"2\", modifiers: [.command])"#))
        XCTAssertTrue(script.contains(#"Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::.keyboardShortcut(\"3\", modifiers: [.command])"#))
        XCTAssertTrue(script.contains(#"Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::.keyboardShortcut(\"4\", modifiers: [.command])"#))
        XCTAssertTrue(script.contains("Sources/SoloPMApp/SoloPMApp.swift::.keyboardShortcut(.return, modifiers: [.command])"))
        XCTAssertTrue(script.contains("--runtime"))
        XCTAssertTrue(script.contains("--skip-source-anchors"))
        XCTAssertTrue(script.contains("System Events"))
        XCTAssertTrue(script.contains("MIN_AX_BUTTONS"))
        XCTAssertTrue(script.contains("MIN_AX_TEXT_FIELDS"))
        XCTAssertTrue(script.contains("MIN_AX_STATIC_TEXTS"))
        XCTAssertTrue(script.contains("--launch-env"))
        XCTAssertTrue(script.contains("LAUNCH_ENV_FILE"))
        XCTAssertTrue(script.contains("DEFAULT_VOICEOVER_LAUNCH_ENV_FILE"))
        XCTAssertTrue(script.contains("./script/prepare_voiceover_review_candidate.sh --skip-build --no-launch"))
        XCTAssertTrue(script.contains("LAUNCH_ENV_FILE=\"$DEFAULT_VOICEOVER_LAUNCH_ENV_FILE\""))
        XCTAssertTrue(script.contains("APP_BINARY=\"$APP_BUNDLE/Contents/MacOS/$APP_NAME\""))
        XCTAssertTrue(script.contains("source \"$LAUNCH_ENV_FILE\""))
        XCTAssertTrue(script.contains("\"$APP_BINARY\" >/dev/null 2>&1 &"))
        XCTAssertTrue(script.contains("set frontmost to true"))
        XCTAssertFalse(script.contains("tell application \\\"$APP_NAME\\\" to activate"))
        XCTAssertTrue(script.contains("REQUIRED_RUNTIME_CRUD_MARKERS"))
        XCTAssertTrue(script.contains("REQUIRED_RUNTIME_FOCUS_MARKERS"))
        XCTAssertTrue(script.contains("REQUIRED_RUNTIME_BUTTON_A11Y_MARKERS"))
        XCTAssertTrue(script.contains("REQUIRED_RUNTIME_SCREEN_MARKERS"))
        XCTAssertTrue(script.contains("REQUIRED_RUNTIME_DESTRUCTIVE_CANCEL_MARKERS"))
        XCTAssertTrue(script.contains("project-board-add-project"))
        XCTAssertTrue(script.contains("project-header-add-task"))
        XCTAssertTrue(script.contains("task-status-move-"))
        XCTAssertTrue(script.contains("task-inspector-apply-suggestion"))
        XCTAssertTrue(script.contains("task-auto-execution-review"))
        XCTAssertTrue(script.contains("task-auto-execution-run-plan"))
        XCTAssertTrue(script.contains("task-card-open-details"))
        XCTAssertTrue(script.contains("project-header-add-task=>Add task"))
        XCTAssertTrue(script.contains("task-card-open-details=>Open task"))
        XCTAssertTrue(script.contains("task-status-move-=>Move"))
        XCTAssertTrue(script.contains("task-inspector-apply-suggestion=>Applies the local next-step suggestion"))
        XCTAssertTrue(script.contains("task-inspector-save=>Saves edits"))
        XCTAssertTrue(script.contains("task-auto-execution-review=>Prepares review-only local automation"))
        XCTAssertTrue(script.contains("task-auto-execution-run-plan=>Runs the reviewed local task step"))
        XCTAssertTrue(script.contains("task-inspector-delete=>Deletes the selected task"))
        XCTAssertTrue(script.contains("Delete task cancel=>task-inspector-delete-confirmation-cancel"))
        XCTAssertFalse(script.contains("project-inspector-save=>Saves edits"))
        XCTAssertFalse(script.contains("project-inspector-delete=>Deletes the selected project"))
        XCTAssertTrue(script.contains("Inbox sidebar=>sidebar-destination-inbox"))
        XCTAssertTrue(script.contains("Today sidebar=>sidebar-destination-today"))
        XCTAssertTrue(script.contains("Settings toolbar=>project-board-settings-link"))
        XCTAssertTrue(script.contains("Voice Command toolbar=>project-board-voice-command"))
        XCTAssertTrue(script.contains("Project navigation"))
        XCTAssertTrue(script.contains("Project board detail"))
        XCTAssertTrue(script.contains("Open task"))
        XCTAssertTrue(script.contains("Inline Task Composer"))
        XCTAssertTrue(script.contains("Status controls"))
        XCTAssertTrue(script.contains("Task inspector"))
        XCTAssertTrue(script.contains("AXButton"))
        XCTAssertTrue(script.contains("AXTextField"))
        XCTAssertTrue(script.contains("AXStaticText"))
        XCTAssertFalse(script.contains("count of buttons of entire contents"))
        XCTAssertFalse(script.contains("count of text fields of entire contents"))
        XCTAssertFalse(script.contains("count of static texts of entire contents"))
        XCTAssertTrue(script.contains("runtime AX smoke did not pass within"))
        XCTAssertTrue(script.contains("runtime AX smoke has too few buttons"))
        XCTAssertTrue(script.contains("runtime AX smoke has too few text fields"))
        XCTAssertTrue(script.contains("runtime AX smoke has too few static texts"))
        XCTAssertTrue(script.contains("unlabeledButtonCount"))
        XCTAssertTrue(script.contains("runtime AX smoke has unlabeled buttons"))
        XCTAssertTrue(script.contains("genericButtonCount"))
        XCTAssertTrue(script.contains("genericButtons="))
        XCTAssertTrue(script.contains("runtime AX smoke has generic button labels without help or child text"))
        XCTAssertTrue(script.contains("crudSignals="))
        XCTAssertTrue(script.contains("runtime AX smoke is missing primary CRUD button labels or help"))
        XCTAssertTrue(script.contains("focusPathSignals="))
        XCTAssertTrue(script.contains("runtime AX smoke is missing VoiceOver focus path labels or help"))
        XCTAssertTrue(script.contains("destructiveCancelSignals="))
        XCTAssertTrue(script.contains("runtime AX smoke is missing destructive cancellation labels or help"))
        XCTAssertTrue(script.contains("open_task_delete_confirmation_for_runtime_focus_path"))
        XCTAssertTrue(script.contains("buttonA11ySignals="))
        XCTAssertTrue(script.contains("runtime AX smoke is missing primary button label or help"))
        XCTAssertTrue(script.contains("screenSignals="))
        XCTAssertTrue(script.contains("runtime AX smoke is missing workflow screen entry labels or help"))
        XCTAssertTrue(script.contains("This is not a substitute for the manual VoiceOver pass."))

        let result = try runScript("script/check_accessibility_preflight.sh", arguments: ["--source-only"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("OK: accessibility source anchors are present"))

        XCTAssertTrue(checklist.contains("./script/check_accessibility_preflight.sh --source-only"))
        XCTAssertTrue(checklist.contains("./script/check_accessibility_preflight.sh --runtime"))
        XCTAssertTrue(checklist.contains("SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT=1 ./script/release_readiness_report.sh"))
        XCTAssertTrue(checklist.contains("verifies both accessibility anchors and primary CRUD keyboard shortcuts"))
        XCTAssertTrue(checklist.contains("fewer than the minimum buttons, text fields, or static texts"))
        XCTAssertTrue(checklist.contains("unlabeled AX buttons"))
        XCTAssertTrue(checklist.contains("generic `button` label without help or child text"))
        XCTAssertTrue(checklist.contains("task lifecycle AX identifier/help signals as `crudSignals=8/8`"))
        XCTAssertTrue(checklist.contains("VoiceOver focus path AX identifier/help signals as `focusPathSignals=6/6`"))
        XCTAssertTrue(checklist.contains("destructive delete cancellation signals as `destructiveCancelSignals=1/1`"))
        XCTAssertTrue(checklist.contains("primary task button label/help signals as `buttonA11ySignals=8/8`"))
        XCTAssertTrue(checklist.contains("Inbox, Today, Settings, and Voice Command entry signals as `screenSignals=4/4`"))
        XCTAssertTrue(checklist.contains("scans visible windows by AX role"))
        XCTAssertTrue(phase14.contains("- [x] 主要buttonがAX labelまたはhelpを失ったら失敗するruntime smokeを追加する。"))
        XCTAssertTrue(phase14.contains("- [x] `check_accessibility_preflight.sh --runtime` の対象画面をInbox/Today/Settingsへ広げる。"))
        XCTAssertTrue(phase.contains("[x] `script/check_accessibility_preflight.sh` はsource-level accessibility anchorsを確認し、任意のruntime AX smokeで手動VoiceOver前の崩れを検出できる。"))
        XCTAssertTrue(phase.contains("[x] `script/check_accessibility_preflight.sh` はProject OverviewのTask snapshot、Local Suggestions、Artifactsの支援技術CRUD入口もsource anchorとして監視する。"))
        XCTAssertTrue(phase.contains("[x] `script/check_accessibility_preflight.sh` は主要CRUDのkeyboard shortcutsをsource anchorとして監視する。"))
        XCTAssertTrue(phase.contains("[x] `script/check_accessibility_preflight.sh --runtime` は見えているrelease候補windowのunlabeled AX buttonsとhelp/child textなしgeneric `button` labelをblockerにする。"))
        XCTAssertTrue(phase.contains("[x] `script/check_accessibility_preflight.sh --runtime` はProject Board上のAdd Task、タスク詳細オープン、ステータス移動、ローカル提案適用、自動化レビュー、承認済み実行、Save、DeleteのAX identifier/help signalsを `crudSignals=8/8` としてblocker化する。"))
        XCTAssertTrue(phase.contains("[x] `script/check_accessibility_preflight.sh --runtime` はProject navigation -> Project board detail -> Open task -> Inline Task Composer -> Status controls -> Task inspector のAX identifier/help signalsを `focusPathSignals=6/6` としてblocker化する。"))
        XCTAssertTrue(phase.contains("[x] `script/check_accessibility_preflight.sh --runtime` はDelete Task確認を開き、Cancel Delete TaskのAX identifier/help signalを `destructiveCancelSignals=1/1` としてblocker化する。"))
        XCTAssertTrue(phase.contains("[x] VoiceOver passed evidence は同じrelease候補で実行したruntime AX smoke OK行、`unlabeledButtons=0`、`genericButtons=0`、`crudSignals=8/8`、`focusPathSignals=6/6`、`destructiveCancelSignals=1/1` を含まない場合release readyにしない。"))
        XCTAssertTrue(phase.contains("[x] `script/prepare_voiceover_review_candidate.sh` は `.tmp/voiceover-review/create-evidence-command.sh` を生成し、同じ候補DB/Project IDを使った手動VoiceOver証跡コマンドをoperatorがplaceholder置換して実行できる。"))
        XCTAssertTrue(phase.contains("[ ] 実機VoiceOverでProject board -> card -> Inline Task Composer -> inspectorのfocus orderを確認する。"))
    }

    func testCompetitorPendingDefaultsUseIgnoredCurrentCommitHelpers() throws {
        let trackedEvidenceURL = packageRoot()
            .appendingPathComponent("docs/release/evidence/competitor-hands-on.md")
        let trackedBenchmarkURL = packageRoot()
            .appendingPathComponent("docs/product/competitor-benchmark.md")
        let originalEvidence = try String(contentsOf: trackedEvidenceURL, encoding: .utf8)
        let originalBenchmark = try String(contentsOf: trackedBenchmarkURL, encoding: .utf8)
        let currentShortCommit = try manualReleaseEvidenceSourceCommit()
        let pendingURL = packageRoot()
            .appendingPathComponent(".tmp/competitor-hands-on/competitor-hands-on-pending-\(currentShortCommit).md")
        let pendingBenchmarkURL = packageRoot()
            .appendingPathComponent(".tmp/competitor-hands-on/competitor-benchmark-pending-\(currentShortCommit).md")
        let commandURL = packageRoot()
            .appendingPathComponent(".tmp/competitor-hands-on/create-evidence-command.sh")
        let worksheetURL = packageRoot()
            .appendingPathComponent(".tmp/competitor-hands-on/hands-on-worksheet.md")

        for artifactURL in [pendingURL, pendingBenchmarkURL, commandURL, worksheetURL] {
            try removeItemIfPresent(at: artifactURL)
        }
        defer {
            try? originalEvidence.write(to: trackedEvidenceURL, atomically: true, encoding: .utf8)
            try? originalBenchmark.write(to: trackedBenchmarkURL, atomically: true, encoding: .utf8)
            for artifactURL in [pendingURL, pendingBenchmarkURL, commandURL, worksheetURL] {
                try? removeItemIfPresent(at: artifactURL)
            }
        }

        let result = try runScript("script/create_competitor_hands_on_evidence.sh", arguments: ["--pending"])

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence written: \(pendingURL.path)"))
        XCTAssertTrue(result.output.contains("Competitor benchmark pending worksheet written: \(pendingBenchmarkURL.path)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingBenchmarkURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: commandURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worksheetURL.path))
        XCTAssertEqual(try String(contentsOf: trackedEvidenceURL, encoding: .utf8), originalEvidence)
        XCTAssertEqual(try String(contentsOf: trackedBenchmarkURL, encoding: .utf8), originalBenchmark)

        let generatedCommand = try String(contentsOf: commandURL, encoding: .utf8)
        XCTAssertTrue(generatedCommand.contains("--output \(pendingURL.path) \\"))
        XCTAssertTrue(generatedCommand.contains("--benchmark-output \(pendingBenchmarkURL.path) \\"))
    }

    func testCompetitorHandsOnEvidenceGeneratorWritesPendingAndPassedEvidence() throws {
        let pendingURL = packageRoot()
            .appendingPathComponent(".build/test-competitor-hands-on-pending.md")
        let passedURL = packageRoot()
            .appendingPathComponent(".build/test-competitor-hands-on-passed.md")
        let pendingBenchmarkURL = packageRoot()
            .appendingPathComponent(".build/test-competitor-hands-on-benchmark-pending.md")
        let benchmarkURL = packageRoot()
            .appendingPathComponent(".build/test-competitor-hands-on-benchmark.md")
        let validateOnlyURL = packageRoot()
            .appendingPathComponent(".build/test-competitor-hands-on-validate-only.md")
        let commandURL = packageRoot()
            .appendingPathComponent(".build/test-competitor-hands-on-command.sh")
        let worksheetURL = packageRoot()
            .appendingPathComponent(".build/test-competitor-hands-on-worksheet.md")
        for artifactURL in [
            pendingURL,
            passedURL,
            pendingBenchmarkURL,
            benchmarkURL,
            validateOnlyURL,
            commandURL,
            worksheetURL
        ] {
            try removeItemIfPresent(at: artifactURL)
        }
        defer {
            for artifactURL in [
                pendingURL,
                passedURL,
                pendingBenchmarkURL,
                benchmarkURL,
                validateOnlyURL,
                commandURL,
                worksheetURL
            ] {
                try? removeItemIfPresent(at: artifactURL)
            }
        }
        let currentShortCommit = try manualReleaseEvidenceSourceCommit()
        let handsOnDuration = "2h 15m total: Notion 35m, Todoist 30m, Linear 35m, Motion 35m"

        let pendingResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--pending",
                "--output", pendingURL.path,
                "--benchmark-output", pendingBenchmarkURL.path,
                "--command-output", commandURL.path,
                "--worksheet-output", worksheetURL.path
            ]
        )

        XCTAssertEqual(pendingResult.exitCode, 0, pendingResult.output)
        XCTAssertTrue(pendingResult.output.contains("Competitor hands-on worksheet written: \(worksheetURL.path)"))
        let pendingEvidence = try String(contentsOf: pendingURL, encoding: .utf8)
        XCTAssertTrue(pendingEvidence.contains("Status: pending"))
        XCTAssertTrue(pendingEvidence.contains("- [ ] Notion"))
        XCTAssertTrue(pendingEvidence.contains("- [ ] Todoist"))
        XCTAssertTrue(pendingEvidence.contains("- [ ] Linear"))
        XCTAssertTrue(pendingEvidence.contains("- [ ] Motion"))
        XCTAssertTrue(pendingEvidence.contains("- Environment:"))
        XCTAssertTrue(pendingEvidence.contains("- Elapsed hands-on time:"))
        XCTAssertTrue(pendingEvidence.contains("- Source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(pendingEvidence.contains("Do not set `Status: passed` until every competitor path below is verified"))
        let pendingBenchmark = try String(contentsOf: pendingBenchmarkURL, encoding: .utf8)
        XCTAssertTrue(pendingBenchmark.contains("# Competitor Benchmark Pending Worksheet"))
        XCTAssertTrue(pendingBenchmark.contains("Status: pending"))
        XCTAssertTrue(pendingBenchmark.contains("This file is not release evidence."))
        XCTAssertTrue(pendingBenchmark.contains("Source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(pendingBenchmark.contains("Evidence output: `\(pendingURL.path)`"))
        XCTAssertTrue(pendingBenchmark.contains("Passed benchmark output: `\(pendingBenchmarkURL.path)`"))
        XCTAssertTrue(pendingBenchmark.contains("## Hands-On Findings To Fill"))
        XCTAssertTrue(pendingBenchmark.contains("- [ ] Notion:"))
        XCTAssertTrue(pendingBenchmark.contains("- [ ] Todoist:"))
        XCTAssertTrue(pendingBenchmark.contains("- [ ] Linear:"))
        XCTAssertTrue(pendingBenchmark.contains("- [ ] Motion:"))
        XCTAssertTrue(pendingBenchmark.contains("## Ship / Defer / Reject To Fill"))
        XCTAssertFalse(pendingBenchmark.contains("Status: passed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: benchmarkURL.path))
        let worksheet = try String(contentsOf: worksheetURL, encoding: .utf8)
        XCTAssertTrue(worksheet.contains("# Competitor Hands-On Worksheet"))
        XCTAssertTrue(worksheet.contains("Status: pending"))
        XCTAssertTrue(worksheet.contains("This worksheet is not release evidence."))
        XCTAssertTrue(worksheet.contains("- Release candidate source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(worksheet.contains("- Output evidence: `\(pendingURL.path)`"))
        XCTAssertTrue(worksheet.contains("- Benchmark output: `\(pendingBenchmarkURL.path)`"))
        XCTAssertTrue(worksheet.contains("- Passed command: `\(commandURL.path)`"))
        XCTAssertTrue(worksheet.contains("## Review Context To Fill"))
        XCTAssertTrue(worksheet.contains("- Elapsed hands-on time with per-competitor timing:"))
        XCTAssertTrue(worksheet.contains("## Competitor Paths"))
        XCTAssertTrue(worksheet.contains("- [ ] Notion: create a project database"))
        XCTAssertTrue(worksheet.contains("- [ ] Todoist: capture with Quick Add"))
        XCTAssertTrue(worksheet.contains("- [ ] Linear: create a project and issue"))
        XCTAssertTrue(worksheet.contains("- [ ] Motion: create due/prioritized tasks"))
        XCTAssertTrue(worksheet.contains("## Ship / Defer / Reject Capture"))
        XCTAssertTrue(worksheet.contains("No external SaaS sync or team workflow was added to SoloPM public alpha scope."))
        XCTAssertFalse(worksheet.contains("Status: passed"))
        let generatedCommand = try String(contentsOf: commandURL, encoding: .utf8)
        XCTAssertTrue(generatedCommand.contains("# Generated by script/create_competitor_hands_on_evidence.sh."))
        XCTAssertTrue(generatedCommand.contains("# Fill \(worksheetURL.path) while reviewing, then replace every placeholder below."))
        XCTAssertTrue(generatedCommand.contains("REPO_ROOT="))
        XCTAssertTrue(generatedCommand.contains("cd \"$REPO_ROOT\""))
        XCTAssertTrue(generatedCommand.contains("EXPECTED_SOURCE_COMMIT=\(currentShortCommit)"))
        XCTAssertTrue(generatedCommand.contains("CURRENT_SOURCE_COMMIT=\"$(release_candidate_source_commit)\""))
        XCTAssertTrue(generatedCommand.contains("TRACKED_SOURCE_STATUS=\"$(git status --porcelain --untracked-files=no)\""))
        XCTAssertTrue(generatedCommand.contains("competitor hands-on evidence command requires a clean tracked source tree"))
        XCTAssertTrue(generatedCommand.contains("competitor hands-on evidence command was generated for source commit"))
        XCTAssertTrue(generatedCommand.contains("COMPETITOR_WORKSHEET_FILE=\(worksheetURL.path)"))
        XCTAssertTrue(generatedCommand.contains("COMPETITOR_BENCHMARK_WORKSHEET_FILE=\(pendingBenchmarkURL.path)"))
        XCTAssertTrue(generatedCommand.contains("verify_competitor_worksheet_for_evidence()"))
        XCTAssertTrue(generatedCommand.contains("verify_competitor_benchmark_worksheet_for_evidence()"))
        XCTAssertTrue(generatedCommand.contains("Status: completed"))
        XCTAssertTrue(generatedCommand.contains("Release candidate source commit: \\`$EXPECTED_SOURCE_COMMIT\\`"))
        XCTAssertTrue(generatedCommand.contains("Source commit: \\`$EXPECTED_SOURCE_COMMIT\\`"))
        XCTAssertTrue(generatedCommand.contains("grep -F -- \"- [ ]\" \"$COMPETITOR_WORKSHEET_FILE\""))
        XCTAssertTrue(generatedCommand.contains("grep -F -- \"- [ ]\" \"$COMPETITOR_BENCHMARK_WORKSHEET_FILE\""))
        XCTAssertTrue(generatedCommand.contains("competitor_worksheet_value_is_placeholder_or_boilerplate()"))
        XCTAssertTrue(generatedCommand.contains("fill %s with concrete competitor hands-on observation."))
        XCTAssertTrue(generatedCommand.contains("fill %s with concrete competitor benchmark observation."))
        XCTAssertTrue(generatedCommand.contains("competitor hands-on worksheet is missing, stale, or incomplete"))
        XCTAssertTrue(generatedCommand.contains("competitor benchmark worksheet is missing, stale, or incomplete"))
        XCTAssertTrue(generatedCommand.contains("Reviewer"))
        XCTAssertTrue(generatedCommand.contains("Elapsed hands-on time with per-competitor timing"))
        XCTAssertTrue(generatedCommand.contains("Ship"))
        let worksheetCheckRange = try XCTUnwrap(generatedCommand.range(of: "verify_competitor_worksheet_for_evidence"))
        let benchmarkWorksheetCheckRange = try XCTUnwrap(generatedCommand.range(of: "verify_competitor_benchmark_worksheet_for_evidence"))
        let validateCommandRange = try XCTUnwrap(generatedCommand.range(of: "# Validate the filled competitor hands-on command before writing tracked evidence."))
        XCTAssertLessThan(worksheetCheckRange.lowerBound, validateCommandRange.lowerBound)
        XCTAssertLessThan(benchmarkWorksheetCheckRange.lowerBound, validateCommandRange.lowerBound)
        XCTAssertTrue(generatedCommand.contains("# Validate the filled competitor hands-on command before writing tracked evidence."))
        XCTAssertTrue(generatedCommand.contains("./script/create_competitor_hands_on_evidence.sh --validate-only \\"))
        XCTAssertTrue(generatedCommand.contains("./script/create_competitor_hands_on_evidence.sh --passed \\"))
        XCTAssertTrue(generatedCommand.contains("--checked-by \"<reviewer name>\" \\"))
        XCTAssertTrue(generatedCommand.contains("--environment \"<macOS/browser versions, competitor app/account tiers, and paid trial details>\" \\"))
        XCTAssertTrue(generatedCommand.contains("--hands-on-duration \"<2-4h total, including Notion/Todoist/Linear/Motion timing>\" \\"))
        XCTAssertTrue(generatedCommand.contains("--notion-note \"<hands-on Notion project database, board, task, and artifact observation>\" \\"))
        XCTAssertTrue(generatedCommand.contains("--todoist-note \"<hands-on Todoist quick add, board/list, drag movement, Today/Upcoming observation>\" \\"))
        XCTAssertTrue(generatedCommand.contains("--linear-note \"<hands-on Linear project, issue detail, keyboard command, and triage observation>\" \\"))
        XCTAssertTrue(generatedCommand.contains("--motion-note \"<hands-on Motion scheduling, risk, deadline change, and recommendation explanation observation>\" \\"))
        XCTAssertTrue(generatedCommand.contains("--output \(pendingURL.path) \\"))
        XCTAssertTrue(generatedCommand.contains("--benchmark-output \(pendingBenchmarkURL.path) \\"))
        XCTAssertTrue(generatedCommand.contains("--confirm-manual-hands-on"))
        let releaseChecklist = try readPackageFile("docs/release/checklist.md")
        XCTAssertTrue(releaseChecklist.contains("Running the pending generator also writes `.tmp/competitor-hands-on/competitor-hands-on-pending-<commit>.md`, `.tmp/competitor-hands-on/hands-on-worksheet.md`, `.tmp/competitor-hands-on/competitor-benchmark-pending-<commit>.md`, and `.tmp/competitor-hands-on/create-evidence-command.sh` by default, so pending review prep does not modify tracked release evidence or the tracked benchmark document."))
        XCTAssertTrue(releaseChecklist.contains("The generated competitor hands-on command requires a clean tracked source tree, pins the release-candidate source commit it was created for, and exits before writing evidence if the worktree is dirty or has moved to another commit."))
        XCTAssertTrue(releaseChecklist.contains("The generated competitor hands-on command also verifies `.tmp/competitor-hands-on/hands-on-worksheet.md` and `.tmp/competitor-hands-on/competitor-benchmark-pending-<commit>.md` are marked completed, pinned to the same source commit, free of unchecked/pending/template markers, and filled before validate-only or passed evidence can run."))
        XCTAssertTrue(releaseChecklist.contains("The generated competitor hands-on command also rejects boilerplate worksheet values such as `TBD`, `Verified`, `OK`, or `No issues`; each required worksheet field must contain concrete hands-on observations."))
        XCTAssertTrue(releaseChecklist.contains("Run the generated competitor `--validate-only` command first; it performs the same passed-evidence validation without writing `docs/release/evidence/competitor-hands-on.md` or `docs/product/competitor-benchmark.md`."))
        XCTAssertTrue(releaseChecklist.contains("The competitor passed command requires `--hands-on-duration` with a real 2-4 hour total and per-competitor timing."))
        let phase11 = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        XCTAssertTrue(phase11.contains("[x] `script/create_competitor_hands_on_evidence.sh --pending` pins `.tmp/competitor-hands-on/create-evidence-command.sh` to a clean tracked source tree and the release-candidate source commit it was generated for"))
        XCTAssertTrue(phase11.contains("[x] `script/create_competitor_hands_on_evidence.sh --pending` はデフォルトで `.tmp/competitor-hands-on/competitor-hands-on-pending-<commit>.md` と `.tmp/competitor-hands-on/competitor-benchmark-pending-<commit>.md` を生成し、tracked evidence / benchmarkをpending worksheetで汚さずfinal benchmark更新漏れを防ぐ。"))
        XCTAssertTrue(phase11.contains("[x] `script/create_competitor_hands_on_evidence.sh --validate-only` validates the filled manual command without writing tracked evidence or benchmark findings."))
        XCTAssertTrue(phase11.contains("[x] competitor hands-on passed evidence requires elapsed 2-4 hour timing with Notion/Todoist/Linear/Motion coverage."))
        XCTAssertTrue(phase11.contains("[x] Generated competitor hands-on evidence command verifies `.tmp/competitor-hands-on/hands-on-worksheet.md` and `.tmp/competitor-hands-on/competitor-benchmark-pending-<commit>.md` are current, marked completed, filled, and free of pending/unchecked markers before validation or passed evidence."))
        XCTAssertTrue(phase11.contains("[x] Generated competitor hands-on evidence command rejects boilerplate worksheet values such as `TBD`, `Verified`, `OK`, or `No issues`; each required worksheet field must contain concrete hands-on observations."))
        let generatedCommandResult = try runTool(["bash", commandURL.path])
        XCTAssertNotEqual(generatedCommandResult.exitCode, 0)
        XCTAssertTrue(
            generatedCommandResult.output.contains("competitor hands-on evidence command requires a clean tracked source tree")
                || generatedCommandResult.output.contains("--checked-by must name the actual reviewer")
                || generatedCommandResult.output.contains("competitor hands-on worksheet is missing, stale, or incomplete")
                || generatedCommandResult.output.contains("competitor benchmark worksheet is missing, stale, or incomplete")
        )

        try """
        # Competitor Hands-On Worksheet

        Status: completed

        ## Candidate Metadata

        - Release candidate source commit: `\(currentShortCommit)`
        - Output evidence: `\(pendingURL.path)`
        - Benchmark output: `\(pendingBenchmarkURL.path)`
        - Passed command: `\(commandURL.path)`

        ## Review Context

        - Reviewer: SoloPM Product Reviewer
        - Review date: 2026-06-19
        - macOS version: macOS 15.5
        - Browser / desktop app versions: Safari 26, Notion web, Todoist web, Linear web, Motion web
        - Account tiers / paid trial details: Notion Free, Todoist Free, Linear Free, Motion trial not used
        - Elapsed hands-on time with per-competitor timing: 2h 15m total: Notion 35m, Todoist 30m, Linear 35m, Motion 35m
        - Screenshot or note locations kept outside release evidence: local reviewer notes only

        ## Measurements

        - Setup steps before first useful task: Notion required schema setup; Todoist was fastest for capture.
        - Clicks / keystrokes for capture and status movement: Todoist quick add was fastest; Linear keyboard flow was strong but team-oriented.
        - Inspector/detail clarity for repeated solo PM work: SoloPM inspector remained more focused on solo task edits.
        - Automation or recommendation trust issues: Motion recommendations required visible reasoning before adoption.

        ## Ship / Defer / Reject Capture

        - Ship: Keep fast local capture, board status movement, and the right inspector as the alpha loop.
        - Defer: Natural-language scheduling until reliability evidence is stronger.
        - Reject: Team cycles, initiatives, and external SaaS sync for public alpha.
        """.write(to: worksheetURL, atomically: true, encoding: .utf8)

        let missingBenchmarkWorksheetResult = try runTool(["bash", commandURL.path])
        XCTAssertNotEqual(missingBenchmarkWorksheetResult.exitCode, 0)
        XCTAssertTrue(missingBenchmarkWorksheetResult.output.contains("competitor benchmark worksheet is missing, stale, or incomplete"))
        XCTAssertFalse(missingBenchmarkWorksheetResult.output.contains("--checked-by must name the actual reviewer"))

        let unsafePassedResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--output", passedURL.path,
                "--benchmark-output", benchmarkURL.path
            ]
        )
        XCTAssertNotEqual(unsafePassedResult.exitCode, 0)
        XCTAssertTrue(unsafePassedResult.output.contains("--confirm-manual-hands-on is required with --passed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: benchmarkURL.path))

        let missingNotesResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(missingNotesResult.exitCode, 0)
        XCTAssertTrue(missingNotesResult.output.contains("--notion-note is required with --passed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: benchmarkURL.path))

        let missingDurationResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--benchmark-output", benchmarkURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(missingDurationResult.exitCode, 0)
        XCTAssertTrue(missingDurationResult.output.contains("--hands-on-duration is required with --passed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: benchmarkURL.path))

        let shortDurationResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--hands-on-duration", "45m total: Notion 10m, Todoist 10m, Linear 15m, Motion 10m",
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--benchmark-output", benchmarkURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(shortDurationResult.exitCode, 0)
        XCTAssertTrue(shortDurationResult.output.contains("--hands-on-duration must describe a real 2-4 hour hands-on pass"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: benchmarkURL.path))

        let placeholderEnvironmentResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS/browser versions, competitor app/account tiers, and whether any paid trial was used",
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(placeholderEnvironmentResult.exitCode, 0)
        XCTAssertTrue(placeholderEnvironmentResult.output.contains("--environment must describe the actual hands-on environment"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let placeholderReviewerResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "Reviewer Name",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(placeholderReviewerResult.exitCode, 0)
        XCTAssertTrue(placeholderReviewerResult.output.contains("--checked-by must name the actual reviewer"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let angleBracketPlaceholderReviewerResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "<reviewer name>",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--hands-on-duration", handsOnDuration,
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(angleBracketPlaceholderReviewerResult.exitCode, 0)
        XCTAssertTrue(angleBracketPlaceholderReviewerResult.output.contains("--checked-by must name the actual reviewer"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let invalidDateResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "June 19, 2026",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(invalidDateResult.exitCode, 0)
        XCTAssertTrue(invalidDateResult.output.contains("--check-date must use YYYY-MM-DD"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let invalidCalendarDateResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-02-31",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(invalidCalendarDateResult.exitCode, 0)
        XCTAssertTrue(invalidCalendarDateResult.output.contains("--check-date must use YYYY-MM-DD"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let futureDateResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2099-01-01",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(futureDateResult.exitCode, 0)
        XCTAssertTrue(futureDateResult.output.contains("--check-date must not be in the future"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let boilerplateNoteResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--notion-note", "Verified.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(boilerplateNoteResult.exitCode, 0)
        XCTAssertTrue(boilerplateNoteResult.output.contains("--notion-note must include concrete competitor hands-on details"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let copiedTemplateNoteResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--hands-on-duration", handsOnDuration,
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Concrete Todoist observation from the hands-on pass.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(copiedTemplateNoteResult.exitCode, 0)
        XCTAssertTrue(copiedTemplateNoteResult.output.contains("--todoist-note must include concrete competitor hands-on details"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let generatedTemplateNoteResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--notion-note", "<hands-on Notion project database, board, task, and artifact observation>",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(generatedTemplateNoteResult.exitCode, 0)
        XCTAssertTrue(generatedTemplateNoteResult.output.contains("--notion-note must include concrete competitor hands-on details"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let copiedDecisionTemplateResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--hands-on-duration", handsOnDuration,
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "SoloPM public-alpha behavior to ship based on the benchmark.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(copiedDecisionTemplateResult.exitCode, 0)
        XCTAssertTrue(copiedDecisionTemplateResult.output.contains("--ship must include concrete competitor hands-on details"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let generatedDecisionTemplateResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--hands-on-duration", handsOnDuration,
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "<behaviors deliberately kept out of public alpha scope>",
                "--output", passedURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(generatedDecisionTemplateResult.exitCode, 0)
        XCTAssertTrue(generatedDecisionTemplateResult.output.contains("--reject must include concrete competitor hands-on details"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: passedURL.path))

        let validateOnlyResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--validate-only",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--hands-on-duration", handsOnDuration,
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", validateOnlyURL.path,
                "--benchmark-output", benchmarkURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertEqual(validateOnlyResult.exitCode, 0, validateOnlyResult.output)
        XCTAssertTrue(validateOnlyResult.output.contains("OK: competitor hands-on evidence command is valid for current source commit"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: validateOnlyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: benchmarkURL.path))

        let validateOnlyPlaceholderResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--validate-only",
                "--checked-by", "<reviewer name>",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", validateOnlyURL.path,
                "--benchmark-output", benchmarkURL.path,
                "--confirm-manual-hands-on"
            ]
        )
        XCTAssertNotEqual(validateOnlyPlaceholderResult.exitCode, 0)
        XCTAssertTrue(validateOnlyPlaceholderResult.output.contains("--checked-by must name the actual reviewer"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: validateOnlyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: benchmarkURL.path))

        let passedResult = try runScript(
            "script/create_competitor_hands_on_evidence.sh",
            arguments: [
                "--passed",
                "--checked-by", "SoloPM Product Reviewer",
                "--check-date", "2026-06-19",
                "--environment", "macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used",
                "--hands-on-duration", handsOnDuration,
                "--notion-note", "Board setup was flexible but required manual schema decisions before task entry felt fast.",
                "--todoist-note", "Quick Add made capture fast, but project context still needed review after entry.",
                "--linear-note", "Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.",
                "--motion-note", "Scheduling suggestions were useful only when the reason and deadline impact were visible.",
                "--ship", "Keep fast local capture, board status movement, and right inspector as the public alpha loop.",
                "--defer", "Natural-language dates and autonomous scheduling stay out until reliability evidence exists.",
                "--reject", "Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.",
                "--output", passedURL.path,
                "--benchmark-output", benchmarkURL.path,
                "--confirm-manual-hands-on"
            ]
        )

        XCTAssertEqual(passedResult.exitCode, 0, passedResult.output)
        let passedEvidence = try String(contentsOf: passedURL, encoding: .utf8)
        XCTAssertTrue(passedEvidence.contains("Status: passed"))
        XCTAssertTrue(passedEvidence.contains("Generated by: script/create_competitor_hands_on_evidence.sh"))
        XCTAssertTrue(passedEvidence.contains("- Checked by: SoloPM Product Reviewer"))
        XCTAssertTrue(passedEvidence.contains("- Source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(passedEvidence.contains("- Check date: 2026-06-19"))
        XCTAssertTrue(passedEvidence.contains("- Environment: macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used"))
        XCTAssertTrue(passedEvidence.contains("- Elapsed hands-on time: \(handsOnDuration)"))
        XCTAssertTrue(passedEvidence.contains("- Notion: passed - Board setup was flexible but required manual schema decisions before task entry felt fast."))
        XCTAssertTrue(passedEvidence.contains("- Todoist: passed - Quick Add made capture fast, but project context still needed review after entry."))
        XCTAssertTrue(passedEvidence.contains("- Linear: passed - Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work."))
        XCTAssertTrue(passedEvidence.contains("- Motion: passed - Scheduling suggestions were useful only when the reason and deadline impact were visible."))
        XCTAssertTrue(passedEvidence.contains("No external SaaS sync or team workflow was added to SoloPM public alpha scope"))
        XCTAssertTrue(passedEvidence.contains("Ship / Defer / Reject Delta"))
        XCTAssertTrue(passedEvidence.contains("- Ship: Keep fast local capture, board status movement, and right inspector as the public alpha loop."))
        XCTAssertTrue(passedEvidence.contains("- Defer: Natural-language dates and autonomous scheduling stay out until reliability evidence exists."))
        XCTAssertTrue(passedEvidence.contains("- Reject: Team cycles, initiatives, and external SaaS sync stay outside public alpha scope."))
        XCTAssertTrue(passedEvidence.contains("## Failure Notes"))
        XCTAssertTrue(passedEvidence.contains("- Blocker observed: none during the competitor hands-on pass."))
        XCTAssertTrue(passedEvidence.contains("- Follow-up source/test link: `docs/product/competitor-benchmark.md` hands-on benchmark closure."))
        XCTAssertFalse(passedEvidence.localizedCaseInsensitiveContains("pending"))
        XCTAssertFalse(passedEvidence.contains("- [ ]"))
        XCTAssertFalse(passedEvidence.localizedCaseInsensitiveContains("placeholder"))
        let benchmark = try String(contentsOf: benchmarkURL, encoding: .utf8)
        XCTAssertTrue(benchmark.contains("# Competitor Benchmark and Hands-On Findings"))
        XCTAssertTrue(benchmark.contains("Source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(benchmark.contains("Elapsed hands-on time: \(handsOnDuration)"))
        XCTAssertTrue(benchmark.contains("## Hands-On Findings"))
        XCTAssertTrue(benchmark.contains("Notion: Board setup was flexible but required manual schema decisions before task entry felt fast."))
        XCTAssertTrue(benchmark.contains("Todoist: Quick Add made capture fast, but project context still needed review after entry."))
        XCTAssertTrue(benchmark.contains("Linear: Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work."))
        XCTAssertTrue(benchmark.contains("Motion: Scheduling suggestions were useful only when the reason and deadline impact were visible."))
        XCTAssertTrue(benchmark.contains("## Ship / Defer / Reject"))
        XCTAssertTrue(benchmark.contains("Ship: Keep fast local capture, board status movement, and right inspector as the public alpha loop."))
        XCTAssertTrue(benchmark.contains("Defer: Natural-language dates and autonomous scheduling stay out until reliability evidence exists."))
        XCTAssertTrue(benchmark.contains("Reject: Team cycles, initiatives, and external SaaS sync stay outside public alpha scope."))
        XCTAssertFalse(benchmark.localizedCaseInsensitiveContains("release candidate hands-on worksheet"))
        XCTAssertFalse(benchmark.localizedCaseInsensitiveContains("not a full hands-on trial record"))
        XCTAssertFalse(benchmark.localizedCaseInsensitiveContains("manual evidence to attach after the pass"))
    }

    func testReleaseReadinessReportFailsWhenCompetitorEvidenceLacksConcreteNotes() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-weak-competitor-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let productDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("product", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: productDirectory, withIntermediateDirectories: true)
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
        # Competitor Hands-On Evidence

        Status: passed
        Generated by: script/create_competitor_hands_on_evidence.sh

        ## Review Context

        - Checked by: SoloPM Product Reviewer
        - Check date: 2026-02-31
        - Evidence source: `Real local hands-on pass`
        - Elapsed hands-on time: 45m total: Notion 10m, Todoist 10m, Linear 15m, Motion 10m
        - Scope: Notion -> Todoist -> Linear -> Motion

        ## Verified Hands-On Path

        - Notion: passed - Verified.
        - Todoist: passed - Concrete Todoist observation from the hands-on pass.
        - Linear: passed - hands-on Linear project, issue detail, keyboard command, and triage observation
        - Motion: passed - hands-on Motion dated task, prioritization, schedule/risk explanation observation
        - No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.

        ## Ship / Defer / Reject Delta

        - Ship: SoloPM behavior to ship now based on the hands-on benchmark.
        - Defer: behavior deferred until reliability or demand evidence is stronger.
        - Reject: behaviors deliberately kept out of public alpha scope.
        """.write(to: evidenceDirectory.appendingPathComponent("competitor-hands-on.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Benchmark and Feature Fit

        Scope: Notion, Todoist, Linear, and Motion were reviewed from official product/help/docs pages. This is not a full hands-on trial record.

        ## Release Candidate Hands-On Worksheet

        Manual evidence to attach after the pass:
        - Date, reviewer, macOS/browser/app versions, account tier used, and whether a paid trial was required.
        """.write(to: productDirectory.appendingPathComponent("competitor-benchmark.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has invalid review context date: Check date"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence missing review context: Environment"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has invalid elapsed hands-on time"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has boilerplate concrete note: Notion"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has boilerplate concrete note: Todoist"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has boilerplate concrete note: Linear"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has boilerplate concrete note: Motion"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has boilerplate decision delta: Ship"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has boilerplate decision delta: Defer"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has boilerplate decision delta: Reject"))
        XCTAssertTrue(result.output.contains("Competitor benchmark still reads as desk research or a hands-on worksheet"))
        XCTAssertTrue(result.output.contains("./script/prepare_release_manual_helpers.sh"))
        XCTAssertTrue(result.output.contains(".tmp/competitor-hands-on/competitor-benchmark-pending-"))
        XCTAssertTrue(result.output.contains(".tmp/competitor-hands-on/create-evidence-command.sh"))
        XCTAssertTrue(result.output.contains("./script/create_competitor_hands_on_evidence.sh --passed"))
        XCTAssertTrue(result.output.contains("--benchmark-output docs/product/competitor-benchmark.md"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportAllowsHandsOnBenchmarkWithOfficialSourceLinks() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-hands-on-benchmark-sources", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let productDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("product", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: productDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }
        let currentShortCommit = try currentShortGitCommit()

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try """
        # Competitor Hands-On Evidence

        Status: passed
        Generated by: script/create_competitor_hands_on_evidence.sh

        ## Review Context

        - Checked by: SoloPM Product Reviewer
        - Check date: 2026-06-19
        - Source commit: `\(currentShortCommit)`
        - Evidence source: `Hands-on local account notes plus official source links`
        - Environment: macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used
        - Elapsed hands-on time: 2h 15m total: Notion 35m, Todoist 30m, Linear 35m, Motion 35m
        - Scope: Notion -> Todoist -> Linear -> Motion

        ## Verified Hands-On Path

        - Notion: passed - Created a project database, switched to board view, added three cards, and confirmed setup choices before the first useful task were heavier than SoloPM.
        - Todoist: passed - Used Quick Add with project and priority, switched to board layout, and confirmed capture was fast but destination review still mattered.
        - Linear: passed - Created a project issue, moved status, opened detail sidebar, and confirmed keyboard operation was strong but team concepts were outside SoloPM alpha scope.
        - Motion: passed - Created dated priority tasks and reviewed scheduling/risk surfaces, confirming recommendations need visible reasoning before applying.
        - No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.

        ## Ship / Defer / Reject Delta

        - Ship: Keep local Inbox capture, board movement, and the right inspector because the hands-on pass showed those are the fastest repeated execution path.
        - Defer: Keep natural-language dates and autonomous scheduling out until local date parsing and calendar trust have stronger evidence.
        - Reject: Keep team cycles, initiatives, and external SaaS sync outside public alpha because the benchmark did not improve the solo local-first loop.
        """.write(to: evidenceDirectory.appendingPathComponent("competitor-hands-on.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Benchmark and Feature Fit

        Verified: 2026-06-19

        Source commit: `\(currentShortCommit)`

        Official references: official product/help/docs pages are retained as links next to the hands-on notes.

        ## Hands-On Findings

        - Notion: The hands-on board setup confirmed flexible structure is powerful, but first useful task capture is slower than SoloPM's fixed project/task model.
        - Todoist: The hands-on Quick Add and board pass confirmed capture speed is the bar SoloPM must match with Inbox and menu bar entry.
        - Linear: The hands-on project and issue detail pass confirmed the right inspector and keyboard shortcuts are worth shipping for repeated CRUD.
        - Motion: The hands-on scheduling pass confirmed risk suggestions need visible reasoning and should not auto-apply in the public alpha.

        ## Ship / Defer / Reject

        - Ship: Fast Inbox capture, board status movement, and right-inspector CRUD.
        - Defer: Natural-language dates, calendar layout, and autonomous scheduling until reliability evidence exists.
        - Reject: Arbitrary database builders, team cycles, initiatives, and external SaaS sync for public alpha.
        """.write(to: productDirectory.appendingPathComponent("competitor-benchmark.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.output.contains("Competitor benchmark source commit does not match current release-candidate source commit"))
        XCTAssertFalse(result.output.contains("Competitor benchmark still reads as desk research or a hands-on worksheet"))
        XCTAssertFalse(result.output.contains("Competitor benchmark missing hands-on marker"))
        XCTAssertTrue(result.output.contains("OK: competitor hands-on evidence covers Notion, Todoist, Linear, Motion, and public alpha scope boundaries"))
    }

    func testReleaseReadinessReportRejectsStaleCompetitorBenchmarkSourceCommit() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-stale-competitor-benchmark", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let productDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("product", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: productDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }
        let currentShortCommit = try currentShortGitCommit()

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try """
        # Competitor Hands-On Evidence

        Status: passed

        ## Review Context

        - Checked by: SoloPM Product Reviewer
        - Check date: 2026-06-19
        - Source commit: `\(currentShortCommit)`
        - Evidence source: `Hands-on local account notes plus official source links`
        - Environment: macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used
        - Elapsed hands-on time: 2h 15m total: Notion 35m, Todoist 30m, Linear 35m, Motion 35m
        - Scope: Notion -> Todoist -> Linear -> Motion

        ## Verified Hands-On Path

        - Notion: passed - Created a project database, switched to board view, added three cards, and confirmed setup choices before first useful task were heavier than SoloPM.
        - Todoist: passed - Used Quick Add with project and priority, switched to board layout, and confirmed capture was fast but destination review still mattered.
        - Linear: passed - Created a project issue, moved status, opened detail sidebar, and confirmed keyboard operation was strong but team concepts were outside SoloPM alpha scope.
        - Motion: passed - Created dated priority tasks and reviewed scheduling/risk surfaces, confirming recommendations need visible reasoning before applying.
        - No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.

        ## Ship / Defer / Reject Delta

        - Ship: Keep local Inbox capture, board movement, and the right inspector because the hands-on pass showed those are the fastest repeated execution path.
        - Defer: Keep natural-language dates and autonomous scheduling out until local date parsing and calendar trust have stronger evidence.
        - Reject: Keep team cycles, initiatives, and external SaaS sync outside public alpha because the benchmark did not improve the solo local-first loop.
        """.write(to: evidenceDirectory.appendingPathComponent("competitor-hands-on.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Benchmark and Feature Fit

        Verified: 2026-06-19

        Source commit: `deadbee`

        ## Hands-On Findings

        - Notion: The hands-on board setup confirmed flexible structure is powerful, but first useful task capture is slower than SoloPM's fixed project/task model.
        - Todoist: The hands-on Quick Add and board pass confirmed capture speed is the bar SoloPM must match with Inbox and menu bar entry.
        - Linear: The hands-on project and issue detail pass confirmed the right inspector and keyboard shortcuts are worth shipping for repeated CRUD.
        - Motion: The hands-on scheduling pass confirmed risk suggestions need visible reasoning and should not auto-apply in the public alpha.

        ## Ship / Defer / Reject

        - Ship: Fast Inbox capture, board status movement, and right-inspector CRUD.
        - Defer: Natural-language dates, calendar layout, and autonomous scheduling until reliability evidence exists.
        - Reject: Arbitrary database builders, team cycles, initiatives, and external SaaS sync for public alpha.
        """.write(to: productDirectory.appendingPathComponent("competitor-benchmark.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Competitor benchmark source commit does not match current release-candidate source commit"))
        XCTAssertFalse(result.output.contains("Competitor hands-on evidence source commit does not match current release-candidate source commit"))
        XCTAssertFalse(result.output.contains("Competitor benchmark still reads as desk research or a hands-on worksheet"))
        XCTAssertFalse(result.output.contains("Competitor benchmark missing hands-on marker"))
    }

    func testLocalCRUDSmokeScriptRunsFocusedPersistentStoreToolAndCLIPaths() throws {
        let script = try readPackageFile("script/check_local_crud_smoke.sh")

        XCTAssertTrue(script.contains("swift test --filter \"$FOCUSED_CRUD_FILTER\""))
        XCTAssertTrue(script.contains("ProjectBoardStoreTests/testCreateTaskPersistsRequestedColumnMetadataAndDetail"))
        XCTAssertTrue(script.contains("ProjectBoardStoreTests/testUpdateTaskMovesCardAcrossColumnsAndUpdatesMetadata"))
        XCTAssertTrue(script.contains("ProjectBoardStoreTests/testMoveTaskPersistsNewStatusWithoutLosingMetadata"))
        XCTAssertTrue(script.contains("ProjectBoardStoreTests/testDeleteTaskRemovesCardFromPersistentSnapshot"))
        XCTAssertTrue(script.contains("ProjectBoardStoreTests/testCreateUpdateAndCompleteProjectAppearInBoardSnapshot"))
        XCTAssertTrue(script.contains("ProjectBoardStoreTests/testArchivedProjectCanBeLoadedAndRestoredToActiveBoard"))
        XCTAssertTrue(script.contains("ProjectBoardStoreTests/testProjectBoardViewModelQuickCapturePersistsToSQLiteInbox"))
        XCTAssertTrue(script.contains("ProjectTaskKnowledgeToolTests/testTaskUpdateToolPersistsEditableTaskMetadataAndMovesProject"))
        XCTAssertTrue(script.contains("ProjectTaskKnowledgeToolTests/testProjectDeleteToolDeletesPersistentProjectGraphWithApproval"))
        XCTAssertTrue(script.contains("SoloPMCLIReadOnlyReporterTests/testStatusReadsPersistentProjectTaskAndKnowledgeCounts"))
        XCTAssertTrue(script.contains("SoloPMCLIReadOnlyReporterTests/testTasksDueReadsDueTasksAndExcludesCompletedArchivedOrCompletedProjectTasks"))
        XCTAssertTrue(script.contains("OK: local CRUD smoke covered SQLite project/task CRUD, project lifecycle, MCP tool mutations, quick capture, and CLI read paths"))
        XCTAssertFalse(script.contains("swift test\n"))
    }

    func testRuntimeAccessibleCRUDSmokeScriptLaunchesIsolatedAppAndVerifiesSQLiteMutations() throws {
        let script = try readPackageFile("script/check_runtime_accessible_crud_smoke.sh")

        XCTAssertTrue(script.contains("SOLOPM_DATABASE_PATH"))
        XCTAssertTrue(script.contains("APP_BINARY=\"$APP_BUNDLE/Contents/MacOS/$APP_NAME\""))
        XCTAssertTrue(script.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH=\"$database_path\" \"$APP_BINARY\" &"))
        XCTAssertTrue(script.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"project:$seed_project_id\""))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"projects\""))
        XCTAssertTrue(script.contains("app_pid=$!"))
        XCTAssertTrue(script.contains("wait \"$app_pid\" >/dev/null 2>&1 || true"))
        XCTAssertTrue(script.contains("wait_for_visible_windows()"))
        XCTAssertGreaterThanOrEqual(script.components(separatedBy: "wait_for_visible_windows").count - 1, 4)
        XCTAssertFalse(script.contains("open -n -F --env \"SOLOPM_DATABASE_PATH=$database_path\""))
        XCTAssertTrue(script.contains("./script/build_and_run.sh --build-only"))
        XCTAssertFalse(script.contains("script/check_accessibility_preflight.sh --runtime --skip-launch"))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"created project\" \"project-board-add-project\""))
        XCTAssertTrue(script.contains("created_project_id=\"$(wait_for_nonempty_value \"created project id\""))
        XCTAssertGreaterThanOrEqual(script.components(separatedBy: "launch_app_for_seed_project \"$created_project_id\"").count - 1, 2)
        XCTAssertTrue(script.contains("value of attribute \"AXIdentifier\" of axItem as text"))
        XCTAssertTrue(script.contains("set frontmost to true"))
        XCTAssertTrue(script.contains("set windowCount to count of windows"))
        XCTAssertTrue(script.contains("repeat with windowIndex from 1 to windowCount"))
        XCTAssertTrue(script.contains("perform action \"AXRaise\" of currentWindow"))
        XCTAssertFalse(script.contains("set currentWindow to window 1"))
        XCTAssertTrue(script.contains("key code 51"))
        XCTAssertTrue(script.contains("key code 48"))
        XCTAssertFalse(script.contains("set value of axItem to replacement"))
        XCTAssertTrue(script.contains("waitForTextFieldContaining \"project-inspector-title\""))
        XCTAssertTrue(script.contains("setTextFieldContaining \"project-inspector-title\" \"AX Runtime CRUD Project\""))
        XCTAssertTrue(script.contains("waitForTextFieldContaining \"AX Runtime CRUD Project\""))
        XCTAssertTrue(script.contains("pressButtonContaining \"project-inspector-save\""))
        XCTAssertTrue(script.contains("pressButtonUntilTextFieldContaining()"))
        XCTAssertTrue(script.contains("textFieldContainingExists()"))
        XCTAssertTrue(script.contains("pressButtonUntilTextFieldContaining \"project-header-add-task\" \"inline-task-title\""))
        XCTAssertTrue(script.contains("waitForTextFieldContaining \"inline-task-title\""))
        XCTAssertTrue(script.contains("setTextFieldContaining \"inline-task-title\" \"AX Runtime CRUD Task\""))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"created task\" \"inline-task-create\""))
        XCTAssertTrue(script.contains("pressButtonContaining \"task-card-open-details\""))
        XCTAssertTrue(script.contains("waitForTextFieldContaining \"task-inspector-title\""))
        XCTAssertTrue(script.contains("setTextFieldContaining \"task-inspector-title\" \"AX Runtime CRUD Task Updated\""))
        XCTAssertTrue(script.contains("waitForTextFieldContaining \"AX Runtime CRUD Task Updated\""))
        XCTAssertTrue(script.contains("pressButtonContaining \"task-inspector-save\""))
        XCTAssertTrue(script.contains("pressButtonContaining \"task-status-move-planned-$created_task_id\""))
        XCTAssertTrue(script.contains("pressDestructiveButtonUntilSQLiteValue()"))
        XCTAssertTrue(script.contains("verify_single_value \"$label waits for confirmation\" \"$sql\" \"$before_confirmation_expected\""))
        XCTAssertTrue(script.contains("BLOCKER: $label mutated before confirmation"))
        XCTAssertTrue(script.contains("local confirmation_fallback=\"$4\""))
        XCTAssertTrue(script.contains("pressConfirmationButtonContaining \"$confirmation_fragment\" \"$confirmation_fallback\" \"$excluded_help\""))
        XCTAssertTrue(script.contains("set fallbackFragment to item 3 of argv"))
        XCTAssertTrue(script.contains("set matchesFallback to false"))
        XCTAssertTrue(script.contains("if fallbackFragment is not \"\" and signalText contains fallbackFragment then set matchesFallback to true"))
        XCTAssertTrue(script.contains("if isEnabled and (matchesPrimary or matchesFallback) and (excludedHelp is \"\" or not (signalText contains excludedHelp)) then"))
        XCTAssertTrue(script.contains("pressDestructiveButtonUntilSQLiteValue \"deleted task\" \"task-inspector-delete\" \"task-inspector-delete-confirmation-confirm\" \"Confirm Delete Task\" \"\" \"SELECT count(*) FROM tasks WHERE id=$created_task_id;\" \"0\" \"1\""))
        XCTAssertTrue(script.contains("INFO: SQLite postcondition for $label was not met after pressing confirmation '$confirmation_fragment'; retrying destructive AX flow."))
        XCTAssertTrue(script.contains("waitForAXElementContaining()"))
        XCTAssertTrue(script.contains("setTextFieldContaining \"inline-task-title\" \"AX Runtime Execution Task\""))
        XCTAssertTrue(script.contains("setTextFieldContaining \"inline-task-detail\" \"Execute this runtime task through the approved plan.\""))
        XCTAssertTrue(script.contains("pressButtonContaining \"task-auto-execution-review\""))
        XCTAssertTrue(script.contains("pressButtonContaining \"task-auto-execution-run-plan\""))
        XCTAssertTrue(script.contains("verify_single_value \"executed task status\" \"SELECT status FROM tasks WHERE id=$execution_task_id;\" \"in_progress\""))
        XCTAssertTrue(script.contains("verify_single_value \"executed task detail marker\" \"SELECT CASE WHEN detail LIKE '%SoloPM approved automation execution%' THEN 1 ELSE 0 END FROM tasks WHERE id=$execution_task_id;\" \"1\""))
        XCTAssertTrue(script.contains("waitForAXElementContaining \"approved-execution-receipt\" \"AX Runtime Execution Task\" \"Execute this runtime task through the approved plan.\""))
        XCTAssertTrue(script.contains("setTextFieldContaining \"inline-task-title\" \"AX Runtime Cascade Task\""))
        XCTAssertTrue(script.contains("activate_app()"))
        XCTAssertTrue(script.contains("set isEnabled to enabled of axItem as boolean"))
        XCTAssertTrue(script.contains("if isEnabled and signalText contains fragment then"))
        XCTAssertTrue(script.contains("local deadline=$((SECONDS + TIMEOUT_SECONDS))"))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue()"))
        XCTAssertTrue(script.contains("INFO: SQLite postcondition for $label was not met after pressing '$fragment'; retrying AX press."))
        let pressButtonStart = try XCTUnwrap(script.range(of: "pressButtonContaining() {"))
        let confirmationButtonStart = try XCTUnwrap(script.range(of: "pressConfirmationButtonContaining() {"))
        let pressButtonFunction = String(script[pressButtonStart.lowerBound..<confirmationButtonStart.lowerBound])
        XCTAssertTrue(pressButtonFunction.contains("activate_app\n    wait_for_visible_windows >/dev/null 2>&1 || true\n    sleep 1"))
        XCTAssertTrue(script.contains("BLOCKER: failed to press button in AX tree"))
        XCTAssertTrue(script.contains("BLOCKER: failed to press confirmation button in AX tree"))
        XCTAssertTrue(script.contains("BLOCKER: failed to set text field in AX tree"))
        XCTAssertTrue(script.contains("kill \"$osascript_pid\""))
        XCTAssertFalse(script.contains("/usr/bin/osascript -e \"tell application \\\"$APP_NAME\\\" to activate\" >/dev/null 2>&1 || true"))
        XCTAssertFalse(script.contains("tell application \"$APP_NAME\" to activate"))
        XCTAssertFalse(script.contains("tell application \"$APP_NAME\" to quit"))
        XCTAssertTrue(script.contains("if not (exists process appName) then return \"missing\""))
        XCTAssertGreaterThanOrEqual(script.components(separatedBy: "waitForTextFieldContaining \"project-inspector-title\"").count - 1, 2)
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"completed project\" \"project-inspector-complete\""))
        XCTAssertTrue(script.contains("pressDestructiveButtonUntilSQLiteValue \"deleted project\" \"project-inspector-delete\" \"project-inspector-delete-confirmation-confirm\" \"Confirm Delete Project\" \"\" \"SELECT count(*) FROM projects WHERE id=$created_project_id;\" \"0\" \"1\""))
        XCTAssertFalse(script.contains("pressButtonContaining \"Creates a new local project\""))
        XCTAssertFalse(script.contains("verify_single_value \"created project\""))
        XCTAssertTrue(script.contains("verify_single_value \"renamed project\""))
        XCTAssertFalse(script.contains("verify_single_value \"created task\""))
        XCTAssertTrue(script.contains("verify_single_value \"renamed task\""))
        XCTAssertTrue(script.contains("verify_single_value \"advanced task status\""))
        XCTAssertTrue(script.contains("verify_single_value \"executed task status\""))
        XCTAssertTrue(script.contains("verify_single_value \"executed task detail marker\""))
        XCTAssertFalse(script.contains("verify_single_value \"deleted task\""))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"created cascade task\" \"inline-task-create\""))
        XCTAssertFalse(script.contains("verify_single_value \"created cascade task\""))
        XCTAssertFalse(script.contains("verify_single_value \"completed project\""))
        XCTAssertFalse(script.contains("verify_single_value \"deleted project\""))
        XCTAssertTrue(script.contains("verify_single_value \"deleted task cascade\""))
        XCTAssertTrue(script.contains("OK: runtime accessible CRUD smoke created, renamed, completed, and deleted a project, then created, updated, moved, executed approved task content with a readable AX receipt, directly deleted, and cascade-deleted tasks through the visible app"))
        XCTAssertFalse(script.contains(":memory:"))
        XCTAssertFalse(script.contains("Static"))
    }

    func testRuntimeWorkflowSmokeScriptDefinesScenarioRegistryAndFailureArtifacts() throws {
        let script = try readPackageFile("script/check_runtime_workflow_smoke.sh")

        XCTAssertTrue(script.contains("SCENARIOS=(\"project_task_crud\" \"inbox_triage\" \"today_complete\" \"settings_save\" \"voice_review\" \"development_pr\" \"schedule_cockpit\")"))
        for scenario in [
            "project_task_crud",
            "inbox_triage",
            "today_complete",
            "settings_save",
            "voice_review",
            "development_pr",
            "schedule_cockpit"
        ] {
            XCTAssertTrue(script.contains("run_\(scenario)()"), "workflow smoke must define \(scenario)")
            XCTAssertTrue(script.contains("write_scenario_artifact \"\(scenario)\""))
        }

        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_WORKFLOW_ARTIFACT_DIR"))
        XCTAssertTrue(script.contains("last_visible_window_context()"))
        XCTAssertTrue(script.contains("scenario_reason"))
        XCTAssertTrue(script.contains("scenario_status=\"failed\""))
        XCTAssertTrue(script.contains("./script/check_runtime_accessible_crud_smoke.sh"))
        XCTAssertTrue(script.contains("./script/check_runtime_inbox_triage_smoke.sh"))
        XCTAssertTrue(script.contains("./script/check_runtime_today_complete_smoke.sh"))
        XCTAssertTrue(script.contains("./script/check_runtime_settings_save_smoke.sh"))
        XCTAssertTrue(script.contains("./script/check_runtime_voice_review_smoke.sh"))
        XCTAssertTrue(script.contains("./script/check_runtime_development_pr_smoke.sh"))
        XCTAssertTrue(script.contains("./script/check_runtime_schedule_cockpit_smoke.sh"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_ACCESSIBLE_CRUD_KEEP_DATABASE=1"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_INBOX_TRIAGE_KEEP_DATABASE=1"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_TODAY_COMPLETE_KEEP_DATABASE=1"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_SETTINGS_SAVE_KEEP_HOME=1"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_VOICE_REVIEW_KEEP_DATABASE=1"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_KEEP_WORKSPACE=1"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_SCHEDULE_COCKPIT_KEEP_DATABASE=1"))
        XCTAssertTrue(script.contains("BLOCKER: runtime workflow scenario failed"))
        XCTAssertTrue(script.contains("Last visible window"))
        XCTAssertFalse(script.contains("inbox_triage runtime DB assertion is not implemented yet"))
        XCTAssertFalse(script.contains("today_complete runtime DB assertion is not implemented yet"))
        XCTAssertFalse(script.contains("settings_save runtime store assertion is not implemented yet"))
        XCTAssertFalse(script.contains("voice_review approval-boundary runtime assertion is not implemented yet"))
        XCTAssertFalse(script.contains("schedule_cockpit runtime DB assertion is not implemented yet"))
        XCTAssertFalse(script.contains("SKIP"))
        XCTAssertFalse(script.contains("TODO"))
        XCTAssertFalse(script.contains("fake success"))
    }

    func testRuntimeScheduleCockpitSmokeScriptVerifiesDraftGridAndApprovalBoundary() throws {
        let script = try readPackageFile("script/check_runtime_schedule_cockpit_smoke.sh")
        let markerHelper = try readPackageFile("script/ui_evidence_ax_marker_check.swift")

        XCTAssertTrue(script.contains("SOLOPM_DATABASE_PATH"))
        XCTAssertTrue(script.contains("APP_BINARY=\"$APP_BUNDLE/Contents/MacOS/$APP_NAME\""))
        XCTAssertTrue(script.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"schedule\""))
        XCTAssertFalse(script.contains("SOLOPM_LAUNCH_RECOVERY_MODE=1"))
        XCTAssertTrue(script.contains("./script/build_and_run.sh --build-only"))
        XCTAssertTrue(script.contains("seed_schedule_tasks()"))
        XCTAssertTrue(script.contains("source_command='runtime-schedule-cockpit-smoke'"))
        XCTAssertTrue(script.contains("AX Runtime Schedule Due"))
        XCTAssertTrue(script.contains("AX Runtime Schedule Unscheduled"))
        XCTAssertTrue(script.contains("schedule-workflow"))
        XCTAssertTrue(script.contains("schedule-week-grid"))
        XCTAssertTrue(script.contains("schedule-status-banner"))
        XCTAssertTrue(script.contains("schedule-unscheduled-add-draft-$unscheduled_task_id"))
        XCTAssertTrue(script.contains("schedule-feedback"))
        XCTAssertTrue(script.contains("schedule-apply-calendar"))
        XCTAssertTrue(script.contains("waitForAXElementContaining()"))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue()"))
        XCTAssertTrue(script.contains("ui_evidence_ax_marker_check.swift"))
        XCTAssertTrue(script.contains("ui_evidence_ax_press_button.swift"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_SCHEDULE_COCKPIT_AX_MAX_NODES"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1"))
        XCTAssertTrue(script.contains("id LIKE 'action-plan:schedule-draft-calendar-apply:%:task:%$unscheduled_task_id%'"))
        XCTAssertTrue(script.contains("payload_kind='action_plan'"))
        XCTAssertTrue(script.contains("state='waitingReview'"))
        XCTAssertTrue(script.contains("risk_level='write'"))
        XCTAssertTrue(script.contains("approval_json IS NULL"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%calendarCreateWorkBlock%'"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%providerExecutionApproval%'"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%appPermission%'"))
        XCTAssertTrue(script.contains("payload_json LIKE '%\\\"requiresApproval\\\":true%'"))
        XCTAssertTrue(script.contains("status='planned' AND due_at IS NULL"))
        XCTAssertTrue(script.contains("status='planned' AND due_at='$runtime_day_key'"))
        XCTAssertTrue(script.contains("OK: runtime schedule cockpit smoke covered weekly grid, unscheduled add-to-draft, and approval-gated Calendar apply"))
        XCTAssertFalse(script.contains(":memory:"))
        XCTAssertFalse(script.contains("not implemented yet"))
        XCTAssertFalse(script.contains("fake success"))

        XCTAssertTrue(markerHelper.contains("SOLOPM_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE"))
        XCTAssertTrue(markerHelper.contains("subtreeContainsText(startingAt:"))
    }

    func testRuntimeDevelopmentPRSmokeScriptRunsApprovedDirectoryFixtureFlow() throws {
        let script = try readPackageFile("script/check_runtime_development_pr_smoke.sh")
        let workflow = try readPackageFile("script/check_runtime_workflow_smoke.sh")
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let projectBoardViewSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let gitRunnerSource = try readPackageFile("Sources/SoloPMCore/DeveloperMode/GitReadOnlyTools.swift")

        XCTAssertTrue(script.contains("swift test --filter DevelopmentAutomationRuntimeSmokeTests/testApprovedProjectDirectoryCanEditVerifyCommitAndPreparePullRequestBranch --quiet"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_ARTIFACT_DIR"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_KEEP_WORKSPACE"))
        XCTAssertTrue(script.contains("approved project directory"))
        XCTAssertTrue(script.contains("development.repository.list_files"))
        XCTAssertTrue(script.contains("development.repository.create_file"))
        XCTAssertTrue(script.contains("development.repository.update_file"))
        XCTAssertTrue(script.contains("development.verification.run"))
        XCTAssertTrue(script.contains("development.pr_workflow.commit"))
        XCTAssertTrue(script.contains("development.pr_workflow.prepare"))
        XCTAssertTrue(script.contains("development.pr_workflow.push"))
        XCTAssertTrue(script.contains("development.pr_workflow.create_pull_request"))
        XCTAssertTrue(script.contains("development.pr_workflow.review_gate"))
        XCTAssertTrue(script.contains("development.pr_workflow.merge"))
        XCTAssertTrue(script.contains("fake Git and GitHub runners"))
        XCTAssertTrue(script.contains("APP_BINARY=\"$APP_BUNDLE/Contents/MacOS/$APP_NAME\""))
        XCTAssertTrue(script.contains("SOLOPM_DATABASE_PATH=\"$database_path\""))
        XCTAssertTrue(script.contains("SOLOPM_LAUNCH_RECOVERY_MODE=1"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK=1"))
        XCTAssertFalse(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_FIXTURE_BOOKMARK"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"project:$seed_project_id\""))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"assistant-queue\""))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_TASK_ID=\"$seed_task_id\""))
        XCTAssertTrue(script.contains("verify_visible_project_directory_picker_assignment()"))
        XCTAssertTrue(script.contains("chooseRuntimeProjectWorkspaceViaOpenPanel()"))
        XCTAssertTrue(script.contains("project-workspace-choose"))
        XCTAssertTrue(script.contains("project-workspace-current"))
        XCTAssertTrue(script.contains("workspace_path IS NULL AND workspace_bookmark IS NULL"))
        XCTAssertTrue(script.contains("workspace_path='$escaped_workspace' AND workspace_bookmark IS NOT NULL"))
        XCTAssertTrue(script.contains("visible Project inspector selected project workspace through NSOpenPanel"))
        XCTAssertTrue(script.contains("receipt_directory=\"$UI_HOME/Library/Application Support/SoloPM/ExecutionReceipts\""))
        XCTAssertTrue(script.contains("solopm-runtime-development-pr-smoke:"))
        XCTAssertTrue(script.contains("fixture_git()"))
        XCTAssertTrue(script.contains("-c commit.gpgsign=false"))
        XCTAssertTrue(script.contains("-c core.hooksPath=/dev/null"))
        XCTAssertTrue(script.contains("fixture_git -C \"$UI_WORKSPACE\" init"))
        XCTAssertTrue(script.contains("project-development-automation-status"))
        XCTAssertTrue(script.contains("project-development-automation-branch-preview"))
        XCTAssertTrue(script.contains("project-development-automation-queue"))
        XCTAssertTrue(script.contains("project-development-automation-queue-handoff"))
        XCTAssertTrue(script.contains("project-development-automation-edit-path"))
        XCTAssertTrue(script.contains("project-development-automation-edit-contents"))
        XCTAssertTrue(script.contains("project-development-automation-edit-preview"))
        XCTAssertTrue(script.contains("project-development-automation-edit-queue"))
        XCTAssertTrue(script.contains("project-development-automation-verification-queue"))
        XCTAssertTrue(script.contains("project-development-automation-commit-paths"))
        XCTAssertTrue(script.contains("project-development-automation-commit-message"))
        XCTAssertTrue(script.contains("project-development-automation-commit-queue"))
        XCTAssertTrue(script.contains("project-development-automation-push-queue"))
        XCTAssertTrue(script.contains("setTextFieldContaining()"))
        XCTAssertTrue(script.contains("if itemRole is not \"AXTextArea\" then"))
        XCTAssertTrue(script.contains("runtime_fake_git_bin"))
        XCTAssertTrue(script.contains("runtime_fake_git_push_log"))
        XCTAssertTrue(script.contains("runtime_fake_github_pr_log"))
        XCTAssertTrue(script.contains("runtime_fake_github_review_log"))
        XCTAssertTrue(script.contains("runtime_fake_github_merge_log"))
        XCTAssertTrue(script.contains("runtime_blocked_external_write_log"))
        XCTAssertTrue(script.contains("runtime_expected_branch_file"))
        XCTAssertTrue(script.contains("runtime_expected_head_file"))
        XCTAssertTrue(script.contains("REAL_GIT=\"$(command -v git || true)\""))
        XCTAssertTrue(script.contains("install_runtime_fake_publish_tools()"))
        XCTAssertTrue(script.contains("verify_runtime_fake_publish_tools_block_bypass()"))
        XCTAssertTrue(script.contains("verify_runtime_fake_push_log()"))
        XCTAssertTrue(script.contains("verify_runtime_fake_pull_request_log()"))
        XCTAssertTrue(script.contains("verify_runtime_fake_pull_request_review_log()"))
        XCTAssertTrue(script.contains("verify_runtime_fake_pull_request_merge_log()"))
        XCTAssertTrue(script.contains("verify_no_merge_followup()"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_EXPECTED_HEAD"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_PUSH_LOG=\"$runtime_fake_git_push_log\""))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_CREATE_LOG=\"$runtime_fake_github_pr_log\""))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_REVIEW_LOG=\"$runtime_fake_github_review_log\""))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_MERGE_LOG=\"$runtime_fake_github_merge_log\""))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_CREATE_URL=\"$runtime_fake_pull_request_url\""))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_EXPECTED_BASE=\"$runtime_pull_request_base_branch\""))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_GIT_EXECUTABLE=\"$runtime_fake_git_bin/git\""))
        XCTAssertTrue(script.contains("expected_refspec=\"${expected_head}:refs/heads/${expected_branch}\""))
        XCTAssertTrue(script.contains("printf '%s\\trefs/heads/%s\\n' \"$expected_head\" \"$expected_branch\""))
        XCTAssertTrue(script.contains("\"$git_command\" -C \"$UI_WORKSPACE\" \"$push_command\" -u blocked-remote"))
        XCTAssertTrue(script.contains("\"$git_command\" -c core.hooksPath=/dev/null \"$push_command\" -u blocked-remote"))
        XCTAssertTrue(script.contains("blocked ls-remote command:"))
        XCTAssertTrue(script.contains("blocked publish command:"))
        XCTAssertTrue(script.contains("assistant-queue-workflow"))
        XCTAssertTrue(script.contains("assistant-queue-row-$queued_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-approve-$queued_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-run-$queued_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-row-$repository_edit_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-approve-$repository_edit_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-run-$repository_edit_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-row-$verification_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-approve-$verification_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-run-$verification_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-row-$commit_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-approve-$commit_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-run-$commit_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-row-$push_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-approve-$push_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-run-$push_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-row-$pull_request_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-approve-$pull_request_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-run-$pull_request_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-row-$pull_request_review_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-approve-$pull_request_review_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-run-$pull_request_review_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-row-$pull_request_merge_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-approve-$pull_request_merge_item_id"))
        XCTAssertTrue(script.contains("assistant-queue-run-$pull_request_merge_item_id"))
        XCTAssertTrue(script.contains("prepared_branch_name=\"\""))
        XCTAssertTrue(script.contains("commit_item_id=\"\""))
        XCTAssertTrue(script.contains("push_item_id=\"\""))
        XCTAssertTrue(script.contains("pull_request_item_id=\"\""))
        XCTAssertTrue(script.contains("pull_request_review_item_id=\"\""))
        XCTAssertTrue(script.contains("pull_request_merge_item_id=\"\""))
        XCTAssertTrue(script.contains("struct Reference: Decodable"))
        XCTAssertTrue(script.contains("wait_for_receipt_json \"visible Assistant Queue branch preparation\" \"$queued_item_id\" \"development.pr_workflow.prepare\""))
        XCTAssertTrue(script.contains("wait_for_receipt_json \"visible Assistant Queue repository edit\" \"$repository_edit_item_id\" \"development.repository.create_file\""))
        XCTAssertTrue(script.contains("wait_for_receipt_json"))
        XCTAssertTrue(script.contains("\"visible Assistant Queue verification\""))
        XCTAssertTrue(script.contains("\"development.verification.run\""))
        XCTAssertTrue(script.contains("\"development_branch\""))
        XCTAssertTrue(script.contains("\"$prepared_branch_name\""))
        XCTAssertTrue(script.contains("\"visible Assistant Queue commit\""))
        XCTAssertTrue(script.contains("\"development.pr_workflow.commit\""))
        XCTAssertTrue(script.contains("\"development_commit\""))
        XCTAssertTrue(script.contains("\"visible Assistant Queue branch push\""))
        XCTAssertTrue(script.contains("\"development.pr_workflow.push\""))
        XCTAssertTrue(script.contains("\"visible Assistant Queue pull request creation\""))
        XCTAssertTrue(script.contains("\"development.pr_workflow.create_pull_request\""))
        XCTAssertTrue(script.contains("\"pull_request\""))
        XCTAssertTrue(script.contains("\"$runtime_fake_pull_request_url\""))
        XCTAssertTrue(script.contains("\"visible Assistant Queue pull request review gate\""))
        XCTAssertTrue(script.contains("\"development.pr_workflow.review_gate\""))
        XCTAssertTrue(script.contains("\"visible Assistant Queue pull request merge\""))
        XCTAssertTrue(script.contains("\"development.pr_workflow.merge\""))
        XCTAssertTrue(script.contains("ensure_no_existing_app_process"))
        XCTAssertTrue(script.contains("the smoke only terminates its own launched PID"))
        XCTAssertTrue(script.contains("kill -9 \"$app_pid\""))
        XCTAssertTrue(script.contains("while ! kill -0 \"$app_pid\""))
        XCTAssertTrue(script.contains("NSRunningApplication(processIdentifier: pid)"))
        XCTAssertTrue(script.contains("_ = app.terminate()"))
        XCTAssertFalse(script.contains("tell application \"$APP_NAME\" to quit"))
        XCTAssertFalse(script.contains("tell application \\\"$APP_NAME\\\" to quit"))
        XCTAssertTrue(script.contains("waitForAXMarkerContaining()"))
        XCTAssertTrue(script.contains("pressButtonContainingBounded()"))
        XCTAssertTrue(script.contains("ui_evidence_ax_marker_check.swift"))
        XCTAssertTrue(script.contains("ui_evidence_ax_press_button.swift"))
        XCTAssertFalse(script.contains("pkill -x \"$APP_NAME\""))
        XCTAssertFalse(script.contains("while ! pgrep -x \"$APP_NAME\""))
        XCTAssertTrue(script.contains("payload_kind='action_plan'"))
        XCTAssertTrue(script.contains("state='waitingReview'"))
        XCTAssertTrue(script.contains("state='approved'"))
        XCTAssertTrue(script.contains("state='done'"))
        XCTAssertTrue(script.contains("approval_json IS NULL"))
        XCTAssertTrue(script.contains("approval_json IS NOT NULL"))
        XCTAssertTrue(script.contains("struct Receipt: Decodable"))
        XCTAssertTrue(script.contains("decoder.decode(Receipt.self"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%developmentPreparePullRequestWorkflow%'"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%developmentRepositoryCreateFile%'"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%developmentRunVerification%'"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%developmentCommitChanges%'"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%developmentPushBranch%'"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%developmentCreatePullRequest%'"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%developmentReviewPullRequestGate%'"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%developmentMergePullRequest%'"))
        XCTAssertTrue(script.contains("required_capabilities_json LIKE '%providerExecutionApproval%'"))
        XCTAssertTrue(script.contains("action-plan:development-repository-edit:$seed_project_id:$seed_task_id:%"))
        XCTAssertTrue(script.contains("action-plan:development-verification:$seed_project_id:$seed_task_id:%"))
        XCTAssertTrue(script.contains("action-plan:development-commit:$seed_project_id:$seed_task_id:%"))
        XCTAssertTrue(script.contains("action-plan:development-pr-push:$seed_project_id:$seed_task_id:%"))
        XCTAssertTrue(script.contains("action-plan:development-pr-create:$seed_project_id:$seed_task_id:%"))
        XCTAssertTrue(script.contains("automation-request:project-development-pr-review:$seed_project_id:$seed_task_id:%"))
        XCTAssertTrue(script.contains("automation-request:project-development-pr-merge:$seed_project_id:$seed_task_id:%"))
        XCTAssertTrue(script.contains("payload_json LIKE '%expectedHeadOID%'"))
        XCTAssertTrue(script.contains("payload_json LIKE '%development.pr_workflow.create_pull_request%'"))
        XCTAssertTrue(script.contains("payload_json LIKE '%development.pr_workflow.review_gate%'"))
        XCTAssertTrue(script.contains("payload_json LIKE '%development.pr_workflow.merge%'"))
        XCTAssertTrue(script.contains("printf '%s' \"$prepared_branch_name\" >\"$runtime_expected_branch_file\""))
        XCTAssertTrue(script.contains("printf '%s' \"$visible_commit_head_after\" >\"$runtime_expected_head_file\""))
        XCTAssertTrue(script.contains("runtime-development-pr-visible-edit.md"))
        XCTAssertTrue(script.contains("visible_commit_head_before"))
        XCTAssertTrue(script.contains("visible_commit_head_after"))
        XCTAssertTrue(script.contains("fixture_git -C \"$UI_WORKSPACE\" diff-tree --no-commit-id --name-only -r \"$visible_commit_head_after\""))
        XCTAssertTrue(script.contains("project-development-automation-pr-create-queue"))
        XCTAssertTrue(script.contains("project-development-automation-pr-review-queue"))
        XCTAssertTrue(script.contains("project-development-automation-pr-merge-queue"))
        XCTAssertTrue(script.contains("requiresPushApproval=true"))
        XCTAssertTrue(script.contains("requiresPullRequestApproval=true"))
        XCTAssertTrue(script.contains("No live GitHub PR creation or merge is created by this smoke"))
        XCTAssertTrue(script.contains("fake branch push"))
        XCTAssertTrue(script.contains("fake pull request create"))
        XCTAssertTrue(script.contains("fake pull request review gate"))
        XCTAssertTrue(script.contains("fake pull request merge"))
        XCTAssertTrue(script.contains("payload_json NOT LIKE '%development.pr_workflow.review_gate%'"))
        XCTAssertTrue(script.contains("payload_json NOT LIKE '%development.pr_workflow.merge%'"))
        XCTAssertTrue(script.contains("receipt_payload_json"))
        XCTAssertTrue(script.contains("visible Project automation panel queued branch automation into Assistant Queue"))
        XCTAssertTrue(script.contains("visible Assistant Queue approved and executed local branch preparation"))
        XCTAssertTrue(script.contains("visible Project automation panel queued repository edit review into Assistant Queue"))
        XCTAssertTrue(script.contains("visible Assistant Queue approved and executed repository edit"))
        XCTAssertTrue(script.contains("visible Project automation panel queued verification review into Assistant Queue"))
        XCTAssertTrue(script.contains("visible Assistant Queue approved and executed verification"))
        XCTAssertTrue(script.contains("visible Project automation panel queued commit review into Assistant Queue"))
        XCTAssertTrue(script.contains("visible Assistant Queue approved and executed local commit"))
        XCTAssertTrue(script.contains("visible Project automation panel queued branch push review into Assistant Queue"))
        XCTAssertTrue(script.contains("visible Assistant Queue approved and executed fake branch push"))
        XCTAssertTrue(script.contains("visible Project automation panel queued pull request creation review into Assistant Queue"))
        XCTAssertTrue(script.contains("visible Assistant Queue approved and executed fake pull request creation"))
        XCTAssertTrue(script.contains("visible Project automation panel queued pull request review gate into Assistant Queue"))
        XCTAssertTrue(script.contains("visible Assistant Queue approved and executed fake pull request review gate"))
        XCTAssertTrue(script.contains("visible Project automation panel queued pull request merge into Assistant Queue"))
        XCTAssertTrue(script.contains("visible Assistant Queue approved and executed fake pull request merge"))
        for prohibitedPattern in [
            #"\b(?:git|fixture_git)\b[^\n]*\bpush\b"#,
            #"\bgh\b[^\n]*\bpr\s+create\b"#,
            #"\bcurl\b[^\n]*(?:-X\s+POST|--request\s+POST|api\.github\.com)"#,
            #"\bssh\b[^\n]*github\.com"#
        ] {
            XCTAssertNil(
                script.range(of: prohibitedPattern, options: .regularExpression),
                "runtime development PR smoke must not contain external write command matching \(prohibitedPattern)"
            )
        }
        XCTAssertNil(
            script.range(
                of: #"(?m)^[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge\b"#,
                options: .regularExpression
            ),
            "runtime development PR smoke must route merge through the app's smoke fake runner instead of a raw gh pr merge command"
        )

        XCTAssertTrue(workflow.contains("\"development_pr\""))
        XCTAssertTrue(workflow.contains("run_development_pr()"))
        XCTAssertTrue(workflow.contains("./script/check_runtime_development_pr_smoke.sh"))

        XCTAssertTrue(appSource.contains("@State private var repositoryEditRelativePath"))
        XCTAssertTrue(appSource.contains("@State private var repositoryEditContents"))
        XCTAssertTrue(appSource.contains("@State private var commitRelativePaths"))
        XCTAssertTrue(appSource.contains("@State private var commitMessage"))
        XCTAssertTrue(appSource.contains("project-development-automation-edit-path"))
        XCTAssertTrue(appSource.contains("project-development-automation-edit-contents"))
        XCTAssertTrue(appSource.contains("project-development-automation-edit-preview"))
        XCTAssertTrue(appSource.contains("project-development-automation-edit-queue"))
        XCTAssertTrue(appSource.contains("project-development-automation-verification-queue"))
        XCTAssertTrue(appSource.contains("project-development-automation-commit-paths"))
        XCTAssertTrue(appSource.contains("project-development-automation-commit-message"))
        XCTAssertTrue(appSource.contains("project-development-automation-commit-queue"))
        XCTAssertTrue(appSource.contains("project-development-automation-push-queue"))
        XCTAssertTrue(projectBoardViewSource.contains("project-development-automation-pr-base"))
        XCTAssertTrue(projectBoardViewSource.contains("project-development-automation-pr-title"))
        XCTAssertTrue(projectBoardViewSource.contains("project-development-automation-pr-body"))
        XCTAssertTrue(projectBoardViewSource.contains("project-development-automation-pr-create-queue"))
        XCTAssertTrue(projectBoardViewSource.contains("project-development-automation-pr-create-detailed-queue"))
        XCTAssertTrue(appSource.contains("enqueueDevelopmentPushReview"))
        XCTAssertTrue(appSource.contains("project-development-automation-pr-merge-queue"))
        XCTAssertTrue(appSource.contains("canQueuePullRequestMergeGate"))
        XCTAssertTrue(gitRunnerSource.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_GIT_EXECUTABLE"))
        XCTAssertTrue(gitRunnerSource.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK"))
        XCTAssertTrue(gitRunnerSource.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_PUSH_LOG"))
        XCTAssertTrue(gitRunnerSource.contains("runtimeDevelopmentSmokePushOutput"))
        XCTAssertTrue(gitRunnerSource.contains("blocked publish command"))
        XCTAssertTrue(gitRunnerSource.contains("environment[Self.runtimeDevelopmentSmokeBookmarkFlagKey] == \"1\""))
        XCTAssertTrue(gitRunnerSource.contains("process.environment = environment"))
        let githubRunnerSource = try readPackageFile("Sources/SoloPMCore/DeveloperMode/DevelopmentPRPublishWorkflow.swift")
        XCTAssertTrue(githubRunnerSource.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_CREATE_LOG"))
        XCTAssertTrue(githubRunnerSource.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_CREATE_URL"))
        XCTAssertTrue(githubRunnerSource.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_REVIEW_LOG"))
        XCTAssertTrue(githubRunnerSource.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_MERGE_LOG"))
        XCTAssertTrue(githubRunnerSource.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_EXPECTED_HEAD"))
        XCTAssertTrue(githubRunnerSource.contains("runtimeDevelopmentSmokePullRequestCreateOutput"))
        XCTAssertTrue(githubRunnerSource.contains("runtimeDevelopmentSmokePullRequestReviewStatusOutput"))
        XCTAssertTrue(githubRunnerSource.contains("runtimeDevelopmentSmokePullRequestReviewThreadsOutput"))
        XCTAssertTrue(githubRunnerSource.contains("runtimeDevelopmentSmokePullRequestMergeOutput"))
        XCTAssertTrue(githubRunnerSource.contains("simulated pull request create"))
        XCTAssertTrue(githubRunnerSource.contains("simulated pull request merge"))
    }

    func testRuntimeInboxTriageSmokeScriptVerifiesAllClassificationActionsAndUndo() throws {
        let script = try readPackageFile("script/check_runtime_inbox_triage_smoke.sh")

        XCTAssertTrue(script.contains("SOLOPM_DATABASE_PATH"))
        XCTAssertTrue(script.contains("APP_BINARY=\"$APP_BUNDLE/Contents/MacOS/$APP_NAME\""))
        XCTAssertTrue(script.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"inbox\""))
        XCTAssertTrue(script.contains("./script/build_and_run.sh --build-only"))
        XCTAssertTrue(script.contains("wait_for_visible_windows()"))
        XCTAssertTrue(script.contains("set_inbox_window_size()"))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue()"))
        XCTAssertTrue(script.contains("setTextFieldContaining()"))
        XCTAssertTrue(script.contains("pressButtonContaining \"workflow-task-row-$task_id\""))
        XCTAssertTrue(script.contains("pressButtonContaining \"inbox-action-make-task\""))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"schedule inbox item\" \"inbox-action-schedule-today\""))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"review later inbox item\" \"inbox-action-review-later\""))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"convert inbox item to project\" \"inbox-action-make-project\""))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"undo inbox schedule\" \"inbox-classification-undo\""))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"undo inbox review later\" \"inbox-classification-undo\""))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"undo inbox project conversion\" \"inbox-classification-undo\""))
        XCTAssertTrue(script.contains("inbox-quick-add-title"))
        XCTAssertTrue(script.contains("inbox-quick-add-button"))
        XCTAssertTrue(script.contains("SELECT id FROM projects WHERE title='Inbox'"))
        XCTAssertTrue(script.contains("status='planned' AND due_at IS NOT NULL"))
        XCTAssertTrue(script.contains("status='backlog' AND due_at IS NULL"))
        XCTAssertTrue(script.contains("SELECT count(*) FROM projects WHERE title='AX Runtime Inbox Project Conversion';"))
        XCTAssertTrue(script.contains("OK: runtime inbox triage smoke covered quick add, make-task, schedule, review-later, project conversion, and undo through the visible app"))
        XCTAssertFalse(script.contains(":memory:"))
        XCTAssertFalse(script.contains("not implemented yet"))
    }

    func testRuntimeTodayCompleteSmokeScriptVerifiesVisibleRowCompletionPersistsToSQLite() throws {
        let script = try readPackageFile("script/check_runtime_today_complete_smoke.sh")

        XCTAssertTrue(script.contains("SOLOPM_DATABASE_PATH"))
        XCTAssertTrue(script.contains("APP_BINARY=\"$APP_BUNDLE/Contents/MacOS/$APP_NAME\""))
        XCTAssertTrue(script.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"today\""))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_TASK_ID=\"$today_task_id\""))
        XCTAssertTrue(script.contains("./script/build_and_run.sh --build-only"))
        XCTAssertTrue(script.contains("seed_today_task()"))
        XCTAssertTrue(script.contains("AX Runtime Today Complete"))
        XCTAssertTrue(script.contains("due_at='2026-01-01T09:00:00Z'"))
        XCTAssertTrue(script.contains("launch_app_for_database_migration()"))
        XCTAssertTrue(script.contains("launch_app_for_database_migration\nwait_for_database_table \"projects\""))
        XCTAssertTrue(script.contains("launch_app_for_today\nwait_for_database_table \"assistant_queue_items\""))
        XCTAssertFalse(script.contains("launch_app_for_today_board()"))
        XCTAssertTrue(script.contains("Keep the edit and subtask checks in separate launches."))
        XCTAssertTrue(script.contains("pressButtonContainingBounded \"today-rail-edit-task\""))
        XCTAssertTrue(script.contains("waitForAXSubtreeMarkerContaining \"task-inspector-title\" \"AX Runtime Today Complete\""))
        XCTAssertTrue(script.contains("pressButtonContainingBounded \"today-rail-add-subtask\""))
        let editActionRange = try XCTUnwrap(script.range(of: "pressButtonContainingBounded \"today-rail-edit-task\""))
        let editCloseRange = try XCTUnwrap(script.range(of: "terminate_app", range: editActionRange.upperBound..<script.endIndex))
        let subtaskLaunchRange = try XCTUnwrap(script.range(of: "launch_app_for_today", range: editCloseRange.upperBound..<script.endIndex))
        let subtaskActionRange = try XCTUnwrap(script.range(of: "pressButtonContainingBounded \"today-rail-add-subtask\"", range: subtaskLaunchRange.upperBound..<script.endIndex))
        XCTAssertLessThan(editActionRange.lowerBound, editCloseRange.lowerBound)
        XCTAssertLessThan(editCloseRange.lowerBound, subtaskLaunchRange.lowerBound)
        XCTAssertLessThan(subtaskLaunchRange.lowerBound, subtaskActionRange.lowerBound)
        XCTAssertTrue(script.contains("waitForAXElementContaining \"today-command-capture-field\""))
        XCTAssertTrue(script.contains("waitForAXElementContaining \"today-command-capture-field\" \"AX Runtime Today Complete\""))
        XCTAssertTrue(script.contains("pressButtonContaining \"workflow-task-row-$today_task_id\""))
        XCTAssertTrue(script.contains("pressButtonContaining \"today-rail-focus\""))
        XCTAssertTrue(script.contains("verify_single_value \"focus kept Today task open\""))
        XCTAssertTrue(script.contains("waitForAXElementContaining()"))
        XCTAssertTrue(script.contains("pressButtonContaining \"today-rail-schedule-block\""))
        XCTAssertTrue(script.contains("waitForAXElementContaining \"today-rail-schedule-draft-status\""))
        XCTAssertTrue(script.contains("verify_single_value \"schedule draft kept Today task open\""))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"queue Today rail reminder draft\" \"today-rail-reminder-draft\""))
        XCTAssertTrue(script.contains("action-plan:today-reminder:%:task:$today_task_id"))
        XCTAssertTrue(script.contains("state='waitingReview' AND approval_json IS NULL"))
        XCTAssertTrue(script.contains("status='planned' AND completed_at IS NULL"))
        XCTAssertTrue(script.contains("pressButtonUntilSQLiteValue \"complete today task\" \"workflow-task-completion-$today_task_id\""))
        XCTAssertTrue(script.contains("status='completed' AND completed_at IS NOT NULL"))
        XCTAssertTrue(script.contains("source_command='runtime-today-complete-smoke'"))
        XCTAssertTrue(script.contains("OK: runtime today complete smoke covered Today rail focus, schedule draft, edit inspector, subtask prefill, reminder draft, and visible row completion"))
        XCTAssertFalse(script.contains(":memory:"))
        XCTAssertFalse(script.contains("not implemented yet"))
    }

    func testRuntimeSettingsSaveSmokeScriptPersistsNonSecretSettingsToIsolatedUserDefaults() throws {
        let script = try readPackageFile("script/check_runtime_settings_save_smoke.sh")
        let helper = try readPackageFile("script/settings_save_smoke_check.swift")

        XCTAssertTrue(script.contains("SOLOPM_OPEN_SETTINGS_ON_LAUNCH=1"))
        XCTAssertTrue(script.contains("SOLOPM_SETTINGS_EVIDENCE_TAB=AI"))
        XCTAssertTrue(script.contains("HOME=\"$settings_home\""))
        XCTAssertTrue(script.contains("SOLOPM_DATABASE_PATH=\"$database_path\""))
        XCTAssertTrue(script.contains("settings-task-auto-execution-toggle"))
        XCTAssertTrue(script.contains("settings-save-button"))
        XCTAssertTrue(script.contains("settings_suite_name=\"$BUNDLE_IDENTIFIER.runtime-settings-save."))
        XCTAssertTrue(script.contains("SOLOPM_APP_SETTINGS_SUITE_NAME=\"$settings_suite_name\""))
        XCTAssertTrue(script.contains("SOLOPM_SETTINGS_SMOKE_BUNDLE_IDENTIFIER=\"$settings_suite_name\""))
        XCTAssertTrue(script.contains("/usr/bin/defaults export \"$settings_suite_name\" \"$settings_home/app-settings.plist\""))
        XCTAssertTrue(script.contains("/usr/bin/defaults delete \"$settings_suite_name\""))
        XCTAssertTrue(script.contains("enableCheckboxContaining()"))
        XCTAssertTrue(script.contains("enableCheckboxContaining \"settings-task-auto-execution-toggle\""))
        XCTAssertTrue(script.contains("/usr/bin/swift \"$ROOT_DIR/script/settings_save_smoke_check.swift\""))
        XCTAssertTrue(script.contains("OK: runtime settings save smoke enabled task automation and verified isolated UserDefaults"))
        XCTAssertFalse(script.contains(":memory:"))
        XCTAssertFalse(script.contains("not implemented yet"))

        XCTAssertTrue(helper.contains("UserDefaults(suiteName: bundleIdentifier)"))
        XCTAssertTrue(helper.contains("data(forKey: \"app.settings\")"))
        XCTAssertTrue(helper.contains("\"taskAutoExecution\""))
        XCTAssertTrue(helper.contains("\"isEnabled\""))
        XCTAssertTrue(helper.contains("BLOCKER: settings save smoke"))
        XCTAssertFalse(helper.contains("print(data)"))
    }

    func testRuntimeVoiceReviewSmokeScriptFailsClosedWithoutAPIKeyAndPersistsPlanningAudit() throws {
        let script = try readPackageFile("script/check_runtime_voice_review_smoke.sh")

        XCTAssertTrue(script.contains("SOLOPM_OPEN_VOICE_COMMAND_ON_LAUNCH=1"))
        XCTAssertTrue(script.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1"))
        XCTAssertTrue(script.contains("SOLOPM_DATABASE_PATH=\"$database_path\""))
        XCTAssertTrue(script.contains("settings_suite_name=\"$BUNDLE_IDENTIFIER.runtime-voice-review."))
        XCTAssertTrue(script.contains("SOLOPM_APP_SETTINGS_SUITE_NAME=\"$settings_suite_name\""))
        XCTAssertTrue(script.contains("/usr/bin/defaults delete \"$settings_suite_name\""))
        XCTAssertTrue(script.contains("setTextAreaContaining \"voice-command-input\""))
        XCTAssertTrue(script.contains("pressControlContaining \"voice-command-generate-plan\""))
        XCTAssertTrue(script.contains("The AI provider rejected the configured API key."))
        XCTAssertTrue(script.contains("category='planning' AND action='generate_plan' AND status='started'"))
        XCTAssertTrue(script.contains("category='planning' AND action='generate_plan' AND status='failed'"))
        XCTAssertTrue(script.contains("category='planning' AND action='generate_plan' AND status='succeeded'"))
        XCTAssertTrue(script.contains("SELECT count(*) FROM tasks;"))
        XCTAssertTrue(script.contains("planning_initial_project_count=\"$(sqlite_scalar \"SELECT count(*) FROM projects;\")\""))
        XCTAssertTrue(script.contains("project count unchanged after rejected planning"))
        XCTAssertTrue(script.contains("seed_daily_planning_task"))
        XCTAssertTrue(script.contains("daily_planning_seed_task_id"))
        XCTAssertTrue(script.contains("Open Today Review and start the recommended task"))
        XCTAssertTrue(script.contains("id LIKE 'action-plan:daily-planning:%:startRecommended:task:${daily_planning_seed_task_id}'"))
        XCTAssertTrue(script.contains("payload_kind='action_plan'"))
        XCTAssertTrue(script.contains("source_transcript='Open Today Review and start the recommended task'"))
        XCTAssertTrue(script.contains("Open Today Review and move the recommended task to today"))
        XCTAssertTrue(script.contains("id LIKE 'action-plan:daily-planning:%:moveRecommendedDueDateToToday:task:${daily_planning_seed_task_id}'"))
        XCTAssertTrue(script.contains("source_transcript='Open Today Review and move the recommended task to today'"))
        XCTAssertTrue(script.contains("daily planning task due date remains unchanged before move-to-today approval"))
        XCTAssertTrue(script.contains("no extra daily planning tasks before move-to-today approval"))
        XCTAssertTrue(script.contains("no extra daily planning projects before move-to-today approval"))
        XCTAssertTrue(script.contains("total project count unchanged after move-to-today daily planning handoff"))
        XCTAssertTrue(script.contains("Open Today Review and defer the recommended task to tomorrow"))
        XCTAssertTrue(script.contains("id LIKE 'action-plan:daily-planning:%:deferRecommendedToTomorrow:task:${daily_planning_seed_task_id}'"))
        XCTAssertTrue(script.contains("source_transcript='Open Today Review and defer the recommended task to tomorrow'"))
        XCTAssertTrue(script.contains("daily planning task due date remains unchanged before defer approval"))
        XCTAssertTrue(script.contains("Open Today Review and split the recommended task"))
        XCTAssertTrue(script.contains("id LIKE 'action-plan:daily-planning:%:splitRecommendedTask:task:${daily_planning_seed_task_id}'"))
        XCTAssertTrue(script.contains("source_transcript='Open Today Review and split the recommended task'"))
        XCTAssertTrue(script.contains("no split follow-up tasks before split approval"))
        XCTAssertTrue(script.contains("daily planning seed task unchanged before split approval"))
        XCTAssertTrue(script.contains("title='Runtime Daily Planning Recommended' AND status='planned' AND due_at='2026-01-01T09:00:00Z' AND source_command='runtime-voice-review-smoke'"))
        XCTAssertTrue(script.contains("two daily planning queue drafts before approval"))
        XCTAssertTrue(script.contains("four daily planning queue drafts before approval"))
        XCTAssertTrue(script.contains("daily_planning_seed_project_count=\"$(sqlite_scalar \"SELECT count(*) FROM projects;\")\""))
        XCTAssertTrue(script.contains("SELECT count(*) FROM projects WHERE source_command='runtime-voice-review-smoke';"))
        XCTAssertTrue(script.contains("total project count unchanged after daily planning handoff"))
        XCTAssertTrue(script.contains("\"SELECT count(*) FROM projects;\""))
        XCTAssertGreaterThanOrEqual(script.components(separatedBy: "\"SELECT count(*) FROM projects;\"").count - 1, 6)
        let moveToTodayBlock = try XCTUnwrap(script.range(of: "Open Today Review and move the recommended task to today"))
        XCTAssertTrue(script[moveToTodayBlock.lowerBound...].contains("total project count unchanged after move-to-today daily planning handoff"))
        let deferBlock = try XCTUnwrap(script.range(of: "Open Today Review and defer the recommended task to tomorrow"))
        XCTAssertTrue(script[deferBlock.lowerBound...].contains("total project count unchanged after defer daily planning handoff"))
        let splitBlock = try XCTUnwrap(script.range(of: "Open Today Review and split the recommended task"))
        XCTAssertTrue(script[splitBlock.lowerBound...].contains("total project count unchanged after split daily planning handoff"))
        XCTAssertTrue(script.contains("approval_json IS NULL"))
        XCTAssertTrue(script.contains("status='planned'"))
        XCTAssertTrue(script.contains("only one daily planning queue draft before approval"))
        XCTAssertTrue(script.contains("planning audit did not start again for local Daily Planning handoff"))
        XCTAssertTrue(script.contains("planning audit did not start again for move-to-today local Daily Planning handoff"))
        XCTAssertTrue(script.contains("planning audit did not start again for defer local Daily Planning handoff"))
        XCTAssertTrue(script.contains("planning audit did not start again for split local Daily Planning handoff"))
        XCTAssertTrue(script.contains("OK: runtime voice review smoke verified fail-closed planning audit and no pre-approval writes"))
        XCTAssertTrue(script.contains("OK: runtime voice review smoke verified local Daily Planning queue handoffs"))
        XCTAssertFalse(script.contains(":memory:"))
        XCTAssertFalse(script.contains("not implemented yet"))
        XCTAssertFalse(script.contains("fake success"))
    }

    func testLayoutStabilitySmokeScriptSamplesImmediateFramesAndWritesArtifacts() throws {
        let script = try readPackageFile("script/check_layout_stability_smoke.sh")
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        XCTAssertTrue(script.contains("LAYOUT_STABILITY_OUTPUT_DIR=\"${SOLOPM_LAYOUT_STABILITY_OUTPUT_DIR:-$ROOT_DIR/.tmp/layout-stability}\""))
        XCTAssertTrue(script.contains("./script/build_and_run.sh --build-only"))
        XCTAssertTrue(script.contains("./script/prepare_voiceover_review_candidate.sh --database \"$LAYOUT_STABILITY_DATABASE_PATH\" --no-launch --skip-build"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"project:$layout_project_id\""))
        XCTAssertTrue(script.contains("collect_ax_frames()"))
        XCTAssertTrue(script.contains("sample_layout_frames()"))
        XCTAssertTrue(script.contains("assert_layout_stable()"))
        XCTAssertTrue(script.contains("set_project_board_window_size()"))
        XCTAssertTrue(script.contains("assert_no_negative_or_overlapping_frames()"))
        XCTAssertTrue(script.contains("capture_layout_screenshot()"))
        XCTAssertTrue(script.contains("t=0ms"))
        XCTAssertTrue(script.contains("t=50ms"))
        XCTAssertTrue(script.contains("t=150ms"))
        XCTAssertTrue(script.contains("t=300ms"))
        XCTAssertTrue(script.contains("LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX"))
        XCTAssertTrue(script.contains("LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX=\"${SOLOPM_LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX:-0}\""))
        XCTAssertTrue(script.contains("write_json_artifacts()"))
        XCTAssertTrue(script.contains("samples.json"))
        XCTAssertTrue(script.contains("diff.json"))
        XCTAssertTrue(script.contains("window-min"))
        XCTAssertTrue(script.contains("window-standard"))
        XCTAssertTrue(script.contains("window-wide"))
        XCTAssertTrue(script.contains("BLOCKER: layout frame overlaps after"))
        XCTAssertTrue(script.contains("BLOCKER: layout frame is clipped outside window after"))
        XCTAssertTrue(script.contains("\"phase\":\"before\""))
        XCTAssertTrue(script.contains("\"phase\":\"immediate\""))
        XCTAssertTrue(script.contains("\"phase\":\"after\""))
        XCTAssertTrue(script.contains("BLOCKER: required AX identifier missing"))
        XCTAssertTrue(script.contains("project-board-header-bar"))
        XCTAssertTrue(script.contains("project-board-detail"))
        XCTAssertTrue(script.contains("project-board-sidebar"))
        XCTAssertTrue(script.contains("project-inspector"))
        XCTAssertTrue(script.contains("layout-stability-summary.md"))
        XCTAssertTrue(script.contains("samples.tsv"))
        XCTAssertTrue(script.contains("diff.tsv"))

        XCTAssertTrue(phase.contains("- [x] `ReleasePipelineTests` にlayout stability scriptの存在、`t=0`即時サンプル、複数サンプル、frame delta thresholdをsource-levelで確認するテストを追加する。"))
        XCTAssertTrue(phase.contains("- [x] scriptが対象AX identifier不足をskipではなく失敗扱いにするテストを追加する。"))
        XCTAssertTrue(phase.contains("- [x] scriptが差分artifactを `.tmp/layout-stability/` に保存することを確認するテストを追加する。"))
        XCTAssertTrue(phase.contains("- [x] thresholdは基本 `0px`、OS差が出る箇所だけ `1px` tolerance を明示する。"))
        XCTAssertTrue(phase.contains("- [x] 失敗時は before / immediate / after のJSONとPNGを保存する。"))
        XCTAssertTrue(phase.contains("- [x] Window resize直後のoverlap / clipping / frame jumpを検出できる。"))
    }

    func testLayoutStabilitySmokeScriptDoesNotUseEmptyAXSamplesAsBaseline() throws {
        let script = try readPackageFile("script/check_layout_stability_smoke.sh")

        XCTAssertTrue(script.contains("collect_layout_sample_frames()"))
        XCTAssertTrue(script.contains("collect_ax_frames_with_timeout()"))
        XCTAssertTrue(script.contains("wait_for_visible_windows"))
        XCTAssertTrue(script.contains("LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_COUNT"))
        XCTAssertTrue(script.contains("LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_DELAY_MS"))
        XCTAssertTrue(script.contains("if ! collect_ax_frames_with_timeout \"$frame_file\" \"$frame_file.err\"; then"))
        XCTAssertTrue(script.contains("BLOCKER: layout AX frame collection timed out"))
        XCTAssertTrue(script.contains("BLOCKER: failed to collect layout AX frames"))
        XCTAssertTrue(script.contains("if has_required_ax_identifiers \"$frame_file\" \"${required_identifiers[@]}\"; then"))
        XCTAssertTrue(script.contains("INFO: required AX identifiers missing after"))
        XCTAssertTrue(script.contains("retrying AX collection"))
        XCTAssertTrue(script.contains("require_ax_identifiers \"$frame_file\" \"${required_identifiers[@]}\""))
        XCTAssertTrue(script.contains("if ! capture_layout_screenshot \"$label\" \"t=${offset_ms}ms\"; then"))
        XCTAssertTrue(script.contains("if ! assert_no_negative_or_overlapping_frames \"$label\" \"$frame_file\" \"${required_identifiers[@]}\"; then"))
        XCTAssertTrue(script.contains("baseSeen[key] = 1"))
        XCTAssertTrue(script.contains("if (!(key in baseSeen))"))
        XCTAssertTrue(script.contains("BLOCKER: layout baseline sample missing"))
    }

    func testLayoutStabilitySmokeScriptDoesNotUseEmptyWindowMetadataAsStructuralBounds() throws {
        let script = try readPackageFile("script/check_layout_stability_smoke.sh")

        XCTAssertTrue(script.contains("window_metadata_has_positive_bounds()"))
        XCTAssertTrue(script.contains("local metadata_status"))
        XCTAssertTrue(script.contains("return \"$metadata_status\""))
        XCTAssertTrue(script.contains(": >\"$WINDOW_METADATA_FILE\""))
        XCTAssertTrue(script.contains("\"$window_width\" -gt 0"))
        XCTAssertTrue(script.contains("\"$window_height\" -gt 0"))
        XCTAssertTrue(script.contains("if read_window_metadata >/dev/null 2>&1 && window_metadata_has_positive_bounds; then"))
    }

    func testProjectBoardStateRestorationSmokeScriptLaunchesEmptyNormalAndManyDatabases() throws {
        let script = try readPackageFile("script/check_project_board_state_restoration_smoke.sh")
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        XCTAssertTrue(script.contains("STATE_RESTORATION_OUTPUT_DIR=\"${SOLOPM_STATE_RESTORATION_OUTPUT_DIR:-$ROOT_DIR/.tmp/project-board-state-restoration}\""))
        XCTAssertTrue(script.contains("./script/build_and_run.sh --build-only"))
        XCTAssertTrue(script.contains("./script/prepare_voiceover_review_candidate.sh --database \"$database_path\" --no-launch --skip-build"))
        XCTAssertTrue(script.contains("launch_state_case \"empty-database\""))
        XCTAssertTrue(script.contains("launch_state_case \"normal-database\""))
        XCTAssertTrue(script.contains("launch_state_case \"many-database\""))
        XCTAssertTrue(script.contains("SOLOPM_DATABASE_PATH=\"$database_path\""))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"$selected_destination\""))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"project:42\""))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"project:$seed_project_id\""))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"projects\""))
        XCTAssertTrue(script.contains("seed_many_projects_and_tasks()"))
        XCTAssertTrue(script.contains("STATE_RESTORATION_MANY_PROJECT_COUNT"))
        XCTAssertTrue(script.contains("STATE_RESTORATION_MANY_TASKS_PER_PROJECT"))
        XCTAssertTrue(script.contains("wait_for_project_board_window_metadata()"))
        XCTAssertTrue(script.contains("script/ui_evidence_window_metadata.swift"))
        XCTAssertTrue(script.contains("state-restoration-summary.md"))
        XCTAssertTrue(script.contains("OK: Project Board state restoration smoke launched empty, normal, and many databases"))
        XCTAssertTrue(script.contains("BLOCKER: Project Board state restoration"))
        XCTAssertFalse(script.contains(":memory:"))
        XCTAssertFalse(script.contains("not implemented yet"))

        XCTAssertTrue(phase.contains("- [x] 空DB、通常DB、大量DBでProject Boardが起動する。"))
    }

    func testVoiceOverReviewCandidateScriptSeedsIsolatedDatabaseAndLaunchesSelectedProject() throws {
        let script = try readPackageFile("script/prepare_voiceover_review_candidate.sh")

        XCTAssertTrue(script.contains("APP_BINARY=\"$APP_BUNDLE/Contents/MacOS/$APP_NAME\""))
        XCTAssertTrue(script.contains("DEFAULT_DATABASE_PATH=\"$ROOT_DIR/.tmp/voiceover-review/SoloPM-voiceover-review.sqlite\""))
        XCTAssertTrue(script.contains("./script/build_and_run.sh --build-only"))
        XCTAssertTrue(script.contains("/usr/bin/open \"${open_args[@]}\""))
        XCTAssertTrue(script.contains("--env"))
        XCTAssertTrue(script.contains("SOLOPM_LAUNCH_RECOVERY_MODE=1"))
        XCTAssertTrue(script.contains("\"SOLOPM_DATABASE_PATH=$database_path\""))
        XCTAssertTrue(script.contains("wait_for_visible_windows()"))
        XCTAssertTrue(script.contains("wait_for_database_table \"projects\""))
        XCTAssertTrue(script.contains("voiceover-review-seed"))
        XCTAssertTrue(script.contains("VoiceOver Review Project"))
        XCTAssertTrue(script.contains("Review Project navigation"))
        XCTAssertTrue(script.contains("Verify inline composer keyboard path"))
        XCTAssertTrue(script.contains("Move status with card controls"))
        XCTAssertTrue(script.contains("Confirm destructive confirmation labels"))
        XCTAssertTrue(script.contains("Delete Task announces an inline inspector confirmation panel before deletion"))
        XCTAssertTrue(script.contains("Save release accessibility notes"))
        XCTAssertTrue(script.contains("Run approved execution receipt review"))
        XCTAssertTrue(script.contains("Confirm the approved execution receipt announces the reviewed task title and detail after the plan runs."))
        XCTAssertTrue(script.contains("VoiceOver review artifact"))
        XCTAssertTrue(script.contains("SELECT CASE WHEN count(*) = 7 THEN 1 ELSE 0 END FROM tasks WHERE project_id=$seed_project_id AND source_command='voiceover-review-seed';"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=project:$seed_project_id"))
        XCTAssertTrue(script.contains("printf 'SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1\\n'"))
        XCTAssertTrue(script.contains("printf 'SOLOPM_LAUNCH_RECOVERY_MODE=1\\n'"))
        XCTAssertTrue(script.contains("evidence_command_file=\"$ROOT_DIR/.tmp/voiceover-review/create-evidence-command.sh\""))
        XCTAssertTrue(script.contains("worksheet_file=\"$ROOT_DIR/.tmp/voiceover-review/voiceover-worksheet.md\""))
        XCTAssertTrue(script.contains("pending_evidence_file=\"$ROOT_DIR/.tmp/voiceover-review/accessibility-voiceover-pending-$SOURCE_COMMIT.md\""))
        XCTAssertTrue(script.contains("voiceover_evidence_source_for_candidate()"))
        XCTAssertTrue(script.contains("isolated .tmp voiceover review database"))
        XCTAssertFalse(script.contains("pending_evidence_source=\"dist/$APP_NAME.app manual VoiceOver pass using $database_path project:$seed_project_id\""))
        XCTAssertTrue(script.contains("write_voiceover_review_worksheet()"))
        XCTAssertTrue(script.contains("./script/create_voiceover_evidence.sh --pending --output \"$pending_evidence_file\""))
        XCTAssertTrue(script.contains("printf 'SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT=%q\\n' \"$SOURCE_COMMIT\""))
        XCTAssertTrue(script.contains("printf 'SOLOPM_VOICEOVER_REVIEW_PROJECT_ID=%q\\n' \"$seed_project_id\""))
        XCTAssertTrue(script.contains("write_voiceover_evidence_command()"))
        XCTAssertTrue(script.contains("# This command must fail if the worksheet still contains placeholders."))
        XCTAssertTrue(script.contains("release_candidate_source_commit()"))
        XCTAssertTrue(script.contains("REPO_ROOT=%q"))
        XCTAssertTrue(script.contains("cd \"$REPO_ROOT\""))
        XCTAssertTrue(script.contains("EXPECTED_SOURCE_COMMIT=%q"))
        XCTAssertTrue(script.contains("CURRENT_SOURCE_COMMIT=\"$(release_candidate_source_commit)\""))
        XCTAssertTrue(script.contains("TRACKED_SOURCE_STATUS=\"$(git status --porcelain --untracked-files=no)\""))
        XCTAssertTrue(script.contains("VoiceOver evidence command requires a clean tracked source tree"))
        XCTAssertTrue(script.contains("VoiceOver evidence command was generated for source commit"))
        XCTAssertTrue(script.contains("VOICEOVER_LAUNCH_ENV_FILE=\"$REPO_ROOT/.tmp/voiceover-review/launch.env\""))
        XCTAssertTrue(script.contains("source \"$VOICEOVER_LAUNCH_ENV_FILE\""))
        XCTAssertTrue(script.contains("EXPECTED_DATABASE_PATH=%q"))
        XCTAssertTrue(script.contains("EXPECTED_PROJECT_ID=%q"))
        XCTAssertTrue(script.contains("EXPECTED_SELECTED_DESTINATION=%q"))
        XCTAssertTrue(script.contains("VoiceOver evidence command launch env is missing or stale"))
        XCTAssertTrue(script.contains("VoiceOver evidence command database is missing the seeded review tasks"))
        XCTAssertTrue(script.contains("VOICEOVER_WORKSHEET_FILE=\"$REPO_ROOT/.tmp/voiceover-review/voiceover-worksheet.md\""))
        XCTAssertTrue(script.contains("verify_voiceover_worksheet_for_evidence()"))
        XCTAssertTrue(script.contains("Status: completed"))
        XCTAssertTrue(script.contains("Source commit: \\`$EXPECTED_SOURCE_COMMIT\\`"))
        XCTAssertTrue(script.contains("Candidate database: \\`$EXPECTED_DATABASE_PATH\\`"))
        XCTAssertTrue(script.contains("Selected destination: \\`$EXPECTED_SELECTED_DESTINATION\\`"))
        XCTAssertTrue(script.contains("grep -F -- \"- [ ]\" \"$VOICEOVER_WORKSHEET_FILE\""))
        XCTAssertTrue(script.contains("voiceover_worksheet_value_is_placeholder_or_boilerplate()"))
        XCTAssertTrue(script.contains("voiceover_worksheet_value_covers_task_content_execution()"))
        XCTAssertTrue(script.contains("Task content execution must mention the redacted receipt, reviewed title, and reviewed detail."))
        XCTAssertTrue(script.contains("fill %s with concrete VoiceOver observation."))
        XCTAssertTrue(script.contains("VoiceOver worksheet is missing, stale, or incomplete"))
        XCTAssertTrue(script.contains("voiceover_worksheet_value()"))
        XCTAssertTrue(script.contains("WORKSHEET_REVIEWER=\"$(voiceover_worksheet_value \"Reviewer\")\""))
        XCTAssertTrue(script.contains("WORKSHEET_PROJECT_NAVIGATION_NOTE=\"$(voiceover_worksheet_value \"Project navigation\")\""))
        XCTAssertTrue(script.contains("WORKSHEET_INBOX_VOICE_TRIAGE_NOTE=\"$(voiceover_worksheet_value \"Inbox voice triage\")\""))
        XCTAssertTrue(script.contains("WORKSHEET_TODAY_RAIL_ACTIONS_NOTE=\"$(voiceover_worksheet_value \"Today rail actions\")\""))
        XCTAssertTrue(script.contains("WORKSHEET_TASK_CONTENT_EXECUTION_NOTE=\"$(voiceover_worksheet_value \"Task content execution\")\""))
        XCTAssertTrue(script.contains("--checked-by \"$WORKSHEET_REVIEWER\""))
        XCTAssertTrue(script.contains("--project-navigation-note \"$WORKSHEET_PROJECT_NAVIGATION_NOTE\""))
        XCTAssertTrue(script.contains("--inbox-voice-triage-note \"$WORKSHEET_INBOX_VOICE_TRIAGE_NOTE\""))
        XCTAssertTrue(script.contains("--today-rail-actions-note \"$WORKSHEET_TODAY_RAIL_ACTIONS_NOTE\""))
        XCTAssertTrue(script.contains("--task-content-execution-note \"$WORKSHEET_TASK_CONTENT_EXECUTION_NOTE\""))
        XCTAssertTrue(script.contains("Project navigation"))
        XCTAssertTrue(script.contains("Inbox voice triage"))
        XCTAssertTrue(script.contains("Today rail actions"))
        XCTAssertTrue(script.contains("Task content execution"))
        XCTAssertTrue(script.contains("No unlabeled primary CRUD controls"))
        XCTAssertTrue(script.contains("| `approved-execution-receipt` | Task content execution | Confirm VoiceOver announces the redacted receipt with reviewed task title and detail after approved execution. |"))
        XCTAssertTrue(script.contains("launch_voiceover_candidate_for_evidence()"))
        XCTAssertTrue(script.contains("/usr/bin/open -n -F \"$REPO_ROOT/dist/$APP_NAME.app\" \\"))
        XCTAssertTrue(script.contains("--env SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \\"))
        XCTAssertTrue(script.contains("--env SOLOPM_LAUNCH_RECOVERY_MODE=1 \\"))
        XCTAssertTrue(script.contains("--env \"SOLOPM_DATABASE_PATH=$EXPECTED_DATABASE_PATH\" \\"))
        XCTAssertTrue(script.contains("--env \"SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=$EXPECTED_SELECTED_DESTINATION\""))
        XCTAssertTrue(script.contains("wait_for_voiceover_candidate_process"))
        XCTAssertTrue(script.contains("wait_for_voiceover_candidate_windows"))
        XCTAssertFalse(script.contains("tell application \"$APP_NAME\" to activate"))
        XCTAssertFalse(script.contains("tell application \"$APP_NAME\" to quit"))
        let worksheetCheckRange = try XCTUnwrap(script.range(of: "verify_voiceover_worksheet_for_evidence"))
        let launchCandidateRange = try XCTUnwrap(script.range(of: "launch_voiceover_candidate_for_evidence"))
        XCTAssertLessThan(worksheetCheckRange.lowerBound, launchCandidateRange.lowerBound)
        XCTAssertTrue(script.contains("launch_voiceover_candidate_for_evidence"))
        XCTAssertTrue(script.contains("--validate-only"))
        XCTAssertTrue(script.contains("Validate the filled VoiceOver evidence command before writing tracked evidence."))
        XCTAssertTrue(script.contains("validate_only=0"))
        XCTAssertTrue(script.contains("usage: $0 [--validate-only]"))
        XCTAssertTrue(script.contains("validate_only=1"))
        XCTAssertTrue(script.contains("if [[ \"$validate_only\" == \"1\" ]]; then"))
        XCTAssertTrue(script.contains("OK: VoiceOver evidence command validated without writing tracked evidence"))
        XCTAssertTrue(script.contains("  exit 0"))
        let validateOnlyRange = try XCTUnwrap(script.range(of: "write_voiceover_evidence_invocation \"--validate-only\""))
        let validateExitRange = try XCTUnwrap(script.range(of: "OK: VoiceOver evidence command validated without writing tracked evidence"))
        let validateExitCommandRange = try XCTUnwrap(script.range(of: "  exit 0", range: validateExitRange.upperBound..<script.endIndex))
        let passedRange = try XCTUnwrap(script.range(of: "write_voiceover_evidence_invocation \"--passed\""))
        XCTAssertLessThan(validateOnlyRange.lowerBound, validateExitRange.lowerBound)
        XCTAssertLessThan(validateExitCommandRange.lowerBound, passedRange.lowerBound)
        XCTAssertLessThan(validateExitRange.lowerBound, passedRange.lowerBound)
        XCTAssertTrue(script.contains("--capture-runtime-ax-smoke"))
        XCTAssertTrue(script.contains("--project-navigation-note"))
        XCTAssertTrue(script.contains("--task-content-execution-note"))
        XCTAssertTrue(script.contains("--delete-confirmation-note \"$WORKSHEET_DELETE_CONFIRMATION_NOTE\""))
        XCTAssertTrue(script.contains("--no-keyboard-trap-note \"$WORKSHEET_NO_KEYBOARD_TRAP_NOTE\""))
        XCTAssertTrue(script.contains("--no-unlabeled-crud-note \"$WORKSHEET_NO_UNLABELED_CRUD_NOTE\""))
        XCTAssertFalse(script.contains("focus leaves sidebar, board, inspector, and dialogs"))
        XCTAssertTrue(script.contains("chmod +x \"$output_path\""))
        XCTAssertTrue(script.contains("Pending evidence: %s\\n"))
        XCTAssertTrue(script.contains("Worksheet: %s\\n"))
        XCTAssertTrue(script.contains("Evidence command: %s\\n"))
        XCTAssertTrue(script.contains("OK: VoiceOver review candidate ready"))
        XCTAssertTrue(script.contains("--no-launch"))
        XCTAssertTrue(script.contains("--skip-build"))
        XCTAssertFalse(script.contains(":memory:"))

        let releaseChecklist = try readPackageFile("docs/release/checklist.md")
        XCTAssertTrue(releaseChecklist.contains("The generated VoiceOver evidence command requires a clean tracked source tree, pins the release-candidate source commit it was created for, and exits before writing evidence if the worktree is dirty or has moved to another commit."))
        XCTAssertTrue(releaseChecklist.contains("Run `.tmp/voiceover-review/create-evidence-command.sh --validate-only` first; it performs the same passed-evidence validation and exits before writing `docs/release/evidence/accessibility-voiceover.md`."))
        XCTAssertTrue(releaseChecklist.contains("The script also writes `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md` so the reviewer can inspect the current release-candidate context without modifying tracked evidence."))
        XCTAssertTrue(releaseChecklist.contains("Direct `./script/create_voiceover_evidence.sh --pending` also defaults to `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md`; it must not modify `docs/release/evidence/accessibility-voiceover.md` unless `--output` points there explicitly."))
        XCTAssertTrue(releaseChecklist.contains("The generated `.tmp/voiceover-review/launch.env` records `SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT` and `SOLOPM_VOICEOVER_REVIEW_PROJECT_ID` so manual reviewers can confirm the launched candidate matches the release-candidate source commit and seeded project."))
        XCTAssertTrue(releaseChecklist.contains("The generated evidence command reloads that `launch.env`, verifies the seeded candidate database and project id, launches the same candidate before runtime AX smoke capture, and blocks if the helper context is stale."))
        XCTAssertTrue(releaseChecklist.contains("The generated VoiceOver evidence command also verifies `.tmp/voiceover-review/voiceover-worksheet.md` is marked completed, pinned to the same source commit and candidate database, free of unchecked/pending/template markers, and filled before validate-only or passed evidence can run."))
        XCTAssertTrue(releaseChecklist.contains("The generated VoiceOver evidence command reads reviewer, environment, and focus observations from the completed worksheet, so manual reviewers do not retype VoiceOver notes into shell placeholders."))
        XCTAssertTrue(releaseChecklist.contains("The generated VoiceOver evidence command also rejects boilerplate worksheet values such as `TBD`, `Verified`, `OK`, or `No issues`; each required worksheet field must contain concrete VoiceOver observations."))
        XCTAssertTrue(releaseChecklist.contains("The worksheet maps `approved-execution-receipt` to the Task content execution note so manual reviewers confirm the approved execution receipt, not only the Run approved plan button."))
        XCTAssertTrue(releaseChecklist.contains("The seeded VoiceOver candidate includes a dedicated approved execution receipt task so the manual pass has a concrete task title/detail pair to run and hear back from `approved-execution-receipt`."))
        XCTAssertTrue(releaseChecklist.contains("The seeded VoiceOver candidate also includes a due-today Today rail task so manual reviewers select a concrete task before checking next action, task detail, focus, schedule draft, edit, subtask draft, and reminder draft controls."))
        XCTAssertTrue(releaseChecklist.contains("The Task content execution observation must explicitly mention the redacted receipt, reviewed title, and reviewed detail"))
        XCTAssertTrue(releaseChecklist.contains("--task-content-execution-note"))
        let phase11 = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        XCTAssertTrue(phase11.contains("[x] `script/prepare_voiceover_review_candidate.sh` pins `.tmp/voiceover-review/create-evidence-command.sh` to a clean tracked source tree and the release-candidate source commit it was generated for"))
        XCTAssertTrue(phase11.contains("[x] `script/prepare_voiceover_review_candidate.sh` writes `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md` with the current release-candidate `Source commit` without modifying tracked evidence."))
        XCTAssertTrue(phase11.contains("[x] Direct `script/create_voiceover_evidence.sh --pending` defaults to `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md` and does not modify tracked VoiceOver release evidence unless `--output` explicitly points there."))
        XCTAssertTrue(phase11.contains("[x] `script/prepare_voiceover_review_candidate.sh` writes `.tmp/voiceover-review/launch.env` with `SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT` and `SOLOPM_VOICEOVER_REVIEW_PROJECT_ID` so manual reviewers do not launch stale VoiceOver candidates."))
        XCTAssertTrue(phase11.contains("[x] Generated VoiceOver evidence command reloads `.tmp/voiceover-review/launch.env`, verifies the seeded candidate database/project id, and launches the same candidate before runtime AX smoke capture."))
        XCTAssertTrue(phase11.contains("[x] Generated VoiceOver evidence command verifies `.tmp/voiceover-review/voiceover-worksheet.md` is current, marked completed, filled, and free of pending/unchecked markers before validate-only or passed evidence."))
        XCTAssertTrue(phase11.contains("[x] Generated VoiceOver evidence command reads the completed worksheet values directly into `script/create_voiceover_evidence.sh`, so the reviewer does not duplicate focus notes in command-line placeholders."))
        XCTAssertTrue(phase11.contains("[x] Generated VoiceOver evidence command rejects boilerplate worksheet values such as `TBD`, `Verified`, `OK`, or `No issues`; each required worksheet field must contain concrete VoiceOver observations."))
        XCTAssertTrue(phase11.contains("[x] VoiceOver evidence generator and generated worksheet command require a Task content execution observation proving approved execution records the reviewed task title and detail in the redacted receipt, and reject notes that only prove the Run approved plan control was reachable."))
        XCTAssertTrue(phase11.contains("[x] VoiceOver review candidate seeds a dedicated approved execution receipt task so manual reviewers can prove the reviewed title/detail is announced from `approved-execution-receipt`."))
        XCTAssertTrue(phase11.contains("[x] `script/create_voiceover_evidence.sh --validate-only` validates the filled manual command without writing tracked evidence."))
        XCTAssertTrue(phase11.contains("[x] Generated `.tmp/voiceover-review/create-evidence-command.sh --validate-only` exits after validation without writing tracked VoiceOver evidence."))
    }

    func testVoiceOverReviewCandidateSeedsTodayRailTaskForManualVoiceOverActions() throws {
        let script = try readPackageFile("script/prepare_voiceover_review_candidate.sh")

        XCTAssertTrue(script.contains("'Review Today rail next action with VoiceOver'"))
        XCTAssertTrue(script.contains("'Open Today and confirm the seeded task drives the assistant rail next action, task detail, focus, schedule draft, edit, subtask draft, and reminder draft controls.'"))
        XCTAssertTrue(script.contains("strftime('%Y-%m-%dT%H:%M:%SZ', 'now')"))
        XCTAssertTrue(script.contains("verify_seed \"1\" \"Today rail seed task\""))
        XCTAssertTrue(script.contains("title='Review Today rail next action with VoiceOver' AND due_at <= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+1 minute')"))
        XCTAssertTrue(script.contains("if [[ \"$SEEDED_TASK_COUNT\" != \"7\" ]]; then"))
        XCTAssertTrue(script.contains("SELECT CASE WHEN count(*) = 7 THEN 1 ELSE 0 END FROM tasks WHERE project_id=$seed_project_id AND source_command='voiceover-review-seed';"))
        XCTAssertTrue(script.contains("- [ ] Today rail actions: Open Today, select `Review Today rail next action with VoiceOver`, then confirm next action, task detail, focus, schedule draft, edit, subtask draft, and reminder draft controls are announced."))
    }

    func testReleaseReadinessReportCanUseAutomatedPreflightEvidenceInsteadOfRerunningLocalProofGates() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-automated-preflight-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let scriptsDirectory = fixtureRoot.appendingPathComponent("scripts", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let tmpDirectory = fixtureRoot.appendingPathComponent(".tmp", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let crudSmokeURL = scriptDirectory.appendingPathComponent("check_local_crud_smoke.sh")
        let accessibleCRUDSmokeURL = scriptDirectory.appendingPathComponent("check_runtime_accessible_crud_smoke.sh")
        let accessibilityURL = scriptDirectory.appendingPathComponent("check_accessibility_preflight.sh")
        let buildAndRunURL = scriptDirectory.appendingPathComponent("build_and_run.sh")
        let mcpComplianceURL = scriptDirectory.appendingPathComponent("verify_mcp_compliance.sh")
        let ciURL = scriptsDirectory.appendingPathComponent("ci.sh")
        let evidenceURL = tmpDirectory.appendingPathComponent("automated-release-preflight.md")
        let actionSummaryURL = fixtureRoot.appendingPathComponent("release-actions.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        let currentShortCommit = try currentShortGitCommit()
        try """
        # Automated Release Preflight Evidence

        Status: passed
        Generated by: script/check_automated_release_preflight.sh
        Generated at: 2026-06-19T12:30:44Z
        Source commit: \(currentShortCommit)
        Tracked source tree: clean
        App: SoloPM
        Xcode workspace: .swiftpm/xcode/package.xcworkspace
        Xcode scheme: SoloPM
        Xcode configuration: Release
        Xcode destination: platform=macOS
        VoiceOver candidate source commit: \(currentShortCommit)
        VoiceOver candidate project ID: 42
        VoiceOver candidate database: /tmp/SoloPM-voiceover-review.sqlite
        VoiceOver candidate selected destination: project:42

        ## Passed Gates

        - Release CI: passed
        - Local CRUD smoke: passed
        - Runtime accessible CRUD smoke: passed
        - Layout stability smoke: passed
        - Xcode build preflight: passed
        - Launch preflight: passed
        - Runtime accessibility preflight: passed
        - MCP compliance preflight: passed

        ## Runtime AX Smoke

        Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=31, textFields=2, staticTexts=29, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        ## Boundaries

        - This does not mark the release ready.
        - Manual VoiceOver evidence remains separate.
        - Competitor hands-on evidence remains separate.
        - Developer ID signing, notarization, Sparkle, Gatekeeper, and clean-environment evidence remain separate.
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "release environment fixture blocker\\n"
        exit 23
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "automated proof fixture should not run: $0\\n"
        exit 99
        """.write(to: ciURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "automated proof fixture should not run: $0\\n"
        exit 99
        """.write(to: crudSmokeURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "automated proof fixture should not run: $0\\n"
        exit 99
        """.write(to: accessibleCRUDSmokeURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "automated proof fixture should not run: $0\\n"
        exit 99
        """.write(to: buildAndRunURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        if [[ "$*" == *"--runtime"* ]]; then
          printf "automated proof fixture should not run: runtime AX\\n"
          exit 99
        fi
        printf "OK: accessibility source anchors are present (fixture)\\n"
        """.write(to: accessibilityURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        evidence_file="${SOLOPM_MCP_EVIDENCE_FILE:-}"
        if [[ -n "$evidence_file" ]]; then
          cat > "$evidence_file" <<'EOF'
        Generated:
        Scope: validate the release MCP stdio fixture
        Stable baseline: `2025-11-25`
        Official stable latest: `2025-11-25`
        Official latest source: https://modelcontextprotocol.io/specification
        Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases
        Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release.
        Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning
        Official versioning assertion: current protocol version is `2025-11-25`
        Official latest checked: 2026-06-24
        Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18
        Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/
        EMA remote authorization is not a SoloPM public-alpha release target
        Official stable source: https://modelcontextprotocol.io/specification/2025-11-25
        Draft watchlist: `2026-07-28`
        Draft release-candidate source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/
        Draft changelog source: https://modelcontextprotocol.io/specification/draft/changelog
        Draft changelog assertion: changes are listed since `2025-11-25`; it is not the current release baseline.
        2026-07-28 is release-candidate; final specification is scheduled for 2026-07-28.
        Draft 2026-07-28 removes initialize/notifications/initialized and protocol-level sessions
        per-request `_meta` protocolVersion/clientInfo/clientCapabilities
        Draft `server/discover` is required
        Draft tools/list cache hints `ttlMs` / `cacheScope` are not implemented
        not a full MCP host
        initialize -> tools/list -> tools/call
        MCP Inspector CLI tools/list
        MCP Inspector CLI tools/call
        SoloPM local smoke success
        malformed-json
        mismatched-id
        invalid-schema
        timeout
        exit: 0
        EOF
        fi
        printf "mcp compliance fixture ok\\n"
        """.write(to: mcpComplianceURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [
            reportURL,
            releasePreflightURL,
            ciURL,
            crudSmokeURL,
            accessibleCRUDSmokeURL,
            accessibilityURL,
            buildAndRunURL,
            mcpComplianceURL
        ] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(
            ["bash", reportURL.path],
            environment: [
                "SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE": evidenceURL.path,
                "SOLOPM_RELEASE_ACTIONS_FILE": actionSummaryURL.path,
                "SOLOPM_XCODE_CONFIGURATION": "Release"
            ]
        )
        let actionSummary = try String(contentsOf: actionSummaryURL, encoding: .utf8)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("== Automated preflight evidence =="))
        XCTAssertTrue(result.output.contains("OK: automated preflight evidence covers current commit and all local proof gates"))
        XCTAssertTrue(result.output.contains("OK: release CI preflight covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: local CRUD smoke covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: runtime accessible CRUD smoke covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: layout stability smoke covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: release Xcode preflight covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: release launch preflight covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: accessibility runtime preflight covered by automated preflight evidence"))
        XCTAssertFalse(result.output.contains("release CI preflight was not run"))
        XCTAssertFalse(result.output.contains("local CRUD smoke was not run"))
        XCTAssertFalse(result.output.contains("runtime accessible CRUD smoke was not run"))
        XCTAssertFalse(result.output.contains("layout stability smoke was not run"))
        XCTAssertFalse(result.output.contains("release Xcode preflight was not run"))
        XCTAssertFalse(result.output.contains("release launch preflight was not run"))
        XCTAssertFalse(result.output.contains("accessibility runtime preflight was not run"))
        XCTAssertFalse(result.output.contains("automated proof fixture should not run"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
        XCTAssertTrue(actionSummary.contains("## Automated Proof Gates"))
        XCTAssertTrue(actionSummary.contains("- [x] Automated preflight evidence accepted: `.tmp/automated-release-preflight.md`"))
        XCTAssertTrue(actionSummary.contains("- Source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(actionSummary.contains("- Release candidate product source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(actionSummary.contains("- Generated at: `2026-06-19T12:30:44Z`"))
        XCTAssertTrue(actionSummary.contains("- Runtime AX smoke: `OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=31, textFields=2, staticTexts=29, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1`"))
        XCTAssertTrue(actionSummary.contains("- [x] Release CI: passed"))
        XCTAssertTrue(actionSummary.contains("- [x] Local CRUD smoke: passed"))
        XCTAssertTrue(actionSummary.contains("- [x] Runtime accessible CRUD smoke: passed"))
        XCTAssertTrue(actionSummary.contains("- [x] Layout stability smoke: passed"))
        XCTAssertTrue(actionSummary.contains("- [x] Xcode build preflight: passed"))
        XCTAssertTrue(actionSummary.contains("- [x] Launch preflight: passed"))
        XCTAssertTrue(actionSummary.contains("- [x] Runtime accessibility preflight: passed"))
        XCTAssertTrue(actionSummary.contains("- [x] MCP compliance preflight: passed"))
        XCTAssertTrue(actionSummary.contains("## Local Product Gate Status"))
        XCTAssertTrue(actionSummary.contains("Local product gates"))
        XCTAssertTrue(actionSummary.contains("The generated VoiceOver evidence command is pinned to a clean tracked source tree and the release-candidate source commit it was created for."))
        XCTAssertTrue(actionSummary.contains("The generated competitor hands-on evidence command is pinned to a clean tracked source tree and the release-candidate source commit it was created for."))
        XCTAssertTrue(actionSummary.contains("The generated competitor hands-on evidence command also refuses to run until `.tmp/competitor-hands-on/hands-on-worksheet.md` and `.tmp/competitor-hands-on/competitor-benchmark-pending-\(currentShortCommit).md` are `Status: completed`, pinned to the same source commit, free of pending/unchecked/template markers, and filled."))
        XCTAssertTrue(actionSummary.contains("The generated release-machine evidence command is pinned to a clean tracked source tree and the release evidence source commit it was created for."))
        XCTAssertTrue(actionSummary.contains("The generated release-machine evidence command also refuses to run until `.tmp/release-machine/release-machine-worksheet.md` is `Status: completed`, pinned to the same source commit, free of pending/unchecked/template markers, and filled."))
        XCTAssertTrue(actionSummary.contains("## Manual Evidence Source Hygiene"))
        XCTAssertTrue(actionSummary.contains("Direct manual evidence scripts enforce the same clean tracked source tree guard before writing passed evidence."))
        XCTAssertTrue(actionSummary.contains("Release-machine evidence must include `generator.name: script/create_release_evidence.sh`; hand-written `packaging/release-evidence.json` files without that canonical generator field stay blocked by `verify_release_environment.sh`."))
        XCTAssertTrue(actionSummary.contains("Do not bypass the generated command files to work around a dirty tree."))
        XCTAssertFalse(actionSummary.contains("- Run: `SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh`"))
    }

    func testReleaseReadinessReportAutoDiscoversCurrentCommitAutomatedPreflightEvidence() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-automated-preflight-auto-discovery", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let scriptsDirectory = fixtureRoot.appendingPathComponent("scripts", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let tmpDirectory = fixtureRoot.appendingPathComponent(".tmp", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let accessibilityURL = scriptDirectory.appendingPathComponent("check_accessibility_preflight.sh")
        let actionSummaryURL = fixtureRoot.appendingPathComponent("release-actions.md")
        let currentShortCommit = try currentShortGitCommit()
        let evidenceURL = tmpDirectory.appendingPathComponent("automated-release-preflight-\(currentShortCommit).md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        try """
        # Automated Release Preflight Evidence

        Status: passed
        Generated by: script/check_automated_release_preflight.sh
        Generated at: 2026-06-19T12:30:44Z
        Source commit: \(currentShortCommit)
        Tracked source tree: clean
        App: SoloPM
        Xcode workspace: .swiftpm/xcode/package.xcworkspace
        Xcode scheme: SoloPM
        Xcode configuration: Release
        Xcode destination: platform=macOS
        VoiceOver candidate source commit: \(currentShortCommit)
        VoiceOver candidate project ID: 42
        VoiceOver candidate database: /tmp/SoloPM-voiceover-review.sqlite
        VoiceOver candidate selected destination: project:42

        ## Passed Gates

        - Release CI: passed
        - Local CRUD smoke: passed
        - Runtime accessible CRUD smoke: passed
        - Layout stability smoke: passed
        - Xcode build preflight: passed
        - Launch preflight: passed
        - Runtime accessibility preflight: passed
        - MCP compliance preflight: passed

        ## Runtime AX Smoke

        Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=31, textFields=2, staticTexts=29, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        ## Boundaries

        - This does not mark the release ready.
        - Manual VoiceOver evidence remains separate.
        - Competitor hands-on evidence remains separate.
        - Developer ID signing, notarization, Sparkle, Gatekeeper, and clean-environment evidence remain separate.
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "OK: accessibility source anchors are present (fixture)\\n"
        """.write(to: accessibilityURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: accessibilityURL.path)

        let result = try runTool(
            ["bash", reportURL.path],
            environment: [
                "SOLOPM_RELEASE_ACTIONS_FILE": actionSummaryURL.path,
                "SOLOPM_XCODE_CONFIGURATION": "Release"
            ]
        )
        let actionSummary = try String(contentsOf: actionSummaryURL, encoding: .utf8)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("OK: automated preflight evidence covers current commit and all local proof gates (.tmp/automated-release-preflight-\(currentShortCommit).md)"))
        XCTAssertTrue(result.output.contains("OK: release CI preflight covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: local CRUD smoke covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: runtime accessible CRUD smoke covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: layout stability smoke covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: release Xcode preflight covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: release launch preflight covered by automated preflight evidence"))
        XCTAssertTrue(result.output.contains("OK: accessibility runtime preflight covered by automated preflight evidence"))
        XCTAssertFalse(result.output.contains("release CI preflight was not run"))
        XCTAssertFalse(result.output.contains("local CRUD smoke was not run"))
        XCTAssertFalse(result.output.contains("runtime accessible CRUD smoke was not run"))
        XCTAssertFalse(result.output.contains("layout stability smoke was not run"))
        XCTAssertFalse(result.output.contains("release Xcode preflight was not run"))
        XCTAssertFalse(result.output.contains("release launch preflight was not run"))
        XCTAssertFalse(result.output.contains("accessibility runtime preflight was not run"))
        XCTAssertTrue(actionSummary.contains("- [x] Automated preflight evidence accepted: `.tmp/automated-release-preflight-\(currentShortCommit).md`"))
        XCTAssertTrue(actionSummary.contains("- Runtime AX smoke: `OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=31, textFields=2, staticTexts=29, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1`"))
        XCTAssertTrue(actionSummary.contains("- Release candidate product source commit: `\(currentShortCommit)`"))
        XCTAssertTrue(actionSummary.contains("- VoiceOver candidate: source `\(currentShortCommit)`, project `42`, destination `project:42`"))
        XCTAssertTrue(actionSummary.contains("- VoiceOver candidate database: `/tmp/SoloPM-voiceover-review.sqlite`"))
        XCTAssertFalse(actionSummary.contains("- Run: `SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh`"))
    }

    func testReleaseReadinessReportRejectsAutomatedPreflightEvidenceWithoutRuntimeAXSmokeProof() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-automated-preflight-evidence-missing-runtime-ax", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let tmpDirectory = fixtureRoot.appendingPathComponent(".tmp", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let evidenceURL = tmpDirectory.appendingPathComponent("missing-runtime-ax-preflight.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        let currentShortCommit = try currentShortGitCommit()
        try """
        # Automated Release Preflight Evidence

        Status: passed
        Generated by: script/check_automated_release_preflight.sh
        Generated at: 2026-06-19T12:30:44Z
        Source commit: \(currentShortCommit)
        Tracked source tree: clean
        App: SoloPM
        Xcode workspace: .swiftpm/xcode/package.xcworkspace
        Xcode scheme: SoloPM
        Xcode configuration: Debug
        Xcode destination: platform=macOS
        VoiceOver candidate source commit: \(currentShortCommit)
        VoiceOver candidate project ID: 42
        VoiceOver candidate database: /tmp/SoloPM-voiceover-review.sqlite
        VoiceOver candidate selected destination: project:42

        ## Passed Gates

        - Release CI: passed
        - Local CRUD smoke: passed
        - Runtime accessible CRUD smoke: passed
        - Layout stability smoke: passed
        - Xcode build preflight: passed
        - Launch preflight: passed
        - Runtime accessibility preflight: passed
        - MCP compliance preflight: passed

        ## Boundaries

        - This does not mark the release ready.
        - Manual VoiceOver evidence remains separate.
        - Competitor hands-on evidence remains separate.
        - Developer ID signing, notarization, Sparkle, Gatekeeper, and clean-environment evidence remain separate.
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE": evidenceURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("automated preflight evidence is invalid: missing runtime AX smoke proof"))
        XCTAssertFalse(result.output.contains("OK: automated preflight evidence covers current commit and all local proof gates"))
        XCTAssertTrue(result.output.contains("release CI preflight was not run"))
    }

    func testReleaseReadinessReportRejectsAutomatedPreflightEvidenceWithoutVoiceOverCandidateContext() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-automated-preflight-evidence-missing-voiceover-candidate", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let tmpDirectory = fixtureRoot.appendingPathComponent(".tmp", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let evidenceURL = tmpDirectory.appendingPathComponent("missing-voiceover-candidate-preflight.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        let currentShortCommit = try currentShortGitCommit()
        try """
        # Automated Release Preflight Evidence

        Status: passed
        Generated by: script/check_automated_release_preflight.sh
        Generated at: 2026-06-19T12:30:44Z
        Source commit: \(currentShortCommit)
        Tracked source tree: clean
        App: SoloPM
        Xcode workspace: .swiftpm/xcode/package.xcworkspace
        Xcode scheme: SoloPM
        Xcode configuration: Debug
        Xcode destination: platform=macOS

        ## Passed Gates

        - Release CI: passed
        - Local CRUD smoke: passed
        - Runtime accessible CRUD smoke: passed
        - Layout stability smoke: passed
        - Xcode build preflight: passed
        - Launch preflight: passed
        - Runtime accessibility preflight: passed
        - MCP compliance preflight: passed

        ## Runtime AX Smoke

        Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=31, textFields=2, staticTexts=29, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        ## Boundaries

        - This does not mark the release ready.
        - Manual VoiceOver evidence remains separate.
        - Competitor hands-on evidence remains separate.
        - Developer ID signing, notarization, Sparkle, Gatekeeper, and clean-environment evidence remain separate.
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE": evidenceURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("automated preflight evidence is invalid: missing VoiceOver candidate context: VoiceOver candidate source commit"))
        XCTAssertFalse(result.output.contains("OK: automated preflight evidence covers current commit and all local proof gates"))
        XCTAssertTrue(result.output.contains("release CI preflight was not run"))
    }

    func testReleaseReadinessReportRejectsAutomatedPreflightEvidenceForDifferentAppContext() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-automated-preflight-evidence-context", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let tmpDirectory = fixtureRoot.appendingPathComponent(".tmp", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let evidenceURL = tmpDirectory.appendingPathComponent("wrong-app-preflight.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        let currentShortCommit = try currentShortGitCommit()
        try """
        # Automated Release Preflight Evidence

        Status: passed
        Generated by: script/check_automated_release_preflight.sh
        Generated at: 2026-06-19T12:30:44Z
        Source commit: \(currentShortCommit)
        Tracked source tree: clean
        App: OtherApp
        Xcode workspace: .swiftpm/xcode/package.xcworkspace
        Xcode scheme: SoloPM
        Xcode configuration: Debug
        Xcode destination: platform=macOS

        ## Passed Gates

        - Release CI: passed
        - Local CRUD smoke: passed
        - Runtime accessible CRUD smoke: passed
        - Layout stability smoke: passed
        - Xcode build preflight: passed
        - Launch preflight: passed
        - Runtime accessibility preflight: passed
        - MCP compliance preflight: passed

        ## Runtime AX Smoke

        Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=31, textFields=2, staticTexts=29, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        ## Boundaries

        - This does not mark the release ready.
        - Manual VoiceOver evidence remains separate.
        - Competitor hands-on evidence remains separate.
        - Developer ID signing, notarization, Sparkle, Gatekeeper, and clean-environment evidence remain separate.
        """.write(to: evidenceURL, atomically: true, encoding: .utf8)
        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE": evidenceURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("automated preflight evidence is invalid: app mismatch: expected SoloPM"))
        XCTAssertFalse(result.output.contains("OK: automated preflight evidence covers current commit and all local proof gates"))
        XCTAssertTrue(result.output.contains("release CI preflight was not run"))
    }

    func testReleaseReadinessReportCanRunLocalCRUDSmokeWhenEnabled() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-local-crud-smoke", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let crudSmokeURL = scriptDirectory.appendingPathComponent("check_local_crud_smoke.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
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
        set -euo pipefail
        printf "local crud fixture smoke invoked\\n"
        exit 23
        """.write(to: crudSmokeURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, preflightURL, crudSmokeURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path], environment: ["SOLOPM_LOCAL_CRUD_SMOKE": "1"])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("== Local CRUD smoke =="))
        XCTAssertTrue(result.output.contains("local crud fixture smoke invoked"))
        XCTAssertTrue(result.output.contains("BLOCKER: local CRUD smoke failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportCanRunRuntimeAccessibleCRUDSmokeWhenEnabled() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-runtime-accessible-crud-smoke", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let accessibleCRUDSmokeURL = scriptDirectory.appendingPathComponent("check_runtime_accessible_crud_smoke.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
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
        set -euo pipefail
        printf "runtime accessible crud fixture smoke invoked\\n"
        exit 23
        """.write(to: accessibleCRUDSmokeURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, preflightURL, accessibleCRUDSmokeURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path], environment: ["SOLOPM_RUNTIME_ACCESSIBLE_CRUD_SMOKE": "1"])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("== Runtime accessible CRUD smoke =="))
        XCTAssertTrue(result.output.contains("runtime accessible crud fixture smoke invoked"))
        XCTAssertTrue(result.output.contains("BLOCKER: runtime accessible CRUD smoke failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportAggregatesRuntimeMockScanTasksAndPreflight() throws {
        let script = try readPackageFile("script/release_readiness_report.sh")
        let contentCheckScript = try readPackageFile("script/ui_evidence_content_check.swift")

        XCTAssertTrue(script.contains("Sources/SoloPMCore"))
        XCTAssertTrue(script.contains("Sources/SoloPMApp"))
        XCTAssertTrue(script.contains("Sources/SoloPMCLI"))
        XCTAssertTrue(script.contains("(?i:fake|mock|fixture|canned|stub|skeleton|fixme"))
        XCTAssertTrue(script.contains("not[[:space:]_-]*implemented"))
        XCTAssertTrue(script.contains("(?i:(^|[^[:alnum:]_])(demo|sample|placeholder)([^[:alnum:]_]|$))"))
        XCTAssertTrue(script.contains("(?i:(^|[[:space:]#/*_-])todo([[:space:]:;.,)_-]|$))"))
        XCTAssertTrue(script.contains("SOLOPM_AUTOMATED_PROOF_GATES"))
        XCTAssertTrue(script.contains("SOLOPM_AUTOMATED_PROOF_GATES must be 0 or 1"))
        XCTAssertTrue(script.contains("RELEASE_CI_PREFLIGHT=\"${SOLOPM_RELEASE_CI_PREFLIGHT:-$AUTOMATED_PROOF_GATES}\""))
        XCTAssertTrue(script.contains("LOCAL_CRUD_SMOKE=\"${SOLOPM_LOCAL_CRUD_SMOKE:-$AUTOMATED_PROOF_GATES}\""))
        XCTAssertTrue(script.contains("RUNTIME_ACCESSIBLE_CRUD_SMOKE=\"${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_SMOKE:-$AUTOMATED_PROOF_GATES}\""))
        XCTAssertTrue(script.contains("RELEASE_XCODE_PREFLIGHT=\"${SOLOPM_RELEASE_XCODE_PREFLIGHT:-$AUTOMATED_PROOF_GATES}\""))
        XCTAssertTrue(script.contains("RELEASE_LAUNCH_PREFLIGHT=\"${SOLOPM_RELEASE_LAUNCH_PREFLIGHT:-$AUTOMATED_PROOF_GATES}\""))
        XCTAssertTrue(script.contains("ACCESSIBILITY_RUNTIME_PREFLIGHT=\"${SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT:-$AUTOMATED_PROOF_GATES}\""))
        XCTAssertTrue(script.contains("SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE"))
        XCTAssertTrue(script.contains("section \"Automated preflight evidence\""))
        XCTAssertTrue(script.contains("validate_automated_preflight_evidence"))
        XCTAssertTrue(script.contains("automated preflight evidence covers current commit"))
        XCTAssertTrue(script.contains("covered by automated preflight evidence"))
        XCTAssertTrue(script.contains("Generated by: script/check_automated_release_preflight.sh"))
        XCTAssertTrue(script.contains("is_utc_timestamp"))
        XCTAssertTrue(script.contains("is_future_utc_timestamp"))
        XCTAssertTrue(script.contains("Generated at"))
        XCTAssertTrue(script.contains("app mismatch: expected"))
        XCTAssertTrue(script.contains("Xcode workspace"))
        XCTAssertTrue(script.contains("Xcode scheme"))
        XCTAssertTrue(script.contains("Xcode destination"))
        XCTAssertTrue(script.contains("Xcode configuration"))
        XCTAssertTrue(script.contains("XCODE_CONFIGURATION=\"${SOLOPM_XCODE_CONFIGURATION:-Debug}\""))
        XCTAssertTrue(script.contains("EXPECTED_AUTOMATED_PREFLIGHT_XCODE_CONFIGURATION=\"$XCODE_CONFIGURATION\""))
        XCTAssertTrue(script.contains("automated_preflight_context_value \"Runtime AX smoke\""))
        XCTAssertTrue(script.contains("automated preflight runtime AX smoke missing marker"))
        XCTAssertTrue(script.contains("-configuration \"$XCODE_CONFIGURATION\""))
        XCTAssertTrue(script.contains("SOLOPM_RELEASE_CI_PREFLIGHT"))
        XCTAssertTrue(script.contains("scripts/ci.sh"))
        XCTAssertTrue(script.contains("release CI preflight failed"))
        XCTAssertTrue(script.contains("release CI preflight was not run"))
        XCTAssertTrue(script.contains("SOLOPM_LOCAL_CRUD_SMOKE"))
        XCTAssertTrue(script.contains("script/check_local_crud_smoke.sh"))
        XCTAssertTrue(script.contains("local CRUD smoke failed"))
        XCTAssertTrue(script.contains("local CRUD smoke was not run"))
        XCTAssertTrue(script.contains("SOLOPM_RUNTIME_ACCESSIBLE_CRUD_SMOKE"))
        XCTAssertTrue(script.contains("script/check_runtime_accessible_crud_smoke.sh"))
        XCTAssertTrue(script.contains("runtime accessible CRUD smoke failed"))
        XCTAssertTrue(script.contains("runtime accessible CRUD smoke was not run"))
        XCTAssertTrue(script.contains("SOLOPM_RELEASE_XCODE_PREFLIGHT"))
        XCTAssertTrue(script.contains(".swiftpm/xcode/package.xcworkspace"))
        XCTAssertTrue(script.contains("xcodebuild"))
        XCTAssertTrue(script.contains("-scheme \"$XCODE_SCHEME\""))
        XCTAssertTrue(script.contains("release Xcode preflight failed"))
        XCTAssertTrue(script.contains("release Xcode preflight was not run"))
        XCTAssertTrue(script.contains("SOLOPM_RELEASE_LAUNCH_PREFLIGHT"))
        XCTAssertTrue(script.contains("script/build_and_run.sh"))
        XCTAssertTrue(script.contains("--verify"))
        XCTAssertTrue(script.contains("release launch preflight failed"))
        XCTAssertTrue(script.contains("release launch preflight was not run"))
        XCTAssertTrue(script.contains("Static[A-Za-z0-9_]*"))
        XCTAssertFalse(script.contains("Fake|Mock|InMemory|Static|Demo|sample|canned|stub"))
        XCTAssertTrue(script.contains("Phase0-Phase11"))
        XCTAssertTrue(script.contains("Phase10-*.md"))
        XCTAssertTrue(script.contains("Phase11-*.md"))
        XCTAssertTrue(script.contains("find \"$ROOT_DIR/tasks\""))
        XCTAssertTrue(script.contains("--with-filename"))
        XCTAssertTrue(script.contains("tasks/README.md"))
        XCTAssertTrue(script.contains("verify_release_environment.sh"))
        XCTAssertTrue(script.contains("NEXT: run ./script/prepare_release_machine_evidence.sh on the release machine"))
        XCTAssertTrue(script.contains("NEXT: complete docs/release/checklist.md release-machine steps"))
        XCTAssertTrue(script.contains("missing runtime source directory"))
        XCTAssertTrue(script.contains("runtime mock/fake/fixture scan failed"))
        XCTAssertTrue(script.contains("section \"UI screenshot evidence\""))
        XCTAssertTrue(script.contains("docs/release/evidence/ui-screenshots.md"))
        XCTAssertTrue(script.contains("project-board-light.png"))
        XCTAssertTrue(script.contains("inbox-voice-light.png"))
        XCTAssertTrue(script.contains("projects-overview-light.png"))
        XCTAssertTrue(script.contains("schedule-light.png"))
        XCTAssertTrue(script.contains("done-light.png"))
        XCTAssertTrue(script.contains("settings-integrations-light.png"))
        XCTAssertTrue(script.contains("settings-overview-light.png"))
        XCTAssertTrue(script.contains("settings-appearance-light.png"))
        XCTAssertTrue(script.contains("settings-mcp-light.png"))
        XCTAssertTrue(script.contains("sips -g pixelWidth -g pixelHeight"))
        XCTAssertTrue(script.contains("assert_screenshot_has_visible_content"))
        XCTAssertTrue(script.contains("ui_evidence_content_check.swift"))
        XCTAssertTrue(contentCheckScript.contains("CGImageSourceCreateWithURL"))
        XCTAssertTrue(script.contains("ui_evidence_source_commit()"))
        XCTAssertTrue(script.contains("UI screenshot evidence is missing source commit"))
        XCTAssertTrue(script.contains("UI screenshot evidence source commit does not match current UI source commit"))
        XCTAssertTrue(script.contains("UI screenshot appears blank or too low contrast"))
        XCTAssertTrue(script.contains("missing UI screenshot file"))
        XCTAssertTrue(script.contains("UI screenshot is unexpectedly small"))
        XCTAssertTrue(script.contains("NEXT: run script/capture_ui_evidence.sh --doctor"))
        XCTAssertTrue(script.contains("then run script/capture_ui_evidence.sh on a visible macOS session with Screen Recording permission"))
        XCTAssertTrue(script.contains("section \"VoiceOver accessibility evidence\""))
        XCTAssertTrue(script.contains("script/check_accessibility_preflight.sh"))
        XCTAssertTrue(script.contains("--source-only"))
        XCTAssertTrue(script.contains("SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT"))
        XCTAssertTrue(script.contains("--runtime --skip-source-anchors"))
        XCTAssertTrue(script.contains("accessibility runtime preflight failed"))
        XCTAssertTrue(script.contains("accessibility runtime preflight was not run"))
        XCTAssertTrue(script.contains("accessibility source preflight failed"))
        XCTAssertTrue(script.contains("docs/release/evidence/accessibility-voiceover.md"))
        XCTAssertTrue(script.contains("Status: passed"))
        XCTAssertTrue(script.contains("grep -Fx \"Status: passed\""))
        XCTAssertTrue(script.contains("Project navigation"))
        XCTAssertTrue(script.contains("Inline Task Composer"))
        XCTAssertTrue(script.contains("Task inspector"))
        XCTAssertTrue(script.contains("Task content execution"))
        XCTAssertTrue(script.contains("missing VoiceOver accessibility evidence file"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence is not marked passed"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence still contains pending/template/placeholder text"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence still contains unchecked checklist markers"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence missing release context"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence has template release context"))
        XCTAssertTrue(script.contains("VoiceOver/keyboard/device details|VoiceOver / keyboard / device details|macOS version.*hardware.*VoiceOver input method.*clean user|manual pass environment"))
        XCTAssertTrue(script.contains("Runtime AX smoke"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence runtime AX smoke missing marker"))
        XCTAssertTrue(script.contains("unlabeledButtons=0"))
        XCTAssertTrue(script.contains("genericButtons=0"))
        XCTAssertTrue(script.contains("crudSignals=8/8"))
        XCTAssertTrue(script.contains("focusPathSignals=6/6"))
        XCTAssertTrue(script.contains("destructiveCancelSignals=1/1"))
        XCTAssertTrue(script.contains("Generated by: script/create_voiceover_evidence.sh"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence was not generated by script/create_voiceover_evidence.sh"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence source commit does not match current release-candidate source commit"))
        XCTAssertTrue(script.contains("manual_failure_note_has_blocker"))
        XCTAssertTrue(script.contains("manual_failure_follow_up_is_actionable"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence manual failure note lacks linked regression test or follow-up issue"))
        XCTAssertTrue(script.contains("expected_voiceover_candidate_source=\"$(manual_release_evidence_source_commit)\""))
        XCTAssertFalse(script.contains("voiceover_candidate_source\" != \"$evidence_commit\""))
        XCTAssertTrue(script.contains("packaging/app_metadata.env"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence bundle identifier does not match packaging metadata"))
        XCTAssertTrue(script.contains("VoiceOver accessibility evidence app build does not match packaging metadata"))
        XCTAssertTrue(script.contains("NEXT: replace docs/release/evidence/accessibility-voiceover.md with a real VoiceOver pass"))
        XCTAssertTrue(script.contains("write_voiceover_manual_evidence_invocation \"--validate-only\""))
        XCTAssertTrue(script.contains("write_voiceover_manual_evidence_invocation \"--passed\""))
        let voiceOverValidateSourceRange = try XCTUnwrap(script.range(of: "write_voiceover_manual_evidence_invocation \"--validate-only\""))
        let voiceOverPassedSourceRange = try XCTUnwrap(script.range(of: "write_voiceover_manual_evidence_invocation \"--passed\""))
        XCTAssertLessThan(voiceOverValidateSourceRange.lowerBound, voiceOverPassedSourceRange.lowerBound)
        XCTAssertTrue(script.contains("--capture-runtime-ax-smoke"))
        XCTAssertTrue(script.contains("--task-content-execution-note"))
        XCTAssertTrue(script.contains("runtime AX smoke OK line with unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, and destructiveCancelSignals=1/1"))
        XCTAssertTrue(script.contains("Task content execution note must mention the redacted receipt, reviewed title, and reviewed detail"))
        XCTAssertTrue(script.contains("complete release-candidate context"))
        XCTAssertTrue(script.contains("section \"Competitor hands-on evidence\""))
        XCTAssertTrue(script.contains("docs/release/evidence/competitor-hands-on.md"))
        XCTAssertTrue(script.contains("docs/product/competitor-benchmark.md"))
        XCTAssertTrue(script.contains("Notion"))
        XCTAssertTrue(script.contains("Todoist"))
        XCTAssertTrue(script.contains("Linear"))
        XCTAssertTrue(script.contains("Motion"))
        XCTAssertTrue(script.contains("No external SaaS sync or team workflow was added"))
        XCTAssertTrue(script.contains("missing competitor hands-on evidence file"))
        XCTAssertTrue(script.contains("Competitor hands-on evidence is not marked passed"))
        XCTAssertTrue(script.contains("Competitor hands-on evidence still contains pending/template/placeholder text"))
        XCTAssertTrue(script.contains("Competitor hands-on evidence still contains unchecked checklist markers"))
        XCTAssertTrue(script.contains("Generated by: script/create_competitor_hands_on_evidence.sh"))
        XCTAssertTrue(script.contains("Competitor hands-on evidence was not generated by script/create_competitor_hands_on_evidence.sh"))
        XCTAssertTrue(script.contains("Competitor hands-on evidence source commit does not match current release-candidate source commit"))
        XCTAssertTrue(script.contains("Competitor hands-on evidence manual failure note lacks linked regression test or follow-up issue"))
        XCTAssertTrue(script.contains("Competitor benchmark source commit does not match current release-candidate source commit"))
        XCTAssertTrue(script.contains("Competitor benchmark still reads as desk research or a hands-on worksheet"))
        XCTAssertTrue(script.contains("macOS/browser versions|competitor app/account tiers|whether any paid trial"))
        XCTAssertTrue(script.contains("NEXT: replace docs/release/evidence/competitor-hands-on.md with a real 2-4 hour hands-on pass"))
        XCTAssertTrue(script.contains("running ./script/prepare_release_manual_helpers.sh"))
        XCTAssertTrue(script.contains("filling .tmp/competitor-hands-on/hands-on-worksheet.md and .tmp/competitor-hands-on/competitor-benchmark-pending-%s.md"))
        XCTAssertTrue(script.contains("./script/create_competitor_hands_on_evidence.sh --pending"))
        XCTAssertTrue(script.contains(".tmp/competitor-hands-on/create-evidence-command.sh"))
        XCTAssertTrue(script.contains("write_competitor_hands_on_evidence_invocation \"--validate-only\""))
        XCTAssertTrue(script.contains("write_competitor_hands_on_evidence_invocation \"--passed\""))
        let competitorValidateSourceRange = try XCTUnwrap(script.range(of: "write_competitor_hands_on_evidence_invocation \"--validate-only\""))
        let competitorPassedSourceRange = try XCTUnwrap(script.range(of: "write_competitor_hands_on_evidence_invocation \"--passed\""))
        XCTAssertLessThan(competitorValidateSourceRange.lowerBound, competitorPassedSourceRange.lowerBound)
        XCTAssertTrue(script.contains("--benchmark-output docs/product/competitor-benchmark.md"))
        XCTAssertTrue(script.contains("section \"MCP Inspector evidence\""))
        XCTAssertTrue(script.contains("script/verify_mcp_compliance.sh"))
        XCTAssertTrue(script.contains("docs/mcp-compliance.md"))
        XCTAssertTrue(script.contains("SOLOPM_MCP_EVIDENCE_FILE=\"$mcp_runtime_evidence_file\""))
        XCTAssertTrue(script.contains("MCP compliance verifier failed"))
        XCTAssertTrue(script.contains("MCP compliance verifier output is missing marker"))
        XCTAssertTrue(script.contains("MCP compliance verifier output is missing source commit"))
        XCTAssertTrue(script.contains("MCP compliance verifier output source commit does not match current MCP source commit"))
        XCTAssertTrue(script.contains("MCP compliance review is missing marker"))
        XCTAssertTrue(script.contains("OK: MCP compliance review covers stable baseline, draft boundary, release subset, and non-host positioning"))
        XCTAssertTrue(script.contains("docs/release/evidence/mcp-inspector.md"))
        XCTAssertTrue(script.contains("mcp_evidence_source_commit()"))
        XCTAssertTrue(script.contains("Last reviewed: 2026-06-24"))
        XCTAssertTrue(script.contains("Stable baseline: `2025-11-25`"))
        XCTAssertTrue(script.contains("Official latest source: https://modelcontextprotocol.io/specification"))
        XCTAssertTrue(script.contains("Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases"))
        XCTAssertTrue(script.contains("Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release."))
        XCTAssertTrue(script.contains("Official latest checked: 2026-06-24"))
        XCTAssertTrue(script.contains("Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning"))
        XCTAssertTrue(script.contains("Official versioning assertion: current protocol version is `2025-11-25`"))
        XCTAssertTrue(script.contains("Official stable source: https://modelcontextprotocol.io/specification/2025-11-25"))
        XCTAssertTrue(script.contains("Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18"))
        XCTAssertTrue(script.contains("Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/"))
        XCTAssertTrue(script.contains("EMA remote authorization is not a SoloPM public-alpha release target"))
        XCTAssertTrue(script.contains("Draft watchlist: `2026-07-28`"))
        XCTAssertTrue(script.contains("Draft changelog source: https://modelcontextprotocol.io/specification/draft/changelog"))
        XCTAssertTrue(script.contains("Draft changelog assertion: changes are listed since `2025-11-25`; it is not the current release baseline."))
        XCTAssertTrue(script.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
        XCTAssertTrue(script.contains("Draft release-candidate source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/"))
        XCTAssertTrue(script.contains("MCP Inspector CLI tools/list"))
        XCTAssertTrue(script.contains("MCP Inspector CLI tools/call"))
        XCTAssertTrue(script.contains("missing MCP Inspector evidence file"))
        XCTAssertTrue(script.contains("MCP Inspector evidence is missing marker"))
        XCTAssertTrue(script.contains("MCP Inspector evidence is missing source commit"))
        XCTAssertTrue(script.contains("MCP Inspector evidence source commit does not match current MCP source commit"))
        XCTAssertTrue(script.contains("OK: MCP Inspector evidence covers stable baseline, draft boundary, tools/list, tools/call, and failure taxonomy"))
        XCTAssertTrue(script.contains("BLOCKER"))
    }

    func testVisualBaselineManifestCoversProductScreensThemesAndSemanticTolerances() throws {
        let manifestData = try Data(contentsOf: packageRoot().appendingPathComponent("docs/quality/visual-baseline-manifest.json"))
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
            "Visual baseline manifest must be parseable JSON so release scripts can consume it without ad hoc text parsing."
        )
        let artifactRoot = try XCTUnwrap(manifest["artifactRoot"] as? String)
        let screens = try XCTUnwrap(manifest["screens"] as? [[String: Any]])
        let tolerances = try XCTUnwrap(manifest["semanticTolerances"] as? [String: Any])

        XCTAssertEqual((manifest["schemaVersion"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(artifactRoot, "docs/release/evidence/ui-screenshots")
        let screenIDs = Set(screens.compactMap { $0["id"] as? String })
        let coreSystemScreens: Set<String> = [
            "project-board",
            "inbox",
            "today",
            "settings-overview",
            "settings-appearance",
            "mcp-settings",
            "voice-command"
        ]
        let sampleDerivedScreens: Set<String> = [
            "inbox-voice",
            "projects-overview",
            "schedule",
            "schedule-workload",
            "done",
            "settings-integrations"
        ]
        XCTAssertEqual(screenIDs, coreSystemScreens.union(sampleDerivedScreens))

        for screen in screens {
            let screenID = try XCTUnwrap(screen["id"] as? String)
            let themes = try XCTUnwrap(screen["themes"] as? [String], "missing themes for \(screenID)")
            let artifacts = try XCTUnwrap(screen["artifacts"] as? [String: String], "missing artifacts for \(screenID)")
            let viewport = try XCTUnwrap(screen["viewport"] as? [String: Any], "missing viewport for \(screenID)")

            XCTAssertTrue(themes.contains("light"), "visual baseline must cover Light theme for \(screenID)")
            XCTAssertTrue(themes.contains("dark"), "visual baseline must cover Dark theme for \(screenID)")
            if coreSystemScreens.contains(screenID) {
                XCTAssertTrue(themes.contains("system"), "core visual baseline must cover System appearance for \(screenID)")
            }
            XCTAssertGreaterThanOrEqual((viewport["width"] as? NSNumber)?.intValue ?? 0, 1_200, "viewport width too small for \(screenID)")
            XCTAssertGreaterThanOrEqual((viewport["height"] as? NSNumber)?.intValue ?? 0, 720, "viewport height too small for \(screenID)")
            XCTAssertTrue((screen["axFrameAudit"] as? Bool) == true, "visual-only comparison is not enough for \(screenID)")

            for theme in themes {
                let artifact = try XCTUnwrap(artifacts[theme], "missing \(theme) artifact for \(screenID)")
                XCTAssertTrue(artifact.hasSuffix("-\(theme).png"), "artifact should encode theme in filename: \(artifact)")
                XCTAssertFalse(artifact.contains(" "), "artifact paths must stay script-friendly: \(artifact)")
            }
        }

        XCTAssertEqual(tolerances["comparisonMode"] as? String, "semantic")
        XCTAssertEqual(tolerances["allowPixelPerfectOnly"] as? Bool, false)
        XCTAssertGreaterThanOrEqual((tolerances["minimumBytes"] as? NSNumber)?.intValue ?? 0, 50_000)
        XCTAssertGreaterThanOrEqual((tolerances["minimumWidth"] as? NSNumber)?.intValue ?? 0, 640)
        XCTAssertGreaterThanOrEqual((tolerances["minimumHeight"] as? NSNumber)?.intValue ?? 0, 420)
        XCTAssertGreaterThanOrEqual((tolerances["minimumLuminanceRange"] as? NSNumber)?.intValue ?? 0, 12)
        XCTAssertGreaterThanOrEqual((tolerances["minimumColorBuckets"] as? NSNumber)?.intValue ?? 0, 8)
        XCTAssertEqual(tolerances["requiresAXFrameAudit"] as? Bool, true)
    }

    func testVisualBaselineDocumentationAndCaptureScriptDescribeReviewableUpdates() throws {
        let documentation = try readPackageFile("docs/quality/visual-baselines.md")
        let captureScript = try readPackageFile("script/capture_ui_evidence.sh")
        let visualSmokeScript = try readPackageFile("script/check_visual_regression_smoke.sh")

        for screen in [
            "Project Board",
            "Inbox",
            "Today",
            "Settings Overview",
            "Settings Appearance",
            "MCP Settings",
            "Voice Command",
            "Inbox Voice",
            "Projects Overview",
            "Schedule",
            "Schedule Workload",
            "Done",
            "Settings Integrations"
        ] {
            XCTAssertTrue(documentation.contains(screen), "visual baseline docs must explain \(screen)")
        }

        XCTAssertTrue(documentation.contains("Light / Dark / System"))
        XCTAssertTrue(documentation.contains("semantic tolerances"))
        XCTAssertTrue(documentation.contains("AX frame"))
        XCTAssertTrue(documentation.contains("before/after artifact"))
        XCTAssertTrue(documentation.contains("`--update-baselines --allow-update`"))
        XCTAssertTrue(documentation.contains("does not overwrite baselines"))

        XCTAssertTrue(captureScript.contains("VISUAL_BASELINE_MANIFEST=\"$ROOT_DIR/docs/quality/visual-baseline-manifest.json\""))
        XCTAssertTrue(captureScript.contains("SOLOPM_VISUAL_BASELINE_VIEWPORT"))
        XCTAssertTrue(captureScript.contains("set bounds of front window"))
        XCTAssertTrue(captureScript.contains("write_visual_baseline_capture_manifest"))
        XCTAssertTrue(captureScript.contains("Light/Dark/System visual baseline manifest"))

        XCTAssertTrue(visualSmokeScript.contains("visual_regression_smoke_check.swift"))
        XCTAssertTrue(visualSmokeScript.contains("SOLOPM_VISUAL_BASELINE_MANIFEST"))
        XCTAssertTrue(visualSmokeScript.contains("SOLOPM_VISUAL_SCREENSHOT_DIR"))
        XCTAssertTrue(visualSmokeScript.contains("--update-baselines"))
        XCTAssertTrue(visualSmokeScript.contains("--allow-update"))
    }

    func testVisualBaselineCaptureScriptTargetsManifestArtifacts() throws {
        let manifestData = try Data(contentsOf: packageRoot().appendingPathComponent("docs/quality/visual-baseline-manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let screens = try XCTUnwrap(manifest["screens"] as? [[String: Any]])
        let captureScript = try readPackageFile("script/capture_ui_evidence.sh")

        for screen in screens {
            let screenID = try XCTUnwrap(screen["id"] as? String)
            let artifacts = try XCTUnwrap(screen["artifacts"] as? [String: String], "missing artifacts for \(screenID)")
            for artifact in artifacts.values {
                XCTAssertTrue(captureScript.contains(artifact), "capture script must produce manifest artifact \(artifact) for \(screenID)")
            }
        }

        XCTAssertTrue(captureScript.contains("capture_project_board_destination system inbox"))
        XCTAssertTrue(captureScript.contains("inbox-voice-intake-detail=>Voice intake detail for Scheduled manual capture"))
        XCTAssertTrue(captureScript.contains("inbox-voice-transcript=>Schedule launch review and capture visual evidence."))
        XCTAssertTrue(captureScript.contains("inbox-voice-interpretation=>Create a task for launch review evidence."))
        XCTAssertTrue(captureScript.contains("inbox-action-grid=>Make Task"))
        XCTAssertTrue(captureScript.contains("capture_project_board_destination system today"))
        XCTAssertTrue(captureScript.contains("capture_project_board_destination light schedule"))
        XCTAssertTrue(captureScript.contains("capture_project_board_destination dark schedule"))
        XCTAssertTrue(captureScript.contains("capture_settings_overview system"))
        XCTAssertTrue(captureScript.contains("capture_settings_appearance system"))
        XCTAssertTrue(captureScript.contains("capture_mcp_settings_appearance system"))
        XCTAssertTrue(captureScript.contains("VOICE_COMMAND_SYSTEM_SCREENSHOT"))
    }

    func testVisualRegressionSmokeBlocksSmallBlackAndLowInformationImages() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-visual-regression-smoke-blockers", isDirectory: true)
        let screenshotDirectory = fixtureRoot.appendingPathComponent("screenshots", isDirectory: true)
        let manifestURL = fixtureRoot.appendingPathComponent("visual-baseline-manifest.json")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try writeVisiblePNG(
            to: screenshotDirectory.appendingPathComponent("too-small-light.png"),
            width: 220,
            height: 120,
            trailingBytes: 60_000
        )
        try writeSolidPNG(
            to: screenshotDirectory.appendingPathComponent("black-dark.png"),
            width: 800,
            height: 600,
            red: 0,
            green: 0,
            blue: 0,
            trailingBytes: 60_000
        )
        try writeSolidPNG(
            to: screenshotDirectory.appendingPathComponent("low-info-system.png"),
            width: 800,
            height: 600,
            red: 128,
            green: 128,
            blue: 128,
            trailingBytes: 60_000
        )
        try visualBaselineManifestFixture(
            artifacts: [
                "light": "too-small-light.png",
                "dark": "black-dark.png",
                "system": "low-info-system.png"
            ]
        ).write(to: manifestURL, atomically: true, encoding: .utf8)

        let result = try runScript(
            "script/check_visual_regression_smoke.sh",
            arguments: [
                "--manifest", manifestURL.path,
                "--screenshot-dir", screenshotDirectory.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("BLOCKER: visual screenshot dimensions are too small"))
        XCTAssertTrue(result.output.contains("BLOCKER: visual screenshot appears black"))
        XCTAssertTrue(result.output.contains("BLOCKER: visual screenshot is low information"))
    }

    func testVisualRegressionSmokeRequiresExplicitBaselineUpdateAndNormalRunDoesNotOverwrite() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-visual-regression-smoke-update-guard", isDirectory: true)
        let screenshotDirectory = fixtureRoot.appendingPathComponent("screenshots", isDirectory: true)
        let baselineDirectory = fixtureRoot.appendingPathComponent("baselines", isDirectory: true)
        let manifestURL = fixtureRoot.appendingPathComponent("visual-baseline-manifest.json")
        let baselineURL = baselineDirectory.appendingPathComponent("project-board-light.png")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: baselineDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try writeVisiblePNG(
            to: screenshotDirectory.appendingPathComponent("project-board-light.png"),
            width: 800,
            height: 600,
            trailingBytes: 60_000
        )
        try "existing baseline\n".write(to: baselineURL, atomically: true, encoding: .utf8)
        try visualBaselineManifestFixture(artifacts: ["light": "project-board-light.png"])
            .write(to: manifestURL, atomically: true, encoding: .utf8)

        let guardedUpdateResult = try runScript(
            "script/check_visual_regression_smoke.sh",
            arguments: [
                "--manifest", manifestURL.path,
                "--screenshot-dir", screenshotDirectory.path,
                "--baseline-dir", baselineDirectory.path,
                "--update-baselines"
            ]
        )

        XCTAssertNotEqual(guardedUpdateResult.exitCode, 0)
        XCTAssertTrue(guardedUpdateResult.output.contains("baseline update requires --allow-update"))

        let normalResult = try runScript(
            "script/check_visual_regression_smoke.sh",
            arguments: [
                "--manifest", manifestURL.path,
                "--screenshot-dir", screenshotDirectory.path,
                "--baseline-dir", baselineDirectory.path
            ]
        )

        XCTAssertEqual(normalResult.exitCode, 0, normalResult.output)
        XCTAssertEqual(try String(contentsOf: baselineURL, encoding: .utf8), "existing baseline\n")
        XCTAssertTrue(normalResult.output.contains("OK: visual regression smoke passed"))
    }

    func testReleaseReadinessReportCanWriteOperatorActionSummaryWithoutPassingManualGates() throws {
        let script = try readPackageFile("script/release_readiness_report.sh")
        let checklist = try readPackageFile("docs/release/checklist.md")
        let phase = try readPackageFile("tasks/Phase10-ReleaseReadinessRuntime.md")

        XCTAssertTrue(script.contains("SOLOPM_RELEASE_ACTIONS_FILE"))
        XCTAssertTrue(script.contains("# SoloPM Release Actions"))
        XCTAssertTrue(script.contains("Status: not-ready"))
        XCTAssertTrue(script.contains("Status: ready"))
        XCTAssertTrue(script.contains("Generated at:"))
        XCTAssertTrue(script.contains("Source commit:"))
        XCTAssertTrue(script.contains("Release-candidate product source commit:"))
        XCTAssertTrue(script.contains("printf \"Release-candidate product source commit: %s\\n\" \"$(manual_release_evidence_source_commit)\""))
        XCTAssertTrue(script.contains("Tracked source tree:"))
        XCTAssertTrue(script.contains("tracked_source_tree_status()"))
        XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" status --porcelain --untracked-files=no"))
        XCTAssertTrue(script.contains("RELEASE_ENVIRONMENT_BLOCKER_MESSAGES=()"))
        XCTAssertTrue(script.contains("VOICEOVER_ACTION_BLOCKERS=()"))
        XCTAssertTrue(script.contains("COMPETITOR_ACTION_BLOCKERS=()"))
        XCTAssertTrue(script.contains("collect_release_environment_blockers()"))
        XCTAssertTrue(script.contains("release_environment_route_for_blocker()"))
        XCTAssertTrue(script.contains("write_release_environment_routes()"))
        XCTAssertTrue(script.contains("collect_manual_action_blocker()"))
        XCTAssertTrue(script.contains("normalized=\"${line#- }\""))
        XCTAssertTrue(script.contains("normalized=\"${normalized#BLOCKER: }\""))
        XCTAssertTrue(script.contains("normalized=\"${normalized//$root_prefix/}\""))
        XCTAssertTrue(script.contains("## Release Environment Blockers"))
        XCTAssertTrue(script.contains("## Release Environment Routes"))
        XCTAssertTrue(script.contains("Signing Configuration"))
        XCTAssertTrue(script.contains("Sparkle / Appcast"))
        XCTAssertTrue(script.contains("Gatekeeper / Stapling"))
        XCTAssertTrue(script.contains("Release Evidence"))
        XCTAssertTrue(script.contains("## Manual VoiceOver Blockers"))
        XCTAssertTrue(script.contains("## Competitor Hands-On Blockers"))
        XCTAssertTrue(script.contains("release environment blocker contained a sensitive field"))
        XCTAssertTrue(phase.contains("[x] VoiceOver / competitor hands-on の手動証跡は `Source commit` を記録し、`Status: passed` の場合は現在のrelease-candidate product source commitと一致しない証跡をrelease blockerにする。"))
        XCTAssertTrue(phase.contains("[x] competitor benchmark の `Source commit` も `Status: passed` の competitor hands-on 証跡と同じrelease候補commitであることをrelease blockerにする。"))
        XCTAssertTrue(phase.contains("[x] action summary は report生成commit と、手動VoiceOver / competitor hands-on証跡が一致すべき release-candidate product source commit を別々に表示する。"))
        XCTAssertTrue(phase.contains("[x] UI screenshot証跡は `Sources/SoloPMApp` / `Sources/SoloPMCore` / `Package.swift` の最新UI source commitを記録し"))
        XCTAssertTrue(script.contains("Blocker groups:"))
        XCTAssertTrue(script.contains("BLOCKER_MESSAGES=()"))
        XCTAssertTrue(script.contains("BLOCKER_MESSAGES+=(\"$1\")"))
        XCTAssertTrue(script.contains("## Current Blocker Groups"))
        XCTAssertTrue(script.contains("for blocker_message in \"${BLOCKER_MESSAGES[@]}\""))
        XCTAssertTrue(script.contains("printf -- \"- [ ] %s\\n\" \"$blocker_message\""))
        XCTAssertTrue(script.contains("blocker_bucket_for_message()"))
        XCTAssertTrue(script.contains("write_blocker_bucket_summary()"))
        XCTAssertTrue(script.contains("write_operator_priority_queue()"))
        XCTAssertTrue(script.contains("## Operator Priority Queue"))
        XCTAssertTrue(script.contains("write_operator_priority_queue_line"))
        XCTAssertTrue(script.contains("nonempty_line_count()"))
        XCTAssertTrue(script.contains("release_environment_item_count"))
        XCTAssertTrue(script.contains("phase_manual_item_count"))
        XCTAssertTrue(script.contains("\"VoiceOver manual pass\""))
        XCTAssertTrue(script.contains("\"Competitor hands-on pass\""))
        XCTAssertTrue(script.contains("\"Release-machine runbook\""))
        XCTAssertTrue(script.contains("manual_helper_relative_is_current()"))
        XCTAssertTrue(script.contains("voiceover_review_helpers_are_current()"))
        XCTAssertTrue(script.contains("competitor_hands_on_helpers_are_current()"))
        XCTAssertTrue(script.contains("release_machine_helpers_are_current()"))
        XCTAssertTrue(script.contains("voiceover_priority_next_action()"))
        XCTAssertTrue(script.contains("competitor_priority_next_action()"))
        XCTAssertTrue(script.contains("release_machine_priority_next_action()"))
        XCTAssertTrue(script.contains("fill `.tmp/voiceover-review/voiceover-worksheet.md` during the manual pass, run generated `.tmp/voiceover-review/create-evidence-command.sh` validate-only first, then rerun readiness."))
        XCTAssertTrue(script.contains("run `./script/prepare_release_manual_helpers.sh`, fill `.tmp/voiceover-review/voiceover-worksheet.md`, run generated `.tmp/voiceover-review/create-evidence-command.sh` validate-only first, then rerun readiness."))
        XCTAssertTrue(script.contains("fill `.tmp/competitor-hands-on/hands-on-worksheet.md` and `.tmp/competitor-hands-on/competitor-benchmark-pending-%s.md` during the 2-4h pass, complete generated `.tmp/competitor-hands-on/create-evidence-command.sh`, run its validate-only path first, then rerun readiness."))
        XCTAssertTrue(script.contains("run `./script/prepare_release_manual_helpers.sh`, fill `.tmp/competitor-hands-on/hands-on-worksheet.md`, complete `.tmp/competitor-hands-on/create-evidence-command.sh`, then rerun readiness."))
        XCTAssertTrue(script.contains("fill `.tmp/release-machine/release-machine-worksheet.md` after signing/notarization/Sparkle/Gatekeeper checks, complete generated `.tmp/release-machine/create-release-evidence-command.sh`, run its validate-only path first, then rerun readiness."))
        XCTAssertTrue(script.contains("Login Item manual check is part of Phase checklist routing. Next: use the signed release app, complete \\`--login-item-toggle\\` in \\`.tmp/release-machine/release-machine-worksheet.md\\` and \\`.tmp/release-machine/create-release-evidence-command.sh\\`, then rerun readiness."))
        XCTAssertTrue(script.contains("release environment blocker item(s)"))
        XCTAssertTrue(script.contains("unchecked manual/release phase item(s)"))
        XCTAssertTrue(script.contains("Phase checklist routing tracks"))
        XCTAssertTrue(script.contains("linked evidence blockers control release readiness"))
        XCTAssertTrue(script.contains("## Blocker Buckets"))
        XCTAssertTrue(script.contains("write_blocker_bucket_line \"Automated Proof Gates\""))
        XCTAssertTrue(script.contains("write_blocker_bucket_line \"Manual VoiceOver\""))
        XCTAssertTrue(script.contains("write_blocker_bucket_line \"Competitor Hands-On\""))
        XCTAssertTrue(script.contains("write_blocker_bucket_line \"Release Machine\""))
        XCTAssertTrue(script.contains("write_blocker_bucket_line \"Phase Checklist\""))
        XCTAssertTrue(script.contains("phase_manual_gate_route_for_item()"))
        XCTAssertTrue(script.contains("write_phase_manual_gate_routes()"))
        XCTAssertTrue(script.contains("## Phase Manual Gate Routes"))
        XCTAssertTrue(script.contains("Login Item Manual Check"))
        XCTAssertTrue(script.contains("## Automated Proof Gates"))
        XCTAssertTrue(script.contains("Automated preflight evidence accepted"))
        XCTAssertTrue(script.contains("automated_preflight_context_value \"Generated at\""))
        XCTAssertTrue(script.contains("for required_gate in \"${AUTOMATED_PREFLIGHT_REQUIRED_GATES[@]}\""))
        XCTAssertTrue(script.contains("## Local Product Gate Status"))
        XCTAssertTrue(script.contains("write_local_product_gate_status"))
        XCTAssertTrue(script.contains("Local product gates are green for this source commit"))
        XCTAssertTrue(script.contains("Remaining gates are manual VoiceOver, competitor hands-on, and release-machine signing/notarization/Sparkle/Gatekeeper evidence."))
        XCTAssertTrue(script.contains("SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh"))
        XCTAssertTrue(script.contains("automated_preflight_default_relative_path()"))
        XCTAssertTrue(script.contains("automated_preflight_default_evidence_path()"))
        XCTAssertTrue(script.contains("Then rerun: \\`./script/release_readiness_report.sh\\` to auto-discover"))
        XCTAssertTrue(script.contains("Explicit reuse also works: \\`SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=%s ./script/release_readiness_report.sh\\`"))
        XCTAssertTrue(script.contains("SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=%s ./script/check_automated_release_preflight.sh"))
        XCTAssertTrue(script.contains("## Manual VoiceOver"))
        XCTAssertTrue(script.contains("write_voiceover_review_candidate_command()"))
        XCTAssertTrue(script.contains("./script/prepare_voiceover_review_candidate.sh --no-launch"))
        XCTAssertTrue(script.contains("./script/prepare_voiceover_review_candidate.sh"))
        XCTAssertTrue(script.contains(".tmp/voiceover-review/create-evidence-command.sh"))
        XCTAssertTrue(script.contains(".tmp/voiceover-review/voiceover-worksheet.md"))
        XCTAssertTrue(script.contains(".tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md"))
        XCTAssertTrue(script.contains("For this action summary, the expected pending preview path is \\`.tmp/voiceover-review/accessibility-voiceover-pending-%s.md\\`."))
        XCTAssertTrue(script.contains("The generated VoiceOver evidence command also refuses to run until \\`.tmp/voiceover-review/voiceover-worksheet.md\\` is \\`Status: completed\\`, pinned to the same source commit and candidate database, free of pending/unchecked/template markers, and filled."))
        XCTAssertTrue(script.contains("./script/create_voiceover_evidence.sh --passed"))
        XCTAssertTrue(script.contains("--capture-runtime-ax-smoke"))
        XCTAssertTrue(script.contains("--project-navigation-note \"<VoiceOver observation for sidebar Inbox, Today, Projects, and selected review project navigation>\""))
        XCTAssertTrue(script.contains("--inline-task-composer-note \"<VoiceOver observation for title/detail/priority/due create flow, Command+Return, and Escape>\""))
        XCTAssertTrue(script.contains("--status-controls-note \"<VoiceOver observation for previous/next status controls and target status labels>\""))
        XCTAssertTrue(script.contains("--task-content-execution-note \"<VoiceOver observation proving approved execution records reviewed task title and detail in the redacted receipt>\""))
        XCTAssertFalse(script.contains("--project-navigation-note \"<VoiceOver observation for sidebar project navigation>\""))
        XCTAssertFalse(script.contains("--inline-task-composer-note \"<VoiceOver observation for title/detail/priority/due create flow>\""))
        XCTAssertTrue(script.contains("--no-unlabeled-crud-note \"<VoiceOver observation proving create, update, status move, local suggestion apply, automation review, approved execution, and delete controls have labels or help>\""))
        XCTAssertTrue(script.contains("## Competitor Hands-On"))
        XCTAssertTrue(script.contains("Run \\`./script/prepare_release_manual_helpers.sh\\` first if you want release-candidate pending helper files for review."))
        XCTAssertTrue(script.contains("The competitor helper files include \\`.tmp/competitor-hands-on/hands-on-worksheet.md\\`, \\`.tmp/competitor-hands-on/competitor-benchmark-pending-%s.md\\`, and \\`.tmp/competitor-hands-on/create-evidence-command.sh\\`."))
        XCTAssertTrue(script.contains(".tmp/competitor-hands-on/hands-on-worksheet.md"))
        XCTAssertTrue(script.contains(".tmp/competitor-hands-on/competitor-benchmark-pending-<commit>.md"))
        XCTAssertTrue(script.contains("./script/create_competitor_hands_on_evidence.sh --pending"))
        XCTAssertTrue(script.contains(".tmp/competitor-hands-on/create-evidence-command.sh"))
        XCTAssertTrue(script.contains("For this action summary, the expected pending evidence path is \\`.tmp/competitor-hands-on/competitor-hands-on-pending-%s.md\\`."))
        XCTAssertTrue(script.contains("./script/create_competitor_hands_on_evidence.sh --passed"))
        XCTAssertTrue(script.contains("--benchmark-output docs/product/competitor-benchmark.md"))
        XCTAssertTrue(script.contains("--notion-note \"<hands-on Notion project database, board, task, and artifact observation>\""))
        XCTAssertTrue(script.contains("--reject \"<behaviors deliberately kept out of public alpha scope>\""))
        XCTAssertTrue(script.contains("## Release Machine"))
        XCTAssertTrue(script.contains("./script/prepare_release_machine_evidence.sh"))
        XCTAssertTrue(script.contains(".tmp/release-machine/release-machine-worksheet.md"))
        XCTAssertTrue(script.contains(".tmp/release-machine/create-release-evidence-command.sh"))
        XCTAssertTrue(script.contains("The generated VoiceOver evidence command is pinned to a clean tracked source tree and the release-candidate source commit it was created for."))
        XCTAssertTrue(script.contains("Rerun \\`./script/prepare_release_manual_helpers.sh\\` after source changes instead of reusing an older command."))
        XCTAssertTrue(script.contains("The generated competitor hands-on evidence command is pinned to a clean tracked source tree and the release-candidate source commit it was created for."))
        XCTAssertTrue(script.contains("The generated competitor hands-on evidence command also refuses to run until \\`.tmp/competitor-hands-on/hands-on-worksheet.md\\` and \\`.tmp/competitor-hands-on/competitor-benchmark-pending-%s.md\\` are \\`Status: completed\\`, pinned to the same source commit, free of pending/unchecked/template markers, and filled."))
        XCTAssertTrue(script.contains("The generated release-machine evidence command is pinned to a clean tracked source tree and the release evidence source commit it was created for."))
        XCTAssertTrue(script.contains("The generated release-machine evidence command also refuses to run until \\`.tmp/release-machine/release-machine-worksheet.md\\` is \\`Status: completed\\`, pinned to the same source commit, free of pending/unchecked/template markers, and filled."))
        XCTAssertTrue(script.contains("Run the generated \\`--validate-only\\` release evidence command first; it performs the same validation without writing \\`packaging/release-evidence.json\\`."))
        XCTAssertTrue(script.contains("## Manual Evidence Source Hygiene"))
        XCTAssertTrue(script.contains("Direct manual evidence scripts enforce the same clean tracked source tree guard before writing passed evidence."))
        XCTAssertTrue(script.contains("Release-machine evidence must include \\`generator.name: script/create_release_evidence.sh\\`"))
        XCTAssertTrue(script.contains("Do not bypass the generated command files to work around a dirty tree."))
        XCTAssertTrue(script.contains("packaging/signing.env"))
        XCTAssertTrue(script.contains("packaging/notarization.env"))
        XCTAssertTrue(script.contains("./script/check_release_machine_local_doctor.sh"))
        XCTAssertTrue(script.contains("write_release_machine_runbook_command()"))
        XCTAssertTrue(script.contains("./script/verify_signing_setup.sh"))
        XCTAssertTrue(script.contains("SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh"))
        XCTAssertTrue(script.contains("SOLOPM_PACKAGE_FORMAT=all ./script/package_release.sh"))
        XCTAssertTrue(script.contains("SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/generate_appcast.sh"))
        XCTAssertTrue(script.contains("./script/create_release_evidence.sh --validate-only"))
        XCTAssertTrue(script.contains("./script/verify_release_environment.sh"))
        XCTAssertTrue(script.contains("This file is an action summary, not release evidence."))
        XCTAssertTrue(script.contains("does not mark manual VoiceOver, competitor hands-on, signing, notarization, Sparkle, or Gatekeeper checks as passed"))
        XCTAssertTrue(script.contains("## Persistent Manual Unblocker Runbook"))
        XCTAssertTrue(script.contains("docs/release/manual-unblockers.md"))
        XCTAssertTrue(script.contains("Use the persistent runbook above as the stable checklist when this generated action summary is replaced or regenerated."))
        XCTAssertTrue(script.contains("Generated manual/release command files must fail validation until every placeholder is replaced."))
        XCTAssertTrue(script.contains("A passing \\`--validate-only\\` run only means the command is ready to write evidence; it does not mean the manual pass is complete."))
        XCTAssertTrue(script.contains("Release action summary written to"))

        XCTAssertTrue(checklist.contains("SOLOPM_RELEASE_ACTIONS_FILE=.tmp/release-actions.md ./script/release_readiness_report.sh"))
        XCTAssertTrue(checklist.contains("Every generated action summary includes a Persistent Manual Unblocker Runbook section that links back to `docs/release/manual-unblockers.md`"))
        XCTAssertTrue(checklist.contains("The Operator Priority Queue appears before the full blocker list and shows the highest-impact manual lanes, the blocker count each lane can clear, the release-environment item count for the release-machine lane, the unchecked manual phase-item count for checklist routing, and the next worksheet plus generated command/helper to use."))
        XCTAssertTrue(checklist.contains("The Operator Priority Queue names the manual worksheet before the generated command for VoiceOver, competitor hands-on, release-machine, and login-item evidence lanes."))
        XCTAssertTrue(checklist.contains("The action summary groups remaining blockers into Automated Proof Gates, Manual VoiceOver, Competitor Hands-On, Release Machine, Phase Checklist, and Other buckets."))
        XCTAssertTrue(checklist.contains("The action summary includes a Local Product Gate Status section so reviewers can distinguish current-commit local MCP/data/CRUD proof from manual and release-machine blockers."))
        XCTAssertTrue(checklist.contains("When valid clean-tree automated preflight evidence is supplied, the Automated Proof Gates section shows the accepted evidence file, source commit, release-candidate product source commit, generated timestamp, runtime AX smoke OK line, and passed gates"))
        XCTAssertTrue(checklist.contains("The action summary header lists both the report `Source commit` and `Release-candidate product source commit`"))
        XCTAssertTrue(checklist.contains("If a login item manual gate remains, the Operator Priority Queue also calls out the signed-app Launch at Login check and points to `--login-item-toggle` in `.tmp/release-machine/create-release-evidence-command.sh`."))
        XCTAssertTrue(checklist.contains("routes unchecked manual gates to Manual VoiceOver, Competitor Hands-On, Release Machine, Login Item Manual Check, or Manual Review"))
        XCTAssertTrue(checklist.contains("routes verifier blockers to Signing Configuration, Notarization, Sparkle / Appcast, Gatekeeper / Stapling, Release Evidence, Source Hygiene, or Local Inspection"))
        XCTAssertTrue(checklist.contains("./script/prepare_release_machine_evidence.sh"))
        XCTAssertTrue(checklist.contains(".tmp/release-machine/release-machine-worksheet.md"))
        XCTAssertTrue(checklist.contains(".tmp/release-machine/create-release-evidence-command.sh"))
        XCTAssertTrue(checklist.contains("That command block now edits and runs the generated `.tmp/release-machine/create-release-evidence-command.sh` before showing the direct `create_release_evidence.sh --force` fallback"))
        XCTAssertTrue(checklist.contains("The Manual Review Helper Freshness section uses `./script/prepare_release_manual_helpers.sh` to regenerate VoiceOver and competitor helper files for the release-candidate product source commit and release-machine helper files for the current release evidence source commit without writing passed evidence."))
        XCTAssertTrue(checklist.contains("Manual Review Helper Freshness verifies `.tmp/voiceover-review/launch.env` contains `SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT` for the release-candidate source commit and a concrete `SOLOPM_VOICEOVER_REVIEW_PROJECT_ID`."))
        XCTAssertTrue(checklist.contains("if legacy default `.tmp/competitor-hands-on/evidence.md` remains, the Ignored Stale Manual Helper Previews section lists them as ignored so operators do not copy stale release-candidate context into tracked evidence"))
        XCTAssertTrue(checklist.contains("`./script/prepare_release_manual_helpers.sh --prune-stale` removes ignored old pending previews and legacy default preview files after the release-candidate helpers are regenerated"))
        XCTAssertTrue(checklist.contains("The Competitor Hands-On section includes `./script/prepare_release_manual_helpers.sh`, `.tmp/competitor-hands-on/hands-on-worksheet.md`, `.tmp/competitor-hands-on/competitor-benchmark-pending-<commit>.md`, and `.tmp/competitor-hands-on/create-evidence-command.sh` before the final passed command"))
        XCTAssertTrue(checklist.contains("Its generated command now refuses to run until the worksheet is `Status: completed`, source-pinned, filled, and free of pending/unchecked/template markers."))
        XCTAssertTrue(checklist.contains("The generated release-machine command refuses to run until its worksheet is `Status: completed`, source-pinned, filled, free of pending/unchecked/template markers, and free of boilerplate values such as `TBD`, `Verified`, `OK`, or `manual checks completed`."))
        XCTAssertTrue(checklist.contains("The Manual VoiceOver section includes `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md`, `.tmp/voiceover-review/voiceover-worksheet.md`, and `.tmp/voiceover-review/create-evidence-command.sh` before the final passed command"))
        XCTAssertTrue(checklist.contains("Its generated command now refuses to run until the VoiceOver worksheet is `Status: completed`, source/database-pinned, filled, and free of pending/unchecked/template markers, reads reviewer/environment/focus notes from that worksheet, and the action summary repeats that the Task content execution note must mention the redacted receipt, reviewed title, and reviewed detail."))
        XCTAssertTrue(checklist.contains("The action summary also expands those pending paths for the current release-candidate product source commit"))
        XCTAssertTrue(checklist.contains("The action summary includes a Manual Evidence Source Hygiene section explaining that direct passed evidence scripts also require a clean tracked source tree."))
        XCTAssertTrue(checklist.contains("It also reminds operators that release-machine evidence must include `generator.name: script/create_release_evidence.sh` and that hand-written `packaging/release-evidence.json` remains blocked."))
        XCTAssertTrue(checklist.contains("Passed VoiceOver evidence must also identify the actual macOS version used for the manual pass."))
        XCTAssertTrue(checklist.contains("Generated competitor/release-machine command files must fail validate-only until every placeholder is replaced, and generated VoiceOver commands must fail until worksheet values are complete, so template commands cannot be treated as evidence-ready."))
        XCTAssertTrue(checklist.contains("When release environment preflight fails, the action summary also prints a `Release Machine Local Doctor` section with `./script/check_release_machine_local_doctor.sh` plus non-secret diagnostics"))
        XCTAssertTrue(phase.contains("[x] `release_readiness_report.sh` は `SOLOPM_RELEASE_ACTIONS_FILE` 指定時に残blockerのoperator action summaryを書き出す。"))
        XCTAssertTrue(phase.contains("[x] action summary は `Source commit` と tracked source tree の clean / dirty / unavailable 状態を併記する。"))
        XCTAssertTrue(phase.contains("[x] action summary は今回の実行で発生した具体blockerを `Current Blocker Groups` のチェックリストとして列挙する。"))
        XCTAssertTrue(phase.contains("[x] action summary は `Operator Priority Queue` を `Current Blocker Groups` より前に出し、手動VoiceOver、競合hands-on、release-machineのどれを先に実施すれば何件のblockerを減らせるか、release-machine内の環境blocker件数、Phase routing対象の手動項目数、worksheet -> generated command の順序を示す。"))
        XCTAssertTrue(phase.contains("[x] action summary は `Blocker Buckets` で Automated Proof Gates / Manual VoiceOver / Competitor Hands-On / Release Machine / Phase Checklist / Other の残件数を分類する。"))
        XCTAssertTrue(phase.contains("[x] action summary は `Release Environment Blockers` に `verify_release_environment.sh` の `BLOCKER:` 明細を相対パス化して列挙し、機密っぽい値を転記しない。"))
        XCTAssertTrue(phase.contains("[x] action summary は release environment blocker を Signing Configuration / Notarization / Sparkle / Appcast / Gatekeeper / Release Evidence / Source Hygiene / Local Inspection に分類し"))
        XCTAssertTrue(phase.contains("[x] action summary は release-machine blocker が残る場合、秘密値を出さずに Developer ID identity、local env、signing/notary/Sparkle verifier、final preflight を確認する `Release Machine Local Doctor` を表示する。"))
        XCTAssertTrue(phase.contains("[x] action summary は clean-tree automated preflight evidence が有効な場合、accepted evidence、source commit、generated at、runtime AX smoke OK行、passed gatesを表示し、再実行指示だけを出さない。"))
        XCTAssertTrue(phase.contains("[x] action summary は Local Product Gate Status でcurrent commitのMCP/data/CRUD/local proofがgreenか、残りがmanual/release-machineかを明示する。"))
        XCTAssertTrue(phase.contains("[x] action summary は `Manual VoiceOver Blockers` と `Competitor Hands-On Blockers` に手動証跡の不足項目を分離表示し、手動作業を完了扱いにしない。"))
        XCTAssertTrue(phase.contains("[x] action summary は VoiceOver の `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md` preview、`.tmp/voiceover-review/voiceover-worksheet.md`、`.tmp/voiceover-review/create-evidence-command.sh` を案内し、operatorがtracked evidenceを汚さずrelease候補contextを確認できるようにする。"))
        XCTAssertTrue(phase.contains("[x] Generated VoiceOver evidence command verifies `.tmp/voiceover-review/voiceover-worksheet.md` is current, marked completed, filled, and free of pending/unchecked markers before validate-only or passed evidence."))
        XCTAssertTrue(phase.contains("[x] action summary は VoiceOver / competitor hands-on の current `Source commit` に対応する pending evidence path も併記する。"))
        XCTAssertTrue(phase.contains("[x] action summary は competitor hands-on の pending generator と `.tmp/competitor-hands-on/create-evidence-command.sh` を案内し、operatorがplaceholderを置換してからpassed証跡を作れるようにする。"))
        XCTAssertTrue(phase.contains("[x] VoiceOver passed evidence は実際の `macOS version` を必須にし、`macOS unknown` / placeholder / sample / example / replacement text をgeneratorとreadiness reportの両方でrelease blockerにする。"))
        XCTAssertTrue(phase.contains("[x] action summary は VoiceOver / competitor hands-on / release-machine の生成済み証跡コマンドが clean tracked source tree と生成時 source commit にpinされ、source変更後は再生成が必要なことを表示する。"))
        XCTAssertTrue(phase.contains("[x] action summary の VoiceOver / competitor hands-on の直接実行例は `--validate-only` を `--passed` より先に表示し、manual evidence を即書き込みしない導線にする。"))
        XCTAssertTrue(phase.contains("[x] `script/prepare_release_manual_helpers.sh` は release-candidate product source commit の VoiceOver pending preview / launch env / worksheet / command、competitor pending evidence、competitor benchmark pending worksheet、competitor worksheet / command と、current release evidence source commit の release-machine worksheet / command を一括再生成し、passed evidence を書かない。"))
        XCTAssertTrue(phase.contains("[x] `script/prepare_release_manual_helpers.sh` は tracked source tree がdirtyな場合、pending preview / command生成前に停止し"))
        XCTAssertTrue(phase.contains("[x] action summary の Manual Review Helper Freshness は stale/missing helper を見つけた場合、個別コマンドの羅列ではなく `./script/prepare_release_manual_helpers.sh` を次アクションとして提示する。"))
        XCTAssertTrue(phase.contains("[x] Manual Review Helper Freshness は command helper の `EXPECTED_SOURCE_COMMIT` 実代入だけを current commit pin として扱い、コメントや説明文に current commit が出るだけでは stale 扱いにする。"))
        XCTAssertTrue(phase.contains("[x] action summary は古い `.tmp/voiceover-review/*-pending-<old-commit>.md` / `.tmp/competitor-hands-on/*-pending-<old-commit>.md` と legacy default preview `.tmp/competitor-hands-on/evidence.md` を ignored stale preview として表示し、operatorが別release候補のcontextをtracked evidenceへ転記しないようにする。"))
        XCTAssertTrue(phase.contains("[x] `script/prepare_release_manual_helpers.sh --prune-stale` は release-candidate source commit のhelper再生成後、古いpending previewとlegacy default previewを削除し、passed evidenceを書かない。"))
        XCTAssertTrue(phase.contains("[x] action summary は direct manual evidence scripts も clean tracked source tree を要求し、dirty tree 回避目的で生成済みコマンドを迂回しないよう表示する。"))
        XCTAssertTrue(phase.contains("[x] action summary は release-machine evidence の `generator.name: script/create_release_evidence.sh` 要件をManual Evidence Source Hygieneに表示し、手書き `packaging/release-evidence.json` がrelease readyにならないことを示す。"))
        XCTAssertTrue(phase.contains("[x] action summary は generated VoiceOver / competitor / release-machine command が placeholder 未置換のままでは `--validate-only` でも失敗することを表示し、template command を evidence-ready に見せない。"))
        XCTAssertTrue(phase.contains("[x] action summary は `docs/release/manual-unblockers.md` への Persistent Manual Unblocker Runbook 導線を出し、一時ファイルが再生成されても恒久runbookへ戻れるようにする。"))
        XCTAssertTrue(phase.contains("[x] action summary は未チェックの手動Phase項目を Manual VoiceOver / Competitor Hands-On / Release Machine / Login Item Manual Check / Manual Review に分類し"))
        XCTAssertTrue(phase.contains("[x] action summary は Login Item manual gate が残る場合、Operator Priority Queue に release-machine worksheet と `--login-item-toggle` 付き release evidence command への導線を独立表示する。"))
        XCTAssertTrue(phase.contains("[x] action summary は Release Machine blocker が残る場合、署名、notarization、package、appcast、release evidence、final preflight の順序付きコマンドを出す。"))
        XCTAssertTrue(phase.contains("[x] `script/prepare_release_machine_evidence.sh` は `.tmp/release-machine/release-machine-worksheet.md` と `.tmp/release-machine/create-release-evidence-command.sh` を生成し"))
        XCTAssertTrue(phase.contains("[x] `.tmp/release-machine/create-release-evidence-command.sh` rejects boilerplate worksheet values such as `TBD`, `Verified`, `OK`, or `manual checks completed`; each required worksheet field must contain concrete release-machine observations."))
        XCTAssertTrue(phase.contains("[x] `script/create_release_evidence.sh --validate-only` validates the filled release-machine command without writing `packaging/release-evidence.json`."))
        XCTAssertTrue(phase.contains("[x] action summary の Release Machine runbook は `.tmp/release-machine/create-release-evidence-command.sh` の編集・実行を direct `create_release_evidence.sh --force` fallback より先に表示し"))
    }

    func testReleaseReadinessReportWritesSpecificReleaseEnvironmentBlockersToActionSummary() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-release-environment-actions", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let actionSummaryURL = fixtureRoot.appendingPathComponent("release-actions.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
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
        ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        printf "release environment fixture\\n"
        printf "Blockers:\\n"
        printf -- "- BLOCKER: missing local signing config: $ROOT_DIR/packaging/signing.env\\n"
        printf -- "- BLOCKER: release app bundle is missing Sparkle framework: $ROOT_DIR/dist/SoloPM.app/Contents/Frameworks/Sparkle.framework\\n"
        printf -- "- BLOCKER: dist app failed Gatekeeper assessment: $ROOT_DIR/dist/SoloPM.app\\n"
        printf -- "- BLOCKER: missing local release evidence: run ./script/create_release_evidence.sh after packaging and manual checks\\n"
        printf -- "- BLOCKER: notarization token failed: super-secret-token\\n"
        exit 23
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_RELEASE_ACTIONS_FILE": actionSummaryURL.path]
        )
        let actionSummary = try String(contentsOf: actionSummaryURL, encoding: .utf8)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release environment preflight did not pass"))
        XCTAssertTrue(actionSummary.contains("## Operator Priority Queue"))
        XCTAssertTrue(actionSummary.contains("- [ ] Release-machine runbook clears up to 1 blocker group(s) and covers 5 release environment blocker item(s)."))
        XCTAssertTrue(actionSummary.contains("- [x] Phase checklist has no active blocker groups in this report run."))
        XCTAssertTrue(actionSummary.contains("## Release Environment Blockers"))
        XCTAssertTrue(actionSummary.contains("- [ ] missing local signing config: packaging/signing.env"))
        XCTAssertTrue(actionSummary.contains("- [ ] release app bundle is missing Sparkle framework: dist/SoloPM.app/Contents/Frameworks/Sparkle.framework"))
        XCTAssertTrue(actionSummary.contains("- [ ] dist app failed Gatekeeper assessment: dist/SoloPM.app"))
        XCTAssertTrue(actionSummary.contains("- [ ] missing local release evidence: run ./script/create_release_evidence.sh after packaging and manual checks"))
        XCTAssertTrue(actionSummary.contains("- [ ] release environment blocker contained a sensitive field; inspect verify_release_environment.sh output locally"))
        XCTAssertTrue(actionSummary.contains("## Release Machine Local Doctor"))
        XCTAssertTrue(actionSummary.contains("Run these non-secret diagnostics on the release machine before filling release evidence:"))
        XCTAssertTrue(actionSummary.contains("./script/check_release_machine_local_doctor.sh"))
        XCTAssertTrue(actionSummary.contains("security find-identity -p codesigning -v"))
        XCTAssertTrue(actionSummary.contains("ls -l packaging/signing.env packaging/notarization.env packaging/sparkle.env"))
        XCTAssertTrue(actionSummary.contains("./script/verify_signing_setup.sh"))
        XCTAssertTrue(actionSummary.contains("SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh"))
        let actionSummaryLines = Set(actionSummary.split(separator: "\n").map(String.init))
        XCTAssertTrue(actionSummaryLines.contains("SOLOPM_BUILD_CONFIGURATION=release SOLOPM_SPARKLE_CONFIG_QUIET=1 ./script/validate_sparkle_release_config.sh"))
        XCTAssertFalse(actionSummaryLines.contains("./script/validate_sparkle_release_config.sh"))
        XCTAssertTrue(actionSummary.contains("./script/verify_release_environment.sh"))
        XCTAssertTrue(actionSummary.contains("## Release Environment Routes"))
        XCTAssertTrue(actionSummary.contains("Signing Configuration blockers:\n- [ ] missing local signing config: packaging/signing.env"))
        XCTAssertTrue(actionSummary.contains("Sparkle / Appcast blockers:\n- [ ] release app bundle is missing Sparkle framework: dist/SoloPM.app/Contents/Frameworks/Sparkle.framework"))
        XCTAssertTrue(actionSummary.contains("Gatekeeper / Stapling blockers:\n- [ ] dist app failed Gatekeeper assessment: dist/SoloPM.app"))
        XCTAssertTrue(actionSummary.contains("Release Evidence blockers:\n- [ ] missing local release evidence: run ./script/create_release_evidence.sh after packaging and manual checks"))
        XCTAssertTrue(actionSummary.contains("Local Inspection blockers:\n- [ ] release environment blocker contained a sensitive field; inspect verify_release_environment.sh output locally"))
        XCTAssertFalse(actionSummary.contains(fixtureRoot.path))
        XCTAssertFalse(actionSummary.contains("super-secret-token"))
    }

    func testReleaseReadinessReportWritesManualEvidenceBlockersToActionSummary() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-manual-evidence-actions", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let productDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("product", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let accessibilityURL = scriptDirectory.appendingPathComponent("check_accessibility_preflight.sh")
        let mcpComplianceURL = scriptDirectory.appendingPathComponent("verify_mcp_compliance.sh")
        let actionSummaryURL = fixtureRoot.appendingPathComponent("release-actions.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: productDirectory, withIntermediateDirectories: true)
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
        set -euo pipefail
        if [[ "$*" == *"--runtime"* ]]; then
          printf "OK: runtime AX smoke visible, windows=1, buttons=29, textFields=1, staticTexts=25, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1\\n"
        else
          printf "OK: accessibility source anchors are present (fixture)\\n"
        fi
        """.write(to: accessibilityURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        evidence_file="${SOLOPM_MCP_EVIDENCE_FILE:-}"
        if [[ -n "$evidence_file" ]]; then
          cat > "$evidence_file" <<'EOF'
        Generated:
        Scope: validate the release MCP stdio fixture
        Stable baseline: `2025-11-25`
        Official stable latest: `2025-11-25`
        Official latest source: https://modelcontextprotocol.io/specification
        Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases
        Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release.
        Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning
        Official versioning assertion: current protocol version is `2025-11-25`
        Official latest checked: 2026-06-24
        Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18
        Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/
        EMA remote authorization is not a SoloPM public-alpha release target
        Official stable source: https://modelcontextprotocol.io/specification/2025-11-25
        Draft watchlist: `2026-07-28`
        Draft release-candidate source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/
        Draft changelog source: https://modelcontextprotocol.io/specification/draft/changelog
        Draft changelog assertion: changes are listed since `2025-11-25`; it is not the current release baseline.
        2026-07-28 is release-candidate; final specification is scheduled for 2026-07-28.
        Draft 2026-07-28 removes initialize/notifications/initialized and protocol-level sessions
        per-request `_meta` protocolVersion/clientInfo/clientCapabilities
        Draft `server/discover` is required
        Draft tools/list cache hints `ttlMs` / `cacheScope` are not implemented
        not a full MCP host
        initialize -> tools/list -> tools/call
        MCP Inspector CLI tools/list
        MCP Inspector CLI tools/call
        SoloPM local smoke success
        malformed-json
        mismatched-id
        invalid-schema
        timeout
        exit: 0
        EOF
        fi
        printf "mcp compliance fixture ok\\n"
        """.write(to: mcpComplianceURL, atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: pending

        - macOS version:
        - App build:
        - Bundle identifier:
        - Source commit:
        - Checked by:
        - Check date: 2026-06-19
        - Evidence source: `docs/release/evidence/accessibility-voiceover.md`
        - Accessibility environment:
        - Runtime AX smoke:

        ## Required Focus Path

        - [ ] Project navigation: select Inbox, Today, and one Project from the sidebar.
        - [ ] Save Changes: confirm keyboard activation reaches the local task save action.
        """.write(to: evidenceDirectory.appendingPathComponent("accessibility-voiceover.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Hands-On Evidence

        Status: pending

        - Checked by:
        - Check date: 2026-06-19
        - Source commit:
        - Evidence source: `docs/release/evidence/competitor-hands-on.md`
        - Environment:
        - Scope: Notion -> Todoist -> Linear -> Motion

        ## Required Hands-On Path

        - [ ] Notion: create a project database, board, three tasks, status grouping, and one artifact/doc/link.

        ## Ship / Defer / Reject Delta

        - Ship:
        - Defer:
        - Reject:
        """.write(to: evidenceDirectory.appendingPathComponent("competitor-hands-on.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Benchmark and Hands-On Findings

        Source commit:
        """.write(to: productDirectory.appendingPathComponent("competitor-benchmark.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, preflightURL, accessibilityURL, mcpComplianceURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(
            ["bash", reportURL.path],
            environment: [
                "SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT": "1",
                "SOLOPM_RELEASE_ACTIONS_FILE": actionSummaryURL.path
            ]
        )
        let actionSummary = try String(contentsOf: actionSummaryURL, encoding: .utf8)
        let sourceCommit = try runTool(["git", "rev-parse", "--short", "HEAD"])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(actionSummary.contains("Source commit: \(sourceCommit)"))
        XCTAssertTrue(actionSummary.contains("Release-candidate product source commit: \(sourceCommit)"))
        XCTAssertTrue(actionSummary.contains("## Operator Priority Queue"))
        XCTAssertTrue(actionSummary.contains("- [ ] VoiceOver manual pass clears up to"))
        XCTAssertTrue(actionSummary.contains("- [ ] Competitor hands-on pass clears up to"))
        XCTAssertTrue(actionSummary.contains("Next: run `./script/prepare_release_manual_helpers.sh`, fill `.tmp/voiceover-review/voiceover-worksheet.md`, run generated `.tmp/voiceover-review/create-evidence-command.sh` validate-only first, then rerun readiness."))
        XCTAssertTrue(actionSummary.contains("Next: run `./script/prepare_release_manual_helpers.sh`, fill `.tmp/competitor-hands-on/hands-on-worksheet.md`, complete `.tmp/competitor-hands-on/create-evidence-command.sh`, then rerun readiness."))
        XCTAssertTrue(actionSummary.contains("- [x] Phase checklist has no active blocker groups in this report run."))
        XCTAssertLessThan(
            try XCTUnwrap(actionSummary.range(of: "## Operator Priority Queue")).lowerBound,
            try XCTUnwrap(actionSummary.range(of: "## Current Blocker Groups")).lowerBound
        )
        XCTAssertTrue(actionSummary.contains("## Manual VoiceOver Blockers"))
        XCTAssertTrue(actionSummary.contains("""
        ```bash
        ./script/prepare_voiceover_review_candidate.sh --no-launch
        ./script/prepare_voiceover_review_candidate.sh
        ```
        """))
        XCTAssertTrue(actionSummary.contains(".tmp/voiceover-review/create-evidence-command.sh"))
        XCTAssertTrue(actionSummary.contains(".tmp/voiceover-review/launch.env"))
        XCTAssertTrue(actionSummary.contains("SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT"))
        XCTAssertTrue(actionSummary.contains("SOLOPM_VOICEOVER_REVIEW_PROJECT_ID"))
        XCTAssertTrue(actionSummary.contains(".tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md"))
        XCTAssertTrue(actionSummary.contains(".tmp/voiceover-review/accessibility-voiceover-pending-\(sourceCommit).md"))
        XCTAssertTrue(actionSummary.contains("```bash\n./script/create_voiceover_evidence.sh --validate-only \\"))
        XCTAssertTrue(actionSummary.contains("./script/create_voiceover_evidence.sh --passed \\"))
        let voiceOverSectionStart = try XCTUnwrap(actionSummary.range(of: "\n## Manual VoiceOver\n"))
        let voiceOverSectionEnd = try XCTUnwrap(actionSummary.range(of: "\n## Competitor Hands-On\n"))
        let voiceOverSection = String(actionSummary[voiceOverSectionStart.lowerBound..<voiceOverSectionEnd.lowerBound])
        let voiceOverValidateActionRange = try XCTUnwrap(voiceOverSection.range(of: "./script/create_voiceover_evidence.sh --validate-only"))
        let voiceOverPassedActionRange = try XCTUnwrap(voiceOverSection.range(of: "./script/create_voiceover_evidence.sh --passed"))
        XCTAssertLessThan(voiceOverValidateActionRange.lowerBound, voiceOverPassedActionRange.lowerBound)
        XCTAssertTrue(actionSummary.contains("--project-navigation-note \"<VoiceOver observation for sidebar Inbox, Today, Projects, and selected review project navigation>\""))
        XCTAssertTrue(actionSummary.contains("--project-board-detail-note \"<VoiceOver observation for the seeded review project board context>\""))
        XCTAssertTrue(actionSummary.contains("--open-task-note \"<VoiceOver observation for focusing a seeded task card and opening details>\""))
        XCTAssertTrue(actionSummary.contains("--inline-task-composer-note \"<VoiceOver observation for title/detail/priority/due create flow, Command+Return, and Escape>\""))
        XCTAssertTrue(actionSummary.contains("--status-controls-note \"<VoiceOver observation for previous/next status controls and target status labels>\""))
        XCTAssertTrue(actionSummary.contains("--task-inspector-note \"<VoiceOver observation for inspector fields, summary, suggestion, save, and danger actions>\""))
        XCTAssertTrue(actionSummary.contains("--inbox-voice-triage-note \"<VoiceOver observation for Inbox voice detail transcript, interpretation, metadata, memo, and triage actions>\""))
        XCTAssertTrue(actionSummary.contains("--today-rail-actions-note \"<VoiceOver observation for Today rail next action, task detail, focus, schedule, edit, subtask, and reminder controls>\""))
        XCTAssertFalse(actionSummary.contains("--project-navigation-note \"<VoiceOver observation for sidebar project navigation>\""))
        XCTAssertFalse(actionSummary.contains("--inline-task-composer-note \"<VoiceOver observation for title/detail/priority/due create flow>\""))
        XCTAssertTrue(actionSummary.contains("--save-changes-note \"<VoiceOver observation proving keyboard activation saves local task changes>\""))
        XCTAssertTrue(actionSummary.contains("--task-content-execution-note \"<VoiceOver observation proving approved execution records reviewed task title and detail in the redacted receipt>\""))
        XCTAssertTrue(actionSummary.contains("Inbox voice triage and Today rail actions notes are required for #5/#6 P0 cockpit closeout"))
        XCTAssertTrue(actionSummary.contains("Task content execution note must mention the redacted receipt, reviewed title, and reviewed detail"))
        XCTAssertTrue(actionSummary.contains("--delete-confirmation-note \"<VoiceOver observation proving Delete Task opens an inline inspector confirmation panel before deletion>\""))
        XCTAssertTrue(actionSummary.contains("--confirm-manual-voiceover-pass"))
        XCTAssertTrue(actionSummary.contains("- [ ] VoiceOver accessibility evidence is not marked passed"))
        XCTAssertTrue(actionSummary.contains("- [ ] VoiceOver accessibility evidence missing release context: Source commit"))
        XCTAssertTrue(actionSummary.contains("- [ ] VoiceOver accessibility evidence missing concrete focus note: Task inspector"))
        XCTAssertTrue(actionSummary.contains("## Competitor Hands-On Blockers"))
        XCTAssertTrue(actionSummary.contains("```bash\n./script/create_competitor_hands_on_evidence.sh --pending"))
        XCTAssertTrue(actionSummary.contains(".tmp/competitor-hands-on/hands-on-worksheet.md"))
        XCTAssertTrue(actionSummary.contains(".tmp/competitor-hands-on/create-evidence-command.sh"))
        XCTAssertTrue(actionSummary.contains(".tmp/competitor-hands-on/competitor-hands-on-pending-\(sourceCommit).md"))
        XCTAssertTrue(actionSummary.contains(".tmp/competitor-hands-on/competitor-benchmark-pending-\(sourceCommit).md"))
        XCTAssertTrue(actionSummary.contains("```bash\n./script/create_competitor_hands_on_evidence.sh --validate-only \\"))
        XCTAssertTrue(actionSummary.contains("./script/create_competitor_hands_on_evidence.sh --passed \\"))
        let competitorSectionStart = try XCTUnwrap(actionSummary.range(of: "\n## Competitor Hands-On\n"))
        let competitorSectionEnd = try XCTUnwrap(actionSummary.range(of: "\n## Release Machine\n"))
        let competitorSection = String(actionSummary[competitorSectionStart.lowerBound..<competitorSectionEnd.lowerBound])
        let competitorValidateActionRange = try XCTUnwrap(competitorSection.range(of: "./script/create_competitor_hands_on_evidence.sh --validate-only"))
        let competitorPassedActionRange = try XCTUnwrap(competitorSection.range(of: "./script/create_competitor_hands_on_evidence.sh --passed"))
        XCTAssertLessThan(competitorValidateActionRange.lowerBound, competitorPassedActionRange.lowerBound)
        XCTAssertTrue(actionSummary.contains("--todoist-note \"<hands-on Todoist quick add, board/list, drag movement, Today/Upcoming observation>\""))
        XCTAssertTrue(actionSummary.contains("--confirm-manual-hands-on"))
        XCTAssertTrue(actionSummary.contains("- [ ] Competitor hands-on evidence is not marked passed"))
        XCTAssertTrue(actionSummary.contains("- [ ] Competitor hands-on evidence missing review context: Checked by"))
        XCTAssertTrue(actionSummary.contains("- [ ] Competitor hands-on evidence missing concrete note: Todoist"))
        XCTAssertTrue(actionSummary.contains("This file is an action summary, not release evidence."))
        XCTAssertTrue(actionSummary.contains("Manual-only evidence boundary"))
        XCTAssertTrue(actionSummary.contains("Do not ask an LLM, automation, or this action summary to create passed evidence for manual VoiceOver, competitor hands-on, signing, notarization, Sparkle, Gatekeeper, clean install, or Launch at Login checks without the real pass."))
        XCTAssertTrue(actionSummary.contains("## Manual Finding Regression Bridge"))
        XCTAssertTrue(actionSummary.contains("Use `docs/quality/manual-to-automated-regression.md` to route any manual VoiceOver, competitor, or release-machine finding back into source/runtime/visual regression coverage."))
        XCTAssertTrue(actionSummary.contains("VoiceOver findings should link to AX/source tests before the manual evidence is treated as closed."))
        XCTAssertTrue(actionSummary.contains("Competitor hands-on deltas should link to `docs/product/competitor-benchmark.md`, a Phase task, or a focused UI regression test."))
        XCTAssertTrue(actionSummary.contains("Release-machine failures should link to `script/verify_release_environment.sh` or `Tests/SoloPMCoreTests/ReleasePipelineTests.swift`."))
        XCTAssertFalse(actionSummary.contains("Status: ready"))
    }

    func testQualityStatusReportSummarizesPhase14RiskAndArtifactsWithoutSecrets() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-quality-status-report", isDirectory: true)
        let outputURL = fixtureRoot.appendingPathComponent("quality-status.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let result = try runTool(
            ["bash", packageRoot().appendingPathComponent("script/quality_status_report.sh").path],
            environment: ["SOLOPM_QUALITY_STATUS_FILE": outputURL.path]
        )
        let report = try String(contentsOf: outputURL, encoding: .utf8)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Quality status report written to"))
        XCTAssertTrue(report.contains("# SoloPM Quality Status"))
        XCTAssertTrue(report.contains("Phase14 completion"))
        XCTAssertTrue(report.contains("## Unfinished Phase14 Items"))
        XCTAssertTrue(report.contains("## Open Risk Items"))
        XCTAssertTrue(report.contains("## Runtime / Visual / Manual Evidence"))
        XCTAssertTrue(report.contains("## Gate Classification"))
        XCTAssertTrue(report.contains("Lightweight PR gate"))
        XCTAssertTrue(report.contains("Focused tests"))
        XCTAssertTrue(report.contains("Full test suite"))
        XCTAssertTrue(report.contains("Runtime smoke"))
        XCTAssertTrue(report.contains("Visual smoke"))
        XCTAssertTrue(report.contains("Manual evidence"))
        XCTAssertTrue(report.contains("Release readiness handoff"))
        XCTAssertTrue(report.contains("## Next Quality Gaps"))
        XCTAssertTrue(report.contains("docs/quality/regression-risk-map.md"))
        XCTAssertTrue(report.contains("tasks/Phase14-QualityRegressionHardening.md"))
        XCTAssertTrue(report.contains("script/check_runtime_accessible_crud_smoke.sh"))
        XCTAssertTrue(report.contains("script/check_accessibility_preflight.sh --runtime"))
        XCTAssertTrue(report.contains("script/capture_ui_evidence.sh --doctor"))
        XCTAssertTrue(report.contains("script/release_readiness_report.sh"))
        XCTAssertTrue(report.contains("`./script/check_automated_release_preflight.sh`"))
        XCTAssertTrue(report.contains("git rev-parse --short HEAD"))
        XCTAssertNil(report.range(of: #"automated-release-preflight-[[:xdigit:]]{7,}\.md"#, options: .regularExpression))
        XCTAssertTrue(report.range(of: #"SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.* ./script/release_readiness_report\.sh"#, options: .regularExpression) != nil)
        XCTAssertNil(report.range(of: #"SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.* ./script/check_automated_release_preflight\.sh"#, options: .regularExpression))
        XCTAssertNil(report.range(of: #"sk-[A-Za-z0-9_-]{8,}"#, options: .regularExpression))
        XCTAssertFalse(report.contains("super-secret-token"))
    }

    func testQualityStatusReportMarksPassedManualEvidenceStaleWhenSourceCommitMoved() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-quality-status-report-stale-manual", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let outputURL = fixtureRoot.appendingPathComponent("quality-status.md")
        let reportURL = scriptDirectory.appendingPathComponent("quality_status_report.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("tasks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("docs/quality", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("docs/release/evidence", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("Sources/SoloPMApp", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("Sources/SoloPMCore", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("Sources/SoloPMCLI", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("Sources/SoloPMExternalConnectors", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("packaging", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try readPackageFile("script/quality_status_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)

        try "- [x] `swift test`\n".write(
            to: fixtureRoot.appendingPathComponent("tasks/Phase14-QualityRegressionHardening.md"),
            atomically: true,
            encoding: .utf8
        )
        try "## Risks\n\n## How to use\n".write(
            to: fixtureRoot.appendingPathComponent("docs/quality/regression-risk-map.md"),
            atomically: true,
            encoding: .utf8
        )
        for relativePath in [
            "Sources/SoloPMApp/App.swift",
            "Sources/SoloPMCore/Core.swift",
            "Sources/SoloPMCLI/CLI.swift",
            "Sources/SoloPMExternalConnectors/Connector.swift"
        ] {
            try "public enum Fixture {}\n".write(
                to: fixtureRoot.appendingPathComponent(relativePath),
                atomically: true,
                encoding: .utf8
            )
        }
        try "// fixture package\n".write(
            to: fixtureRoot.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "APP_NAME=SoloPM\n".write(
            to: fixtureRoot.appendingPathComponent("packaging/app_metadata.env"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "init"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.email", "quality-tests@example.invalid"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.name", "Quality Tests"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "add", "."]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "commit", "-m", "initial quality fixture"]).exitCode, 0)
        let currentShortCommit = try runTool(["git", "-C", fixtureRoot.path, "rev-parse", "--short", "HEAD"])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try "- Source commit: `\(currentShortCommit)`\n".write(
            to: fixtureRoot.appendingPathComponent("docs/release/evidence/ui-screenshots.md"),
            atomically: true,
            encoding: .utf8
        )
        try "- Source commit: `\(currentShortCommit)`\n".write(
            to: fixtureRoot.appendingPathComponent("docs/release/evidence/mcp-inspector.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        Status: passed
        - Source commit: `oldcafe`
        """.write(
            to: fixtureRoot.appendingPathComponent("docs/release/evidence/accessibility-voiceover.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        Status: passed
        - Source commit: `\(currentShortCommit)`
        """.write(
            to: fixtureRoot.appendingPathComponent("docs/release/evidence/competitor-hands-on.md"),
            atomically: true,
            encoding: .utf8
        )

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_QUALITY_STATUS_FILE": outputURL.path]
        )
        let report = try String(contentsOf: outputURL, encoding: .utf8)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(report.contains("| `docs/release/evidence/accessibility-voiceover.md` | stale (passed; expected \(currentShortCommit)) | oldcafe |"))
        XCTAssertTrue(report.contains("Manual evidence | manual | VoiceOver: stale (passed; expected \(currentShortCommit)); Competitor: passed"))
        XCTAssertTrue(report.contains("Manual evidence status is VoiceOver=stale (passed; expected \(currentShortCommit)), Competitor=passed"))
    }

    func testSecurityRegressionScriptPassesCurrentArtifactsAndFailsTmpLeaksWhenEnabled() throws {
        let passing = try runScript("script/check_security_regressions.sh")

        XCTAssertEqual(passing.exitCode, 0, passing.output)
        XCTAssertTrue(passing.output.contains("OK: security regression scan passed"))

        let leakRoot = packageRoot().appendingPathComponent(".tmp/security-regression-test", isDirectory: true)
        let leakFile = leakRoot.appendingPathComponent("leak.md")
        let token = "sk-" + "securityRegressionLeak1234"
        try? FileManager.default.removeItem(at: leakRoot)
        try FileManager.default.createDirectory(at: leakRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: leakRoot) }
        try "token=\(token)\n".write(to: leakFile, atomically: true, encoding: .utf8)

        let failing = try runScript(
            "script/check_security_regressions.sh",
            environment: ["SOLOPM_SECURITY_SCAN_EXTRA_PATHS": ".tmp/security-regression-test"]
        )

        XCTAssertNotEqual(failing.exitCode, 0)
        XCTAssertTrue(failing.output.contains("BLOCKER: secret-like token matched in .tmp/security-regression-test/leak.md"))
        XCTAssertTrue(failing.output.contains("security regression scan found secret-like material"))
    }

    func testSecurityRegressionScriptRejectsTrackedVoiceModelBinaries() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-security-regression-model-binary", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let modelsDirectory = fixtureRoot.appendingPathComponent("Models", isDirectory: true)
        let copiedScriptURL = scriptDirectory.appendingPathComponent("check_security_regressions.sh")
        let trackedModelURL = modelsDirectory.appendingPathComponent("ggml-test.bin")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try readPackageFile("script/check_security_regressions.sh")
            .write(to: copiedScriptURL, atomically: true, encoding: .utf8)
        try """
        /.tmp/
        """.write(to: fixtureRoot.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try Data([0x67, 0x67, 0x6d, 0x6c])
            .write(to: trackedModelURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copiedScriptURL.path)

        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "init"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.email", "security-tests@example.invalid"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.name", "Security Tests"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "add", "."]).exitCode, 0)

        let result = try runTool(["bash", copiedScriptURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("BLOCKER: tracked voice model binary is not allowed: Models/ggml-test.bin"))
        XCTAssertTrue(result.output.contains("security regression scan found tracked local voice model binaries"))
    }

    func testVoiceModelDocsDefineNoBundleCloseoutAndRuntimeProof() throws {
        let docs = try readPackageFile("docs/voice-models.md")
        let script = try readPackageFile("script/check_security_regressions.sh")

        XCTAssertTrue(script.contains("check_tracked_voice_model_binaries()"))
        XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" ls-files -z"))
        XCTAssertTrue(script.contains("VOICE_MODEL_BINARY_PATTERNS=("))
        for extensionPattern in ["*.gguf", "*.ggml", "*.onnx", "*.safetensors", "*.pt", "*.pth", "*.tflite", "*.mlmodel", "*.mlpackage", "*.mlpackage/*", "*ggml*.bin", "*whisper*.bin", "*model*.bin"] {
            XCTAssertTrue(script.contains(extensionPattern), "Missing model binary guard pattern: \(extensionPattern)")
        }
        XCTAssertTrue(script.contains("tracked voice model binary is not allowed"))

        XCTAssertTrue(docs.contains("No-Bundle Guard"))
        XCTAssertTrue(docs.contains("script/check_security_regressions.sh"))
        XCTAssertTrue(docs.contains("git ls-files"))
        XCTAssertTrue(docs.contains("Runtime Proof For Issue Closeout"))
        XCTAssertTrue(docs.contains("whisper-cli"))
        XCTAssertTrue(docs.contains("Kokoro runtime path"))
        XCTAssertTrue(docs.contains("Settings Test Play"))
        XCTAssertTrue(docs.contains("they do not by themselves prove the whisper.cpp STT or Kokoro TTS providers are ready in a packaged app"))
    }

    func testKokoroRuntimeWrapperUsesLocalCacheOnlyContract() throws {
        let docs = try readPackageFile("docs/voice-models.md")
        let wrapper = try readPackageFile("script/kokoro_tts_runtime.py")
        let smokeScript = try readPackageFile("script/check_local_voice_runtime_smoke.sh")
        let releaseReport = try readPackageFile("script/release_readiness_report.sh")

        for marker in [
            "--model",
            "--text-file",
            "--language",
            "--voice",
            "--output",
            "config.json",
            "voices",
            "HF_HUB_OFFLINE",
            "TRANSFORMERS_OFFLINE",
            "check_offline_language_assets",
            "en_core_web_sm",
            "prefer_unidic_lite_for_japanese",
            "unidic_lite.DICDIR",
            "SAFE_VOICE_ID",
            "English Kokoro voice id must start with a or b",
            "KModel(",
            "KPipeline("
        ] {
            XCTAssertTrue(wrapper.contains(marker), "Missing Kokoro wrapper marker: \(marker)")
        }
        XCTAssertTrue(wrapper.contains("os.environ[\"HF_HUB_OFFLINE\"] = \"1\""))
        XCTAssertTrue(wrapper.contains("os.environ[\"TRANSFORMERS_OFFLINE\"] = \"1\""))
        for networkMarker in ["hf_hub_download", "requests.", "curl ", "wget ", "huggingface.co"] {
            XCTAssertFalse(wrapper.contains(networkMarker), "Kokoro wrapper must not fetch network resources during smoke: \(networkMarker)")
        }
        XCTAssertTrue(smokeScript.contains("script/kokoro_tts_runtime.py"))
        XCTAssertTrue(smokeScript.contains("SOLOPM_LOCAL_VOICE_EVIDENCE_FILE requires SOLOPM_KOKORO_EXECUTABLE to be the checked-in reference wrapper script/kokoro_tts_runtime.py"))
        XCTAssertTrue(smokeScript.contains("KOKORO_RUNTIME_WRAPPER_RELATIVE=\"script/kokoro_tts_runtime.py\""))
        XCTAssertTrue(smokeScript.contains("Kokoro runtime adapter"))
        XCTAssertTrue(smokeScript.contains("Offline env enforcement: passed"))
        XCTAssertTrue(smokeScript.contains("Kokoro English voice id must start with a or b"))
        XCTAssertTrue(releaseReport.contains("script/kokoro_tts_runtime.py"))
        XCTAssertTrue(releaseReport.contains("Kokoro runtime adapter: `script/kokoro_tts_runtime.py`"))
        XCTAssertTrue(releaseReport.contains("Offline env enforcement: passed"))
        XCTAssertTrue(docs.contains("script/kokoro_tts_runtime.py"))
        XCTAssertTrue(docs.contains("sets Hugging Face/Transformers offline flags"))
    }

    func testKokoroRuntimeWrapperFailsClosedBeforeImportForUnsafeRuntimeInputs() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-kokoro-runtime-wrapper-input-boundaries", isDirectory: true)
        let voicesDirectory = fixtureRoot.appendingPathComponent("voices", isDirectory: true)
        let modelURL = fixtureRoot.appendingPathComponent("kokoro-v1_0.pth")
        let configURL = fixtureRoot.appendingPathComponent("config.json")
        let promptURL = fixtureRoot.appendingPathComponent("prompt.txt")
        let emptyPromptURL = fixtureRoot.appendingPathComponent("empty-prompt.txt")
        let outputURL = fixtureRoot.appendingPathComponent("speech.wav")
        let wrapperURL = packageRoot().appendingPathComponent("script/kokoro_tts_runtime.py")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: voicesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try Data([0x01]).write(to: modelURL, options: .atomic)
        try "{}\n".write(to: configURL, atomically: true, encoding: .utf8)
        try "今日の未完了タスクは3件です。\n".write(to: promptURL, atomically: true, encoding: .utf8)
        try "".write(to: emptyPromptURL, atomically: true, encoding: .utf8)
        try Data([0x02]).write(to: voicesDirectory.appendingPathComponent("jf_alpha.pt"), options: .atomic)

        func runWrapper(_ arguments: [String]) throws -> (exitCode: Int32, output: String) {
            try runTool([wrapperURL.path] + arguments)
        }

        let relativeModelResult = try runWrapper([
            "--model", "relative-model.pth",
            "--text-file", promptURL.path,
            "--language", "ja",
            "--voice", "jf_alpha",
            "--output", outputURL.path
        ])
        XCTAssertNotEqual(relativeModelResult.exitCode, 0)
        XCTAssertTrue(relativeModelResult.output.contains("Kokoro model path must be absolute"))

        let unsafeVoiceResult = try runWrapper([
            "--model", modelURL.path,
            "--text-file", promptURL.path,
            "--language", "ja",
            "--voice", "../escape",
            "--output", outputURL.path
        ])
        XCTAssertNotEqual(unsafeVoiceResult.exitCode, 0)
        XCTAssertTrue(unsafeVoiceResult.output.contains("Kokoro voice id must contain only letters, numbers, underscore, or hyphen"))

        let relativeOutputResult = try runWrapper([
            "--model", modelURL.path,
            "--text-file", promptURL.path,
            "--language", "ja",
            "--voice", "jf_alpha",
            "--output", "speech.wav"
        ])
        XCTAssertNotEqual(relativeOutputResult.exitCode, 0)
        XCTAssertTrue(relativeOutputResult.output.contains("Kokoro output path must be absolute"))

        let emptyPromptResult = try runWrapper([
            "--model", modelURL.path,
            "--text-file", emptyPromptURL.path,
            "--language", "ja",
            "--voice", "jf_alpha",
            "--output", outputURL.path
        ])
        XCTAssertNotEqual(emptyPromptResult.exitCode, 0)
        XCTAssertTrue(emptyPromptResult.output.contains("Kokoro prompt is missing or empty"))

        let englishVoicePrefixResult = try runWrapper([
            "--model", modelURL.path,
            "--text-file", promptURL.path,
            "--language", "en",
            "--voice", "jf_alpha",
            "--output", outputURL.path
        ])
        XCTAssertNotEqual(englishVoicePrefixResult.exitCode, 0)
        XCTAssertTrue(englishVoicePrefixResult.output.contains("English Kokoro voice id must start with a or b"))

        let helpResult = try runWrapper(["--help"])
        XCTAssertEqual(helpResult.exitCode, 0)
        XCTAssertTrue(helpResult.output.contains("Generate a local WAV with a cached Kokoro model and voice pack."))
    }

    func testLocalVoiceRuntimeSmokeScriptFailsClosedAndDocumentsIssueCloseout() throws {
        let docs = try readPackageFile("docs/voice-models.md")
        let script = try readPackageFile("script/check_local_voice_runtime_smoke.sh")
        let phase10 = try readPackageFile("tasks/Phase10-ReleaseReadinessRuntime.md")

        XCTAssertTrue(script.contains("SOLOPM_LOCAL_VOICE_CACHE_ROOT"))
        XCTAssertTrue(script.contains("SOLOPM_WHISPER_CPP_EXECUTABLE"))
        XCTAssertTrue(script.contains("SOLOPM_STT_SAMPLE_WAV"))
        XCTAssertTrue(script.contains("SOLOPM_KOKORO_EXECUTABLE"))
        XCTAssertTrue(script.contains("SOLOPM_LOCAL_VOICE_SMOKE_OUTPUT_DIR"))
        XCTAssertTrue(script.contains("SOLOPM_LOCAL_VOICE_EVIDENCE_FILE"))
        XCTAssertTrue(script.contains("SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS"))
        XCTAssertTrue(script.contains("Generated by: script/check_local_voice_runtime_smoke.sh"))
        XCTAssertTrue(script.contains("SOLOPM_LOCAL_VOICE_EVIDENCE_FILE requires SOLOPM_TTS_LANGUAGES to include both ja and en"))
        XCTAssertTrue(script.contains("No network download: passed"))
        XCTAssertTrue(script.contains("No model binary committed or bundled: passed"))
        XCTAssertTrue(script.contains("KOKORO_RUNTIME_WRAPPER_RELATIVE=\"script/kokoro_tts_runtime.py\""))
        XCTAssertTrue(script.contains("Kokoro runtime adapter"))
        XCTAssertTrue(script.contains("Offline env enforcement: passed"))
        XCTAssertTrue(script.contains("be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"))
        XCTAssertTrue(script.contains("496dba118d1a58f5f3db2efc88dbdc216e0483fc89fe6e47ee1f2c53f18ad1e4"))
        XCTAssertTrue(script.contains("whisper-cli -m <model> -f <sample.wav> -l ja -np -nt"))
        XCTAssertTrue(script.contains("Kokoro runtime --model <model> --text-file <prompt.txt> --language ja --voice jf_alpha --output <speech.wav>"))
        XCTAssertTrue(script.contains("BLOCKER: local voice runtime smoke found"))
        XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" check-ignore -q"))
        XCTAssertTrue(script.contains("SOLOPM_LOCAL_VOICE_SMOKE_OUTPUT_DIR inside repo must be ignored by git"))
        XCTAssertTrue(script.contains("has_tts_language()"))
        XCTAssertTrue(script.contains("if ! has_tts_language ja || ! has_tts_language en; then"))
        XCTAssertTrue(script.contains("STT sample WAV path must be absolute"))
        XCTAssertTrue(script.contains("STT sample WAV must use a .wav file"))
        XCTAssertTrue(script.contains("Kokoro voice id must not contain whitespace"))
        for networkMarker in ["curl ", "wget ", "git clone", "python -c", "python3 -c", "huggingface.co", "URLSession"] {
            XCTAssertFalse(script.contains(networkMarker), "Local voice runtime smoke must not fetch network resources: \(networkMarker)")
        }

        XCTAssertTrue(docs.contains("script/check_local_voice_runtime_smoke.sh"))
        XCTAssertTrue(docs.contains("SOLOPM_WHISPER_CPP_EXECUTABLE"))
        XCTAssertTrue(docs.contains("SOLOPM_KOKORO_EXECUTABLE"))
        XCTAssertTrue(docs.contains("SOLOPM_STT_SAMPLE_WAV"))
        XCTAssertTrue(docs.contains("SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS"))
        XCTAssertTrue(docs.contains("SOLOPM_LOCAL_VOICE_EVIDENCE_FILE=docs/release/evidence/local-voice-runtime.md"))
        XCTAssertTrue(docs.contains("does not prove Settings Test Play or VoiceOver accessibility"))
        XCTAssertTrue(docs.contains("no network download"))

        XCTAssertTrue(phase10.contains("P10-023a: Local OSS voice runtime proof"))
        XCTAssertTrue(phase10.contains("[x] `script/check_local_voice_runtime_smoke.sh`"))
        XCTAssertTrue(phase10.contains("[x] `release_readiness_report.sh` は `docs/release/evidence/local-voice-runtime.md`"))
        XCTAssertTrue(phase10.contains("[x] checksum 済み `ggml-tiny.bin`"))
        XCTAssertTrue(phase10.contains("[x] checksum 済み `kokoro-v1_0.pth`"))

        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-local-voice-runtime-smoke-missing-inputs", isDirectory: true)
        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let emptyCacheRoot = fixtureRoot.appendingPathComponent("VoiceModels", isDirectory: true)
        let outputRoot = fixtureRoot.appendingPathComponent("smoke-output", isDirectory: true)
        let result = try runScript(
            "script/check_local_voice_runtime_smoke.sh",
            environment: [
                "SOLOPM_LOCAL_VOICE_CACHE_ROOT": emptyCacheRoot.path,
                "SOLOPM_WHISPER_CPP_EXECUTABLE": fixtureRoot.appendingPathComponent("missing-whisper-cli").path,
                "SOLOPM_STT_SAMPLE_WAV": fixtureRoot.appendingPathComponent("missing-sample.wav").path,
                "SOLOPM_KOKORO_EXECUTABLE": fixtureRoot.appendingPathComponent("missing-kokoro").path,
                "SOLOPM_LOCAL_VOICE_SMOKE_OUTPUT_DIR": outputRoot.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("BLOCKER: whisper.cpp executable is missing or not executable"))
        XCTAssertTrue(result.output.contains("BLOCKER: STT sample WAV is missing"))
        XCTAssertTrue(result.output.contains("BLOCKER: whisper.cpp tiny model is missing"))
        XCTAssertTrue(result.output.contains("BLOCKER: Kokoro executable is missing or not executable"))
        XCTAssertTrue(result.output.contains("BLOCKER: Kokoro model is missing"))
        XCTAssertTrue(result.output.contains("BLOCKER: local voice runtime smoke found 5 prerequisite problem(s)"))

        let fakeKokoroURL = fixtureRoot.appendingPathComponent("fake-kokoro")
        try """
        #!/usr/bin/env bash
        exit 0
        """.write(to: fakeKokoroURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeKokoroURL.path)

        let nonReferenceEvidenceResult = try runScript(
            "script/check_local_voice_runtime_smoke.sh",
            environment: [
                "SOLOPM_LOCAL_VOICE_CACHE_ROOT": emptyCacheRoot.path,
                "SOLOPM_WHISPER_CPP_EXECUTABLE": fixtureRoot.appendingPathComponent("missing-whisper-cli").path,
                "SOLOPM_STT_SAMPLE_WAV": fixtureRoot.appendingPathComponent("missing-sample.wav").path,
                "SOLOPM_KOKORO_EXECUTABLE": fakeKokoroURL.path,
                "SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS": "今日の未完了",
                "SOLOPM_LOCAL_VOICE_EVIDENCE_FILE": packageRoot()
                    .appendingPathComponent("docs", isDirectory: true)
                    .appendingPathComponent("release", isDirectory: true)
                    .appendingPathComponent("evidence", isDirectory: true)
                    .appendingPathComponent("local-voice-runtime.md")
                    .path,
                "SOLOPM_LOCAL_VOICE_SMOKE_OUTPUT_DIR": outputRoot.path
            ]
        )

        XCTAssertNotEqual(nonReferenceEvidenceResult.exitCode, 0)
        XCTAssertTrue(nonReferenceEvidenceResult.output.contains("SOLOPM_LOCAL_VOICE_EVIDENCE_FILE requires SOLOPM_KOKORO_EXECUTABLE to be the checked-in reference wrapper script/kokoro_tts_runtime.py"))
    }

    func testLocalVoiceRuntimeSmokeScriptSupportsExplicitSttOnlyMode() throws {
        let docs = try readPackageFile("docs/voice-models.md")
        let script = try readPackageFile("script/check_local_voice_runtime_smoke.sh")
        let phase10 = try readPackageFile("tasks/Phase10-ReleaseReadinessRuntime.md")

        XCTAssertTrue(script.contains("--stt-only"))
        XCTAssertTrue(script.contains("Runs fail-closed local STT/TTS runtime proof"))
        XCTAssertTrue(script.contains("SOLOPM_LOCAL_VOICE_EVIDENCE_FILE in --stt-only mode must state that TTS was not verified"))
        XCTAssertTrue(script.contains("STT-only smoke cannot prove #14 / full release closeout"))
        XCTAssertTrue(script.contains("SOLOPM_LOCAL_VOICE_EVIDENCE_FILE in --stt-only mode must use an explicit *stt-only*.md filename and must not overwrite local-voice-runtime.md"))
        XCTAssertTrue(script.contains("Required environment for all modes:"))
        XCTAssertTrue(script.contains("Required environment for default full STT+TTS mode:"))
        XCTAssertTrue(script.contains("MODE_LABEL=\"STT-only\""))
        XCTAssertTrue(script.contains("Evidence source: `local whisper.cpp STT runtime smoke only (no Kokoro TTS proof)`"))
        XCTAssertTrue(script.contains("TTS proof: not run - --stt-only mode does not verify Kokoro runtime"))
        XCTAssertTrue(script.contains("Release closeout scope: issue #13 STT-only smoke only"))
        XCTAssertTrue(script.contains("Full release closeout: blocked - rerun without --stt-only to prove Kokoro Japanese/English TTS"))
        XCTAssertFalse(script.contains("curl "))
        XCTAssertFalse(script.contains("wget "))
        XCTAssertFalse(script.contains("git clone"))

        XCTAssertTrue(docs.contains("--stt-only"))
        XCTAssertTrue(docs.contains("Issue #13 STT-only smoke"))
        XCTAssertTrue(docs.contains("Issue #14 full STT + TTS smoke"))
        XCTAssertTrue(docs.contains("does not prove Kokoro TTS"))
        XCTAssertTrue(docs.contains("cannot be used for #14 or full release closeout"))

        XCTAssertTrue(phase10.contains("Issue #13 STT-only smoke"))
        XCTAssertTrue(phase10.contains("Issue #14 full TTS smoke"))

        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-local-voice-runtime-smoke-stt-only-missing-inputs", isDirectory: true)
        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let emptyCacheRoot = fixtureRoot.appendingPathComponent("VoiceModels", isDirectory: true)
        let outputRoot = fixtureRoot.appendingPathComponent("smoke-output", isDirectory: true)
        let result = try runTool(
            [
                "bash",
                "script/check_local_voice_runtime_smoke.sh",
                "--stt-only"
            ],
            environment: [
                "SOLOPM_LOCAL_VOICE_CACHE_ROOT": emptyCacheRoot.path,
                "SOLOPM_WHISPER_CPP_EXECUTABLE": fixtureRoot.appendingPathComponent("missing-whisper-cli").path,
                "SOLOPM_STT_SAMPLE_WAV": fixtureRoot.appendingPathComponent("missing-sample.wav").path,
                "SOLOPM_LOCAL_VOICE_SMOKE_OUTPUT_DIR": outputRoot.path
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("BLOCKER: whisper.cpp executable is missing or not executable"))
        XCTAssertTrue(result.output.contains("BLOCKER: STT sample WAV is missing"))
        XCTAssertTrue(result.output.contains("BLOCKER: whisper.cpp tiny model is missing"))
        XCTAssertFalse(result.output.contains("BLOCKER: Kokoro executable is missing or not executable"))
        XCTAssertFalse(result.output.contains("BLOCKER: Kokoro model is missing"))
        XCTAssertTrue(result.output.contains("BLOCKER: local voice runtime smoke found 3 prerequisite problem(s)"))

        let canonicalEvidenceResult = try runTool(
            [
                "bash",
                "script/check_local_voice_runtime_smoke.sh",
                "--stt-only"
            ],
            environment: [
                "SOLOPM_LOCAL_VOICE_CACHE_ROOT": emptyCacheRoot.path,
                "SOLOPM_WHISPER_CPP_EXECUTABLE": fixtureRoot.appendingPathComponent("missing-whisper-cli").path,
                "SOLOPM_STT_SAMPLE_WAV": fixtureRoot.appendingPathComponent("missing-sample.wav").path,
                "SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS": "sample",
                "SOLOPM_LOCAL_VOICE_EVIDENCE_FILE": packageRoot()
                    .appendingPathComponent("docs", isDirectory: true)
                    .appendingPathComponent("release", isDirectory: true)
                    .appendingPathComponent("evidence", isDirectory: true)
                    .appendingPathComponent("local-voice-runtime.md")
                    .path,
                "SOLOPM_LOCAL_VOICE_SMOKE_OUTPUT_DIR": outputRoot.path
            ]
        )

        XCTAssertNotEqual(canonicalEvidenceResult.exitCode, 0)
        XCTAssertTrue(canonicalEvidenceResult.output.contains("SOLOPM_LOCAL_VOICE_EVIDENCE_FILE in --stt-only mode must use an explicit *stt-only*.md filename and must not overwrite local-voice-runtime.md"))
        XCTAssertFalse(canonicalEvidenceResult.output.contains("BLOCKER: Kokoro executable is missing or not executable"))
        XCTAssertFalse(canonicalEvidenceResult.output.contains("BLOCKER: Kokoro model is missing"))
    }

    func testReleaseReadinessReportRequiresLocalVoiceRuntimeEvidence() throws {
        let currentShortCommit = try currentShortGitCommit()
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-local-voice-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let actionSummaryURL = fixtureRoot.appendingPathComponent("release-actions.md")

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
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)

        let missingResult = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_RELEASE_ACTIONS_FILE": actionSummaryURL.path]
        )
        let missingActionSummary = try String(contentsOf: actionSummaryURL, encoding: .utf8)

        XCTAssertNotEqual(missingResult.exitCode, 0)
        XCTAssertTrue(missingResult.output.contains("missing local voice runtime evidence file: docs/release/evidence/local-voice-runtime.md"))
        XCTAssertTrue(missingActionSummary.contains("SOLOPM_LOCAL_VOICE_EVIDENCE_FILE=docs/release/evidence/local-voice-runtime.md"))

        try """
        # Local Voice Runtime Evidence

        Status: pending
        Generated by: script/check_local_voice_runtime_smoke.sh

        ## Runtime Context

        - Source commit: `deadbee`
        - Generated at: 2026-06-19T00:00:00Z
        - Evidence source: `placeholder`
        - Kokoro runtime adapter: `placeholder`
        - Offline env enforcement: placeholder
        - Voice cache: placeholder
        - STT language: `ja`
        - STT expected transcript marker: `sample`
        - STT transcript:
        - whisper.cpp tiny model SHA-256: `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21`
        - Kokoro model SHA-256: `496dba118d1a58f5f3db2efc88dbdc216e0483fc89fe6e47ee1f2c53f18ad1e4`
        - TTS languages: `ja`
        - TTS Japanese WAV:
        - Runtime artifacts: `/Users/alice/private`
        """.write(to: evidenceDirectory.appendingPathComponent("local-voice-runtime.md"), atomically: true, encoding: .utf8)

        let invalidResult = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(invalidResult.exitCode, 0)
        XCTAssertTrue(invalidResult.output.contains("local voice runtime evidence is not marked passed"))
        XCTAssertTrue(invalidResult.output.contains("local voice runtime evidence still contains pending/template/placeholder text"))
        XCTAssertTrue(invalidResult.output.contains("local voice runtime evidence contains local path text"))
        XCTAssertTrue(invalidResult.output.contains("local voice runtime evidence is missing marker: STT transcript: passed"))
        XCTAssertTrue(invalidResult.output.contains("local voice runtime evidence is missing marker: TTS English WAV: passed"))
        XCTAssertTrue(invalidResult.output.contains("local voice runtime evidence must cover both Japanese and English TTS"))

        try """
        # Local Voice Runtime Evidence

        Status: passed
        Generated by: script/check_local_voice_runtime_smoke.sh

        ## Runtime Context

        - Source commit: `deadbee`
        - Generated at: 2026-06-19T00:00:00Z
        - Evidence source: `local whisper.cpp STT and Kokoro TTS runtime smoke`
        - No network download: passed - local cache and user-configured executables only
        - Kokoro runtime adapter: `script/kokoro_tts_runtime.py`
        - Offline env enforcement: passed - reference wrapper forces HF_HUB_OFFLINE=1 and TRANSFORMERS_OFFLINE=1 before importing Kokoro
        - No model binary committed or bundled: passed - model files remained outside git and app artifacts
        - Voice cache: checksum-verified user cache; model binaries are not bundled in git or app artifacts
        - STT language: `ja`
        - STT expected transcript marker: `今日の未完了`
        - STT transcript: passed - transcript contains the expected marker
        - whisper.cpp tiny model SHA-256: `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21`
        - Kokoro model SHA-256: `496dba118d1a58f5f3db2efc88dbdc216e0483fc89fe6e47ee1f2c53f18ad1e4`
        - TTS languages: `ja en`
        - TTS Japanese WAV: passed - generated non-empty WAV and afinfo-readable when afinfo is available
        - TTS English WAV: passed - generated non-empty WAV and afinfo-readable when afinfo is available
        - Runtime artifacts: `.tmp/local-voice-runtime-smoke`
        """.write(to: evidenceDirectory.appendingPathComponent("local-voice-runtime.md"), atomically: true, encoding: .utf8)

        let staleResult = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(staleResult.exitCode, 0)
        XCTAssertTrue(staleResult.output.contains("local voice runtime evidence source commit does not match current local voice source commit"))

        try """
        # Local Voice Runtime Evidence

        Status: passed
        Generated by: script/check_local_voice_runtime_smoke.sh

        ## Runtime Context

        - Source commit: `\(currentShortCommit)`
        - Generated at: 2026-06-19T00:00:00Z
        - Evidence source: `local whisper.cpp STT and Kokoro TTS runtime smoke`
        - No network download: passed - local cache and user-configured executables only
        - Kokoro runtime adapter: `script/kokoro_tts_runtime.py`
        - Offline env enforcement: passed - reference wrapper forces HF_HUB_OFFLINE=1 and TRANSFORMERS_OFFLINE=1 before importing Kokoro
        - No model binary committed or bundled: passed - model files remained outside git and app artifacts
        - Voice cache: checksum-verified user cache; model binaries are not bundled in git or app artifacts
        - STT language: `ja`
        - STT expected transcript marker: `今日の未完了`
        - STT transcript: passed - transcript contains the expected marker
        - whisper.cpp tiny model SHA-256: `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21`
        - Kokoro model SHA-256: `496dba118d1a58f5f3db2efc88dbdc216e0483fc89fe6e47ee1f2c53f18ad1e4`
        - TTS languages: `ja en`
        - TTS Japanese WAV: passed - generated non-empty WAV and afinfo-readable when afinfo is available
        - TTS English WAV: passed - generated non-empty WAV and afinfo-readable when afinfo is available
        - Runtime artifacts: `.tmp/local-voice-runtime-smoke`
        """.write(to: evidenceDirectory.appendingPathComponent("local-voice-runtime.md"), atomically: true, encoding: .utf8)

        let validResult = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(validResult.exitCode, 0)
        XCTAssertTrue(validResult.output.contains("OK: local voice runtime evidence covers checksum-verified STT and Japanese/English TTS runtime proof"))
        XCTAssertFalse(validResult.output.contains("local voice runtime evidence source commit does not match current local voice source commit"))
        XCTAssertFalse(validResult.output.contains("local voice runtime evidence is not marked passed"))
    }

    func testReleaseReadinessReportTreatsKokoroWrapperChangesAsLocalVoiceStale() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-stale-kokoro-wrapper-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let wrapperURL = scriptDirectory.appendingPathComponent("kokoro_tts_runtime.py")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourcesDirectory.appendingPathComponent("SoloPMCore/Voice", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourcesDirectory.appendingPathComponent("SoloPMCore/App", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourcesDirectory.appendingPathComponent("SoloPMApp", isDirectory: true), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try readPackageFile("script/check_local_voice_runtime_smoke.sh")
            .write(to: scriptDirectory.appendingPathComponent("check_local_voice_runtime_smoke.sh"), atomically: true, encoding: .utf8)
        try readPackageFile("script/kokoro_tts_runtime.py")
            .write(to: wrapperURL, atomically: true, encoding: .utf8)
        try readPackageFile("docs/voice-models.md")
            .write(to: fixtureRoot.appendingPathComponent("docs/voice-models.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "// package fixture\n"
            .write(to: fixtureRoot.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "SOLOPM_APP_VERSION=fixture\n"
            .write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try "enum VoiceRuntimeFixture {}\n"
            .write(to: sourcesDirectory.appendingPathComponent("SoloPMCore/Voice/VoiceRuntime.swift"), atomically: true, encoding: .utf8)
        try "enum AppSettingsFixture {}\n"
            .write(to: sourcesDirectory.appendingPathComponent("SoloPMCore/App/AppSettings.swift"), atomically: true, encoding: .utf8)
        try "enum DailyPlanningReviewReadoutFixture {}\n"
            .write(to: sourcesDirectory.appendingPathComponent("SoloPMCore/App/DailyPlanningReviewReadout.swift"), atomically: true, encoding: .utf8)
        try "enum SoloPMAppFixture {}\n"
            .write(to: sourcesDirectory.appendingPathComponent("SoloPMApp/SoloPMApp.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)

        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "init"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.email", "release-tests@example.invalid"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "config", "user.name", "Release Tests"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "add", "."]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "commit", "-m", "baseline local voice runtime source"]).exitCode, 0)
        let baselineCommit = try runTool(["git", "-C", fixtureRoot.path, "rev-parse", "--short", "HEAD"])
            .output.trimmingCharacters(in: .whitespacesAndNewlines)

        try """
        # Local Voice Runtime Evidence

        Status: passed
        Generated by: script/check_local_voice_runtime_smoke.sh

        ## Runtime Context

        - Source commit: `\(baselineCommit)`
        - Generated at: 2026-06-19T00:00:00Z
        - Evidence source: `local whisper.cpp STT and Kokoro TTS runtime smoke`
        - No network download: passed - local cache and user-configured executables only
        - Kokoro runtime adapter: `script/kokoro_tts_runtime.py`
        - Offline env enforcement: passed - reference wrapper forces HF_HUB_OFFLINE=1 and TRANSFORMERS_OFFLINE=1 before importing Kokoro
        - No model binary committed or bundled: passed - model files remained outside git and app artifacts
        - Voice cache: checksum-verified user cache; model binaries are not bundled in git or app artifacts
        - STT language: `ja`
        - STT expected transcript marker: `今日の未完了`
        - STT transcript: passed - transcript contains the expected marker
        - whisper.cpp tiny model SHA-256: `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21`
        - Kokoro model SHA-256: `496dba118d1a58f5f3db2efc88dbdc216e0483fc89fe6e47ee1f2c53f18ad1e4`
        - TTS languages: `ja en`
        - TTS Japanese WAV: passed - generated non-empty WAV and afinfo-readable when afinfo is available
        - TTS English WAV: passed - generated non-empty WAV and afinfo-readable when afinfo is available
        - Runtime artifacts: `.tmp/local-voice-runtime-smoke`
        """.write(to: evidenceDirectory.appendingPathComponent("local-voice-runtime.md"), atomically: true, encoding: .utf8)

        try "\n# wrapper source changed after evidence capture\n"
            .write(to: wrapperURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "add", "script/kokoro_tts_runtime.py"]).exitCode, 0)
        XCTAssertEqual(try runTool(["git", "-C", fixtureRoot.path, "commit", "-m", "change kokoro runtime wrapper"]).exitCode, 0)
        let wrapperCommit = try runTool(["git", "-C", fixtureRoot.path, "rev-parse", "--short", "HEAD"])
            .output.trimmingCharacters(in: .whitespacesAndNewlines)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("local voice runtime evidence source commit does not match current local voice source commit: expected \(wrapperCommit)"))
    }

    func testReleaseReadinessReportClassifiesUncheckedPhaseItems() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-phase-classification", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let actionSummaryURL = fixtureRoot.appendingPathComponent("release-actions.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
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
        - [ ] Implement durable local CRUD recovery for corrupted project rows.
        - [ ] 手動確認: login item 設定をオン / オフできる。
        - [ ] VoiceOver label、focus order、button help、destructive confirmationを確認する。
        - [ ] Notion、Todoist、Linear、Motion を2-4時間で触り、SoloPMに関係する機能だけを記録する。
        - [ ] Developer ID signing、notarization、Gatekeeper、clean environment evidence が揃う。
        """.write(to: tasksDirectory.appendingPathComponent("Phase11.md"), atomically: true, encoding: .utf8)
        try "- [x] README template is ignored here\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_RELEASE_ACTIONS_FILE": actionSummaryURL.path]
        )
        let actionSummary = try String(contentsOf: actionSummaryURL, encoding: .utf8)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Unchecked implementation phase items:"))
        XCTAssertTrue(result.output.contains("Implement durable local CRUD recovery for corrupted project rows."))
        XCTAssertTrue(result.output.contains("phase checklist still has unchecked implementation tasks"))
        XCTAssertTrue(result.output.contains("Unchecked manual/release phase gates:"))
        XCTAssertTrue(result.output.contains("login item 設定をオン / オフできる。"))
        XCTAssertTrue(result.output.contains("OK: unchecked manual/release phase gates are routed to evidence lanes"))
        XCTAssertFalse(result.output.contains("phase checklist still has unchecked manual/release gates"))
        XCTAssertTrue(actionSummary.contains("## Phase Checklist Items"))
        XCTAssertTrue(actionSummary.contains("## Blocker Buckets"))
        XCTAssertTrue(actionSummary.contains("Phase Checklist:"))
        XCTAssertTrue(actionSummary.contains("Manual VoiceOver:"))
        XCTAssertTrue(actionSummary.contains("Release Machine:"))
        XCTAssertTrue(actionSummary.contains("Unchecked implementation phase items:"))
        XCTAssertTrue(actionSummary.contains("Implement durable local CRUD recovery for corrupted project rows."))
        XCTAssertTrue(actionSummary.contains("Unchecked manual/release phase gates:"))
        XCTAssertTrue(actionSummary.contains("login item 設定をオン / オフできる。"))
        XCTAssertTrue(actionSummary.contains("VoiceOver label、focus order、button help、destructive confirmationを確認する。"))
        XCTAssertTrue(actionSummary.contains("Notion、Todoist、Linear、Motion を2-4時間で触り"))
        XCTAssertTrue(actionSummary.contains("Developer ID signing、notarization、Gatekeeper、clean environment evidence が揃う。"))
        XCTAssertTrue(actionSummary.contains("## Phase Manual Gate Routes"))
        XCTAssertTrue(actionSummary.contains("Phase checklist routing tracks 4 unchecked manual/release phase item(s); linked evidence blockers control release readiness while implementation or unmapped checklist items stay in Phase Checklist."))
        XCTAssertTrue(actionSummary.contains("- [ ] Login Item manual check is part of Phase checklist routing. Next: use the signed release app, complete `--login-item-toggle` in `.tmp/release-machine/release-machine-worksheet.md` and `.tmp/release-machine/create-release-evidence-command.sh`, then rerun readiness."))
        XCTAssertTrue(actionSummary.contains("Manual VoiceOver phase gates:"))
        XCTAssertTrue(actionSummary.contains("Competitor Hands-On phase gates:"))
        XCTAssertTrue(actionSummary.contains("Release Machine phase gates:"))
        XCTAssertTrue(actionSummary.contains("Release Machine phase gates:\n- [ ] tasks/Phase11.md:5:- [ ] Developer ID signing、notarization、Gatekeeper、clean environment evidence が揃う。"))
        XCTAssertTrue(actionSummary.contains("Login Item Manual Check phase gates:"))
        XCTAssertTrue(actionSummary.contains("Login Item Manual Check phase gates:\n- [ ] tasks/Phase11.md:2:- [ ] 手動確認: login item 設定をオン / オフできる。"))
        XCTAssertTrue(actionSummary.contains("## Login Item Manual Check"))
        XCTAssertTrue(actionSummary.contains("Login item evidence is recorded through `script/create_release_evidence.sh`, not a standalone checkbox."))
        let loginItemSectionStart = try XCTUnwrap(actionSummary.range(of: "## Login Item Manual Check"))
        let releaseMachineSectionStart = try XCTUnwrap(actionSummary.range(of: "## Release Machine"))
        let loginItemSection = String(actionSummary[loginItemSectionStart.lowerBound..<releaseMachineSectionStart.lowerBound])
        XCTAssertTrue(loginItemSection.contains("./script/create_release_evidence.sh --validate-only \\"))
        XCTAssertTrue(loginItemSection.contains("./script/create_release_evidence.sh --force \\"))
        XCTAssertTrue(actionSummary.contains("--login-item-toggle \\"))
        XCTAssertTrue(actionSummary.contains("--manual-environment \"<macOS version, hardware, clean user or VM/install context>\" \\"))
        XCTAssertTrue(actionSummary.contains("--note \"<concrete note covering Settings launch-at-login toggle on and off in the signed app>\""))
        XCTAssertTrue(actionSummary.contains("## Release Machine"))
        XCTAssertTrue(actionSummary.contains("./script/prepare_release_machine_evidence.sh"))
        XCTAssertTrue(actionSummary.contains(".tmp/release-machine/release-machine-worksheet.md"))
        XCTAssertTrue(actionSummary.contains(".tmp/release-machine/create-release-evidence-command.sh"))
        XCTAssertTrue(actionSummary.contains("$EDITOR .tmp/release-machine/release-machine-worksheet.md .tmp/release-machine/create-release-evidence-command.sh"))
        XCTAssertTrue(actionSummary.contains("./.tmp/release-machine/create-release-evidence-command.sh"))
        XCTAssertTrue(actionSummary.contains("```bash\n./script/prepare_release_machine_evidence.sh"))
        XCTAssertTrue(actionSummary.contains("# 1. Configure local release secrets"))
        XCTAssertTrue(actionSummary.contains("./script/verify_signing_setup.sh"))
        XCTAssertTrue(actionSummary.contains("SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh"))
        XCTAssertTrue(actionSummary.contains("SOLOPM_PACKAGE_FORMAT=all ./script/package_release.sh"))
        XCTAssertTrue(actionSummary.contains("SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/generate_appcast.sh"))
        XCTAssertTrue(actionSummary.contains("SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/verify_appcast.sh dist/releases/appcast.xml"))
        XCTAssertTrue(actionSummary.contains("SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh"))
        let releaseMachineSection = String(actionSummary[releaseMachineSectionStart.lowerBound...])
        let generatedReleaseEvidenceCommandRange = try XCTUnwrap(releaseMachineSection.range(of: "./.tmp/release-machine/create-release-evidence-command.sh"))
        let directReleaseEvidenceForceRange = try XCTUnwrap(releaseMachineSection.range(of: "./script/create_release_evidence.sh --force"))
        XCTAssertLessThan(generatedReleaseEvidenceCommandRange.lowerBound, directReleaseEvidenceForceRange.lowerBound)
    }

    func testReleaseReadinessReportRoutesManualPhaseGatesWithoutDuplicatePhaseBlocker() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-phase-manual-routing", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let actionSummaryURL = fixtureRoot.appendingPathComponent("release-actions.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
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
        - [ ] 手動確認: login item 設定をオン / オフできる。
        - [ ] VoiceOver label、focus order、button help、destructive confirmationを確認する。
        - [ ] Notion、Todoist、Linear、Motion を2-4時間で触り、SoloPMに関係する機能だけを記録する。
        - [ ] Developer ID signing、notarization、Gatekeeper、clean environment evidence が揃う。
        """.write(to: tasksDirectory.appendingPathComponent("Phase11.md"), atomically: true, encoding: .utf8)
        try "- [x] README template is ignored here\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_RELEASE_ACTIONS_FILE": actionSummaryURL.path]
        )
        let actionSummary = try String(contentsOf: actionSummaryURL, encoding: .utf8)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Unchecked manual/release phase gates:"))
        XCTAssertTrue(result.output.contains("VoiceOver label、focus order、button help、destructive confirmationを確認する。"))
        XCTAssertFalse(result.output.contains("phase checklist still has unchecked manual/release gates"))
        XCTAssertTrue(actionSummary.contains("## Phase Checklist Items"))
        XCTAssertTrue(actionSummary.contains("Unchecked manual/release phase gates:"))
        XCTAssertTrue(actionSummary.contains("## Phase Manual Gate Routes"))
        XCTAssertTrue(actionSummary.contains("Manual VoiceOver phase gates:"))
        XCTAssertTrue(actionSummary.contains("Competitor Hands-On phase gates:"))
        XCTAssertTrue(actionSummary.contains("Release Machine phase gates:"))
        XCTAssertTrue(actionSummary.contains("Login Item Manual Check phase gates:"))
        XCTAssertTrue(actionSummary.contains("Phase checklist manual gates are routed to evidence lanes; linked evidence blockers control release readiness."))
        XCTAssertFalse(actionSummary.contains("- [ ] phase checklist still has unchecked manual/release gates"))
    }

    func testReleaseReadinessReportKeepsUnmappedManualPhaseGatesAsPhaseBlockers() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-phase-manual-review", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let actionSummaryURL = fixtureRoot.appendingPathComponent("release-actions.md")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
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
        - [ ] manual evidence: PM must approve release copy before launch.
        """.write(to: tasksDirectory.appendingPathComponent("Phase11.md"), atomically: true, encoding: .utf8)
        try "- [x] README template is ignored here\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_RELEASE_ACTIONS_FILE": actionSummaryURL.path]
        )
        let actionSummary = try String(contentsOf: actionSummaryURL, encoding: .utf8)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Unchecked manual/release phase gates:"))
        XCTAssertTrue(result.output.contains("manual evidence: PM must approve release copy before launch."))
        XCTAssertTrue(result.output.contains("Unchecked manual review phase gates:"))
        XCTAssertTrue(result.output.contains("phase checklist still has unchecked manual review gates"))
        XCTAssertTrue(actionSummary.contains("Phase Checklist:"))
        XCTAssertTrue(actionSummary.contains("Manual Review phase gates:\n- [ ] tasks/Phase11.md:1:- [ ] manual evidence: PM must approve release copy before launch."))
        XCTAssertFalse(actionSummary.contains("Phase checklist manual gates are routed to evidence lanes; linked evidence blockers control release readiness."))
    }

    func testReleaseReadinessReportIncludesPhase11AndIgnoresFuturePhasePlanning() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-phase11-scope", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let screenshotDirectory = evidenceDirectory.appendingPathComponent("ui-screenshots", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
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
        try "- [x] Phase 10 complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase10-ReleaseReadinessRuntime.md"), atomically: true, encoding: .utf8)
        try "- [ ] Phase 11 productization gate\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase11-ProviderSyncUXProductization.md"), atomically: true, encoding: .utf8)
        try "- [ ] Phase 12 future idea\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase12-Future.md"), atomically: true, encoding: .utf8)
        try "- [x] template examples are ignored\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Phase11-ProviderSyncUXProductization.md:1:- [ ] Phase 11 productization gate"))
        XCTAssertFalse(result.output.contains("Phase12-Future.md"))
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
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
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
        XCTAssertTrue(result.output.contains("runtime mock/fake/fixture scan failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportBlocksRuntimeFixtureTerminology() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-runtime-fixture-terminology", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }
        let coreDirectory = sourcesDirectory.appendingPathComponent("SoloPMCore", isDirectory: true)
        try "public struct RetrievalFixture {}\n"
            .write(to: coreDirectory.appendingPathComponent("KnowledgeAdvanced.swift"), atomically: true, encoding: .utf8)

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
        XCTAssertTrue(result.output.contains("KnowledgeAdvanced.swift"))
        XCTAssertTrue(result.output.contains("RetrievalFixture"))
        XCTAssertTrue(result.output.contains("runtime source contains mock/fake/fixture/demo/test-only markers"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportScansExternalConnectorSourceWhenPresent() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-external-connector-scan", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI", "SoloPMExternalConnectors"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)ProductSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("ProductSource.swift"), atomically: true, encoding: .utf8)
        }
        let connectorDirectory = sourcesDirectory.appendingPathComponent("SoloPMExternalConnectors", isDirectory: true)
        try "public struct ConnectorFixture {}\n"
            .write(to: connectorDirectory.appendingPathComponent("ConnectorSource.swift"), atomically: true, encoding: .utf8)

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
        XCTAssertTrue(result.output.contains("SoloPMExternalConnectors/ConnectorSource.swift"))
        XCTAssertTrue(result.output.contains("ConnectorFixture"))
        XCTAssertTrue(result.output.contains("runtime source contains mock/fake/fixture/demo/test-only markers"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportShowsReleaseMachineNextActionsWhenPreflightFails() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-preflight-next-actions", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
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
        printf "BLOCKER: SOLOPM_SIGNING_IDENTITY is not set; Developer ID Application signing cannot run\\n"
        exit 1
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("== Release environment preflight =="))
        XCTAssertTrue(result.output.contains("SOLOPM_SIGNING_IDENTITY is not set"))
        XCTAssertTrue(result.output.contains("NEXT: run ./script/prepare_release_machine_evidence.sh on the release machine"))
        XCTAssertTrue(result.output.contains("NEXT: complete docs/release/checklist.md release-machine steps"))
        XCTAssertTrue(result.output.contains("packaging/signing.env"))
        XCTAssertTrue(result.output.contains("packaging/notarization.env"))
        XCTAssertTrue(result.output.contains("production Sparkle feed/key"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
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
        - Inbox Voice Light: `docs/release/evidence/ui-screenshots/inbox-voice-light.png`
        - Inbox Voice Dark: `docs/release/evidence/ui-screenshots/inbox-voice-dark.png`
        - Projects Overview Light: `docs/release/evidence/ui-screenshots/projects-overview-light.png`
        - Projects Overview Dark: `docs/release/evidence/ui-screenshots/projects-overview-dark.png`
        - Schedule Light: `docs/release/evidence/ui-screenshots/schedule-light.png`
        - Schedule Dark: `docs/release/evidence/ui-screenshots/schedule-dark.png`
        - Done Light: `docs/release/evidence/ui-screenshots/done-light.png`
        - Done Dark: `docs/release/evidence/ui-screenshots/done-dark.png`
        - Settings Integrations Light: `docs/release/evidence/ui-screenshots/settings-integrations-light.png`
        - Settings Integrations Dark: `docs/release/evidence/ui-screenshots/settings-integrations-dark.png`
        - Settings Overview Light: `docs/release/evidence/ui-screenshots/settings-overview-light.png`
        - Settings Overview Dark: `docs/release/evidence/ui-screenshots/settings-overview-dark.png`
        - Settings Appearance Light: `docs/release/evidence/ui-screenshots/settings-appearance-light.png`
        - Settings Appearance Dark: `docs/release/evidence/ui-screenshots/settings-appearance-dark.png`
        - MCP Settings Light: `docs/release/evidence/ui-screenshots/settings-mcp-light.png`
        - MCP Settings Dark: `docs/release/evidence/ui-screenshots/settings-mcp-dark.png`
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
        XCTAssertTrue(result.output.contains("NEXT: run script/capture_ui_evidence.sh --doctor"))
        XCTAssertTrue(result.output.contains("then run script/capture_ui_evidence.sh on a visible macOS session with Screen Recording permission"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportBlocksUIScreenshotEvidenceFromDifferentUISourceCommit() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-stale-ui-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let screenshotDirectory = evidenceDirectory.appendingPathComponent("ui-screenshots", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let currentUISourceCommit = try currentShortGitCommit()

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try readPackageFile("script/ui_evidence_content_check.swift")
            .write(
                to: scriptDirectory.appendingPathComponent("ui_evidence_content_check.swift"),
                atomically: true,
                encoding: .utf8
            )
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try """
        # UI Screenshot Evidence

        Generated with `script/capture_ui_evidence.sh`.

        - Generated at: `2026-06-19T00:00:00Z`
        - Source commit: `deadbee`

        ## Screenshots

        - Light: `docs/release/evidence/ui-screenshots/project-board-light.png`
        - Dark: `docs/release/evidence/ui-screenshots/project-board-dark.png`
        - System: `docs/release/evidence/ui-screenshots/project-board-system.png`
        - Inbox Voice Light: `docs/release/evidence/ui-screenshots/inbox-voice-light.png`
        - Inbox Voice Dark: `docs/release/evidence/ui-screenshots/inbox-voice-dark.png`
        - Projects Overview Light: `docs/release/evidence/ui-screenshots/projects-overview-light.png`
        - Projects Overview Dark: `docs/release/evidence/ui-screenshots/projects-overview-dark.png`
        - Schedule Light: `docs/release/evidence/ui-screenshots/schedule-light.png`
        - Schedule Dark: `docs/release/evidence/ui-screenshots/schedule-dark.png`
        - Done Light: `docs/release/evidence/ui-screenshots/done-light.png`
        - Done Dark: `docs/release/evidence/ui-screenshots/done-dark.png`
        - Settings Integrations Light: `docs/release/evidence/ui-screenshots/settings-integrations-light.png`
        - Settings Integrations Dark: `docs/release/evidence/ui-screenshots/settings-integrations-dark.png`
        - Settings Overview Light: `docs/release/evidence/ui-screenshots/settings-overview-light.png`
        - Settings Overview Dark: `docs/release/evidence/ui-screenshots/settings-overview-dark.png`
        - Settings Appearance Light: `docs/release/evidence/ui-screenshots/settings-appearance-light.png`
        - Settings Appearance Dark: `docs/release/evidence/ui-screenshots/settings-appearance-dark.png`
        - MCP Settings Light: `docs/release/evidence/ui-screenshots/settings-mcp-light.png`
        - MCP Settings Dark: `docs/release/evidence/ui-screenshots/settings-mcp-dark.png`
        """.write(to: evidenceDirectory.appendingPathComponent("ui-screenshots.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for screenshotFilename in [
            "project-board-light.png",
            "project-board-dark.png",
            "project-board-system.png",
            "inbox-voice-light.png",
            "inbox-voice-dark.png",
            "projects-overview-light.png",
            "projects-overview-dark.png",
            "schedule-light.png",
            "schedule-dark.png",
            "done-light.png",
            "done-dark.png",
            "settings-integrations-light.png",
            "settings-integrations-dark.png",
            "settings-overview-light.png",
            "settings-overview-dark.png",
            "settings-appearance-light.png",
            "settings-appearance-dark.png",
            "settings-mcp-light.png",
            "settings-mcp-dark.png"
        ] {
            try writeVisiblePNG(
                to: screenshotDirectory.appendingPathComponent(screenshotFilename),
                width: 800,
                height: 600,
                trailingBytes: 60_000
            )
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("UI screenshot evidence source commit does not match current UI source commit: expected \(currentUISourceCommit)"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenUIScreenshotEvidenceIsBlank() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-blank-ui-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let screenshotDirectory = evidenceDirectory.appendingPathComponent("ui-screenshots", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try readPackageFile("script/ui_evidence_content_check.swift")
            .write(
                to: scriptDirectory.appendingPathComponent("ui_evidence_content_check.swift"),
                atomically: true,
                encoding: .utf8
            )
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
        - Inbox Voice Light: `docs/release/evidence/ui-screenshots/inbox-voice-light.png`
        - Inbox Voice Dark: `docs/release/evidence/ui-screenshots/inbox-voice-dark.png`
        - Projects Overview Light: `docs/release/evidence/ui-screenshots/projects-overview-light.png`
        - Projects Overview Dark: `docs/release/evidence/ui-screenshots/projects-overview-dark.png`
        - Schedule Light: `docs/release/evidence/ui-screenshots/schedule-light.png`
        - Schedule Dark: `docs/release/evidence/ui-screenshots/schedule-dark.png`
        - Done Light: `docs/release/evidence/ui-screenshots/done-light.png`
        - Done Dark: `docs/release/evidence/ui-screenshots/done-dark.png`
        - Settings Integrations Light: `docs/release/evidence/ui-screenshots/settings-integrations-light.png`
        - Settings Integrations Dark: `docs/release/evidence/ui-screenshots/settings-integrations-dark.png`
        - Settings Overview Light: `docs/release/evidence/ui-screenshots/settings-overview-light.png`
        - Settings Overview Dark: `docs/release/evidence/ui-screenshots/settings-overview-dark.png`
        - Settings Appearance Light: `docs/release/evidence/ui-screenshots/settings-appearance-light.png`
        - Settings Appearance Dark: `docs/release/evidence/ui-screenshots/settings-appearance-dark.png`
        - MCP Settings Light: `docs/release/evidence/ui-screenshots/settings-mcp-light.png`
        - MCP Settings Dark: `docs/release/evidence/ui-screenshots/settings-mcp-dark.png`
        """.write(to: evidenceDirectory.appendingPathComponent("ui-screenshots.md"), atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: passed

        - [ ] Project navigation
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

        for screenshotFilename in [
            "project-board-light.png",
            "project-board-dark.png",
            "project-board-system.png",
            "inbox-voice-light.png",
            "inbox-voice-dark.png",
            "projects-overview-light.png",
            "projects-overview-dark.png",
            "schedule-light.png",
            "schedule-dark.png",
            "done-light.png",
            "done-dark.png",
            "settings-integrations-light.png",
            "settings-integrations-dark.png",
            "settings-overview-light.png",
            "settings-overview-dark.png",
            "settings-appearance-light.png",
            "settings-appearance-dark.png",
            "settings-mcp-light.png",
            "settings-mcp-dark.png"
        ] {
            try writeSolidPNG(
                to: screenshotDirectory.appendingPathComponent(screenshotFilename),
                width: 800,
                height: 600,
                red: 0,
                green: 0,
                blue: 0,
                trailingBytes: 60_000
            )
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/project-board-light.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/project-board-dark.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/project-board-system.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/inbox-voice-light.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/projects-overview-light.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/schedule-light.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/done-light.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/settings-integrations-light.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/settings-overview-light.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/settings-overview-dark.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/settings-appearance-light.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/settings-appearance-dark.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/settings-mcp-light.png"))
        XCTAssertTrue(result.output.contains("UI screenshot appears blank or too low contrast: docs/release/evidence/ui-screenshots/settings-mcp-dark.png"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
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
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
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

        - [ ] Project navigation
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
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence still contains pending/template/placeholder text"))
        XCTAssertTrue(result.output.contains("NEXT: replace docs/release/evidence/accessibility-voiceover.md with a real VoiceOver pass"))
        XCTAssertTrue(result.output.contains("./script/create_voiceover_evidence.sh --passed"))
        XCTAssertTrue(result.output.contains("--capture-runtime-ax-smoke"))
        XCTAssertTrue(result.output.contains("complete release-candidate context"))
        XCTAssertTrue(result.output.contains("Task content execution note must mention the redacted receipt, reviewed title, and reviewed detail"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenVoiceOverEvidencePassedButReleaseContextIsBlank() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-blank-voiceover-context", isDirectory: true)
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

        Status: passed

        ## Release Candidate Context

        - macOS version:
        - App build:
        - Bundle identifier: `dev.solopm.SoloPM`
        - Checked by:
        - Check date:
        - Evidence source: signed or release-candidate `dist/SoloPM.app`
        - Accessibility environment:
        - Runtime AX smoke:

        - [ ] Project navigation
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
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing release context: macOS version"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing release context: App build"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing release context: Checked by"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing release context: Check date"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing release context: Accessibility environment"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing release context: Runtime AX smoke"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence has template release context: Evidence source"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence still contains unchecked checklist markers"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenVoiceOverEvidenceDoesNotMatchAppMetadata() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-voiceover-metadata-mismatch", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
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
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: passed

        ## Release Candidate Context

        - macOS version: macOS 15.5
        - App build: `0.1.0 (999)`
        - Bundle identifier: `dev.solopm.wrong`
        - Checked by: SoloPM Release Owner
        - Check date: 2026-06-19
        - Evidence source: `dist/SoloPM.app` manual pass
        - Accessibility environment: VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display
        - Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        - Project navigation: passed
        - Project board detail: passed
        - Open task: passed
        - Status controls: passed
        - Task inspector: passed
        - Save Changes: passed
        - Delete Task confirmation: passed
        - No keyboard trap: passed
        - No unlabeled primary CRUD controls: passed
        """.write(to: evidenceDirectory.appendingPathComponent("accessibility-voiceover.md"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence bundle identifier does not match packaging metadata: expected dev.solopm.app"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence app build does not match packaging metadata: expected 0.1.0 (1)"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence is not marked passed"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence still contains pending/template/placeholder text"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence still contains unchecked checklist markers"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenVoiceOverEvidenceLacksConcreteFocusNotes() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-weak-voiceover-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
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
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: passed

        ## Release Candidate Context

        - macOS version: macOS unknown
        - App build: `0.1.0 (1)`
        - Bundle identifier: `dev.solopm.app`
        - Source commit: `deadbee`
        - Checked by: SoloPM Release Owner
        - Check date: 2026-02-31
        - Evidence source: `dist/SoloPM.app` manual pass
        - Accessibility environment: VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display
        - Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        ## Verified Focus Path

        - Project navigation: passed - Verified.
        - Project board detail: passed - Concrete VoiceOver observation for selected project board context.
        - Open task: passed -
        - Inline Task Composer: passed -
        - Status controls: passed -
        - Task inspector: passed -
        - Save Changes: passed -
        - Delete Task confirmation: passed -
        - No keyboard trap: passed -
        - No unlabeled primary CRUD controls: passed -
        """.write(to: evidenceDirectory.appendingPathComponent("accessibility-voiceover.md"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence has template release context: macOS version"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence has invalid release context date: Check date"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence has boilerplate focus note: Project navigation"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence has boilerplate focus note: Project board detail"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: Open task"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: Inline Task Composer"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: Status controls"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: Task inspector"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: Inbox voice triage"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: Today rail actions"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: Save Changes"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: Task content execution"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: Delete Task confirmation"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: No keyboard trap"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: No unlabeled primary CRUD controls"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenTaskContentExecutionNoteDoesNotProveReceiptContent() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-weak-task-content-execution-note", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let accessibilityPreflightURL = scriptDirectory.appendingPathComponent("check_accessibility_preflight.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }
        let currentShortCommit = try currentShortGitCommit()

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "accessibility source ok\\n"
        """.write(to: accessibilityPreflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: passed
        Generated by: script/create_voiceover_evidence.sh

        ## Release Candidate Context

        - macOS version: macOS 15.5
        - App build: `0.1.0 (1)`
        - Bundle identifier: `dev.solopm.app`
        - Source commit: `\(currentShortCommit)`
        - Checked by: SoloPM Release Owner
        - Check date: 2026-06-19
        - Evidence source: `dist/SoloPM.app` manual pass
        - Accessibility environment: VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display
        - Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        ## Verified Focus Path

        - Project navigation: passed - Sidebar Inbox, Today, and selected project rows announce destination and counts in order.
        - Project board detail: passed - Selected project board announces project title before card navigation begins.
        - Open task: passed - Task card details open from keyboard focus without relying on drag.
        - Inline Task Composer: passed - Title, detail, priority, due, create, cancel, Command+Return, and Escape paths are reachable.
        - Status controls: passed - Previous and next status buttons announce the target status before moving the task.
        - Task inspector: passed - Title, detail, status, priority, due, summary, save, suggestion, and danger actions are reachable.
        - Inbox voice triage: passed - Inbox voice detail announced transcript and triage actions.
        - Today rail actions: passed - Today rail announced focus, schedule, and reminder controls.
        - Save Changes: passed - Keyboard activation reaches the local task save action and returns without a trap.
        - Task content execution: passed - VoiceOver announced Run approved plan and the selected task execution completed.
        - Delete Task confirmation: passed - Delete opens confirmation before local deletion and exposes cancel.
        - No keyboard trap: passed - Focus can leave sidebar, board, card controls, inspector fields, and dialogs.
        - No unlabeled primary CRUD controls: passed - Create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.
        """.write(to: evidenceDirectory.appendingPathComponent("accessibility-voiceover.md"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, accessibilityPreflightURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence Task content execution note must mention the redacted receipt, reviewed title, and reviewed detail"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence Inbox voice triage note must mention transcript, interpretation, metadata, memo, make task, schedule, review later, project, and triage"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence Today rail actions note must mention next action, task detail, focus, schedule, edit, subtask, and reminder"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence missing concrete focus note: Task content execution"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence has boilerplate focus note: Task content execution"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence source commit does not match current release-candidate source commit"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportRequiresRegressionFollowUpForManualFailureNotes() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-manual-finding-follow-up", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let docsDirectory = fixtureRoot.appendingPathComponent("docs", isDirectory: true)
        let productDirectory = docsDirectory.appendingPathComponent("product", isDirectory: true)
        let evidenceDirectory = docsDirectory
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let accessibilityPreflightURL = scriptDirectory.appendingPathComponent("check_accessibility_preflight.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: productDirectory, withIntermediateDirectories: true)
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
        printf "accessibility source ok\\n"
        """.write(to: accessibilityPreflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: passed
        Generated by: script/create_voiceover_evidence.sh

        ## Release Candidate Context

        - macOS version: macOS 15.5
        - App build: `0.1.0 (1)`
        - Bundle identifier: `dev.solopm.app`
        - Source commit: `unknown`
        - Checked by: SoloPM Release Owner
        - Check date: 2026-06-01
        - Evidence source: `dist/SoloPM.app` manual pass
        - Accessibility environment: VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display
        - Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        ## Verified Focus Path

        - Project navigation: passed - Sidebar navigation announced destination and counts.
        - Project board detail: passed - Board detail announced project context.
        - Open task: passed - Task card opened from keyboard focus.
        - Inline Task Composer: passed - Composer fields, create, and cancel were reachable.
        - Status controls: passed - Status move buttons announced target status.
        - Task inspector: passed - Inspector fields and actions were reachable.
        - Inbox voice triage: passed - Inbox voice detail announced transcript, interpretation, source metadata, memo editing, and make task, schedule, review later, and project triage actions.
        - Today rail actions: passed - Today assistant rail announced next action, task detail, focus, schedule draft, edit, subtask, and reminder draft controls.
        - Save Changes: passed - Save activated from keyboard.
        - Task content execution: passed - Approved execution recorded the reviewed task title and detail in the redacted receipt.
        - Delete Task confirmation: passed - Destructive confirmation was announced.
        - No keyboard trap: passed - Focus left every primary region.
        - No unlabeled primary CRUD controls: passed - Primary CRUD controls had labels.

        ## Failure Notes

        - Blocker observed: Delete confirmation announced a generic action during the manual VoiceOver pass.
        - Affected path: Delete Task confirmation.
        - Follow-up source/test link: none.
        - Fix owner: Accessibility owner.
        """.write(to: evidenceDirectory.appendingPathComponent("accessibility-voiceover.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Hands-On Evidence

        Status: passed
        Generated by: script/create_competitor_hands_on_evidence.sh

        ## Review Context

        - Checked by: SoloPM Product Reviewer
        - Check date: 2026-06-01
        - Source commit: `unknown`
        - Evidence source: `Real local hands-on pass`
        - Environment: macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used
        - Elapsed hands-on time: 2h 15m total: Notion 35m, Todoist 30m, Linear 35m, Motion 35m
        - Scope: Notion -> Todoist -> Linear -> Motion

        ## Verified Hands-On Path

        - Notion: passed - Board setup was flexible but required manual schema decisions before task entry felt fast.
        - Todoist: passed - Quick Add made capture fast, but project context still needed review after entry.
        - Linear: passed - Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.
        - Motion: passed - Scheduling suggestions were useful only when the reason and deadline impact were visible.
        - No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.

        ## Ship / Defer / Reject Delta

        - Ship: Keep fast local capture, board status movement, and right inspector as the public alpha loop.
        - Defer: Natural-language dates and autonomous scheduling stay out until reliability evidence exists.
        - Reject: Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.

        ## Failure Notes

        - Blocker observed: Motion recommendation copy made the schedule tradeoff unclear.
        - Affected path: Motion scheduling comparison.
        - Follow-up source/test link: none.
        - Fix owner: Product owner.
        """.write(to: evidenceDirectory.appendingPathComponent("competitor-hands-on.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Benchmark and Hands-On Findings

        Verified: 2026-06-01

        Reviewed by: SoloPM Product Reviewer

        Source commit: `unknown`

        Environment: macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used

        Elapsed hands-on time: 2h 15m total

        Evidence source: `Real local hands-on pass`

        Scope: Notion -> Todoist -> Linear -> Motion

        ## Hands-On Findings

        - Notion: Board setup was flexible but required manual schema decisions before task entry felt fast.
        - Todoist: Quick Add made capture fast, but project context still needed review after entry.
        - Linear: Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.
        - Motion: Scheduling suggestions were useful only when the reason and deadline impact were visible.

        ## Ship / Defer / Reject

        - Ship: Keep fast local capture, board status movement, and right inspector as the public alpha loop.
        - Defer: Natural-language dates and autonomous scheduling stay out until reliability evidence exists.
        - Reject: Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.
        """.write(to: productDirectory.appendingPathComponent("competitor-benchmark.md"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, accessibilityPreflightURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence manual failure note lacks linked regression test or follow-up issue"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence manual failure note lacks linked regression test or follow-up issue"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence missing concrete focus note"))
        XCTAssertFalse(result.output.contains("Competitor hands-on evidence missing concrete note"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenManualEvidenceCheckDateIsFuture() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-future-manual-evidence-date", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let accessibilityPreflightURL = scriptDirectory.appendingPathComponent("check_accessibility_preflight.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
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
        printf "accessibility source ok\\n"
        """.write(to: accessibilityPreflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: passed

        ## Release Candidate Context

        - macOS version: macOS 15.5
        - App build: `0.1.0 (1)`
        - Bundle identifier: `dev.solopm.app`
        - Source commit: `deadbee`
        - Checked by: SoloPM Release Owner
        - Check date: 2099-01-01
        - Evidence source: `dist/SoloPM.app` manual pass
        - Accessibility environment: VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display
        - Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        ## Verified Focus Path

        - Project navigation: passed - Sidebar navigation announced destination and counts.
        - Project board detail: passed - Board detail announced project context.
        - Open task: passed - Task card opened from keyboard focus.
        - Inline Task Composer: passed - Composer fields, create, and cancel were reachable.
        - Status controls: passed - Status move buttons announced target status.
        - Task inspector: passed - Inspector fields and actions were reachable.
        - Inbox voice triage: passed - Inbox voice detail announced transcript, interpretation, source metadata, memo editing, and make task, schedule, review later, and project triage actions.
        - Today rail actions: passed - Today assistant rail announced next action, task detail, focus, schedule draft, edit, subtask, and reminder draft controls.
        - Save Changes: passed - Save activated from keyboard.
        - Task content execution: passed - Approved execution recorded the reviewed task title and detail in the redacted receipt.
        - Delete Task confirmation: passed - Destructive confirmation was announced.
        - No keyboard trap: passed - Focus left every primary region.
        - No unlabeled primary CRUD controls: passed - Primary CRUD controls had labels.
        """.write(to: evidenceDirectory.appendingPathComponent("accessibility-voiceover.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Hands-On Evidence

        Status: passed

        ## Review Context

        - Checked by: SoloPM Product Reviewer
        - Check date: 2099-01-01
        - Source commit: `deadbee`
        - Evidence source: `Real local hands-on pass`
        - Environment: macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used
        - Elapsed hands-on time: 2h 15m total: Notion 35m, Todoist 30m, Linear 35m, Motion 35m
        - Scope: Notion -> Todoist -> Linear -> Motion

        ## Verified Hands-On Path

        - Notion: passed - Board setup was flexible but required manual schema decisions before task entry felt fast.
        - Todoist: passed - Quick Add made capture fast, but project context still needed review after entry.
        - Linear: passed - Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.
        - Motion: passed - Scheduling suggestions were useful only when the reason and deadline impact were visible.
        - No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.

        ## Ship / Defer / Reject Delta

        - Ship: Keep fast local capture, board status movement, and right inspector as the public alpha loop.
        - Defer: Natural-language dates and autonomous scheduling stay out until reliability evidence exists.
        - Reject: Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.
        """.write(to: evidenceDirectory.appendingPathComponent("competitor-hands-on.md"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, accessibilityPreflightURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence has future release context date: Check date"))
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence source commit does not match current release-candidate source commit"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has future review context date: Check date"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence source commit does not match current release-candidate source commit"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence missing concrete focus note"))
        XCTAssertFalse(result.output.contains("Competitor hands-on evidence missing concrete note"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportRejectsPlaceholderManualEvidenceReviewers() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-placeholder-manual-evidence-reviewers", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let accessibilityPreflightURL = scriptDirectory.appendingPathComponent("check_accessibility_preflight.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
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
        printf "accessibility source ok\\n"
        """.write(to: accessibilityPreflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: passed

        ## Release Candidate Context

        - macOS version: macOS 15.5
        - App build: `0.1.0 (1)`
        - Bundle identifier: `dev.solopm.app`
        - Checked by: Reviewer Name
        - Check date: 2026-06-19
        - Evidence source: `dist/SoloPM.app` manual pass
        - Accessibility environment: VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display
        - Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        ## Verified Focus Path

        - Project navigation: passed - Sidebar navigation announced destination and counts.
        - Project board detail: passed - Board detail announced project context.
        - Open task: passed - Task card opened from keyboard focus.
        - Inline Task Composer: passed - Composer fields, create, and cancel were reachable.
        - Status controls: passed - Status move buttons announced target status.
        - Task inspector: passed - Inspector fields and actions were reachable.
        - Inbox voice triage: passed - Inbox voice detail announced transcript, interpretation, source metadata, memo editing, and make task, schedule, review later, and project triage actions.
        - Today rail actions: passed - Today assistant rail announced next action, task detail, focus, schedule draft, edit, subtask, and reminder draft controls.
        - Save Changes: passed - Save activated from keyboard.
        - Task content execution: passed - Approved execution recorded the reviewed task title and detail in the redacted receipt.
        - Delete Task confirmation: passed - Destructive confirmation was announced.
        - No keyboard trap: passed - Focus left every primary region.
        - No unlabeled primary CRUD controls: passed - Primary CRUD controls had labels.
        """.write(to: evidenceDirectory.appendingPathComponent("accessibility-voiceover.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Hands-On Evidence

        Status: passed

        ## Review Context

        - Checked by: Reviewer Name
        - Check date: 2026-06-19
        - Evidence source: `Real local hands-on pass`
        - Environment: macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used
        - Elapsed hands-on time: 2h 15m total: Notion 35m, Todoist 30m, Linear 35m, Motion 35m
        - Scope: Notion -> Todoist -> Linear -> Motion

        ## Verified Hands-On Path

        - Notion: passed - Board setup was flexible but required manual schema decisions before task entry felt fast.
        - Todoist: passed - Quick Add made capture fast, but project context still needed review after entry.
        - Linear: passed - Keyboard-driven issue triage was fast, but team concepts were heavier than solo project work.
        - Motion: passed - Scheduling suggestions were useful only when the reason and deadline impact were visible.
        - No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.

        ## Ship / Defer / Reject Delta

        - Ship: Keep fast local capture, board status movement, and right inspector as the public alpha loop.
        - Defer: Natural-language dates and autonomous scheduling stay out until reliability evidence exists.
        - Reject: Team cycles, initiatives, and external SaaS sync stay outside public alpha scope.
        """.write(to: evidenceDirectory.appendingPathComponent("competitor-hands-on.md"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, accessibilityPreflightURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence has template release context: Checked by"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence has template review context: Checked by"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence missing concrete focus note"))
        XCTAssertFalse(result.output.contains("Competitor hands-on evidence missing concrete note"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence has future release context date"))
        XCTAssertFalse(result.output.contains("Competitor hands-on evidence has future review context date"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportRejectsPassedManualEvidenceWithoutGeneratorProvenance() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-manual-evidence-provenance", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let productDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("product", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let accessibilityPreflightURL = scriptDirectory.appendingPathComponent("check_accessibility_preflight.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: productDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for targetName in ["SoloPMCore", "SoloPMApp", "SoloPMCLI"] {
            let targetDirectory = sourcesDirectory.appendingPathComponent(targetName, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            try "final class \(targetName)RuntimeSource {}\n"
                .write(to: targetDirectory.appendingPathComponent("RuntimeSource.swift"), atomically: true, encoding: .utf8)
        }
        let currentShortCommit = try currentShortGitCommit()

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "accessibility source ok\\n"
        """.write(to: accessibilityPreflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: passed

        ## Release Candidate Context

        - macOS version: macOS 15.5
        - App build: `0.1.0 (1)`
        - Bundle identifier: `dev.solopm.app`
        - Source commit: `\(currentShortCommit)`
        - Checked by: SoloPM Release Owner
        - Check date: 2026-06-19
        - Evidence source: `dist/SoloPM.app` manual pass
        - Accessibility environment: VoiceOver on macOS 15.5, built-in keyboard, trackpad, 14-inch display
        - Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0, crudSignals=8/8, focusPathSignals=6/6, destructiveCancelSignals=1/1

        ## Verified Focus Path

        - Project navigation: passed - Selected Inbox, Today, and Project Alpha from the sidebar with VoiceOver; each row announced destination and task counts before selection.
        - Project board detail: passed - Project Alpha board announced the project title before card navigation and kept the board context while moving between columns.
        - Open task: passed - Focused a task card with the keyboard, opened details, and confirmed the inspector title matched the selected task.
        - Inline Task Composer: passed - Reached title, detail, priority, due, create, cancel, Command+Return, and Escape paths from a board column.
        - Status controls: passed - Previous and next status controls announced the target status before moving the selected local task.
        - Task inspector: passed - Focus reached title, detail, status, priority, due, summary, save, suggestion, and destructive actions.
        - Inbox voice triage: passed - Inbox voice detail announced transcript, interpretation, source metadata, memo editing, and make task, schedule, review later, and project triage actions.
        - Today rail actions: passed - Today assistant rail announced next action, task detail, focus, schedule draft, edit, subtask, and reminder draft controls.
        - Save Changes: passed - Keyboard activation saved the local task edit and left focus in the inspector without trapping it.
        - Task content execution: passed - Approved execution recorded the reviewed task title and detail in the redacted receipt for the selected local task.
        - Delete Task confirmation: passed - Delete opened the inline confirmation panel, announced cancel and confirm, and did not delete until confirmation.
        - No keyboard trap: passed - Focus moved out of sidebar, board, card controls, inspector fields, and inline confirmation panels.
        - No unlabeled primary CRUD controls: passed - Create, update, status move, local suggestion apply, automation review, approved execution, and delete controls exposed labels or help.
        """.write(to: evidenceDirectory.appendingPathComponent("accessibility-voiceover.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Hands-On Evidence

        Status: passed

        ## Review Context

        - Checked by: SoloPM Product Reviewer
        - Check date: 2026-06-19
        - Source commit: `\(currentShortCommit)`
        - Evidence source: `Hands-on local account notes plus official source links`
        - Environment: macOS 15.5, Safari 26, Notion Free, Todoist Free, Linear Free, Motion trial not used
        - Elapsed hands-on time: 2h 15m total: Notion 35m, Todoist 30m, Linear 35m, Motion 35m
        - Scope: Notion -> Todoist -> Linear -> Motion

        ## Verified Hands-On Path

        - Notion: passed - Created a project database, switched to board view, added three cards, and confirmed setup choices before the first useful task were heavier than SoloPM.
        - Todoist: passed - Used Quick Add with project and priority, switched to board layout, and confirmed capture was fast but destination review still mattered.
        - Linear: passed - Created a project issue, moved status, opened detail sidebar, and confirmed keyboard operation was strong but team concepts were outside SoloPM alpha scope.
        - Motion: passed - Created dated priority tasks and reviewed scheduling/risk surfaces, confirming recommendations need visible reasoning before applying.
        - No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.

        ## Ship / Defer / Reject Delta

        - Ship: Keep local Inbox capture, board movement, and the right inspector because the hands-on pass showed those are the fastest repeated execution path.
        - Defer: Keep natural-language dates and autonomous scheduling out until local date parsing and calendar trust have stronger evidence.
        - Reject: Keep team cycles, initiatives, and external SaaS sync outside public alpha because the benchmark did not improve the solo local-first loop.
        """.write(to: evidenceDirectory.appendingPathComponent("competitor-hands-on.md"), atomically: true, encoding: .utf8)
        try """
        # Competitor Benchmark and Feature Fit

        Verified: 2026-06-19

        Source commit: `\(currentShortCommit)`

        ## Hands-On Findings

        - Notion: The hands-on board setup confirmed flexible structure is powerful, but first useful task capture is slower than SoloPM's fixed project/task model.
        - Todoist: The hands-on Quick Add and board pass confirmed capture speed is the bar SoloPM must match with Inbox and menu bar entry.
        - Linear: The hands-on project and issue detail pass confirmed the right inspector and keyboard shortcuts are worth shipping for repeated CRUD.
        - Motion: The hands-on scheduling pass confirmed risk suggestions need visible reasoning and should not auto-apply in the public alpha.

        ## Ship / Defer / Reject

        - Ship: Fast Inbox capture, board status movement, and right-inspector CRUD.
        - Defer: Natural-language dates, calendar layout, and autonomous scheduling until reliability evidence exists.
        - Reject: Arbitrary database builders, team cycles, initiatives, and external SaaS sync for public alpha.
        """.write(to: productDirectory.appendingPathComponent("competitor-benchmark.md"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, accessibilityPreflightURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("VoiceOver accessibility evidence was not generated by script/create_voiceover_evidence.sh"))
        XCTAssertTrue(result.output.contains("Competitor hands-on evidence was not generated by script/create_competitor_hands_on_evidence.sh"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence source commit does not match current release-candidate source commit"))
        XCTAssertFalse(result.output.contains("Competitor hands-on evidence source commit does not match current release-candidate source commit"))
        XCTAssertFalse(result.output.contains("VoiceOver accessibility evidence missing concrete focus note"))
        XCTAssertFalse(result.output.contains("Competitor hands-on evidence missing concrete note"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenAccessibilitySourcePreflightFails() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-accessibility-source-preflight", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let accessibilityPreflightURL = scriptDirectory.appendingPathComponent("check_accessibility_preflight.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
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
        echo "BLOCKER: missing accessibility anchor 'task-inspector-save' in ProjectBoardView.swift" >&2
        exit 1
        """.write(to: accessibilityPreflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try """
        # VoiceOver Accessibility Evidence

        Status: passed

        ## Release Candidate Context

        - macOS version: macOS 15.5
        - App build: `0.1.0 (1)`
        - Bundle identifier: `dev.solopm.app`
        - Checked by: SoloPM Release Owner
        - Check date: 2026-06-19
        - Evidence source: `dist/SoloPM.app` manual pass

        ## Verified Focus Path

        - Project navigation: passed - Sidebar navigation announced counts.
        - Project board detail: passed - Board detail announced project title.
        - Open task: passed - Task opened from keyboard focus.
        - Inline Task Composer: passed - Composer controls were reachable.
        - Status controls: passed - Move controls announced target status.
        - Task inspector: passed - Inspector fields and actions were reachable.
        - Save Changes: passed - Save activated from keyboard.
        - Task content execution: passed - Approved execution recorded the reviewed task title and detail in the redacted receipt.
        - Delete Task confirmation: passed - Delete confirmation was announced.
        - No keyboard trap: passed - Focus left all primary regions.
        - No unlabeled primary CRUD controls: passed - Primary CRUD labels were present.
        """.write(to: evidenceDirectory.appendingPathComponent("accessibility-voiceover.md"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, accessibilityPreflightURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("missing accessibility anchor 'task-inspector-save'"))
        XCTAssertTrue(result.output.contains("accessibility source preflight failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportCanRunRuntimeAccessibilityPreflightWhenEnabled() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-accessibility-runtime-preflight", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let accessibilityPreflightURL = scriptDirectory.appendingPathComponent("check_accessibility_preflight.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
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
        case "${1:-}" in
          --source-only)
            printf "source preflight ok\\n"
            printf "This is not a substitute for the manual VoiceOver pass.\\n"
            ;;
          --runtime)
            if [[ "${2:-}" == "--skip-source-anchors" ]]; then
              printf "runtime preflight ok without duplicate source anchors\\n"
            else
              printf "runtime preflight ok\\n"
            fi
            printf "This is not a substitute for the manual VoiceOver pass.\\n"
            ;;
          *)
            echo "unexpected accessibility preflight argument: ${1:-}" >&2
            exit 2
            ;;
        esac
        """.write(to: accessibilityPreflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, accessibilityPreflightURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT": "1"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("source preflight ok"))
        XCTAssertTrue(result.output.contains("runtime preflight ok without duplicate source anchors"))
        XCTAssertEqual(result.output.components(separatedBy: "source preflight ok").count - 1, 1)
        XCTAssertEqual(result.output.components(separatedBy: "This is not a substitute for the manual VoiceOver pass.").count - 1, 1)
        XCTAssertFalse(result.output.contains("accessibility runtime preflight failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportCanRunReleaseCIPreflightWhenEnabled() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-ci-preflight", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let scriptsDirectory = fixtureRoot.appendingPathComponent("scripts", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let ciPreflightURL = scriptsDirectory.appendingPathComponent("ci.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
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
        printf "release ci preflight ok\\n"
        """.write(to: ciPreflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, ciPreflightURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_RELEASE_CI_PREFLIGHT": "1"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release ci preflight ok"))
        XCTAssertFalse(result.output.contains("release CI preflight failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportCanRunXcodePreflightWhenEnabled() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-xcode-preflight", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let fakeBinDirectory = fixtureRoot.appendingPathComponent("bin", isDirectory: true)
        let swiftpmXcodeDirectory = fixtureRoot
            .appendingPathComponent(".swiftpm", isDirectory: true)
            .appendingPathComponent("xcode", isDirectory: true)
        let workspaceDirectory = swiftpmXcodeDirectory.appendingPathComponent("package.xcworkspace", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let fakeXcodebuildURL = fakeBinDirectory.appendingPathComponent("xcodebuild")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeBinDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
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
        printf "release xcode preflight ok: %s\\n" "$*"
        """.write(to: fakeXcodebuildURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, fakeXcodebuildURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let path = "\(fakeBinDirectory.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        let result = try runTool(
            ["bash", reportURL.path],
            environment: [
                "PATH": path,
                "SOLOPM_RELEASE_XCODE_PREFLIGHT": "1"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release xcode preflight ok"))
        XCTAssertTrue(result.output.contains("-workspace"))
        XCTAssertTrue(result.output.contains(".swiftpm/xcode/package.xcworkspace"))
        XCTAssertTrue(result.output.contains("-scheme SoloPM"))
        XCTAssertFalse(result.output.contains("release Xcode preflight failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportCanRunLaunchPreflightWhenEnabled() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-launch-preflight", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let launchPreflightURL = scriptDirectory.appendingPathComponent("build_and_run.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
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
        if [[ "${1:-}" != "--verify" ]]; then
          echo "unexpected launch preflight argument: ${1:-}" >&2
          exit 2
        fi
        printf "release launch preflight ok\\n"
        printf "OK: Project Board window visible (100 40 40 1200 760)\\n"
        """.write(to: launchPreflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, launchPreflightURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_RELEASE_LAUNCH_PREFLIGHT": "1"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release launch preflight ok"))
        XCTAssertTrue(result.output.contains("OK: Project Board window visible"))
        XCTAssertFalse(result.output.contains("release launch preflight failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportCanRunLayoutStabilitySmokeWhenEnabled() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-layout-stability-smoke", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let packagingDirectory = fixtureRoot.appendingPathComponent("packaging", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let releasePreflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let layoutStabilityURL = scriptDirectory.appendingPathComponent("check_layout_stability_smoke.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
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
        printf "OK: layout stability smoke passed; artifacts written to .tmp/layout-stability\\n"
        """.write(to: layoutStabilityURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: releasePreflightURL, atomically: true, encoding: .utf8)
        try """
        APP_NAME=SoloPM
        BUNDLE_IDENTIFIER=dev.solopm.app
        MARKETING_VERSION=0.1.0
        CURRENT_PROJECT_VERSION=1
        """.write(to: packagingDirectory.appendingPathComponent("app_metadata.env"), atomically: true, encoding: .utf8)
        try "- [x] release gate checked\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] release readme checked\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, releasePreflightURL, layoutStabilityURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(
            ["bash", reportURL.path],
            environment: ["SOLOPM_LAYOUT_STABILITY_SMOKE": "1"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("OK: layout stability smoke passed; artifacts written to .tmp/layout-stability"))
        XCTAssertFalse(result.output.contains("layout stability smoke failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))

        let script = try readPackageFile("script/release_readiness_report.sh")
        XCTAssertTrue(script.contains("SOLOPM_LAYOUT_STABILITY_SMOKE"))
        XCTAssertTrue(script.contains("script/check_layout_stability_smoke.sh"))
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")
        XCTAssertTrue(phase.contains("- [x] `release_readiness_report.sh` がlayout stability smokeの結果を取り込めることをテストする。"))
    }

    func testReleaseReadinessReportFailsWhenMCPInspectorEvidenceIsMissing() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-missing-mcp-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")

        try? FileManager.default.removeItem(at: fixtureRoot)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
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
        XCTAssertTrue(result.output.contains("== MCP Inspector evidence =="))
        XCTAssertTrue(result.output.contains("missing MCP Inspector evidence file: docs/release/evidence/mcp-inspector.md"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenMCPInspectorEvidenceIsIncomplete() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-incomplete-mcp-evidence", isDirectory: true)
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
        # MCP Inspector Evidence

        Generated: 2026-06-19T00:00:00Z

        Scope: validate the release MCP stdio fixture with the official MCP Inspector CLI and SoloPM's local JSON-RPC smoke checks.

        Stable baseline: `2025-11-25`

        MCP Inspector CLI tools/list
        """.write(to: evidenceDirectory.appendingPathComponent("mcp-inspector.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reportURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preflightURL.path)

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("== MCP Inspector evidence =="))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence is missing marker: Draft watchlist: `2026-07-28`"))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence is missing marker: Official stable latest: `2025-11-25`"))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence is missing marker: Official latest source: https://modelcontextprotocol.io/specification"))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence is missing marker: Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases"))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence is missing marker: Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release."))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence is missing marker: Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning"))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence is missing marker: Official latest checked: 2026-06-24"))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence is missing marker: 2026-07-28 is release-candidate; final specification is scheduled for 2026-07-28."))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence is missing marker: MCP Inspector CLI tools/call"))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence is missing marker: malformed-json"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportBlocksMCPInspectorEvidenceFromDifferentMCPSourceCommit() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-stale-mcp-source-evidence", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let docsDirectory = fixtureRoot.appendingPathComponent("docs", isDirectory: true)
        let evidenceDirectory = docsDirectory
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let mcpVerifierURL = scriptDirectory.appendingPathComponent("verify_mcp_compliance.sh")

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

        let currentShortCommit = try currentShortGitCommit()
        let completeRuntimeEvidence = """
        # MCP Inspector Evidence

        Generated: 2026-06-19T00:00:00Z

        - Source commit: `\(currentShortCommit)`

        Scope: validate the release MCP stdio fixture with the official MCP Inspector CLI and SoloPM's local JSON-RPC smoke checks.

        Stable baseline: `2025-11-25`

        Official stable latest: `2025-11-25`

        Official latest source: https://modelcontextprotocol.io/specification

        Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases

        Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release.

        Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning

        Official versioning assertion: current protocol version is `2025-11-25`

        Official latest checked: 2026-06-24

        Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18

        Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/

        EMA remote authorization is not a SoloPM public-alpha release target

        Official stable source: https://modelcontextprotocol.io/specification/2025-11-25

        Draft watchlist: `2026-07-28`

        Draft release-candidate source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/

        Draft changelog source: https://modelcontextprotocol.io/specification/draft/changelog

        Draft changelog assertion: changes are listed since `2025-11-25`; it is not the current release baseline.

        2026-07-28 is release-candidate; final specification is scheduled for 2026-07-28.

        Draft 2026-07-28 removes initialize/notifications/initialized and protocol-level sessions.

        Draft 2026-07-28 uses per-request `_meta` protocolVersion/clientInfo/clientCapabilities.

        Draft `server/discover` is required for draft 2026-07-28 version and capability discovery.

        Draft tools/list cache hints `ttlMs` / `cacheScope` are not implemented in SoloPM public alpha.

        Release positioning: SoloPM is not a full MCP host; this evidence covers stable client-side stdio Tools only.

        Success path: `initialize -> tools/list -> tools/call`

        ## MCP Inspector CLI tools/list
        exit: 0

        ## MCP Inspector CLI tools/call
        exit: 0

        ## SoloPM local smoke success
        malformed-json
        mismatched-id
        invalid-schema
        timeout
        exit: 0
        """
        let staleTrackedEvidence = completeRuntimeEvidence
            .replacingOccurrences(of: "- Source commit: `\(currentShortCommit)`", with: "- Source commit: `deadbee`")

        try staleTrackedEvidence.write(to: evidenceDirectory.appendingPathComponent("mcp-inspector.md"), atomically: true, encoding: .utf8)
        try readPackageFile("docs/mcp-compliance.md")
            .write(to: docsDirectory.appendingPathComponent("mcp-compliance.md"), atomically: true, encoding: .utf8)
        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        cat >"${SOLOPM_MCP_EVIDENCE_FILE:?}" <<'EOF'
        \(completeRuntimeEvidence)
        EOF
        printf "MCP compliance evidence written to %s\\n" "$SOLOPM_MCP_EVIDENCE_FILE"
        """.write(to: mcpVerifierURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, preflightURL, mcpVerifierURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("== MCP Inspector evidence =="))
        XCTAssertTrue(result.output.contains("OK: MCP compliance verifier passed"))
        XCTAssertTrue(result.output.contains("MCP Inspector evidence source commit does not match current MCP source commit: expected \(currentShortCommit)"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenMCPComplianceReviewIsIncomplete() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-incomplete-mcp-compliance-review", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let docsDirectory = fixtureRoot.appendingPathComponent("docs", isDirectory: true)
        let evidenceDirectory = docsDirectory
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let mcpVerifierURL = scriptDirectory.appendingPathComponent("verify_mcp_compliance.sh")

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
        let currentShortCommit = try currentShortGitCommit()

        let completeMCPEvidence = """
        # MCP Inspector Evidence

        Generated: 2026-06-19T00:00:00Z

        - Source commit: `\(currentShortCommit)`

        Scope: validate the release MCP stdio fixture with the official MCP Inspector CLI and SoloPM's local JSON-RPC smoke checks.

        Stable baseline: `2025-11-25`

        Official stable latest: `2025-11-25`

        Official latest source: https://modelcontextprotocol.io/specification

        Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases

        Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release.

        Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning

        Official versioning assertion: current protocol version is `2025-11-25`

        Official latest checked: 2026-06-24

        Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18

        Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/

        EMA remote authorization is not a SoloPM public-alpha release target

        Official stable source: https://modelcontextprotocol.io/specification/2025-11-25

        Draft watchlist: `2026-07-28`

        Draft release-candidate source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/

        Draft changelog source: https://modelcontextprotocol.io/specification/draft/changelog

        Draft changelog assertion: changes are listed since `2025-11-25`; it is not the current release baseline.

        2026-07-28 is release-candidate; final specification is scheduled for 2026-07-28.

        Draft 2026-07-28 removes initialize/notifications/initialized and protocol-level sessions.

        Draft 2026-07-28 uses per-request `_meta` protocolVersion/clientInfo/clientCapabilities.

        Draft `server/discover` is required for draft 2026-07-28 version and capability discovery.

        Draft tools/list cache hints `ttlMs` / `cacheScope` are not implemented in SoloPM public alpha.

        Release positioning: SoloPM is not a full MCP host; this evidence covers stable client-side stdio Tools only.

        Success path: `initialize -> tools/list -> tools/call`

        ## MCP Inspector CLI tools/list
        exit: 0

        ## MCP Inspector CLI tools/call
        exit: 0

        ## SoloPM local smoke success
        malformed-json
        mismatched-id
        invalid-schema
        timeout
        exit: 0
        """
        try completeMCPEvidence.write(to: evidenceDirectory.appendingPathComponent("mcp-inspector.md"), atomically: true, encoding: .utf8)
        try """
        # SoloPM MCP Compliance Review

        Stable baseline: `2025-11-25`

        Release positioning: SoloPM is not a full MCP host.
        """.write(to: docsDirectory.appendingPathComponent("mcp-compliance.md"), atomically: true, encoding: .utf8)

        try readPackageFile("script/release_readiness_report.sh")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf "preflight ok\\n"
        """.write(to: preflightURL, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        cat >"${SOLOPM_MCP_EVIDENCE_FILE:?}" <<'EOF'
        \(completeMCPEvidence)
        EOF
        printf "MCP compliance evidence written to %s\\n" "$SOLOPM_MCP_EVIDENCE_FILE"
        """.write(to: mcpVerifierURL, atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, preflightURL, mcpVerifierURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("== MCP Inspector evidence =="))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Last reviewed: 2026-06-24"))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Official stable latest: `2025-11-25`"))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Official latest source: https://modelcontextprotocol.io/specification"))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases"))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release."))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning"))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Official versioning assertion: current protocol version is `2025-11-25`"))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Official latest checked: 2026-06-24"))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Draft watchlist: `2026-07-28`"))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Draft changelog source: https://modelcontextprotocol.io/specification/draft/changelog"))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: Draft changelog assertion: changes are listed since `2025-11-25`; it is not the current release baseline."))
        XCTAssertTrue(result.output.contains("MCP compliance review is missing marker: will not claim draft or full-host compatibility"))
        XCTAssertTrue(result.output.contains("OK: MCP Inspector evidence covers stable baseline, draft boundary, tools/list, tools/call, and failure taxonomy"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
    }

    func testReleaseReadinessReportFailsWhenMCPComplianceVerifierFails() throws {
        let fixtureRoot = packageRoot()
            .appendingPathComponent(".build/test-release-readiness-mcp-compliance-verifier", isDirectory: true)
        let scriptDirectory = fixtureRoot.appendingPathComponent("script", isDirectory: true)
        let tasksDirectory = fixtureRoot.appendingPathComponent("tasks", isDirectory: true)
        let sourcesDirectory = fixtureRoot.appendingPathComponent("Sources", isDirectory: true)
        let evidenceDirectory = fixtureRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
        let reportURL = scriptDirectory.appendingPathComponent("release_readiness_report.sh")
        let preflightURL = scriptDirectory.appendingPathComponent("verify_release_environment.sh")
        let mcpVerifierURL = scriptDirectory.appendingPathComponent("verify_mcp_compliance.sh")

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
        #!/usr/bin/env bash
        set -euo pipefail
        echo "BLOCKER: MCP protocol schema drift" >&2
        exit 1
        """.write(to: mcpVerifierURL, atomically: true, encoding: .utf8)
        try """
        # MCP Inspector Evidence

        Generated: 2026-06-19T00:00:00Z

        Scope: validate the release MCP stdio fixture with the official MCP Inspector CLI and SoloPM's local JSON-RPC smoke checks.

        Stable baseline: `2025-11-25`

        Draft watchlist: `2026-07-28`

        Release positioning: SoloPM is not a full MCP host; this evidence covers stable client-side stdio Tools only.

        Success path: `initialize -> tools/list -> tools/call`

        ## MCP Inspector CLI tools/list

        exit: 0

        ## MCP Inspector CLI tools/call

        exit: 0

        ## SoloPM local smoke success

        malformed-json
        mismatched-id
        invalid-schema
        timeout
        """.write(to: evidenceDirectory.appendingPathComponent("mcp-inspector.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture phase is complete\n"
            .write(to: tasksDirectory.appendingPathComponent("Phase0.md"), atomically: true, encoding: .utf8)
        try "- [x] fixture readme has no template blockers\n"
            .write(to: tasksDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        for url in [reportURL, preflightURL, mcpVerifierURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let result = try runTool(["bash", reportURL.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("== MCP Inspector evidence =="))
        XCTAssertTrue(result.output.contains("BLOCKER: MCP protocol schema drift"))
        XCTAssertTrue(result.output.contains("MCP compliance verifier failed"))
        XCTAssertFalse(result.output.contains("READY: runtime, task checklist, automated proof gates, and release environment gates passed."))
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
        // todo: remove this temporary local path before release.
        """.write(to: markerFile, atomically: true, encoding: .utf8)
        try """
        let settings = [AVSampleRateKey: 44_100]
        let openCodeModelID = "opencode-model"
        let todoistProviderID = "todoist"
        let documentIntentKeywords = ["task", "todo", "implementation"]
        struct TodoistConnector {}
        private struct ArchivedProjectReadOnlyState {}
        static func buildProductionValue() {}
        """.write(to: benignFile, atomically: true, encoding: .utf8)

        let markerResult = try runTool(["rg", "-n", pattern, markerFile.path])
        XCTAssertEqual(markerResult.exitCode, 0, markerResult.output)
        XCTAssertTrue(markerResult.output.contains("LocalmockExecutor"))
        XCTAssertTrue(markerResult.output.contains("StaticPlanningProvider"))
        XCTAssertTrue(markerResult.output.contains("demoProvider"))
        XCTAssertTrue(markerResult.output.contains("Not_Implemented"))
        XCTAssertTrue(markerResult.output.contains(":memory:"))
        XCTAssertTrue(markerResult.output.contains("todo: remove"))

        let benignResult = try runTool(["rg", "-n", pattern, benignFile.path])
        XCTAssertEqual(benignResult.exitCode, 1, benignResult.output)
    }

    func testRuntimeProductSourceDoesNotTripReleaseMarkerScan() throws {
        let availability = try runTool(["rg", "--version"])
        try XCTSkipIf(availability.exitCode != 0, "rg is required to exercise the release marker pattern")

        let script = try readPackageFile("script/release_readiness_report.sh")
        guard let patternLine = script
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("MOCK_PATTERN=\"") }) else {
            return XCTFail("release readiness report must define MOCK_PATTERN")
        }
        let pattern = String(patternLine.dropFirst("MOCK_PATTERN=\"".count).dropLast())
        var runtimeSourcePaths = [
            packageRoot().appendingPathComponent("Sources/SoloPMCore").path,
            packageRoot().appendingPathComponent("Sources/SoloPMApp").path,
            packageRoot().appendingPathComponent("Sources/SoloPMCLI").path
        ]
        let optionalConnectorsPath = packageRoot()
            .appendingPathComponent("Sources/SoloPMExternalConnectors").path
        if FileManager.default.fileExists(atPath: optionalConnectorsPath) {
            runtimeSourcePaths.append(optionalConnectorsPath)
        }

        let scanResult = try runTool(["rg", "-n", pattern] + runtimeSourcePaths)
        XCTAssertEqual(scanResult.exitCode, 1, scanResult.output)
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

    private func currentShortGitCommit() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", packageRoot().path, "rev-parse", "--short", "HEAD"]
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

    private func manualReleaseEvidenceSourceCommit() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "git", "-C", packageRoot().path,
            "log", "-1", "--format=%h", "--",
            "Sources/SoloPMApp",
            "Sources/SoloPMCore",
            "Sources/SoloPMCLI",
            "Sources/SoloPMExternalConnectors",
            "Package.swift",
            "packaging/app_metadata.env"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        return output.isEmpty ? try currentShortGitCommit() : output
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

    private func writeSolidPNG(
        to url: URL,
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        trailingBytes: Int = 0
    ) throws {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = red
            pixels[offset + 1] = green
            pixels[offset + 2] = blue
            pixels[offset + 3] = 255
        }

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            XCTFail("Could not create PNG fixture context.")
            return
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            XCTFail("Could not create PNG fixture destination.")
            return
        }

        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        if trailingBytes > 0 {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(repeating: 0, count: trailingBytes))
            try handle.close()
        }
    }

    private func writeVisiblePNG(
        to url: URL,
        width: Int,
        height: Int,
        trailingBytes: Int = 0
    ) throws {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = ((y * width) + x) * 4
                let lightStripe = ((x / 24) + (y / 24)).isMultiple(of: 2)
                pixels[offset] = lightStripe ? 245 : 32
                pixels[offset + 1] = lightStripe ? 245 : 74
                pixels[offset + 2] = lightStripe ? 245 : 128
                pixels[offset + 3] = 255
            }
        }

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            XCTFail("Could not create PNG fixture context.")
            return
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            XCTFail("Could not create PNG fixture destination.")
            return
        }

        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        if trailingBytes > 0 {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(repeating: 0, count: trailingBytes))
            try handle.close()
        }
    }

    private func visualBaselineManifestFixture(artifacts: [String: String]) -> String {
        let artifactLines = artifacts
            .sorted { $0.key < $1.key }
            .map { "          \"\($0.key)\": \"\($0.value)\"" }
            .joined(separator: ",\n")
        let themeLines = artifacts.keys
            .sorted()
            .map { "\"\($0)\"" }
            .joined(separator: ", ")

        return """
        {
          "schemaVersion": 1,
          "artifactRoot": "screenshots",
          "baselineRoot": "baselines",
          "semanticTolerances": {
            "comparisonMode": "semantic",
            "allowPixelPerfectOnly": false,
            "minimumBytes": 50000,
            "minimumWidth": 640,
            "minimumHeight": 420,
            "minimumLuminanceRange": 12,
            "minimumColorBuckets": 2,
            "blackScreenMaximumLuminance": 8,
            "requiresAXFrameAudit": true
          },
          "screens": [
            {
              "id": "project-board",
              "title": "Project Board",
              "themes": [\(themeLines)],
              "viewport": {
                "width": 1200,
                "height": 720
              },
              "axFrameAudit": true,
              "artifacts": {
        \(artifactLines)
              }
            }
          ]
        }
        """
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func removeItemIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private var completeManualReleaseEvidenceNote: String {
        "Verified release-machine launch from dist/SoloPM.app, checksum SHA-256, clean DMG install, Applications install, Gatekeeper acceptance, clean environment launch, login item toggle, and Sparkle appcast metadata on macOS 15.5 arm64 signed build."
    }

    private func runScript(
        _ relativePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> (exitCode: Int32, output: String) {
        try runProcess(
            arguments: ["bash", packageRoot().appendingPathComponent(relativePath).path] + arguments,
            environment: environment
        )
    }

    private func runTool(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) throws -> (exitCode: Int32, output: String) {
        try runProcess(arguments: arguments, environment: environment)
    }

    private func runProcess(
        arguments: [String],
        environment: [String: String]
    ) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = packageRoot()
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        let outputQueue = DispatchQueue(label: "SoloPM.ReleasePipelineTests.output-drain")
        let outputGroup = DispatchGroup()
        let outputBuffer = ProcessOutputBuffer()
        outputGroup.enter()
        outputQueue.async {
            outputBuffer.replace(with: output.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForWriting.closeFile()
            outputGroup.wait()
            throw error
        }
        process.waitUntilExit()
        output.fileHandleForWriting.closeFile()
        outputGroup.wait()

        // Several release-readiness tests intentionally exercise verbose shell
        // reports. Draining while the child is running prevents the child bash
        // process from blocking on a full stdout/stderr pipe.
        return (process.terminationStatus, String(data: outputBuffer.data, encoding: .utf8) ?? "")
    }

    private final class ProcessOutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func replace(with data: Data) {
            lock.lock()
            storage = data
            lock.unlock()
        }
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
