import Foundation
import XCTest
@testable import SuisuiCore

final class DevelopmentRepositoryIndexTests: XCTestCase {
    #if os(iOS) || targetEnvironment(macCatalyst)
    func testGitManifestReaderFailsClosedWhenSubprocessesAreUnsupported() {
        XCTAssertThrowsError(try GitManifestReader.paths(at: URL(fileURLWithPath: "/workspace"))) { error in
            XCTAssertEqual(error as? DevelopmentRepositoryIndexError, .gitManifestUnsupported)
        }
    }
    #endif

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

    func testRefreshDoesNotPersistStandaloneProviderCredentials() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let slackCredential = "xoxb-" + "slackindexmarker123"
        let googleCredential = "AIza" + "googleindexmarker1234567890"
        let gitLabCredential = "glpat-" + "gitlabindexmarker123"
        let stripeCredential = "sk_live_" + "stripeindexmarker123"
        try fixture.write("Leaked sample: \(slackCredential)", to: "Slack.md")
        try fixture.write("Copied value: \(googleCredential)", to: "Notes.md")
        try fixture.write("Leaked sample: \(gitLabCredential)", to: "README.md")
        try fixture.write("Captured output: \(stripeCredential)", to: "BuildLog.txt")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let slack = try await index.search(query: "slackindexmarker123", workspace: workspace(fixture))
        let google = try await index.search(query: "googleindexmarker1234567890", workspace: workspace(fixture))
        let gitLab = try await index.search(query: "gitlabindexmarker123", workspace: workspace(fixture))
        let stripe = try await index.search(query: "stripeindexmarker123", workspace: workspace(fixture))
        XCTAssertTrue(slack.isEmpty)
        XCTAssertTrue(google.isEmpty)
        XCTAssertTrue(gitLab.isEmpty)
        XCTAssertTrue(stripe.isEmpty)
    }

    func testRefreshDoesNotPersistGenericCredentialKeys() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("credentials = \"tomlcredentialmarker\"", to: "Settings.toml")
        try fixture.write("credential: yamlcredentialmarker", to: "Settings.yaml")
        try fixture.write("{\"credentials\":\"jsoncredentialmarker\"}", to: "Settings.json")
        try fixture.write("let credentials: CredentialStore\nlet credentialSourceMarker = credentials", to: "Sources/Credentials.swift")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let toml = try await index.search(query: "tomlcredentialmarker", workspace: workspace(fixture))
        let yaml = try await index.search(query: "yamlcredentialmarker", workspace: workspace(fixture))
        let json = try await index.search(query: "jsoncredentialmarker", workspace: workspace(fixture))
        let swift = try await index.search(query: "credentialSourceMarker", workspace: workspace(fixture))
        XCTAssertTrue(toml.isEmpty)
        XCTAssertTrue(yaml.isEmpty)
        XCTAssertTrue(json.isEmpty)
        XCTAssertEqual(swift.map(\.sourcePath), ["Sources/Credentials.swift"])
    }

    func testRefreshDoesNotPersistConnectionURIsWithEmptyUsername() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("redis://:redisindexmarker@cache.example/0", to: "Config/Redis.txt")
        try fixture.write("amqp://:amqpindexmarker@queue.example/vhost", to: "Config/AMQP.txt")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let redis = try await index.search(query: "redisindexmarker", workspace: workspace(fixture))
        let amqp = try await index.search(query: "amqpindexmarker", workspace: workspace(fixture))
        XCTAssertTrue(redis.isEmpty)
        XCTAssertTrue(amqp.isEmpty)
    }

    func testRefreshDoesNotPersistKubernetesKeyDataOrPEM() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let encodedKeyData = "QUJDREVG" + "R0hJSktMTU4="
        let quotedYAMLKeyData = "quotedkubesentinel"
        let flowYAMLKeyData = "flowkubesentinel"
        let extensionlessFlowKeyData = "extensionlesskubesentinel"
        let aliasYAMLKeyData = "aliaskubesentinel"
        let camelCaseKeyData = "camelkubesentinel"
        let jsonKeyData = "jsonkubesentinel"
        try fixture.write("client-key-data: \(encodedKeyData)", to: "Kube.yml")
        try fixture.write("\"client-key-data\": \"\(quotedYAMLKeyData)\"", to: "QuotedKube.yml")
        try fixture.write("users: [{name: prod, user: {\"client_key_data\": \"\(flowYAMLKeyData)\"}}]", to: "FlowKube.yaml")
        try fixture.write("key_name: &k client-key-data\nusers: [{user: {*k: \(aliasYAMLKeyData)}}]", to: "AliasKube.yaml")
        try fixture.write("users: [{name: prod, user: {\"client-key-data\": \"\(extensionlessFlowKeyData)\"}}]", to: "Dockerfile")
        try fixture.write("clientKeyData: \(camelCaseKeyData)", to: "CamelKube.yaml")
        try fixture.write("{\"client-key-data\":\"\(jsonKeyData)\"}", to: "Kube.json")
        try fixture.write("  -----BEGIN PRIVATE KEY-----\n  placeholder\n  -----END PRIVATE KEY-----", to: "KeyMaterial.txt")
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let kubernetesResults = try await index.search(query: encodedKeyData, workspace: workspace(fixture))
        let quotedYAMLResults = try await index.search(query: quotedYAMLKeyData, workspace: workspace(fixture))
        let flowYAMLResults = try await index.search(query: flowYAMLKeyData, workspace: workspace(fixture))
        let aliasYAMLResults = try await index.search(query: aliasYAMLKeyData, workspace: workspace(fixture))
        let extensionlessFlowResults = try await index.search(query: extensionlessFlowKeyData, workspace: workspace(fixture))
        let camelCaseResults = try await index.search(query: camelCaseKeyData, workspace: workspace(fixture))
        let jsonResults = try await index.search(query: jsonKeyData, workspace: workspace(fixture))
        let pemResults = try await index.search(query: "PRIVATE", workspace: workspace(fixture))
        XCTAssertTrue(kubernetesResults.isEmpty)
        XCTAssertTrue(quotedYAMLResults.isEmpty)
        XCTAssertTrue(flowYAMLResults.isEmpty)
        XCTAssertTrue(aliasYAMLResults.isEmpty)
        XCTAssertTrue(extensionlessFlowResults.isEmpty)
        XCTAssertTrue(camelCaseResults.isEmpty)
        XCTAssertTrue(jsonResults.isEmpty)
        XCTAssertTrue(pemResults.isEmpty)
    }

    func testRefreshDoesNotPersistAuthorizationHeadersOrJWTs() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("Authorization: Bearer bearerindexmarker", to: "Config/Authorization.txt")
        try fixture.write("Authorization: Basic basicindexmarker", to: "Config/Basic.txt")
        try fixture.write("Authorization: Bearer abc", to: "Config/ShortBearer.txt")
        try fixture.write("Authorization: Basic dTpw", to: "Config/ShortBasic.txt")
        try fixture.write("Authorization: \"Bearer quotedbearerindexmarker\"", to: "Config/QuotedBearer.txt")
        try fixture.write("{\"Authorization\":\"Basic quotedbasicindexmarker\"}", to: "Config/QuotedBasic.json")
        try fixture.write("Authorization = \"Bearer equalsbearerindexmarker\"", to: "Config/Authorization.toml")
        try fixture.write("AUTHORIZATION=Basic equalsbasicindexmarker", to: "Config/Authorization.env")
        try fixture.write("Authorization = \"Token customtokenindexmarker\"", to: "Config/CustomAuthorization.toml")
        try fixture.write("Authorization: AWS4-HMAC-SHA256 Credential=awscredentialindexmarker", to: "Config/AWSAuthorization.txt")
        try fixture.write("Authorization: Digest digestindexmarker", to: "Config/DigestAuthorization.txt")
        try fixture.write("Authorization: Negotiate negotiateindexmarker", to: "Config/NegotiateAuthorization.txt")
        try fixture.write("AuthorizationPolicy = harmlessauthorizationmarker", to: "Config/AuthorizationPolicy.txt")
        try fixture.write("session eyJheadersentinel.payloadsentinel.signaturesentinel", to: "Config/Token.txt")
        try fixture.write("session eyJhbGciOiJub25lIn0.e30.", to: "Config/UnsignedToken.txt")
        try fixture.write("session eyJhbGciOiJub25lIn0.e30.trailinghyphen-", to: "Config/TrailingHyphenToken.txt")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let bearer = try await index.search(query: "bearerindexmarker", workspace: workspace(fixture))
        let basic = try await index.search(query: "basicindexmarker", workspace: workspace(fixture))
        let jwt = try await index.search(query: "signaturesentinel", workspace: workspace(fixture))
        let shortBearer = try await index.search(query: "abc", workspace: workspace(fixture))
        let shortBasic = try await index.search(query: "dTpw", workspace: workspace(fixture))
        let quotedBearer = try await index.search(query: "quotedbearerindexmarker", workspace: workspace(fixture))
        let quotedBasic = try await index.search(query: "quotedbasicindexmarker", workspace: workspace(fixture))
        let equalsBearer = try await index.search(query: "equalsbearerindexmarker", workspace: workspace(fixture))
        let equalsBasic = try await index.search(query: "equalsbasicindexmarker", workspace: workspace(fixture))
        let customToken = try await index.search(query: "customtokenindexmarker", workspace: workspace(fixture))
        let awsCredential = try await index.search(query: "awscredentialindexmarker", workspace: workspace(fixture))
        let digest = try await index.search(query: "digestindexmarker", workspace: workspace(fixture))
        let negotiate = try await index.search(query: "negotiateindexmarker", workspace: workspace(fixture))
        let harmlessAuthorization = try await index.search(query: "harmlessauthorizationmarker", workspace: workspace(fixture))
        let unsignedJWT = try await index.search(query: "e30", workspace: workspace(fixture))
        let trailingHyphenJWT = try await index.search(query: "trailinghyphen", workspace: workspace(fixture))
        XCTAssertTrue(bearer.isEmpty)
        XCTAssertTrue(basic.isEmpty)
        XCTAssertTrue(jwt.isEmpty)
        XCTAssertTrue(shortBearer.isEmpty)
        XCTAssertTrue(shortBasic.isEmpty)
        XCTAssertTrue(quotedBearer.isEmpty)
        XCTAssertTrue(quotedBasic.isEmpty)
        XCTAssertTrue(equalsBearer.isEmpty)
        XCTAssertTrue(equalsBasic.isEmpty)
        XCTAssertTrue(customToken.isEmpty)
        XCTAssertTrue(awsCredential.isEmpty)
        XCTAssertTrue(digest.isEmpty)
        XCTAssertTrue(negotiate.isEmpty)
        XCTAssertEqual(harmlessAuthorization.map(\.sourcePath), ["Config/AuthorizationPolicy.txt"])
        XCTAssertTrue(unsignedJWT.isEmpty)
        XCTAssertTrue(trailingHyphenJWT.isEmpty)
    }

    func testRefreshIndexesTypedSwiftTokenButExcludesCredentialAssignment() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("func approve(token: ApprovalToken) {}\nprivate let clientSecret: String\nfunc use(authToken: Token) {}\nlet apiKey = value\nlet password: Password\nlet token = value", to: "Sources/Approval.swift")
        try fixture.write("public struct ServiceAccessToken: Codable {}", to: "Sources/ServiceAccessToken.swift")
        try fixture.write(
            "final class KeychainOAuthCredentialStore: OAuthCredentialStore, @unchecked Sendable {}\nfinal class OAuthCredentialStoreBox: @unchecked Sendable {}\nlet uncheckedNominalMarker = KeychainOAuthCredentialStore()\nlet uncheckedOnlyMarker = OAuthCredentialStoreBox()",
            to: "Sources/KeychainOAuthCredentialStore.swift"
        )
        try fixture.write(
            "AppleSpeechReadinessSnapshot(\n    authorization: .notDetermined,\n    isRecognizerAvailable: true\n)\nlet appSettingsAuthorizationMarker = settings",
            to: "Sources/AppSettings.swift"
        )
        try fixture.write(
            "func register(authorization: ToolActionAuthorization? = nil) {}\nlet toolingAuthorizationMarker = registration",
            to: "Sources/Tooling.swift"
        )
        try fixture.write(
            "@Published public private(set) var openAIAPIKeyInput: String\nlet setterAccessModifierMarker = openAIAPIKeyInput",
            to: "Sources/SettingsAccess.swift"
        )
        try fixture.write(
            "@Published public private(set) var openAIAPIKeyInput = \"setterliteralmarker\"",
            to: "Sources/SettingsAccessLiteral.swift"
        )
        try fixture.write(
            """
            final class TokenState {
                @Published private var rerunRequestToken: UUID?
                private var authorization: ToolActionAuthorization?

                func load(credentialStore: CredentialStore) {
                    guard let accessToken = try credentialStore.accessToken(for: account) else { return }
                    if let idToken = cachedToken { consume(idToken) }
                    if let refreshToken = credentialStore.refreshToken { consume(refreshToken) }
                    let optionalBindingMarker = accessToken
                }

                func use(authorization: AuthorizationPolicy) {}
                func useDefault(authorization: ToolActionAuthorization? = nil) {}

                func send() {
                    request(authorization: authorizationStatus())
                    request(authorization: authorization)
                    request(authorization: .notDetermined)
                    request(authorization: try ToolActionAuthorization(level: level))
                    let authorizationGrammarMarker = authorization
                }
            }
            """,
            to: "Sources/OptionalBindings.swift"
        )
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
        let credentialMarker = "ABCDEFGH" + "IJK1234"
        let credentials = [
            "Settings.env.swift": "API_KEY=long-secret-value",
            "TokenQuoted.swift": "token=\"long-secret-value\"",
            "TokenBare.swift": "token=long-secret-value",
            "APIKeyBare.swift": "apiKey=long-secret-value",
            "TokenExport.swift": "export token=long-secret-value",
            "TokenYAML.yml": "token: long-secret-value",
            "TokenTyped.swift": "token: String = \"long-secret-value\"",
            "TokenMixed.swift": "func f(token: ApprovalToken, password: long-secret-value) {}\n{ token: ApprovalToken, password: long-secret-value }",
            "TokenUppercase.yml": "TOKEN: \(credentialMarker)",
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
            "CredentialValueSuffix.swift": "let accessTokenValue = \"long-secret-value\"\nlet apiKeyString = \"long-secret-value\"",
            "OptionalBindingLiteral.swift": "guard let accessToken = \"long-secret-value\" else { return }",
            "OptionalBindingTrailingCredential.swift": "if let idToken = cachedToken { accessToken = \"long-secret-value\" }\nguard let refreshToken = cachedRefreshToken else { accessToken = \"long-secret-value\" }",
            "SameNameOptionalBindingTrailingCredential.swift": "if let accessToken = cachedToken { accessToken = \"long-secret-value\" }\nguard let accessToken = cachedToken else { accessToken = \"long-secret-value\" }",
            "AuthorizationLiteral.swift": "request(authorization: \"Token long-secret-value\")",
            "AuthorizationNumericLiteral.swift": "request(authorization: 424242)",
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
            "Dockerfile": "ENV ACCESS_TOKEN long-secret-value",
            "Makefile": "ACCESS_TOKEN := long-secret-value",
            "Gemfile": "accessToken = \"long-secret-value\"",
            "Data.csv": "accessToken,long-secret-value",
            "SingleQuotedCredential.yml": "'token': long-secret-value",
            "CommentOpen.swift": "// fake(\ntoken: \(credentialMarker)",
            "CommentInsideCall.swift": "request(\n// token: \(credentialMarker)\n)",
            "BlockCommentCall.swift": "request(\n/*\naccessToken: \(credentialMarker)\n*/\n)",
            "BlockCommentAssignment.swift": "/*\nlet googleClientSecret = \(credentialMarker)\n*/",
            "MultilineStringCall.swift": "request(\n\"\"\"\naccessToken: \(credentialMarker)\n\"\"\"\n)",
            "MultilineStringAssignment.swift": "let template = \"\"\"\nlet googleClientSecret = \(credentialMarker)\n\"\"\"",
            "RawStringAssignment.swift": "let template = #\"let googleClientSecret = \(credentialMarker)\"#",
            "RawMultilineAssignment.swift": "#\"\"\"\nliteral \"\"\"\nlet googleClientSecret = \(credentialMarker)\n\"\"\"#",
            "RawMultilineCall.swift": "request(\n#\"\"\"\naccessToken: \(credentialMarker)\n\"\"\"#\n)",
            "RawEscapedDelimiter.swift": "#\"\"\"\n\\#\"\"\"#\nlet googleClientSecret = \(credentialMarker)\n\"\"\"#",
            "RawRegexAssignment.swift": "let pattern = #/\nliteral \\/\nlet googleClientSecret = \(credentialMarker)\n/#",
            "RawRegexDoubleHashAssignment.swift": "##/\nliteral /#\nlet googleClientSecret = \(credentialMarker)\n/##",
            "RawRegexCall.swift": "request(\n#/\naccessToken: \(credentialMarker)\n/#\n)",
            "RawRegexEscapedDelimiter.swift": "let pattern = #/\n\\/#\nlet googleClientSecret = \(credentialMarker)\n/#",
            "RawRegexDoubleHashEscapedDelimiter.swift": "let pattern = ##/\n\\/##\nlet googleClientSecret = \(credentialMarker)\n/##",
            "RawRegexEscapedDelimiterCall.swift": "request(\n##/\n\\/##\naccessToken: \(credentialMarker)\n/##\n)",
            "TokenStandalone.swift": "TOKEN: \(credentialMarker)",
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
        let uncheckedNominalResults = try await index.search(query: "uncheckedNominalMarker", workspace: workspace(fixture))
        let uncheckedOnlyResults = try await index.search(query: "uncheckedOnlyMarker", workspace: workspace(fixture))
        let optionalBindingResults = try await index.search(query: "optionalBindingMarker", workspace: workspace(fixture))
        let authorizationGrammarResults = try await index.search(query: "authorizationGrammarMarker", workspace: workspace(fixture))
        let appSettingsAuthorizationResults = try await index.search(query: "appSettingsAuthorizationMarker", workspace: workspace(fixture))
        let toolingAuthorizationResults = try await index.search(query: "toolingAuthorizationMarker", workspace: workspace(fixture))
        let setterAccessModifierResults = try await index.search(query: "setterAccessModifierMarker", workspace: workspace(fixture))
        let setterLiteralResults = try await index.search(query: "setterliteralmarker", workspace: workspace(fixture))
        let numericAuthorizationResults = try await index.search(query: "424242", workspace: workspace(fixture))
        let credentialResults = try await index.search(query: "long", workspace: workspace(fixture))
        let uppercaseCredentialResults = try await index.search(query: credentialMarker, workspace: workspace(fixture))
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
        XCTAssertEqual(uncheckedNominalResults.map(\.sourcePath), ["Sources/KeychainOAuthCredentialStore.swift"])
        XCTAssertEqual(uncheckedOnlyResults.map(\.sourcePath), ["Sources/KeychainOAuthCredentialStore.swift"])
        XCTAssertEqual(optionalBindingResults.map(\.sourcePath), ["Sources/OptionalBindings.swift"])
        XCTAssertEqual(authorizationGrammarResults.map(\.sourcePath), ["Sources/OptionalBindings.swift"])
        XCTAssertEqual(appSettingsAuthorizationResults.map(\.sourcePath), ["Sources/AppSettings.swift"])
        XCTAssertEqual(toolingAuthorizationResults.map(\.sourcePath), ["Sources/Tooling.swift"])
        XCTAssertEqual(setterAccessModifierResults.map(\.sourcePath), ["Sources/SettingsAccess.swift"])
        XCTAssertTrue(setterLiteralResults.isEmpty)
        XCTAssertTrue(numericAuthorizationResults.isEmpty)
        XCTAssertTrue(credentialResults.isEmpty)
        XCTAssertTrue(uppercaseCredentialResults.isEmpty)
        XCTAssertTrue(compoundCredentialResults.isEmpty)
        XCTAssertTrue(textCredentialResults.isEmpty)
        XCTAssertTrue(nonSwiftFunctionResults.isEmpty)
    }

    func testRefreshIndexesSwiftCollectionTypesButRejectsLiteralAssignment() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write(
            """
            struct CollectionState {
                let tokens: [String]
                let tokensByID: [String: String]
                let tokenPair: (String, Date)
            }
            func use(tokens: [String], tokensByID: [String: String], tokenPair: (String, Date)) {
                let collectiontypemarker = tokens.count
            }
            """,
            to: "Sources/CollectionState.swift"
        )
        try fixture.write(
            "let tokens: [String] = [\"collectionliteralsecretmarker\"]",
            to: "Sources/CollectionLiteral.swift"
        )
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let safe = try await index.search(query: "collectiontypemarker", workspace: workspace(fixture))
        let literal = try await index.search(query: "collectionliteralsecretmarker", workspace: workspace(fixture))
        XCTAssertEqual(safe.map(\.sourcePath), ["Sources/CollectionState.swift"])
        XCTAssertTrue(literal.isEmpty)
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

    func testRefreshIndexesCredentialNamedSwiftExtensions() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("extension AccessToken: Codable {}\nextension APIKey: Sendable {}", to: "Sources/CredentialExtensions.swift")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let accessToken = try await index.search(query: "AccessToken", workspace: workspace(fixture))
        let apiKey = try await index.search(query: "APIKey", workspace: workspace(fixture))
        XCTAssertEqual(accessToken.map(\.sourcePath), ["Sources/CredentialExtensions.swift"])
        XCTAssertEqual(apiKey.map(\.sourcePath), ["Sources/CredentialExtensions.swift"])
    }

    func testRefreshHonorsGlobalExcludeForUntrackedFiles() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let home = fixture.url.appendingPathComponent("home", isDirectory: true)
        let excludes = home.appendingPathComponent("global-ignore")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "GloballyIgnored.md\n".write(to: excludes, atomically: true, encoding: .utf8)
        try "[core]\n\texcludesFile = \(excludes.path)\n\tfsmonitor = /bin/false\n".write(
            to: home.appendingPathComponent(".gitconfig"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.write("globalignoremarker", to: "GloballyIgnored.md")
        try fixture.write("visibleglobalmarker", to: "Visible.md")

        let previousHome = ProcessInfo.processInfo.environment["HOME"]
        let previousXDGConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        setenv("HOME", home.path, 1)
        unsetenv("XDG_CONFIG_HOME")
        defer {
            if let previousHome {
                setenv("HOME", previousHome, 1)
            } else {
                unsetenv("HOME")
            }
            if let previousXDGConfigHome {
                setenv("XDG_CONFIG_HOME", previousXDGConfigHome, 1)
            }
        }

        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let ignored = try await index.search(query: "globalignoremarker", workspace: workspace(fixture))
        let visible = try await index.search(query: "visibleglobalmarker", workspace: workspace(fixture))
        XCTAssertTrue(ignored.isEmpty)
        XCTAssertEqual(visible.map(\.sourcePath), ["Visible.md"])
    }

    func testRefreshHonorsRepositoryAndGlobalExcludesWithoutLoadingGlobalHooks() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let home = fixture.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let repositoryExcludes = fixture.url.appendingPathComponent("repository-ignore")
        let globalExcludes = home.appendingPathComponent("global-ignore")
        let hookMarker = fixture.url.appendingPathComponent("global-fsmonitor-ran")
        let hook = fixture.url.appendingPathComponent("global-fsmonitor.sh")
        try "RepositoryIgnored.md\n".write(to: repositoryExcludes, atomically: true, encoding: .utf8)
        try "GlobalIgnored.md\n".write(to: globalExcludes, atomically: true, encoding: .utf8)
        try "#!/bin/sh\ntouch '\(hookMarker.path)'\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hook.path)
        try "[core]\n\texcludesFile = \(globalExcludes.path)\n\tfsmonitor = \(hook.path)\n".write(
            to: home.appendingPathComponent(".gitconfig"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.runGit(["config", "core.excludesFile", repositoryExcludes.path])
        try fixture.write("repositoryignoremarker", to: "RepositoryIgnored.md")
        try fixture.write("globalignoremarker", to: "GlobalIgnored.md")
        try fixture.write("visiblebothignoresmarker", to: "Visible.md")

        let previousHome = ProcessInfo.processInfo.environment["HOME"]
        let previousXDGConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        setenv("HOME", home.path, 1)
        unsetenv("XDG_CONFIG_HOME")
        defer {
            if let previousHome {
                setenv("HOME", previousHome, 1)
            } else {
                unsetenv("HOME")
            }
            if let previousXDGConfigHome {
                setenv("XDG_CONFIG_HOME", previousXDGConfigHome, 1)
            }
        }

        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let repositoryIgnored = try await index.search(query: "repositoryignoremarker", workspace: workspace(fixture))
        let globalIgnored = try await index.search(query: "globalignoremarker", workspace: workspace(fixture))
        let visible = try await index.search(query: "visiblebothignoresmarker", workspace: workspace(fixture))
        XCTAssertTrue(repositoryIgnored.isEmpty)
        XCTAssertTrue(globalIgnored.isEmpty)
        XCTAssertEqual(visible.map(\.sourcePath), ["Visible.md"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: hookMarker.path))
    }

    func testRefreshHonorsDefaultGlobalExcludeForUntrackedFiles() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let configDirectory = fixture.url.appendingPathComponent("home/.config/git", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try "DefaultGloballyIgnored.md\n".write(
            to: configDirectory.appendingPathComponent("ignore"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.write("defaultglobalignoremarker", to: "DefaultGloballyIgnored.md")
        try fixture.write("defaultvisiblemarker", to: "Visible.md")

        let previousHome = ProcessInfo.processInfo.environment["HOME"]
        let previousXDGConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        setenv("HOME", fixture.url.appendingPathComponent("home").path, 1)
        unsetenv("XDG_CONFIG_HOME")
        defer {
            if let previousHome {
                setenv("HOME", previousHome, 1)
            } else {
                unsetenv("HOME")
            }
            if let previousXDGConfigHome {
                setenv("XDG_CONFIG_HOME", previousXDGConfigHome, 1)
            }
        }

        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let ignored = try await index.search(query: "defaultglobalignoremarker", workspace: workspace(fixture))
        let visible = try await index.search(query: "defaultvisiblemarker", workspace: workspace(fixture))
        XCTAssertTrue(ignored.isEmpty)
        XCTAssertEqual(visible.map(\.sourcePath), ["Visible.md"])
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
        try fixture.write(#"{"Authoriz\u0061tion":"Bearer escapedauthorizationmarker"}"#, to: "Config/EscapedAuthorization.json")
        try fixture.write(#"{"to\u006ben":"malformedjsonmarker""#, to: "Config/MalformedEscapedToken.json")
        try fixture.write(#""to\u006ben" = "escapedtomlmarker""#, to: "Config/EscapedToken.toml")
        try fixture.write(#""client_\u0073ecret" = "escapedtomlsecretmarker""#, to: "Config/EscapedSecret.toml")
        try fixture.write(#"{"message":"OAuth token lifecycle harmlessjsonmarker","items":[{"label":"normal"}]}"#, to: "Config/Harmless.json")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let escapedToken = try await index.search(query: "escapedtokenmarker", workspace: workspace(fixture))
        let escapedSecret = try await index.search(query: "escapedsecretmarker", workspace: workspace(fixture))
        let escapedAuth = try await index.search(query: "escapedauthmarker", workspace: workspace(fixture))
        let escapedAuthorization = try await index.search(query: "escapedauthorizationmarker", workspace: workspace(fixture))
        let malformed = try await index.search(query: "malformedjsonmarker", workspace: workspace(fixture))
        let escapedTOML = try await index.search(query: "escapedtomlmarker", workspace: workspace(fixture))
        let escapedTOMLSecret = try await index.search(query: "escapedtomlsecretmarker", workspace: workspace(fixture))
        let harmless = try await index.search(query: "harmlessjsonmarker", workspace: workspace(fixture))
        XCTAssertTrue(escapedToken.isEmpty)
        XCTAssertTrue(escapedSecret.isEmpty)
        XCTAssertTrue(escapedAuth.isEmpty)
        XCTAssertTrue(escapedAuthorization.isEmpty)
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

    func testRefreshTreatsExtensionlessReadmeAndLicenseAsProse() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("OAuth token lifecycle readmeprosemarker", to: "README")
        try fixture.write("refresh token lifecycle licenseprosemarker", to: "LICENSE")
        try fixture.write("accessToken = longsecretassignmentmarker", to: "README.md")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let readme = try await index.search(query: "readmeprosemarker", workspace: workspace(fixture))
        let license = try await index.search(query: "licenseprosemarker", workspace: workspace(fixture))
        let assignment = try await index.search(query: "longsecretassignmentmarker", workspace: workspace(fixture))
        XCTAssertEqual(readme.map(\.sourcePath), ["README"])
        XCTAssertEqual(license.map(\.sourcePath), ["LICENSE"])
        XCTAssertTrue(assignment.isEmpty)
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

    func testRefreshRollsBackWhenWorkspaceIsReplacedBeforeCommit() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let index = DevelopmentRepositoryIndex(connection: connection)
        try fixture.write("preservedgenerationmarker", to: "Notes.md")
        try await index.refresh(workspace: workspace(fixture))
        try fixture.write("candidategenerationmarker", to: "Notes.md")

        let fixtureURL = fixture.url
        let movedRoot = fixtureURL.deletingLastPathComponent().appendingPathComponent("suisui-index-commit-race-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: fixtureURL)
            try? FileManager.default.moveItem(at: movedRoot, to: fixtureURL)
        }
        let racingIndex = DevelopmentRepositoryIndex(
            connection: connection,
            beforeRefreshCommit: {
                try FileManager.default.moveItem(at: fixtureURL, to: movedRoot)
                try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
                try "replacementrootmarker".write(
                    to: fixtureURL.appendingPathComponent("Notes.md"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        )

        await XCTAssertThrowsErrorAsync(try await racingIndex.refresh(workspace: workspace(fixture)))

        let rows = try connection.queryRows("SELECT contents FROM codebase_index_files;")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows[0].string("contents"), "preservedgenerationmarker")
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
                inode: original.st_ino,
                birthTimeSeconds: Int64(original.st_birthtimespec.tv_sec),
                birthTimeNanoseconds: Int64(original.st_birthtimespec.tv_nsec)
            )
        ) { error in
            XCTAssertEqual(error as? DevelopmentRepositoryIndexError, .fileReadUnavailable)
        }
    }

    func testWorkspaceRootIdentityAndKeyIncludeBirthTime() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        var state = stat()
        XCTAssertEqual(Darwin.lstat(fixture.url.path, &state), 0)
        let birthTimeSeconds = Int64(state.st_birthtimespec.tv_sec)
        let birthTimeNanoseconds = Int64(state.st_birthtimespec.tv_nsec)

        let originalKey = DevelopmentRepositoryIndex.workspaceKey(
            root: fixture.url,
            device: state.st_dev,
            inode: state.st_ino,
            birthTimeSeconds: birthTimeSeconds,
            birthTimeNanoseconds: birthTimeNanoseconds
        )
        let reusedInodeKey = DevelopmentRepositoryIndex.workspaceKey(
            root: fixture.url,
            device: state.st_dev,
            inode: state.st_ino,
            birthTimeSeconds: birthTimeSeconds + 1,
            birthTimeNanoseconds: birthTimeNanoseconds
        )

        XCTAssertNotEqual(originalKey, reusedInodeKey)
        XCTAssertThrowsError(
            try DevelopmentRepositoryIndex.verifyWorkspaceRootIdentity(
                fixture.url,
                device: state.st_dev,
                inode: state.st_ino,
                birthTimeSeconds: birthTimeSeconds + 1,
                birthTimeNanoseconds: birthTimeNanoseconds
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

    func testManifestRejectsMismatchedChildWorkingDirectoryIdentity() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let marker = fixture.url.appendingPathComponent("manifest-helper-ran")
        let helper = fixture.url.appendingPathComponent("manifest-helper.sh")
        try "#!/bin/sh\nif [ \"$1\" = \"config\" ]; then exit 1; fi\ntouch '\(marker.path)'\nprintf '? Notes.md\\0'\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

        XCTAssertThrowsError(
            try GitManifestReader.paths(
                at: fixture.url,
                executableURL: helper,
                expectedRootIdentity: .init(device: 0, inode: 0)
            )
        ) { error in
            XCTAssertEqual(error as? DevelopmentRepositoryIndexError, .gitManifestUnavailable)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testGlobalExcludeLookupTimeoutKeepsPriorGeneration() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("priorglobalignoremarker", to: "Notes.md")
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let index = DevelopmentRepositoryIndex(connection: connection)
        try await index.refresh(workspace: workspace(fixture))

        let helper = fixture.url.appendingPathComponent("hang-global-config.sh")
        try "#!/bin/sh\nif [ \"$1\" = \"config\" ]; then\n  trap '' TERM\n  while :; do :; done\nfi\nprintf '? Added.md\\0'\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let hangingIndex = DevelopmentRepositoryIndex(connection: connection, manifestExecutableURL: helper)

        let startedAt = Date()
        await XCTAssertThrowsErrorAsync(try await hangingIndex.refresh(workspace: workspace(fixture)))
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
        let retained = try connection.queryRows("SELECT contents FROM codebase_index_files;")
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(try retained[0].string("contents"), "priorglobalignoremarker")
    }

    func testGlobalExcludeLookupRejectsMultiplePaths() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let helper = fixture.url.appendingPathComponent("multiple-global-config.sh")
        try "#!/bin/sh\nif [ \"$1\" = \"config\" ]; then\n  printf '/first\\n/second\\n'\n  exit 0\nfi\nprintf '? Visible.md\\0'\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

        XCTAssertThrowsError(try GitManifestReader.paths(at: fixture.url, executableURL: helper)) { error in
            XCTAssertEqual(error as? DevelopmentRepositoryIndexError, .gitManifestUnavailable)
        }
    }

    func testGlobalExcludeLookupRejectsOversizedPath() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let helper = fixture.url.appendingPathComponent("oversized-global-config.sh")
        let oversizedPath = String(repeating: "a", count: 5_000)
        try "#!/bin/sh\nif [ \"$1\" = \"config\" ]; then\n  printf '\(oversizedPath)\\n'\n  exit 0\nfi\nprintf '? Visible.md\\0'\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

        XCTAssertThrowsError(try GitManifestReader.paths(at: fixture.url, executableURL: helper)) { error in
            XCTAssertEqual(error as? DevelopmentRepositoryIndexError, .gitManifestUnavailable)
        }
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

    func testRefreshCountsOversizedSkippedFilesAgainstAggregateBudget() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("previousbudgetmarker", to: "Notes.md")
        let perFileReadBytes = DevelopmentRepositoryFilePathPolicy.maximumContentBytes + 1
        let index = try migratedIndex(maximumRefreshReadBytes: perFileReadBytes * 2)
        try await index.refresh(workspace: workspace(fixture))

        let oversized = Data(repeating: 0x61, count: perFileReadBytes)
        try fixture.write(oversized, to: "Large/One.md")
        try fixture.write(oversized, to: "Large/Two.md")
        try fixture.write(oversized, to: "Large/Three.md")

        await XCTAssertThrowsErrorAsync(try await index.refresh(workspace: workspace(fixture)))
        let preserved = try await index.search(query: "previousbudgetmarker", workspace: workspace(fixture))
        XCTAssertEqual(preserved.map(\.sourcePath), ["Notes.md"])
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

    func testSearchCompletesANDResultsWithORMatches() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("sqlite natural exactandmarker", to: "Docs/Exact.md")
        try fixture.write("sqlite partialormarker", to: "Docs/Partial.md")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let results = try await index.search(query: "sqlite natural", workspace: workspace(fixture), topK: 2)
        XCTAssertEqual(results.map(\.sourcePath), ["Docs/Exact.md", "Docs/Partial.md"])
    }

    func testSearchPrefersCJKFullFallbackBeforeEnglishOnlyORMatches() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("設計 sqlite ftsexactmarker", to: "Docs/FTSExact.md")
        try fixture.write("詳細設計 SQLite fallbackfullmarker", to: "Docs/Fallback.md")
        try fixture.write("sqlite englishonlymarker", to: "Docs/EnglishOnly.md")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let results = try await index.search(query: "設計 sqlite", workspace: workspace(fixture), topK: 2)
        XCTAssertEqual(results.map(\.sourcePath), ["Docs/FTSExact.md", "Docs/Fallback.md"])
    }

    func testSearchUsesCJKBigramsForUnspacedNaturalLanguage() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("設定画面の説明 settingsmarker", to: "Docs/Settings.md")
        try fixture.write("保存処理の説明 savemarker", to: "Docs/Save.md")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let results = try await index.search(query: "設定画面の保存処理を直して", workspace: workspace(fixture), topK: 2)

        XCTAssertEqual(results.map(\.sourcePath), ["Docs/Save.md", "Docs/Settings.md"])
    }

    func testSearchSplitsLatinAndCJKRunsWithinOneToken() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("Swift の実装 mixedrunmarker", to: "Docs/Mixed.md")
        let index = try migratedIndex()

        try await index.refresh(workspace: workspace(fixture))

        let results = try await index.search(query: "Swift実装", workspace: workspace(fixture))
        XCTAssertEqual(results.map(\.sourcePath), ["Docs/Mixed.md"])
    }

    func testSearchRejectsPunctuationOnlyQuery() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let index = try migratedIndex()

        await XCTAssertThrowsErrorAsync(try await index.search(query: "***", workspace: workspace(fixture)))
    }

    func testSearchRejectsByteOversizedSingleGraphemeBeforeDatabaseQuery() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let index = DevelopmentRepositoryIndex(connection: try SQLiteConnection(path: ":memory:"))
        let oversizedQuery = "a" + String(repeating: "\u{0301}", count: 4_096)
        XCTAssertEqual(oversizedQuery.count, 1)

        do {
            _ = try await index.search(query: oversizedQuery, workspace: workspace(fixture))
            XCTFail("Expected byte-oversized query to be rejected")
        } catch {
            XCTAssertEqual(error as? DevelopmentRepositoryIndexError, .invalidQuery)
        }
    }

    private func migratedIndex(
        maximumRefreshReadBytes: Int = DevelopmentRepositoryIndex.maximumIndexedContentBytes
    ) throws -> DevelopmentRepositoryIndex {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return DevelopmentRepositoryIndex(connection: connection, maximumRefreshReadBytes: maximumRefreshReadBytes)
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
