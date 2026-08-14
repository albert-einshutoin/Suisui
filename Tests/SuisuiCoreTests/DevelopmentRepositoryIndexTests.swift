import Foundation
import XCTest
@testable import SuisuiCore

final class DevelopmentRepositoryIndexTests: XCTestCase {
    func testRefreshIndexesTrackedAndUntrackedTextWhileSkippingSensitiveBinaryAndSymlinkFiles() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("tracked needle", to: "Sources/Tracked.swift")
        try fixture.write("untracked needle", to: "Notes.md")
        try fixture.write("SECRET=value", to: ".env")
        try fixture.write("ignored needle", to: "ignored.md")
        try fixture.write(Data([0, 1, 2]), to: "binary.txt")
        try fixture.runGit(["add", "Sources/Tracked.swift", ".gitignore"])
        try fixture.write("ignored.md\n", to: ".gitignore")
        try fixture.runGit(["add", ".gitignore"])
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appendingPathComponent("linked.md"),
            withDestinationURL: fixture.url.appendingPathComponent("Notes.md")
        )

        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let found = try await index.search(query: "needle", workspace: workspace(fixture))
        XCTAssertEqual(Set(found.map(\.sourcePath)), ["Notes.md", "Sources/Tracked.swift"])
    }

    func testRefreshDoesNotNormalizeManifestPathIntoIgnoredSibling() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("ignored marker", to: "Notes.md")
        try fixture.write("tracked marker", to: "Notes.md ")
        try fixture.write("Notes.md\n", to: ".gitignore")
        try fixture.runGit(["add", ".gitignore"])
        try fixture.runGit(["add", "Notes.md "])

        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let results = try await index.search(query: "ignored", workspace: workspace(fixture))
        XCTAssertTrue(results.isEmpty)
    }

    func testRefreshFailsClosedForFinalSymlinksAndCredentialFiles() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("safe marker", to: "Notes.md")
        try fixture.write("credential marker", to: ".docker/config.json")
        try fixture.write("credential marker", to: "Nested/.docker/config.json")
        try fixture.write("credential marker", to: "auth.json")
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appendingPathComponent("Race.md"),
            withDestinationURL: fixture.url.appendingPathComponent("Notes.md")
        )

        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let safeResults = try await index.search(query: "safe", workspace: workspace(fixture))
        let credentialResults = try await index.search(query: "credential", workspace: workspace(fixture))
        XCTAssertEqual(safeResults.map(\.sourcePath), ["Notes.md"])
        XCTAssertTrue(credentialResults.isEmpty)
    }

    func testRefreshDoesNotPersistDockerOrCredentialJSON() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("{\"auths\": {\"registry.invalid\": {\"auth\": \"encoded-placeholder\"}}}", to: "Settings.json")
        try fixture.write("{\"client_secret\": \"placeholder\", \"private_key\": \"placeholder\"}", to: "Service.json")

        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let results = try await index.search(query: "registry", workspace: workspace(fixture))
        XCTAssertTrue(results.isEmpty)
        let serviceResults = try await index.search(query: "client", workspace: workspace(fixture))
        XCTAssertTrue(serviceResults.isEmpty)
    }

    func testRefreshDoesNotPersistKubernetesKeyDataOrPEM() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("client-key-data: QUJDREVGR0hJSktMTU4=", to: "Kube.yml")
        try fixture.write("  -----BEGIN PRIVATE KEY-----\n  placeholder\n  -----END PRIVATE KEY-----", to: "KeyMaterial.txt")
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let kubernetesResults = try await index.search(query: "QUJDREVGR0hJSktMTU4", workspace: workspace(fixture))
        let pemResults = try await index.search(query: "PRIVATE", workspace: workspace(fixture))
        XCTAssertTrue(kubernetesResults.isEmpty)
        XCTAssertTrue(pemResults.isEmpty)
    }

    func testRefreshIndexesTypedSwiftTokenButExcludesCredentialAssignment() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("func approve(token: ApprovalToken) {}\nprivate let clientSecret: String\nfunc use(authToken: Token) {}\nlet apiKey = value\nlet password: Password\nlet token = value", to: "Sources/Approval.swift")
        try fixture.write(
            """
            public struct OAuthTokenResponse: Decodable {}
            enum OAuthError {
            case .tokenExpiredWithoutRefresh:
            }
            struct Connector {
                let accessTokenKey: SecretKey
                init(
                    accessTokenKey: SecretKey
                ) {
                    self.accessTokenKey = accessTokenKey
                    let accessTokenKey = Self.accessTokenKey(connectorID)
                    accessToken = try store.accessToken(for: credential)
                    accessToken = nil
                    let normalizedToken = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                func send(response: OAuthTokenResponse) {
                    request(accessToken: response.accessToken)
                    request(
                        accessToken: response.accessToken,
                        refreshToken: response.refreshToken ?? refreshToken,
                        accessToken: try tokenProvider.bearerToken(),
                        hasRefreshToken: refreshToken?.isEmpty == false
                    )
                }
            }
            """,
            to: "Sources/SaaSConnectors.swift"
        )
        let credentials = [
            "Settings.env.swift": "API_KEY=long-secret-value",
            "TokenQuoted.swift": "token=\"long-secret-value\"",
            "TokenBare.swift": "token=long-secret-value",
            "APIKeyBare.swift": "apiKey=long-secret-value",
            "TokenExport.swift": "export token=long-secret-value",
            "TokenYAML.yml": "token: long-secret-value",
            "TokenTyped.swift": "token: String = \"long-secret-value\"",
            "TokenMixed.swift": "func f(token: ApprovalToken, password: long-secret-value) {}\n{ token: ApprovalToken, password: long-secret-value }",
            "TokenUppercase.yml": "TOKEN: ABCDEFGHIJK1234",
            "ClientSecret.env.swift": "CLIENT_SECRET=compound-secret-value",
            "PrivateKey.env.swift": "PRIVATE_KEY=compound-secret-value",
            "AWSSecret.env.swift": "AWS_SECRET_ACCESS_KEY=compound-secret-value",
            "DatabasePassword.env.swift": "DATABASE_PASSWORD=compound-secret-value",
            "AccessToken.env.swift": "access_token=compound-secret-value",
            "ClientSecretSource.swift": "let clientSecret = \"compound-secret-value\"",
            "ClientSecretSnakeSource.swift": "let client_secret = \"compound-secret-value\"",
            "PrivateKeySource.swift": "let privateKey = \"compound-secret-value\"",
            "GoogleClientSecret.swift": "let googleClientSecret = \"long-secret-value\"",
            "GitHubAccessToken.swift": "let githubAccessToken = \"long-secret-value\"",
            "OAuthRefreshToken.swift": "let oauthRefreshToken = \"long-secret-value\"",
            "AWSSecretAccessKey.swift": "let awsSecretAccessKey = \"long-secret-value\"",
            "OAuth2Token.yml": "oauth2_token: long-secret-value",
            "CommentOpen.swift": "// fake(\ntoken: ABCDEFGHIJK1234",
            "CommentInsideCall.swift": "request(\n// token: ABCDEFGHIJK1234\n)",
            "BlockCommentCall.swift": "request(\n/*\naccessToken: ABCDEFGHIJK1234\n*/\n)",
            "BlockCommentAssignment.swift": "/*\nlet googleClientSecret = ABCDEFGHIJK1234\n*/",
            "MultilineStringCall.swift": "request(\n\"\"\"\naccessToken: ABCDEFGHIJK1234\n\"\"\"\n)",
            "MultilineStringAssignment.swift": "let template = \"\"\"\nlet googleClientSecret = ABCDEFGHIJK1234\n\"\"\"",
            "TokenStandalone.swift": "TOKEN: ABCDEFGHIJK1234",
            "TokenSource.txt": "let token = textonlymarker",
            "TokenFunction.yml": "func f(token: NonSwiftMarker)",
        ]
        for (path, contents) in credentials {
            try fixture.write(contents, to: path)
        }
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let sourceResults = try await index.search(query: "approve", workspace: workspace(fixture))
        let compoundSourceResults = try await index.search(query: "authToken", workspace: workspace(fixture))
        let responseResults = try await index.search(query: "OAuthTokenResponse", workspace: workspace(fixture))
        let caseResults = try await index.search(query: "tokenExpiredWithoutRefresh", workspace: workspace(fixture))
        let memberResults = try await index.search(query: "accessTokenKey", workspace: workspace(fixture))
        let callLabelResults = try await index.search(query: "response", workspace: workspace(fixture))
        let localAssignmentResults = try await index.search(query: "connectorID", workspace: workspace(fixture))
        let optionalExpressionResults = try await index.search(query: "hasRefreshToken", workspace: workspace(fixture))
        let enumShorthandResults = try await index.search(query: "normalizedToken", workspace: workspace(fixture))
        let credentialResults = try await index.search(query: "long", workspace: workspace(fixture))
        let uppercaseCredentialResults = try await index.search(query: "ABCDEFGHIJK1234", workspace: workspace(fixture))
        let compoundCredentialResults = try await index.search(query: "compound", workspace: workspace(fixture))
        let textCredentialResults = try await index.search(query: "textonlymarker", workspace: workspace(fixture))
        let nonSwiftFunctionResults = try await index.search(query: "NonSwiftMarker", workspace: workspace(fixture))
        XCTAssertEqual(sourceResults.map(\.sourcePath), ["Sources/Approval.swift"])
        XCTAssertEqual(compoundSourceResults.map(\.sourcePath), ["Sources/Approval.swift"])
        XCTAssertEqual(responseResults.map(\.sourcePath), ["Sources/SaaSConnectors.swift"])
        XCTAssertEqual(caseResults.map(\.sourcePath), ["Sources/SaaSConnectors.swift"])
        XCTAssertEqual(memberResults.map(\.sourcePath), ["Sources/SaaSConnectors.swift"])
        XCTAssertEqual(callLabelResults.map(\.sourcePath), ["Sources/SaaSConnectors.swift"])
        XCTAssertEqual(localAssignmentResults.map(\.sourcePath), ["Sources/SaaSConnectors.swift"])
        XCTAssertEqual(optionalExpressionResults.map(\.sourcePath), ["Sources/SaaSConnectors.swift"])
        XCTAssertEqual(enumShorthandResults.map(\.sourcePath), ["Sources/SaaSConnectors.swift"])
        XCTAssertTrue(credentialResults.isEmpty)
        XCTAssertTrue(uppercaseCredentialResults.isEmpty)
        XCTAssertTrue(compoundCredentialResults.isEmpty)
        XCTAssertTrue(textCredentialResults.isEmpty)
        XCTAssertTrue(nonSwiftFunctionResults.isEmpty)
    }

    func testRepositoryDescriptorWalkRejectsIntermediateAndFinalSymlinks() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("suisui-index-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try "outside".write(to: outside.appendingPathComponent("Outside.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appendingPathComponent("Docs"),
            withDestinationURL: outside
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appendingPathComponent("Race.md"),
            withDestinationURL: outside.appendingPathComponent("Outside.md")
        )
        let rootLink = fixture.url.deletingLastPathComponent().appendingPathComponent("suisui-index-root-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: fixture.url)
        defer { try? FileManager.default.removeItem(at: rootLink) }

        XCTAssertThrowsError(try DevelopmentRepositoryIndex.boundedFileData(root: rootLink, relativePath: "Race.md")) { error in
            XCTAssertEqual(error as? DevelopmentRepositoryIndexError, .fileReadUnavailable)
        }
        XCTAssertThrowsError(try DevelopmentRepositoryIndex.boundedFileData(root: fixture.url, relativePath: "Docs/Outside.md")) { error in
            XCTAssertEqual(error as? DevelopmentRepositoryIndexError, .fileReadUnavailable)
        }
        XCTAssertThrowsError(try DevelopmentRepositoryIndex.boundedFileData(root: fixture.url, relativePath: "Race.md")) { error in
            XCTAssertEqual(error as? DevelopmentRepositoryFileError, .symlinkNotAllowed)
        }
    }

    func testRefreshDoesNotRunRepositoryConfiguredFsmonitor() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("safe marker", to: "Notes.md")
        let markerURL = fixture.url.appendingPathComponent("fsmonitor-ran")
        let hookURL = fixture.url.appendingPathComponent("fsmonitor.sh")
        try "#!/bin/sh\ntouch '\(markerURL.path)'\n".write(to: hookURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hookURL.path)
        try fixture.runGit(["config", "core.fsmonitor", hookURL.path])

        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testManifestTimeoutTerminatesHungProcessWithinBound() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let helper = fixture.url.appendingPathComponent("hang.sh")
        try "#!/bin/sh\ntrap '' TERM\nwhile :; do :; done\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

        let startedAt = Date()
        XCTAssertThrowsError(try GitManifestReader.paths(at: fixture.url, timeout: 0.01, executableURL: helper))
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
    }

    func testRefreshReplacesSnapshotAndKeepsPreviousGenerationAfterGitFailure() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("first value", to: "Notes.md")
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        try fixture.write("second value", to: "Notes.md")
        try fixture.write("new file", to: "Added.md")
        try await index.refresh(workspace: workspace(fixture))

        let oldResults = try await index.search(query: "first", workspace: workspace(fixture))
        let updatedResults = try await index.search(query: "second", workspace: workspace(fixture))
        let addedResults = try await index.search(query: "new", workspace: workspace(fixture))
        XCTAssertTrue(oldResults.isEmpty)
        XCTAssertEqual(updatedResults.map(\.sourcePath), ["Notes.md"])
        XCTAssertEqual(addedResults.map(\.sourcePath), ["Added.md"])

        let missingRepository = FileManager.default.temporaryDirectory.appendingPathComponent("suisui-index-not-a-repository-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: missingRepository, withIntermediateDirectories: true)
        try "gitdir: /definitely-missing-suisui-index-git-directory\n".write(
            to: missingRepository.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: missingRepository) }
        await XCTAssertThrowsErrorAsync(try await index.refresh(workspace: CodebaseMemoryWorkspace(rootPath: missingRepository.path, selectedRelativePaths: [])))
        let preservedResults = try await index.search(query: "second", workspace: workspace(fixture))
        XCTAssertEqual(preservedResults.map(\.sourcePath), ["Notes.md"])
    }

    func testRefreshKeepsPreviousGenerationWhenManifestFileCannotBeRead() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("previous marker", to: "Notes.md")
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let fileURL = fixture.url.appendingPathComponent("Notes.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path) }
        await XCTAssertThrowsErrorAsync(try await index.refresh(workspace: workspace(fixture)))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)

        let preservedResults = try await index.search(query: "previous", workspace: workspace(fixture))
        XCTAssertEqual(preservedResults.map(\.sourcePath), ["Notes.md"])
    }

    func testRefreshRejectsSymlinkWorkspaceAndPreservesPreviousGeneration() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("preserved marker", to: "Notes.md")
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let backing = fixture.url.deletingLastPathComponent().appendingPathComponent("suisui-index-backing-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: fixture.url, to: backing)
        try FileManager.default.createSymbolicLink(at: fixture.url, withDestinationURL: backing)
        await XCTAssertThrowsErrorAsync(try await index.refresh(workspace: workspace(fixture)))
        try FileManager.default.removeItem(at: fixture.url)
        try FileManager.default.moveItem(at: backing, to: fixture.url)

        let preservedResults = try await index.search(query: "preserved", workspace: workspace(fixture))
        XCTAssertEqual(preservedResults.map(\.sourcePath), ["Notes.md"])
    }

    func testSearchIsolatesWorkspaceAndSelectedPathsAndFallsBackForCJK() async throws {
        let first = try RepositoryFixture()
        let second = try RepositoryFixture()
        defer {
            first.remove()
            second.remove()
        }
        try first.write("設計", to: "Docs/Japanese.md")
        try first.write("filename only", to: "Docs/設計ノート.md")
        try first.write("half-width filename only", to: "Docs/ｶﾀｶﾅ.md")
        try first.write("shared secret-free phrase", to: "Sources/Only.swift")
        try second.write("shared secret-free phrase", to: "Other.md")
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(first))
        try await index.refresh(workspace: workspace(second))
        try await index.refresh(workspace: workspace(first))

        let cjkResults = try await index.search(query: "設計", workspace: workspace(first), topK: 2)
        let halfWidthResults = try await index.search(query: "ｶﾀｶﾅ", workspace: workspace(first))
        let selectedResults = try await index.search(
            query: "shared",
            workspace: CodebaseMemoryWorkspace(rootPath: first.url.path, selectedRelativePaths: ["Sources/Only.swift"])
        )
        let directoryResults = try await index.search(
            query: "shared",
            workspace: CodebaseMemoryWorkspace(rootPath: first.url.path, selectedRelativePaths: ["Sources"])
        )
        let isolatedResults = try await index.search(query: "shared", workspace: workspace(second))
        XCTAssertEqual(Set(cjkResults.map(\.sourcePath)), ["Docs/Japanese.md", "Docs/設計ノート.md"])
        XCTAssertEqual(halfWidthResults.map(\.sourcePath), ["Docs/ｶﾀｶﾅ.md"])
        XCTAssertEqual(selectedResults.map(\.sourcePath), ["Sources/Only.swift"])
        XCTAssertEqual(directoryResults.map(\.sourcePath), ["Sources/Only.swift"])
        XCTAssertEqual(isolatedResults.map(\.sourcePath), ["Other.md"])
    }

    func testSearchTokenizesNaturalLanguageAndReturnsMatchContextPreview() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write(
            String(repeating: "prefix ", count: 100) + "sqlite stores project search state; a natural interface supports language queries.",
            to: "Docs/Search.md"
        )
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let naturalLanguage = try await index.search(query: "sqlite natural language", workspace: workspace(fixture))
        let partialLanguage = try await index.search(query: "sqlite absent-term", workspace: workspace(fixture))
        let operatorSyntax = try await index.search(query: "\" OR *", workspace: workspace(fixture))

        XCTAssertEqual(naturalLanguage.map(\.sourcePath), ["Docs/Search.md"])
        XCTAssertEqual(partialLanguage.map(\.sourcePath), ["Docs/Search.md"])
        XCTAssertTrue(naturalLanguage[0].bodyPreview.contains("sqlite"))
        XCTAssertFalse(naturalLanguage[0].bodyPreview.hasPrefix("prefix"))
        XCTAssertTrue(operatorSyntax.isEmpty)
    }

    func testSearchRejectsPunctuationOnlyQuery() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let index = try migratedIndex()

        await XCTAssertThrowsErrorAsync(try await index.search(query: "***", workspace: workspace(fixture)))
    }

    private func migratedIndex() throws -> DevelopmentRepositoryIndex {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return DevelopmentRepositoryIndex(connection: connection)
    }

    private func workspace(_ fixture: RepositoryFixture) -> CodebaseMemoryWorkspace {
        CodebaseMemoryWorkspace(rootPath: fixture.url.path, selectedRelativePaths: [])
    }
}

private final class RepositoryFixture {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("suisui-repository-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init"])
        try runGit(["config", "user.email", "index@example.invalid"])
        try runGit(["config", "user.name", "Repository Index Test"])
        try write("", to: ".gitignore")
    }

    func write(_ contents: String, to relativePath: String) throws {
        try write(Data(contents.utf8), to: relativePath)
    }

    func write(_ data: Data, to relativePath: String) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error.", file: file, line: line)
    } catch {}
}
