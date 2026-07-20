import Foundation
import XCTest

final class ProductionDistributionTests: XCTestCase {
    func testInitialReleasePinsAndVerifiesAppleSiliconArchitecture() throws {
        let metadata = try readRepositoryFile("packaging/app_metadata.env")
        let verifier = try readRepositoryFile("script/verify_release_architecture.sh")
        let distribution = try readRepositoryFile("docs/release/distribution.md")

        XCTAssertTrue(metadata.contains("SUPPORTED_ARCHITECTURES=arm64"))
        XCTAssertTrue(verifier.contains("lipo -archs"))
        XCTAssertTrue(verifier.contains("SUPPORTED_ARCHITECTURES"))
        XCTAssertTrue(verifier.contains("release app architecture mismatch"))
        XCTAssertTrue(distribution.contains("Apple Silicon"))
        XCTAssertTrue(distribution.contains("arm64"))
    }

    func testReleaseAppcastVerifiesCryptographicSignatureAndPublishedBytes() throws {
        let verifier = try readRepositoryFile("script/verify_appcast.sh")
        let environment = try readRepositoryFile("script/verify_release_environment.sh")
        let sparkleExample = try readRepositoryFile("packaging/sparkle.env.example")

        XCTAssertTrue(verifier.contains("sign_update"))
        XCTAssertTrue(verifier.contains("--verify"))
        XCTAssertTrue(verifier.contains("SUISUI_VERIFY_REMOTE_SPARKLE"))
        XCTAssertTrue(verifier.contains("curl"))
        XCTAssertTrue(verifier.contains("published Sparkle artifact SHA-256 does not match"))
        XCTAssertTrue(verifier.contains("$remote_enclosure_url\" --output \"$remote_artifact"))
        XCTAssertTrue(verifier.contains("published Sparkle feed enclosure URL does not match"))
        XCTAssertTrue(verifier.contains("published Sparkle feed edSignature does not match"))
        XCTAssertTrue(verifier.contains("--verify \"$remote_artifact\" \"$remote_enclosure_signature\""))
        XCTAssertTrue(environment.contains("SUISUI_VERIFY_REMOTE_SPARKLE=\"$ONLINE_PREFLIGHT\""))
        XCTAssertTrue(sparkleExample.contains("SUISUI_SPARKLE_SIGN_UPDATE="))

        let sourceRange = try XCTUnwrap(verifier.range(of: "source \"$SPARKLE_ENV_FILE\""))
        let toolRange = try XCTUnwrap(verifier.range(of: "SPARKLE_SIGN_UPDATE=\"${SUISUI_SPARKLE_SIGN_UPDATE:-}\""))
        XCTAssertLessThan(sourceRange.lowerBound, toolRange.lowerBound)
    }

    func testDMGNotarizationPersistsStructuredAuditableEvidence() throws {
        let notarizer = try readRepositoryFile("script/notarize_release_dmg.sh")
        let verifier = try readRepositoryFile("script/verify_dmg_notarization_evidence.sh")
        let releaseEnvironment = try readRepositoryFile("script/verify_release_environment.sh")

        XCTAssertTrue(notarizer.contains(".notarization.json"))
        XCTAssertTrue(notarizer.contains("\"submissionID\""))
        XCTAssertTrue(notarizer.contains("\"artifactSha256\""))
        XCTAssertTrue(notarizer.contains("\"staplerValidated\": true"))
        XCTAssertTrue(notarizer.contains("\"gatekeeperAccepted\": true"))
        XCTAssertTrue(verifier.contains("notarization.submissionID"))
        XCTAssertTrue(verifier.contains("notarization.status"))
        XCTAssertTrue(verifier.contains("notarization.artifactSha256"))
        XCTAssertTrue(releaseEnvironment.contains("verify_dmg_notarization_evidence.sh"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let fileURL = repositoryRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
