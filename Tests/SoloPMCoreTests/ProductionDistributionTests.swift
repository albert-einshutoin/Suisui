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
        XCTAssertTrue(verifier.contains("SOLOPM_VERIFY_REMOTE_SPARKLE"))
        XCTAssertTrue(verifier.contains("curl"))
        XCTAssertTrue(verifier.contains("published Sparkle artifact SHA-256 does not match"))
        XCTAssertTrue(environment.contains("SOLOPM_VERIFY_REMOTE_SPARKLE=\"$ONLINE_PREFLIGHT\""))
        XCTAssertTrue(sparkleExample.contains("SOLOPM_SPARKLE_SIGN_UPDATE="))
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
