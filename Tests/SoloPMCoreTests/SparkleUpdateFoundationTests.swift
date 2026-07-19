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

        XCTAssertTrue(script.contains("validate_sparkle_release_config.sh"))
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

    func testReleaseBuildRequiresProductionSparkleFeedConfiguration() throws {
        let missingFeed = try runScript(
            "script/validate_sparkle_release_config.sh",
            environment: [
                "SOLOPM_BUILD_CONFIGURATION": "release"
            ]
        )

        XCTAssertNotEqual(missingFeed.exitCode, 0)
        XCTAssertTrue(missingFeed.output.contains("SOLOPM_SPARKLE_FEED_URL is required for release builds"))

        let httpFeed = try runScript(
            "script/validate_sparkle_release_config.sh",
            environment: [
                "SOLOPM_BUILD_CONFIGURATION": "release",
                "SOLOPM_SPARKLE_FEED_URL": "http://updates.example.invalid/solopm/appcast.xml",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertNotEqual(httpFeed.exitCode, 0)
        XCTAssertTrue(httpFeed.output.contains("SOLOPM_SPARKLE_FEED_URL must use https for release builds"))

        let placeholderFeed = try runScript(
            "script/validate_sparkle_release_config.sh",
            environment: [
                "SOLOPM_BUILD_CONFIGURATION": "release",
                "SOLOPM_SPARKLE_FEED_URL": "https://example.com/solopm/appcast.xml",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertNotEqual(placeholderFeed.exitCode, 0)
        XCTAssertTrue(placeholderFeed.output.contains("SOLOPM_SPARKLE_FEED_URL must not use placeholder or local domains for release builds"))

        let placeholderKey = try runScript(
            "script/validate_sparkle_release_config.sh",
            environment: [
                "SOLOPM_BUILD_CONFIGURATION": "release",
                "SOLOPM_SPARKLE_FEED_URL": "https://updates.solopm.app/releases/appcast.xml",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "base64-public-key-from-generate_keys"
            ]
        )

        XCTAssertNotEqual(placeholderKey.exitCode, 0)
        XCTAssertTrue(placeholderKey.output.contains("SOLOPM_SPARKLE_PUBLIC_ED_KEY must not use a placeholder key for release builds"))

        let malformedKey = try runScript(
            "script/validate_sparkle_release_config.sh",
            environment: [
                "SOLOPM_BUILD_CONFIGURATION": "release",
                "SOLOPM_SPARKLE_FEED_URL": "https://updates.solopm.app/releases/appcast.xml",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "generated-public-ed-key-value"
            ]
        )

        XCTAssertNotEqual(malformedKey.exitCode, 0)
        XCTAssertTrue(malformedKey.output.contains("SOLOPM_SPARKLE_PUBLIC_ED_KEY must be a base64 EdDSA public key for release builds"))

        let validFeed = try runScript(
            "script/validate_sparkle_release_config.sh",
            environment: [
                "SOLOPM_BUILD_CONFIGURATION": "release",
                "SOLOPM_SPARKLE_FEED_URL": "https://updates.solopm.app/releases/appcast.xml",
                "SOLOPM_SPARKLE_PUBLIC_ED_KEY": "MCowBQYDK2VwAyEATestPublicKeyForSoloPMReleaseOnly"
            ]
        )

        XCTAssertEqual(validFeed.exitCode, 0, validFeed.output)
        XCTAssertTrue(validFeed.output.contains("Sparkle release config is valid."))
    }

    func testSampleAppcastSmokeContainsCurrentBundleVersion() throws {
        let appcast = try readPackageFile("packaging/appcast.sample.xml")
        let metadata = try readMetadata()

        XCTAssertTrue(appcast.contains("<rss"))
        XCTAssertTrue(appcast.contains("sparkle:version=\"\(metadata["CURRENT_PROJECT_VERSION"] ?? "")\""))
        XCTAssertTrue(appcast.contains("sparkle:shortVersionString=\"\(metadata["MARKETING_VERSION"] ?? "")\""))
        XCTAssertTrue(appcast.contains("url=\"https://example.com/solopm/SoloPM-\(metadata["MARKETING_VERSION"] ?? "")+\(metadata["CURRENT_PROJECT_VERSION"] ?? "").zip\""))
    }

    func testAppcastVerifierAcceptsSparkleGeneratedElementMetadata() throws {
        let appcastURL = packageRoot()
            .appendingPathComponent(".build/test-generated-element-appcast.xml")
        try FileManager.default.createDirectory(
            at: appcastURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artifactURLs = try writeReleaseZipEvidence(in: appcastURL.deletingLastPathComponent())
        try """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <title>SoloPM</title>
            <item>
              <title>0.1.0</title>
              <sparkle:version>1</sparkle:version>
              <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
              <enclosure url="https://updates.solopm.app/releases/SoloPM-0.1.0+1.zip" length="12345" type="application/octet-stream" sparkle:edSignature="release-signature-smoke-value"/>
            </item>
          </channel>
        </rss>
        """.write(to: appcastURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: appcastURL)
            for artifactURL in artifactURLs {
                try? FileManager.default.removeItem(at: artifactURL)
            }
        }

        let result = try runScript(
            "script/verify_appcast.sh",
            arguments: [appcastURL.path],
            environment: [
                "SOLOPM_REQUIRE_RELEASE_APPCAST": "1",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.solopm.app/releases"
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Appcast smoke passed"))
    }

    func testReleaseAppcastVerifierRequiresGeneratedZipArtifactEvidence() throws {
        let appcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-missing-zip-evidence.xml")
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
              <enclosure url="https://updates.solopm.app/releases/SoloPM-0.1.0+1.zip" length="12345" type="application/octet-stream" sparkle:edSignature="release-signature-smoke-value"/>
            </item>
          </channel>
        </rss>
        """.write(to: appcastURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: appcastURL) }

        let result = try runScript(
            "script/verify_appcast.sh",
            arguments: [appcastURL.path],
            environment: [
                "SOLOPM_REQUIRE_RELEASE_APPCAST": "1",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.solopm.app/releases"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release appcast artifact is missing"))
    }

    func testAppcastVerifierReportsMetadataMismatch() throws {
        let appcastURL = packageRoot()
            .appendingPathComponent(".build/test-mismatched-appcast.xml")
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
              <sparkle:version>999</sparkle:version>
              <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
              <enclosure url="https://updates.solopm.app/releases/SoloPM-0.1.0+1.zip" length="12345" type="application/octet-stream" sparkle:edSignature="release-signature-smoke-value"/>
            </item>
          </channel>
        </rss>
        """.write(to: appcastURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: appcastURL) }

        let result = try runScript(
            "script/verify_appcast.sh",
            arguments: [appcastURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("appcast missing current Sparkle build version: 1"))
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
            .replacingOccurrences(of: "https://example.com/solopm/", with: "https://updates.solopm.app/solopm/")
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

    func testReleaseAppcastVerifierRequiresHTTPSURL() throws {
        let releaseLikeAppcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-http-url.xml")
        try FileManager.default.createDirectory(
            at: releaseLikeAppcastURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try readPackageFile("packaging/appcast.sample.xml")
            .replacingOccurrences(of: "https://example.com/solopm/", with: "http://updates.example.invalid/solopm/")
            .replacingOccurrences(of: "local-smoke-signature-placeholder", with: "release-signature-smoke-value")
            .replacingOccurrences(of: #" length="0""#, with: #" length="12345""#)
            .write(to: releaseLikeAppcastURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: releaseLikeAppcastURL) }

        let result = try runScript(
            "script/verify_appcast.sh",
            arguments: [releaseLikeAppcastURL.path],
            environment: ["SOLOPM_REQUIRE_RELEASE_APPCAST": "1"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release appcast enclosure URL must use https"))

        let mixedSchemeAppcast = try readPackageFile("packaging/appcast.sample.xml")
            .replacingOccurrences(of: "https://example.com/solopm/", with: "https://updates.solopm.app/solopm/")
            .replacingOccurrences(of: "local-smoke-signature-placeholder", with: "release-signature-smoke-value")
            .replacingOccurrences(of: #" length="0""#, with: #" length="12345""#)
            .replacingOccurrences(
                of: "    </item>",
                with: """
                      <enclosure
                        url="http://updates.solopm.app/solopm/legacy.zip"
                        length="12345"
                        type="application/octet-stream" />
                    </item>
                """
            )
        try mixedSchemeAppcast.write(to: releaseLikeAppcastURL, atomically: true, encoding: .utf8)

        let mixedSchemeResult = try runScript(
            "script/verify_appcast.sh",
            arguments: [releaseLikeAppcastURL.path],
            environment: ["SOLOPM_REQUIRE_RELEASE_APPCAST": "1"]
        )

        XCTAssertNotEqual(mixedSchemeResult.exitCode, 0)
        XCTAssertTrue(mixedSchemeResult.output.contains("release appcast enclosure URL must use https"))
    }

    func testReleaseAppcastVerifierRequiresConfiguredDownloadPrefix() throws {
        let releaseLikeAppcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-download-prefix.xml")
        try FileManager.default.createDirectory(
            at: releaseLikeAppcastURL.deletingLastPathComponent(),
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
              <enclosure url="https://cdn.solopm.app/releases/SoloPM-0.1.0+1.zip" length="12345" type="application/octet-stream" sparkle:edSignature="release-signature-smoke-value"/>
            </item>
          </channel>
        </rss>
        """.write(to: releaseLikeAppcastURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: releaseLikeAppcastURL) }

        let result = try runScript(
            "script/verify_appcast.sh",
            arguments: [releaseLikeAppcastURL.path],
            environment: [
                "SOLOPM_REQUIRE_RELEASE_APPCAST": "1",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.solopm.app/releases"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("release appcast enclosure URL does not match configured SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX"))
    }

    func testReleaseAppcastVerifierRejectsPlaceholderOrLocalDomains() throws {
        let releaseLikeAppcastURL = packageRoot()
            .appendingPathComponent(".build/test-release-appcast-placeholder-url.xml")
        try FileManager.default.createDirectory(
            at: releaseLikeAppcastURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let releaseLikeAppcast = try readPackageFile("packaging/appcast.sample.xml")
            .replacingOccurrences(of: "local-smoke-signature-placeholder", with: "release-signature-smoke-value")
            .replacingOccurrences(of: #" length="0""#, with: #" length="12345""#)
        try releaseLikeAppcast
            .replacingOccurrences(of: "https://example.com/solopm/", with: "https://updates.example.invalid/solopm/")
            .write(to: releaseLikeAppcastURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: releaseLikeAppcastURL) }

        let reservedDomainResult = try runScript(
            "script/verify_appcast.sh",
            arguments: [releaseLikeAppcastURL.path],
            environment: ["SOLOPM_REQUIRE_RELEASE_APPCAST": "1"]
        )

        XCTAssertNotEqual(reservedDomainResult.exitCode, 0)
        XCTAssertTrue(reservedDomainResult.output.contains("release appcast enclosure URL must not use placeholder or local domains"))

        try releaseLikeAppcast
            .replacingOccurrences(of: "https://example.com/solopm/", with: "https://localhost/solopm/")
            .write(to: releaseLikeAppcastURL, atomically: true, encoding: .utf8)

        let localDomainResult = try runScript(
            "script/verify_appcast.sh",
            arguments: [releaseLikeAppcastURL.path],
            environment: ["SOLOPM_REQUIRE_RELEASE_APPCAST": "1"]
        )

        XCTAssertNotEqual(localDomainResult.exitCode, 0)
        XCTAssertTrue(localDomainResult.output.contains("release appcast enclosure URL must not use placeholder or local domains"))
    }

    func testReleaseAppcastGeneratorRequiresProductionHTTPSPrefix() throws {
        let missingPrefix = try runScript(
            "script/generate_appcast.sh",
            environment: [
                "SOLOPM_REQUIRE_RELEASE_APPCAST": "1",
                "SOLOPM_REQUIRE_SPARKLE_TOOLS": "0"
            ]
        )

        XCTAssertNotEqual(missingPrefix.exitCode, 0)
        XCTAssertTrue(missingPrefix.output.contains("SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX is required for release appcast"))

        let httpPrefix = try runScript(
            "script/generate_appcast.sh",
            environment: [
                "SOLOPM_REQUIRE_RELEASE_APPCAST": "1",
                "SOLOPM_REQUIRE_SPARKLE_TOOLS": "0",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "http://updates.example.invalid/solopm"
            ]
        )

        XCTAssertNotEqual(httpPrefix.exitCode, 0)
        XCTAssertTrue(httpPrefix.output.contains("SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX must use https for release appcast"))

        let examplePrefix = try runScript(
            "script/generate_appcast.sh",
            environment: [
                "SOLOPM_REQUIRE_RELEASE_APPCAST": "1",
                "SOLOPM_REQUIRE_SPARKLE_TOOLS": "0",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://example.com/solopm"
            ]
        )

        XCTAssertNotEqual(examplePrefix.exitCode, 0)
        XCTAssertTrue(examplePrefix.output.contains("SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX must not use placeholder or local domains for release appcast"))

        let reservedPrefix = try runScript(
            "script/generate_appcast.sh",
            environment: [
                "SOLOPM_REQUIRE_RELEASE_APPCAST": "1",
                "SOLOPM_REQUIRE_SPARKLE_TOOLS": "0",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.example.invalid/solopm"
            ]
        )

        XCTAssertNotEqual(reservedPrefix.exitCode, 0)
        XCTAssertTrue(reservedPrefix.output.contains("SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX must not use placeholder or local domains for release appcast"))

        let validPrefixMissingTool = try runScript(
            "script/generate_appcast.sh",
            environment: [
                "SOLOPM_REQUIRE_RELEASE_APPCAST": "1",
                "SOLOPM_REQUIRE_SPARKLE_TOOLS": "0",
                "SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX": "https://updates.solopm.app/releases"
            ]
        )

        XCTAssertNotEqual(validPrefixMissingTool.exitCode, 0)
        XCTAssertTrue(validPrefixMissingTool.output.contains("SOLOPM_REQUIRE_SPARKLE_TOOLS must be 1 for release appcast generation"))
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

    private func writeReleaseZipEvidence(in directoryURL: URL) throws -> [URL] {
        let artifactURL = directoryURL.appendingPathComponent("SoloPM-0.1.0+1.zip")
        let checksumURL = directoryURL.appendingPathComponent("SoloPM-0.1.0+1.zip.sha256")
        let packageEvidenceURL = directoryURL.appendingPathComponent("SoloPM-0.1.0+1.zip.package-evidence.json")
        let artifactPath = artifactURL.path
        let artifactSha = "554f3f497395d59fc12389d51b5fb7208248425e0dbad975db3f08132f58dbed"

        try "zip content".write(to: artifactURL, atomically: true, encoding: .utf8)
        let artifactBytes = try XCTUnwrap(
            (FileManager.default.attributesOfItem(atPath: artifactURL.path)[.size] as? NSNumber)?.intValue
        )
        try "\(artifactSha)  \(artifactPath)\n"
            .write(to: checksumURL, atomically: true, encoding: .utf8)
        try """
        {
          "package": {
            "artifactPath": "\(artifactPath)",
            "format": "zip",
            "createdAt": "2026-06-18T00:00:00Z",
            "signedPackageRequired": true,
            "notarizedPackageRequired": true,
            "appBundleBytes": 1,
            "appBinaryBytes": 1,
            "artifactBytes": \(artifactBytes),
            "stripMode": "local-symbols-removed",
            "sparklePruneMode": "development-assets-removed"
          },
          "source": {
            "gitCommit": "test-fixture"
          }
        }
        """.write(to: packageEvidenceURL, atomically: true, encoding: .utf8)

        return [artifactURL, checksumURL, packageEvidenceURL]
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
