import Foundation
import XCTest

final class SparkleUpdateFoundationTests: XCTestCase {
    func testPackageDeclaresSparkleDependencyForAppTarget() throws {
        let manifest = try readPackageFile("Package.swift")

        XCTAssertTrue(manifest.contains("https://github.com/sparkle-project/Sparkle"))
        XCTAssertTrue(manifest.contains(".product(name: \"Sparkle\", package: \"Sparkle\")"))
    }

    func testBundleBuilderSupportsSparkleInfoPlistKeysAndEmbeddedFrameworks() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("SPARKLE_FEED_URL"))
        XCTAssertTrue(script.contains("SPARKLE_PUBLIC_ED_KEY"))
        XCTAssertTrue(script.contains("SUFeedURL"))
        XCTAssertTrue(script.contains("SUPublicEDKey"))
        XCTAssertTrue(script.contains("APP_CONTENTS/Resources"))
        XCTAssertTrue(script.contains("APP_CONTENTS/Frameworks"))
        XCTAssertTrue(script.contains("*.framework"))
        XCTAssertTrue(script.contains("install_name_tool -add_rpath"))
        XCTAssertTrue(script.contains("@executable_path/../Frameworks"))
        XCTAssertTrue(script.contains("codesign --force --deep --sign -"))
    }

    func testAppcastScriptUsesSparkleGenerateAppcastAndKeepsKeysOutOfRepo() throws {
        let script = try readPackageFile("script/generate_appcast.sh")
        let example = try readPackageFile("packaging/sparkle.env.example")
        let docs = try readPackageFile("docs/release/sparkle.md")

        XCTAssertTrue(script.contains("generate_appcast"))
        XCTAssertTrue(script.contains("SOLOPM_SPARKLE_BIN_DIR"))
        XCTAssertTrue(script.contains("SOLOPM_REQUIRE_SPARKLE_TOOLS"))
        XCTAssertTrue(example.contains("SOLOPM_SPARKLE_PUBLIC_ED_KEY"))
        XCTAssertFalse(example.contains("PRIVATE_KEY"))
        XCTAssertFalse(example.contains("PASSWORD="))
        XCTAssertTrue(docs.contains("generate_keys"))
        XCTAssertTrue(docs.contains("Keychain"))
        XCTAssertTrue(docs.contains("local appcast"))
    }

    func testSampleAppcastSmokeContainsCurrentBundleVersion() throws {
        let appcast = try readPackageFile("packaging/appcast.sample.xml")
        let metadata = try readMetadata()

        XCTAssertTrue(appcast.contains("<rss"))
        XCTAssertTrue(appcast.contains("sparkle:version=\"\(metadata["CURRENT_PROJECT_VERSION"] ?? "")\""))
        XCTAssertTrue(appcast.contains("sparkle:shortVersionString=\"\(metadata["MARKETING_VERSION"] ?? "")\""))
        XCTAssertTrue(appcast.contains("url=\"https://example.com/solopm/SoloPM-\(metadata["MARKETING_VERSION"] ?? "")+\(metadata["CURRENT_PROJECT_VERSION"] ?? "").zip\""))
    }

    func testReleaseAppcastVerifierRejectsSamplePlaceholderSignature() throws {
        let releaseLikeAppcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-placeholder.xml")
        try FileManager.default.createDirectory(
            at: releaseLikeAppcastURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try readPackageFile("packaging/appcast.sample.xml")
            .write(to: releaseLikeAppcastURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: releaseLikeAppcastURL) }

        let result = try runScript(
            "script/verify_appcast.sh",
            arguments: [releaseLikeAppcastURL.path],
            environment: ["SOLOPM_REQUIRE_RELEASE_APPCAST": "1"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release appcast still contains local smoke placeholder signature"))
    }

    func testReleaseAppcastVerifierRejectsZeroLengthOrMissingSignature() throws {
        let releaseLikeAppcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-zero-length.xml")
        try FileManager.default.createDirectory(
            at: releaseLikeAppcastURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let zeroLengthAppcast = try readPackageFile("packaging/appcast.sample.xml")
            .replacingOccurrences(of: "https://example.com/solopm/", with: "https://updates.example.invalid/solopm/")
            .replacingOccurrences(of: "local-smoke-signature-placeholder", with: "release-signature-smoke-value")
        try zeroLengthAppcast.write(to: releaseLikeAppcastURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: releaseLikeAppcastURL) }

        let zeroLengthResult = try runScript(
            "script/verify_appcast.sh",
            arguments: [releaseLikeAppcastURL.path],
            environment: ["SOLOPM_REQUIRE_RELEASE_APPCAST": "1"]
        )

        XCTAssertNotEqual(zeroLengthResult.exitCode, 0)
        XCTAssertTrue(zeroLengthResult.output.contains("release appcast has zero-length enclosure"))

        try zeroLengthAppcast
            .replacingOccurrences(of: #" sparkle:edSignature="release-signature-smoke-value""#, with: "")
            .replacingOccurrences(of: #" length="0""#, with: #" length="12345""#)
            .write(to: releaseLikeAppcastURL, atomically: true, encoding: .utf8)

        let missingSignatureResult = try runScript(
            "script/verify_appcast.sh",
            arguments: [releaseLikeAppcastURL.path],
            environment: ["SOLOPM_REQUIRE_RELEASE_APPCAST": "1"]
        )

        XCTAssertNotEqual(missingSignatureResult.exitCode, 0)
        XCTAssertTrue(missingSignatureResult.output.contains("release appcast is missing Sparkle edSignature"))
    }

    func testLocalSparkleEnvironmentFileIsIgnored() throws {
        let gitignore = try readPackageFile(".gitignore")
        let ignoredPaths = gitignore
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        XCTAssertTrue(ignoredPaths.contains("/packaging/sparkle.env"))
    }

    private func readMetadata() throws -> [String: String] {
        let contents = try readPackageFile("packaging/app_metadata.env")
        return contents
            .split(separator: "\n")
            .reduce(into: [String: String]()) { result, line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let separator = trimmed.firstIndex(of: "=") else {
                    return
                }
                let key = String(trimmed[..<separator])
                let value = String(trimmed[trimmed.index(after: separator)...]).trimmingMetadataQuotes()
                result[key] = value
            }
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

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}

private extension String {
    func trimmingMetadataQuotes() -> String {
        if hasPrefix("\""), hasSuffix("\""), count >= 2 {
            return String(dropFirst().dropLast())
        }
        return self
    }
}
