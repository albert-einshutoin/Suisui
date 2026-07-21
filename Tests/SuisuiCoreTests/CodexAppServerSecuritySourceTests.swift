import Foundation
import XCTest

final class CodexAppServerSecuritySourceTests: XCTestCase {
    func testProductionSessionCodeCannotReadOrInjectCodexCredentials() throws {
        let root = repositoryRoot()
        let relativePaths = [
            "Sources/SuisuiCore/Planning/CodexAppServerAccountClient.swift",
            "Sources/SuisuiCore/Planning/CodexAppServerProvider.swift",
            "Sources/SuisuiCore/Planning/CodexLocalRuntimeProvider.swift",
            "Sources/SuisuiApp/Views/CodexAccountSettingsView.swift"
        ]
        let source = try relativePaths.map { path in
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }.joined(separator: "\n")

        // These session owners may ask Codex to authenticate, but credential
        // location and token injection must remain impossible from this layer.
        XCTAssertFalse(source.contains("homeDirectoryForCurrentUser"))
        XCTAssertFalse(source.contains("chatgptAuthTokens"))
        XCTAssertFalse(source.contains("accessToken"))
        XCTAssertFalse(source.contains("refreshToken"))
        XCTAssertFalse(source.contains("Data(contentsOf:"))
        XCTAssertFalse(source.contains("FileHandle(forReadingFrom:"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
