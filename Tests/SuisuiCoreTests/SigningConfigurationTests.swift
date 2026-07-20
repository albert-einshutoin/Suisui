import Foundation
import XCTest

final class SigningConfigurationTests: XCTestCase {
    func testDeveloperIDSigningScriptRequiresExplicitIdentityAndHardenedRuntime() throws {
        let script = try readPackageFile("script/sign_app.sh")

        XCTAssertTrue(script.contains("SUISUI_SIGNING_IDENTITY"))
        XCTAssertTrue(script.contains("security find-identity -p codesigning -v"))
        XCTAssertTrue(script.contains("--timestamp"))
        XCTAssertTrue(script.contains("--options"))
        XCTAssertTrue(script.contains("runtime"))
        XCTAssertTrue(script.contains("Developer ID Application:"))
        XCTAssertTrue(script.contains("SUISUI_SIGNING_IDENTITY must be a Developer ID Application identity"))
        XCTAssertTrue(script.contains("SUISUI_BUILD_CONFIGURATION=release"))
        XCTAssertTrue(script.contains("codesign --verify --strict --deep"))
        XCTAssertFalse(script.contains("APPLE_ID_PASSWORD"))
        XCTAssertFalse(script.contains("notarytool store-credentials"))
    }

    func testSigningExampleKeepsSecretMaterialOutOfRepository() throws {
        let example = try readPackageFile("packaging/signing.env.example")

        XCTAssertTrue(example.contains("SUISUI_SIGNING_IDENTITY"))
        XCTAssertTrue(example.contains("Developer ID Application:"))
        XCTAssertFalse(example.contains("PRIVATE_KEY"))
        XCTAssertFalse(example.contains("PASSWORD="))
        XCTAssertFalse(example.contains("TOKEN="))
    }

    func testLocalSigningEnvironmentFileIsIgnored() throws {
        let gitignore = try readPackageFile(".gitignore")
        let ignoredPaths = gitignore
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        XCTAssertTrue(ignoredPaths.contains("/packaging/signing.env"))
    }

    func testReleaseSigningDocsDeclareLocalSigningAndValidationPath() throws {
        let docs = try readPackageFile("docs/release/signing.md")

        XCTAssertTrue(docs.contains("local release machine"))
        XCTAssertTrue(docs.contains("Keychain"))
        XCTAssertTrue(docs.contains("repo に入れない"))
        XCTAssertTrue(docs.contains("codesign --verify"))
        XCTAssertTrue(docs.contains("spctl -a -vv"))
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
