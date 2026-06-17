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

    func testDistributionPackageScriptBuildsDmgWithApplicationsLinkAndChecksums() throws {
        let script = try readPackageFile("script/package_release.sh")

        XCTAssertTrue(script.contains("hdiutil create"))
        XCTAssertTrue(script.contains("ln -s /Applications"))
        XCTAssertTrue(script.contains("shasum -a 256"))
        XCTAssertTrue(script.contains("SOLOPM_PACKAGE_FORMAT"))
        XCTAssertTrue(script.contains("ditto -c -k --keepParent"))
        XCTAssertTrue(script.contains("SOLOPM_REQUIRE_SIGNED_PACKAGE"))
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

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
