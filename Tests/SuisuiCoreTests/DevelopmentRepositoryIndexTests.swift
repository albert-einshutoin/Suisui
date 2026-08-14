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
        try fixture.write("public struct ServiceAccessToken: Codable {}", to: "Sources/ServiceAccessToken.swift")
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
            "PascalCredential.swift": "let ServiceAccessToken = \"long-secret-value\"",
            "PascalCredential.json": "{\"ServiceAccessToken\":\"long-secret-value\"}",
            "TypealiasCredential.swift": "typealias ServiceAccessToken: Codable",
            "BacktickedCredential.swift": "let `accessToken` = \"long-secret-value\"",
            "CommentedCredential.swift": "let accessToken /* nested /* note */ note */ = \"long-secret-value\"",
            "LineCommentCredential.c": "const char *accessToken // note\n= \"long-secret-value\";",
            "SQLLineCommentCredential.sql": "UPDATE config SET token -- note\n= 'long-secret-value';",
            "PythonLineCommentCredential.py": "(token # note\n := \"long-secret-value\")",
            "PythonContinuationCredential.py": "token \\\n= \"long-secret-value\"",
            "MultilineTypedCredential.swift": "struct C { let accessToken: String\n = \"long-secret-value\" }",
            "MultilineAssignmentCredential.swift": "let accessToken = safe\n + \"long-secret-value\"",
            "MultilineCallCredential.swift": "request(\naccessToken: safe\n + \"long-secret-value\"\n)",
            "MultilineCustomOperatorCredential.swift": "infix operator <>\nfunc <>(lhs: String, rhs: String) -> String { lhs + rhs }\nlet safe = \"x\"\nlet accessToken = safe\n <> \"long-secret-value\"",
            "MultilineCastCredential.swift": "let safe: Any = \"x\"\nlet accessToken = safe\n as! String + \"long-secret-value\"",
            "MultilineCastTabCredential.swift": "let safe: String = \"x\"\nlet accessToken = safe\n as\tString + \"long-secret-value\"",
            "MultilineCastNewlineCredential.swift": "let safe: String = \"x\"\nlet accessToken = safe\n as\n String + \"long-secret-value\"",
            "MultilineIsCredential.swift": "let safe: Any = \"x\"\nlet accessToken = safe\n is\n String ? \"long-secret-value\" : \"\"",
            "ConditionalCompilationCredential.swift": "import Foundation\nlet safe = \"x\"\nlet accessToken = safe\n#if DEBUG\n.appending(\"long-secret-value\")\n#endif",
            "CArrayCredential.c": "char accessToken[32] = \"long-secret-value\";",
            "GoTypedCredential.go": "var accessToken []byte = []byte(\"long-secret-value\")",
            "TypeScriptOptionalCredential.ts": "class C { accessToken?: string = \"long-secret-value\" }",
            "TypeScriptDefiniteCredential.ts": "class C { accessToken!: string = \"long-secret-value\" }",
            "CppBraceCredential.cpp": "std::string accessToken{\"long-secret-value\"};",
            "CppParenCredential.cpp": "std::string refreshToken(\"long-secret-value\");",
            "SingleQuotedCredential.yml": "'token': long-secret-value",
            "CommentOpen.swift": "// fake(\ntoken: ABCDEFGHIJK1234",
            "CommentInsideCall.swift": "request(\n// token: ABCDEFGHIJK1234\n)",
            "BlockCommentCall.swift": "request(\n/*\naccessToken: ABCDEFGHIJK1234\n*/\n)",
            "BlockCommentAssignment.swift": "/*\nlet googleClientSecret = ABCDEFGHIJK1234\n*/",
            "MultilineStringCall.swift": "request(\n\"\"\"\naccessToken: ABCDEFGHIJK1234\n\"\"\"\n)",
            "MultilineStringAssignment.swift": "let template = \"\"\"\nlet googleClientSecret = ABCDEFGHIJK1234\n\"\"\"",
            "RawStringAssignment.swift": "let template = #\"let googleClientSecret = ABCDEFGHIJK1234\"#",
            "RawMultilineAssignment.swift": "#\"\"\"\nliteral \"\"\"\nlet googleClientSecret = ABCDEFGHIJK1234\n\"\"\"#",
            "RawMultilineCall.swift": "request(\n#\"\"\"\naccessToken: ABCDEFGHIJK1234\n\"\"\"#\n)",
            "RawEscapedDelimiter.swift": "#\"\"\"\n\\#\"\"\"#\nlet googleClientSecret = ABCDEFGHIJK1234\n\"\"\"#",
            "RawRegexAssignment.swift": "let pattern = #/\nliteral \\/\nlet googleClientSecret = ABCDEFGHIJK1234\n/#",
            "RawRegexDoubleHashAssignment.swift": "##/\nliteral /#\nlet googleClientSecret = ABCDEFGHIJK1234\n/##",
            "RawRegexCall.swift": "request(\n#/\naccessToken: ABCDEFGHIJK1234\n/#\n)",
            "RawRegexEscapedDelimiter.swift": "let pattern = #/\n\\/#\nlet googleClientSecret = ABCDEFGHIJK1234\n/#",
            "RawRegexDoubleHashEscapedDelimiter.swift": "let pattern = ##/\n\\/##\nlet googleClientSecret = ABCDEFGHIJK1234\n/##",
            "RawRegexEscapedDelimiterCall.swift": "request(\n##/\n\\/##\naccessToken: ABCDEFGHIJK1234\n/##\n)",
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
        let nominalTypeResults = try await index.search(query: "ServiceAccessToken", workspace: workspace(fixture))
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
        XCTAssertEqual(nominalTypeResults.map(\.sourcePath), ["Sources/ServiceAccessToken.swift"])
        XCTAssertTrue(credentialResults.isEmpty)
        XCTAssertTrue(uppercaseCredentialResults.isEmpty)
        XCTAssertTrue(compoundCredentialResults.isEmpty)
        XCTAssertTrue(textCredentialResults.isEmpty)
        XCTAssertTrue(nonSwiftFunctionResults.isEmpty)
    }

    func testRefreshIndexesDenseSafeSwiftCredentialNames() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write(String(repeating: "let accessToken = denseSafeMarker\n", count: 6_000), to: "Sources/Dense.swift")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let results = try await index.search(query: "denseSafeMarker", workspace: workspace(fixture))
        XCTAssertEqual(results.map(\.sourcePath), ["Sources/Dense.swift"])
    }

    func testRefreshIndexesHarmlessCredentialWords() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("OAuth token lifecycle harmlessmarker", to: "Docs/OAuth.md")
        try fixture.write("let message = \"refresh token harmlessswiftmarker\"", to: "Sources/Message.swift")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let markdown = try await index.search(query: "harmlessmarker", workspace: workspace(fixture))
        let swift = try await index.search(query: "harmlessswiftmarker", workspace: workspace(fixture))
        XCTAssertEqual(markdown.map(\.sourcePath), ["Docs/OAuth.md"])
        XCTAssertEqual(swift.map(\.sourcePath), ["Sources/Message.swift"])
    }

    func testRefreshExcludesJSONCredentialsWithEscapedKeys() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write(#"{"to\u006ben":"escapedtokenmarker"}"#, to: "Config/EscapedToken.json")
        try fixture.write(#"{"items":[{"client_\u0073ecret":"escapedsecretmarker"}]}"#, to: "Config/EscapedSecret.json")
        try fixture.write(#"{"auths":{"registry":{"au\u0074h":"escapedauthmarker"}}}"#, to: "Config/EscapedDocker.json")
        try fixture.write(#"{"to\u006ben":"malformedjsonmarker""#, to: "Config/MalformedEscapedToken.json")
        try fixture.write(#""to\u006ben" = "escapedtomlmarker""#, to: "Config/EscapedToken.toml")
        try fixture.write(#""client_\u0073ecret" = "escapedtomlsecretmarker""#, to: "Config/EscapedSecret.toml")
        try fixture.write(#"{"message":"OAuth token lifecycle harmlessjsonmarker","items":[{"label":"normal"}]}"#, to: "Config/Harmless.json")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let escapedToken = try await index.search(query: "escapedtokenmarker", workspace: workspace(fixture))
        let escapedSecret = try await index.search(query: "escapedsecretmarker", workspace: workspace(fixture))
        let escapedAuth = try await index.search(query: "escapedauthmarker", workspace: workspace(fixture))
        let malformed = try await index.search(query: "malformedjsonmarker", workspace: workspace(fixture))
        let escapedTOML = try await index.search(query: "escapedtomlmarker", workspace: workspace(fixture))
        let escapedTOMLSecret = try await index.search(query: "escapedtomlsecretmarker", workspace: workspace(fixture))
        let harmless = try await index.search(query: "harmlessjsonmarker", workspace: workspace(fixture))
        XCTAssertTrue(escapedToken.isEmpty)
        XCTAssertTrue(escapedSecret.isEmpty)
        XCTAssertTrue(escapedAuth.isEmpty)
        XCTAssertTrue(malformed.isEmpty)
        XCTAssertTrue(escapedTOML.isEmpty)
        XCTAssertTrue(escapedTOMLSecret.isEmpty)
        XCTAssertEqual(harmless.map(\.sourcePath), ["Config/Harmless.json"])
    }

    func testRefreshExcludesEscapedJavaScriptCredentialIdentifiers() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write(#"const to\u006ben = "escapedjstokenmarker";"#, to: "Scripts/EscapedToken.js")
        try fixture.write(#"const access\u0054oken = "escapedtsaccessmarker";"#, to: "Scripts/EscapedAccess.ts")
        try fixture.write(#"const \u{74}oken = "escapedjsxmarker";"#, to: "Scripts/EscapedBrace.jsx")
        try fixture.write(#"const pattern = /"/; const config = {"to\u006ben":"escapedpropertymarker"};"#, to: "Scripts/EscapedProperty.js")
        try fixture.write(#"const $access\u0054oken = "escapeddollarmarker";"#, to: "Scripts/EscapedDollar.js")
        try fixture.write(#"class Credential { String to\u006ben = "escapedjavamarker"; }"#, to: "Sources/EscapedCredential.java")
        try fixture.write(#"const pattern = /"/; const config = {"to\x6ben":"escapedhexmarker"};"#, to: "Scripts/EscapedHex.js")
        try fixture.write(#"const config = {["to\x6ben"]:"escapedcomputedmarker"};"#, to: "Scripts/EscapedComputed.js")
        try fixture.write(#"const message = "harmlessjsmarker";"#, to: "Scripts/Harmless.js")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let escapedToken = try await index.search(query: "escapedjstokenmarker", workspace: workspace(fixture))
        let escapedAccess = try await index.search(query: "escapedtsaccessmarker", workspace: workspace(fixture))
        let escapedBrace = try await index.search(query: "escapedjsxmarker", workspace: workspace(fixture))
        let escapedProperty = try await index.search(query: "escapedpropertymarker", workspace: workspace(fixture))
        let escapedDollar = try await index.search(query: "escapeddollarmarker", workspace: workspace(fixture))
        let escapedJava = try await index.search(query: "escapedjavamarker", workspace: workspace(fixture))
        let escapedHex = try await index.search(query: "escapedhexmarker", workspace: workspace(fixture))
        let escapedComputed = try await index.search(query: "escapedcomputedmarker", workspace: workspace(fixture))
        let harmless = try await index.search(query: "harmlessjsmarker", workspace: workspace(fixture))
        XCTAssertTrue(escapedToken.isEmpty)
        XCTAssertTrue(escapedAccess.isEmpty)
        XCTAssertTrue(escapedBrace.isEmpty)
        XCTAssertTrue(escapedProperty.isEmpty)
        XCTAssertTrue(escapedDollar.isEmpty)
        XCTAssertTrue(escapedJava.isEmpty)
        XCTAssertTrue(escapedHex.isEmpty)
        XCTAssertTrue(escapedComputed.isEmpty)
        XCTAssertEqual(harmless.map(\.sourcePath), ["Scripts/Harmless.js"])
    }

    func testRefreshHandlesCRCommentsAndSwiftTriviaAfterSafeAssignments() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("const char *accessToken // note\r= \"crcredentialmarker\";", to: "Sources/CRCredential.c")
        try fixture.write(
            """
            let accessToken = safe
            // documentation
            let commenttriviamarker = true
            let refreshToken = safe
            @MainActor
            func marked() {}
            let attributetriviamarker = true
            let clientSecret = safe
            #if DEBUG
            let directivetriviamarker = true
            #endif
            """,
            to: "Sources/Trivia.swift"
        )
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let credential = try await index.search(query: "crcredentialmarker", workspace: workspace(fixture))
        let comment = try await index.search(query: "commenttriviamarker", workspace: workspace(fixture))
        let attribute = try await index.search(query: "attributetriviamarker", workspace: workspace(fixture))
        let directive = try await index.search(query: "directivetriviamarker", workspace: workspace(fixture))
        XCTAssertTrue(credential.isEmpty)
        XCTAssertEqual(comment.map(\.sourcePath), ["Sources/Trivia.swift"])
        XCTAssertEqual(attribute.map(\.sourcePath), ["Sources/Trivia.swift"])
        XCTAssertEqual(directive.map(\.sourcePath), ["Sources/Trivia.swift"])
    }

    func testRefreshIndexesDenseCredentialWordsInsideLineComment() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let contents = "token // " + String(repeating: "token ", count: 30_000) + "densecommentmarker"
        try fixture.write(contents, to: "Docs/DenseComment.md")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let results = try await index.search(query: "densecommentmarker", workspace: workspace(fixture))
        XCTAssertEqual(results.map(\.sourcePath), ["Docs/DenseComment.md"])
    }

    func testSearchDoesNotExposePriorRepositoryAfterSamePathReplacement() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("previousrepositorymarker", to: "Notes.md")
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let replacement = fixture.url.deletingLastPathComponent().appendingPathComponent("suisui-index-replacement-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: fixture.url, to: replacement)
        defer {
            try? FileManager.default.removeItem(at: fixture.url)
            try? FileManager.default.moveItem(at: replacement, to: fixture.url)
        }
        try FileManager.default.createDirectory(at: fixture.url, withIntermediateDirectories: true)
        try "replacement marker".write(to: fixture.url.appendingPathComponent("Notes.md"), atomically: true, encoding: .utf8)

        let stale = try await index.search(query: "previousrepositorymarker", workspace: workspace(fixture))
        XCTAssertTrue(stale.isEmpty)
    }

    func testSuccessfulRefreshRetiresPriorIdentityAtSameWorkspacePath() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("prioridentitymarker", to: "Notes.md")
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let index = DevelopmentRepositoryIndex(connection: connection)
        try await index.refresh(workspace: workspace(fixture))

        let replacement = fixture.url.deletingLastPathComponent().appendingPathComponent("suisui-index-cleanup-replacement-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: fixture.url, to: replacement)
        defer {
            try? FileManager.default.removeItem(at: fixture.url)
            try? FileManager.default.moveItem(at: replacement, to: fixture.url)
        }
        try FileManager.default.createDirectory(at: fixture.url, withIntermediateDirectories: true)
        try "replacementidentitymarker".write(to: fixture.url.appendingPathComponent("Notes.md"), atomically: true, encoding: .utf8)

        await XCTAssertThrowsErrorAsync(try await index.refresh(workspace: workspace(fixture)))
        let retained = try connection.queryRows("SELECT contents FROM codebase_index_files;")
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(try retained[0].string("contents"), "prioridentitymarker")

        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init"]
        git.currentDirectoryURL = fixture.url
        try git.run()
        git.waitUntilExit()
        XCTAssertEqual(git.terminationStatus, 0)
        try await index.refresh(workspace: workspace(fixture))

        let rows = try connection.queryRows("SELECT contents FROM codebase_index_files;")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows[0].string("contents"), "replacementidentitymarker")
    }

    func testWorkspaceRootIdentityRejectsSamePathReplacement() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        var original = stat()
        XCTAssertEqual(Darwin.lstat(fixture.url.path, &original), 0)
        let replacement = fixture.url.deletingLastPathComponent().appendingPathComponent("suisui-index-identity-replacement-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: fixture.url, to: replacement)
        defer {
            try? FileManager.default.removeItem(at: fixture.url)
            try? FileManager.default.moveItem(at: replacement, to: fixture.url)
        }
        try FileManager.default.createDirectory(at: fixture.url, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try DevelopmentRepositoryIndex.verifyWorkspaceRootIdentity(
                fixture.url,
                device: original.st_dev,
                inode: original.st_ino
            )
        ) { error in
            XCTAssertEqual(error as? DevelopmentRepositoryIndexError, .fileReadUnavailable)
        }
    }

    func testRefreshSkipsUnavailableManifestEntriesAndGitlinks() async throws {
        let fixture = try RepositoryFixture()
        let submodule = try RepositoryFixture()
        defer {
            fixture.remove()
            submodule.remove()
        }
        try submodule.write("gitlink content", to: "Inner.md")
        try submodule.runGit(["add", "Inner.md"])
        try submodule.runGit(["commit", "-m", "Initial submodule"])
        try fixture.write("stable manifest marker", to: "Notes.md")
        try fixture.write("weirdpathmarker", to: "Notes/\tstrange.md")
        try fixture.write("retiredonlymarker", to: "Deleted.md")
        try fixture.write("skiponlymarker", to: "Skipped.md")
        try fixture.runGit(["add", "Deleted.md", "Skipped.md"])
        try FileManager.default.removeItem(at: fixture.url.appendingPathComponent("Deleted.md"))
        try fixture.runGit(["update-index", "--skip-worktree", "Skipped.md"])
        try fixture.runGit(["-c", "protocol.file.allow=always", "submodule", "add", submodule.url.path, "Vendor/Inner"])
        let unavailable = Set(try GitManifestReader.entries(at: fixture.url).filter(\.isUnavailable).map(\.path))
        XCTAssertTrue(unavailable.isSuperset(of: ["Deleted.md", "Skipped.md", "Vendor/Inner"]))
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let stable = try await index.search(query: "stable manifest marker", workspace: workspace(fixture))
        let weirdPath = try await index.search(query: "weirdpathmarker", workspace: workspace(fixture))
        let deleted = try await index.search(query: "retiredonlymarker", workspace: workspace(fixture))
        let skipped = try await index.search(query: "skiponlymarker", workspace: workspace(fixture))
        XCTAssertEqual(stable.map(\.sourcePath), ["Notes.md"])
        XCTAssertEqual(weirdPath.map(\.sourcePath), ["Notes/\tstrange.md"])
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertTrue(skipped.isEmpty)
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

    func testRefreshFailsClosedWhenManifestFileBecomesFIFO() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("previous marker", to: "Notes.md")
        try fixture.write("placeholder", to: "Pipe.md")
        try fixture.runGit(["add", "Pipe.md"])
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let pipeURL = fixture.url.appendingPathComponent("Pipe.md")
        try FileManager.default.removeItem(at: pipeURL)
        XCTAssertEqual(Darwin.mkfifo(pipeURL.path, 0o600), 0)
        let startedAt = Date()
        await XCTAssertThrowsErrorAsync(try await index.refresh(workspace: workspace(fixture)))
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)

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
