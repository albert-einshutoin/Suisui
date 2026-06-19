import XCTest
@testable import SoloPMCore

final class ExternalMCPTests: XCTestCase {
    func testClientInitializesListsAndCallsToolsWith20251125Protocol() async throws {
        let transport = ExternalMCPTestKit.makeFakeServerTransport()
        let client = MCPClient(serverID: "fake", transport: transport)

        let initialize = try await client.initialize()
        let tools = try await client.listTools()
        let result = try await client.callTool(name: "read_status", arguments: ["project": .string("soloPM")])

        XCTAssertEqual(initialize.protocolVersion, MCPProtocolVersion.v2025_11_25.rawValue)
        XCTAssertEqual(tools.map(\.name), ["read_status", "write_issue", "danger_delete", "slow_tool", "invalid_response"])
        XCTAssertEqual(result.content.first?.text, "status: ok")
        XCTAssertEqual(transport.recordedMethods, ["initialize", "notifications/initialized", "tools/list", "tools/call"])
        XCTAssertEqual(transport.recordedRequests.first?.params?.objectValue?["protocolVersion"], .string("2025-11-25"))
    }

    func testClientFollowsToolsListPaginationCursor() async throws {
        let transport = RecordingMCPTransport { request in
            if request.method != "tools/list" {
                return MCPJSONRPCResponse(id: request.id, result: .object([:]))
            }
            let cursor = request.params?.objectValue?["cursor"]?.stringValue
            if cursor == nil {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            MCPToolDefinition(
                                name: "read_status",
                                title: "Read Status",
                                description: "Read local project status.",
                                inputSchema: ["type": .string("object")]
                            ).jsonValue
                        ]),
                        "nextCursor": .string("page-2")
                    ])
                )
            }
            return MCPJSONRPCResponse(
                id: request.id,
                result: .object([
                    "tools": .array([
                        MCPToolDefinition(
                            name: "write_issue",
                            title: "Write Issue",
                            description: "Create an issue.",
                            inputSchema: ["type": .string("object")]
                        ).jsonValue
                    ])
                ])
            )
        }
        let client = MCPClient(serverID: "paged", transport: transport)

        let tools = try await client.listTools()

        XCTAssertEqual(tools.map(\.name), ["read_status", "write_issue"])
        let listRequests = transport.recordedRequests.filter { $0.method == "tools/list" }
        XCTAssertEqual(listRequests.count, 2)
        XCTAssertEqual(listRequests[0].params, .object([:]))
        XCTAssertEqual(listRequests[1].params?.objectValue?["cursor"], .string("page-2"))
    }

    func testClientRejectsMalformedToolsListPaginationCursor() async throws {
        let transport = RecordingMCPTransport { request in
            MCPJSONRPCResponse(
                id: request.id,
                result: .object([
                    "tools": .array([]),
                    "nextCursor": .number(42)
                ])
            )
        }
        let client = MCPClient(serverID: "paged", transport: transport)

        do {
            _ = try await client.listTools()
            XCTFail("non-string tools/list nextCursor should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "paged",
                    method: "tools/list",
                    reason: "result.nextCursor must be a string when present."
                )
            )
        }
    }

    func testClientRejectsRepeatedToolsListPaginationCursor() async throws {
        let transport = RecordingMCPTransport { request in
            MCPJSONRPCResponse(
                id: request.id,
                result: .object([
                    "tools": .array([]),
                    "nextCursor": .string("same-page")
                ])
            )
        }
        let client = MCPClient(serverID: "paged", transport: transport)

        do {
            _ = try await client.listTools()
            XCTFail("repeated tools/list nextCursor should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "paged",
                    method: "tools/list",
                    reason: "result.nextCursor repeated a previously seen cursor."
                )
            )
        }
        XCTAssertEqual(transport.recordedRequests.filter { $0.method == "tools/list" }.count, 2)
    }

    func testClientRejectsNonObjectInitializeServerInfo() async throws {
        let transport = RecordingMCPTransport { request in
            MCPJSONRPCResponse(
                id: request.id,
                result: .object([
                    "protocolVersion": .string(MCPProtocolVersion.v2025_11_25.rawValue),
                    "serverInfo": .string("not-an-object")
                ])
            )
        }
        let client = MCPClient(serverID: "bad-init", transport: transport)

        do {
            _ = try await client.initialize()
            XCTFail("non-object initialize serverInfo should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "bad-init",
                    method: "initialize",
                    reason: "result.serverInfo must be an object when present."
                )
            )
        }
    }

    func testClientRejectsNonStringInitializeServerName() async throws {
        let transport = RecordingMCPTransport { request in
            MCPJSONRPCResponse(
                id: request.id,
                result: .object([
                    "protocolVersion": .string(MCPProtocolVersion.v2025_11_25.rawValue),
                    "serverInfo": .object([
                        "name": .number(42)
                    ])
                ])
            )
        }
        let client = MCPClient(serverID: "bad-init", transport: transport)

        do {
            _ = try await client.initialize()
            XCTFail("non-string initialize serverInfo.name should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "bad-init",
                    method: "initialize",
                    reason: "result.serverInfo.name must be a string when present."
                )
            )
        }
    }

    func testClientRejectsUnsupportedInitializeProtocolVersionBeforeInitializedNotification() async throws {
        let transport = RecordingMCPTransport { request in
            MCPJSONRPCResponse(
                id: request.id,
                result: .object([
                    "protocolVersion": .string("2024-11-05"),
                    "serverInfo": .object(["name": .string("legacy-mcp")])
                ])
            )
        }
        let client = MCPClient(serverID: "legacy", transport: transport)

        do {
            _ = try await client.initialize()
            XCTFail("unsupported initialize protocolVersion should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "legacy",
                    method: "initialize",
                    reason: "Unsupported result.protocolVersion: 2024-11-05."
                )
            )
        }
        XCTAssertEqual(transport.recordedMethods, ["initialize"])
    }

    func testServerRegistrationValidatesCommandBinaryDisabledAndKeychainEnvReferences() async throws {
        let validator = MCPServerRegistrationValidator(binaryLocator: StaticBinaryLocator(availableCommands: ["node"]))
        let workingDirectory = try temporaryDirectory()
        let valid = MCPServerRegistration(
            id: "github",
            displayName: "GitHub MCP",
            command: "node",
            arguments: ["server.js"],
            environment: ["GITHUB_TOKEN": .keychain(.githubToken)],
            workingDirectory: workingDirectory.path,
            isEnabled: true
        )

        XCTAssertNoThrow(try validator.validate(valid))
        XCTAssertEqual(valid.environment["GITHUB_TOKEN"], .keychain(.githubToken))
        let display = MCPServerRegistrationDisplayModel(registration: valid)
        XCTAssertEqual(display.displayName, "GitHub MCP")
        XCTAssertEqual(display.commandLine, "node server.js")
        XCTAssertEqual(display.transportLabel, "stdio")
        XCTAssertEqual(display.environmentRows, [
            MCPEnvironmentDisplayRow(name: "GITHUB_TOKEN", sourceLabel: "Keychain: github_token")
        ])
        XCTAssertEqual(display.statusLabel, "Enabled")

        XCTAssertThrowsError(try validator.validate(MCPServerRegistration(
            id: "empty",
            displayName: "Empty",
            command: " ",
            arguments: [],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        ))) { error in
            XCTAssertEqual(error as? MCPRegistrationError, .invalidCommand)
        }

        XCTAssertThrowsError(try validator.validate(MCPServerRegistration(
            id: "missing",
            displayName: "Missing",
            command: "missing-binary",
            arguments: [],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        ))) { error in
            XCTAssertEqual(error as? MCPRegistrationError, .missingBinary("missing-binary"))
        }

        let pathWithSpaceValidator = MCPServerRegistrationValidator(
            binaryLocator: StaticBinaryLocator(availableCommands: ["/Applications/MCP Server/server"])
        )
        XCTAssertNoThrow(try pathWithSpaceValidator.validate(MCPServerRegistration(
            id: "path-with-space",
            displayName: "Path With Space",
            command: "/Applications/MCP Server/server",
            arguments: [],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )))

        let launcher = MCPStdioServerLauncher(
            validator: validator,
            transportFactory: { _ in ExternalMCPTestKit.makeFakeServerTransport() }
        )
        let launchedClient = try await launcher.client(for: valid)
        let tools = try await launchedClient.listTools()
        let result = try await launchedClient.callTool(name: "read_status", arguments: [:])
        XCTAssertTrue(tools.contains { $0.name == "read_status" })
        XCTAssertEqual(result.content.first?.text, "status: ok")

        do {
            _ = try await launcher.client(for: MCPServerRegistration(
                id: "disabled",
                displayName: "Disabled",
                command: "node",
                arguments: [],
                environment: [:],
                workingDirectory: nil,
                isEnabled: false
            ))
            XCTFail("disabled server should not launch")
        } catch {
            XCTAssertEqual(error as? MCPRegistrationError, .serverDisabled)
        }
    }

    @MainActor
    func testExternalMCPSettingsRejectsCompositeCommandBeforeSavingRegistration() throws {
        let store = InMemoryMCPServerRegistrationStore()
        let validator = MCPServerRegistrationValidator(binaryLocator: StaticBinaryLocator(availableCommands: ["node"]))
        let viewModel = ExternalMCPSettingsViewModel(store: store, registrationValidator: validator)

        viewModel.updateDisplayName("Local Docs MCP")
        viewModel.updateCommand("node server.js")
        viewModel.updateEnabled(true)
        viewModel.save()

        XCTAssertEqual(try store.loadRegistrations(), [])
        XCTAssertEqual(
            viewModel.errorMessage,
            "MCP command must contain only the executable. Move arguments for node into the Arguments field."
        )
    }

    func testDefaultMCPEnvironmentResolverDoesNotReadFromInMemorySecrets() throws {
        let resolver = NoSecretMCPEnvironmentResolver()

        XCTAssertEqual(try resolver.resolve([:]), [:])
        XCTAssertThrowsError(try resolver.resolve(["GITHUB_TOKEN": .keychain(.githubToken)])) { error in
            XCTAssertEqual(error as? MCPRegistrationError, .missingSecret("GITHUB_TOKEN"))
        }
    }

    func testMCPEnvironmentTextCodecParsesKeychainReferencesAndRejectsRawValues() throws {
        let environment = try MCPEnvironmentTextCodec.parse("""
        GITHUB_TOKEN=keychain:github_token
        OPENAI_API_KEY = keychain: openai_api_key
        """)

        XCTAssertEqual(environment, [
            "GITHUB_TOKEN": .keychain(.githubToken),
            "OPENAI_API_KEY": .keychain(.openAIAPIKey)
        ])
        XCTAssertEqual(
            MCPEnvironmentTextCodec.format(environment),
            """
            GITHUB_TOKEN=keychain:github_token
            OPENAI_API_KEY=keychain:openai_api_key
            """
        )

        XCTAssertThrowsError(try MCPEnvironmentTextCodec.parse("GITHUB_TOKEN=ghp_raw_secret")) { error in
            XCTAssertEqual(
                error as? MCPEnvironmentTextError,
                .rawValueNotAllowed(line: 1)
            )
        }
        XCTAssertThrowsError(try MCPEnvironmentTextCodec.parse("9TOKEN=keychain:github_token")) { error in
            XCTAssertEqual(
                error as? MCPEnvironmentTextError,
                .invalidName(line: 1, name: "9TOKEN")
            )
        }
        XCTAssertThrowsError(try MCPEnvironmentTextCodec.parse("トークン=keychain:github_token")) { error in
            XCTAssertEqual(
                error as? MCPEnvironmentTextError,
                .invalidName(line: 1, name: "トークン")
            )
        }
        XCTAssertThrowsError(try MCPEnvironmentTextCodec.parse("GITHUB_TOKEN=keychain:github token")) { error in
            XCTAssertEqual(
                error as? MCPEnvironmentTextError,
                .invalidKeychainKey(line: 1, name: "github token")
            )
        }
    }

    func testStdioLauncherStartsProcessAndCallsTools() async throws {
        let scriptURL = try makeStdioServerScript()
        let registration = MCPServerRegistration(
            id: "stdio",
            displayName: "Stdio MCP",
            command: scriptURL.path,
            arguments: [],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let client = try await MCPStdioServerLauncher().client(for: registration)

        let initialize = try await client.initialize()
        let tools = try await client.listTools()
        let result = try await client.callTool(name: "read_status", arguments: [:])

        XCTAssertEqual(initialize.protocolVersion, MCPProtocolVersion.v2025_11_25.rawValue)
        XCTAssertEqual(tools.map(\.name), ["read_status"])
        XCTAssertEqual(result.content.first?.text, "status: ok")
    }

    func testStdioTransportReportsMalformedJSONAsInvalidResponse() async throws {
        let scriptURL = try makeMalformedStdioServerScript()
        let registration = MCPServerRegistration(
            id: "stdio",
            displayName: "Malformed Stdio MCP",
            command: scriptURL.path,
            arguments: [],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let client = try await MCPStdioServerLauncher().client(for: registration)

        do {
            _ = try await client.listTools()
            XCTFail("malformed stdio response should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(serverID: "stdio", method: "tools/list", reason: "Malformed JSON-RPC response.")
            )
        }
    }

    func testClientRejectsNonBooleanToolCallIsError() async throws {
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/call" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([MCPContentItem(type: "text", text: "status: ok").jsonValue]),
                        "isError": .string("false")
                    ])
                )
            }

            return MCPJSONRPCResponse(
                id: request.id,
                result: .object([
                    "protocolVersion": .string(MCPProtocolVersion.v2025_11_25.rawValue)
                ])
            )
        }
        let client = MCPClient(serverID: "invalid-is-error", transport: transport)

        do {
            _ = try await client.callTool(name: "read_status", arguments: [:])
            XCTFail("non-boolean tools/call isError should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "invalid-is-error",
                    method: "tools/call",
                    reason: "result.isError must be a boolean when present."
                )
            )
        }
    }

    func testClientRejectsNonStringToolCallTextContent() async throws {
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/call" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([
                            .object([
                                "type": .string("text"),
                                "text": .number(42)
                            ])
                        ])
                    ])
                )
            }

            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "invalid-text-content", transport: transport)

        do {
            _ = try await client.callTool(name: "read_status", arguments: [:])
            XCTFail("non-string text content should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "invalid-text-content",
                    method: "tools/call",
                    reason: "Content entry text must be a string when present."
                )
            )
        }
    }

    func testToolsListParsesStructuredOutputSchema() async throws {
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("read_status"),
                                "description": .string("Read structured project status."),
                                "inputSchema": .object(["type": .string("object")]),
                                "outputSchema": .object([
                                    "type": .string("object"),
                                    "properties": .object([
                                        "status": .object(["type": .string("string")])
                                    ]),
                                    "required": .array([.string("status")])
                                ])
                            ])
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "structured", transport: transport)

        let tools = try await client.listTools()

        XCTAssertEqual(tools.first?.outputSchema?["type"], .string("object"))
        XCTAssertEqual(tools.first?.outputSchema?["required"], .array([.string("status")]))
    }

    func testToolsListRejectsMalformedOutputSchema() async throws {
        let cases: [(schema: JSONValue, expectedReason: String)] = [
            (
                .string("not-an-object"),
                "Tool entry outputSchema must be an object when present."
            ),
            (
                .object([
                    "type": .string("array")
                ]),
                "Tool entry outputSchema.type must be \"object\" when present."
            ),
            (
                .object([
                    "type": .string("object"),
                    "required": .array([.number(42)])
                ]),
                "Tool entry outputSchema.required must be an array of strings."
            ),
            (
                .object([
                    "$schema": .number(42),
                    "type": .string("object")
                ]),
                "Tool entry outputSchema.$schema must be a string when present."
            ),
            (
                .object([
                    "type": .string("object"),
                    "properties": .array([])
                ]),
                "Tool entry outputSchema.properties must be an object."
            ),
            (
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "status": .string("not-a-schema")
                    ])
                ]),
                "Tool entry outputSchema.properties.status must be an object."
            )
        ]

        for testCase in cases {
            let transport = RecordingMCPTransport { request in
                if request.method == "tools/list" {
                    return MCPJSONRPCResponse(
                        id: request.id,
                        result: .object([
                            "tools": .array([
                                .object([
                                    "name": .string("read_status"),
                                    "description": .string("Malformed output schema."),
                                    "inputSchema": .object(["type": .string("object")]),
                                    "outputSchema": testCase.schema
                                ])
                            ])
                        ])
                    )
                }
                return MCPJSONRPCResponse(id: request.id, result: .object([:]))
            }
            let client = MCPClient(serverID: "structured", transport: transport)

            do {
                _ = try await client.listTools()
                XCTFail("malformed outputSchema should fail")
            } catch let error as MCPClientError {
                XCTAssertEqual(
                    error,
                    .invalidResponse(serverID: "structured", method: "tools/list", reason: testCase.expectedReason)
                )
            }
        }
    }

    @MainActor
    func testExternalMCPSettingsViewModelPersistsRegistration() throws {
        let store = InMemoryMCPServerRegistrationStore()
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        viewModel.updateDisplayName("Local Files")
        viewModel.updateCommand("/usr/bin/env")
        viewModel.updateArgumentsText("node server.js")
        viewModel.updateWorkingDirectory("/tmp")
        viewModel.updateEnabled(true)
        viewModel.save()

        let saved = try XCTUnwrap(try store.loadRegistrations().first)
        XCTAssertEqual(saved.displayName, "Local Files")
        XCTAssertEqual(saved.command, "/usr/bin/env")
        XCTAssertEqual(saved.arguments, ["node", "server.js"])
        XCTAssertEqual(saved.workingDirectory, "/tmp")
        XCTAssertTrue(saved.isEnabled)
    }

    @MainActor
    func testExternalMCPSettingsViewModelKeepsAuditLoadErrorSeparateFromEmptyAuditRows() throws {
        let store = InMemoryMCPServerRegistrationStore()
        let viewModel = ExternalMCPSettingsViewModel(
            store: store,
            auditRows: [],
            auditErrorMessage: "MCP audit history is unavailable because audit logging could not be opened."
        )

        XCTAssertTrue(viewModel.auditRows.isEmpty)
        XCTAssertEqual(viewModel.auditErrorMessage, "MCP audit history is unavailable because audit logging could not be opened.")

        viewModel.refresh()

        XCTAssertEqual(viewModel.auditErrorMessage, "MCP audit history is unavailable because audit logging could not be opened.")
    }

    @MainActor
    func testExternalMCPSettingsViewModelKeepsCurrentRegistrationWhenRefreshFails() throws {
        let registration = MCPServerRegistration(
            id: "local",
            displayName: "Local MCP",
            command: "/usr/bin/env",
            arguments: ["node", "server.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let store = ToggleFailingMCPServerRegistrationStore(registrations: [registration])
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        store.shouldFailLoads = true
        viewModel.refresh()

        XCTAssertEqual(viewModel.registration, registration)
        XCTAssertEqual(viewModel.errorMessage, "MCP registrations could not be loaded from the local database.")
    }

    @MainActor
    func testExternalMCPSettingsViewModelReportsStoreSaveFailureWithoutInternalErrorName() throws {
        let store = ToggleFailingMCPServerRegistrationStore(registrations: [])
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        viewModel.updateDisplayName("Local MCP")
        viewModel.updateCommand("/usr/bin/env")
        viewModel.updateEnabled(true)

        store.shouldFailSaves = true
        viewModel.save()

        XCTAssertEqual(viewModel.errorMessage, "MCP registrations could not be saved to the local database.")
        XCTAssertEqual(try store.loadRegistrations(), [])
    }

    @MainActor
    func testExternalMCPSettingsViewModelRejectsInvalidCommandBeforeSaving() throws {
        let store = InMemoryMCPServerRegistrationStore()
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        viewModel.updateDisplayName("Local Files")
        viewModel.updateCommand("  ")
        viewModel.updateEnabled(true)
        viewModel.save()

        XCTAssertEqual(viewModel.errorMessage, "MCP command is required.")
        XCTAssertEqual(try store.loadRegistrations(), [])
    }

    @MainActor
    func testExternalMCPSettingsViewModelRejectsMissingWorkingDirectoryBeforeSaving() throws {
        let store = InMemoryMCPServerRegistrationStore()
        let viewModel = ExternalMCPSettingsViewModel(store: store)
        let missingDirectory = try temporaryDirectory().appendingPathComponent("missing")

        viewModel.updateDisplayName("Local Files")
        viewModel.updateCommand("/usr/bin/env")
        viewModel.updateWorkingDirectory(missingDirectory.path)
        viewModel.updateEnabled(true)
        viewModel.save()

        XCTAssertEqual(viewModel.errorMessage, "MCP working directory was not found: \(missingDirectory.path)")
        XCTAssertEqual(try store.loadRegistrations(), [])
    }

    @MainActor
    func testExternalMCPSettingsViewModelSavePreservesOtherPersistedRegistrations() throws {
        let first = MCPServerRegistration(
            id: "first",
            displayName: "First MCP",
            command: "/usr/bin/env",
            arguments: ["node", "first.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let second = MCPServerRegistration(
            id: "second",
            displayName: "Second MCP",
            command: "/usr/bin/env",
            arguments: ["node", "second.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: false
        )
        let store = InMemoryMCPServerRegistrationStore(registrations: [first, second])
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        viewModel.updateDisplayName("Updated First MCP")
        viewModel.save()

        let saved = try store.loadRegistrations()
        XCTAssertEqual(saved.map(\.id), ["first", "second"])
        XCTAssertEqual(saved.first?.displayName, "Updated First MCP")
        XCTAssertEqual(saved.last, second)
    }

    @MainActor
    func testExternalMCPSettingsViewModelUsesRowLevelCrudForSaveAndDelete() throws {
        let persisted = MCPServerRegistration(
            id: "first",
            displayName: "First MCP",
            command: "/usr/bin/env",
            arguments: ["node", "first.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let store = RowLevelOnlyMCPServerRegistrationStore(registrations: [persisted])
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        viewModel.updateDisplayName("Updated First MCP")
        viewModel.save()

        XCTAssertEqual(try store.loadRegistrations().first?.displayName, "Updated First MCP")
        XCTAssertEqual(store.savedRegistrationIDs, ["first"])
        XCTAssertEqual(store.wholeTableSaveCount, 0)

        viewModel.deleteRegistration()

        XCTAssertEqual(try store.loadRegistrations(), [])
        XCTAssertEqual(store.deletedRegistrationIDs, ["first"])
        XCTAssertEqual(store.wholeTableSaveCount, 0)
    }

    @MainActor
    func testExternalMCPSettingsViewModelSelectsPersistedRegistration() throws {
        let first = MCPServerRegistration(
            id: "first",
            displayName: "First MCP",
            command: "/usr/bin/env",
            arguments: ["node", "first.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let second = MCPServerRegistration(
            id: "second",
            displayName: "Second MCP",
            command: "/usr/bin/env",
            arguments: ["node", "second.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: false
        )
        let store = InMemoryMCPServerRegistrationStore(registrations: [first, second])
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        XCTAssertEqual(viewModel.registrationRows.map(\.id), ["first", "second"])
        XCTAssertEqual(viewModel.selectedRegistrationID, "first")

        viewModel.selectRegistration(id: "second")

        XCTAssertEqual(viewModel.selectedRegistrationID, "second")
        XCTAssertEqual(viewModel.registration, second)
        XCTAssertEqual(viewModel.argumentsText, "node second.js")
    }

    @MainActor
    func testExternalMCPSettingsViewModelCreatesNewRegistrationDraftWithoutDroppingExisting() throws {
        let existing = MCPServerRegistration(
            id: "custom-mcp",
            displayName: "First MCP",
            command: "/usr/bin/env",
            arguments: ["node", "first.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let store = InMemoryMCPServerRegistrationStore(registrations: [existing])
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        viewModel.createRegistration()

        XCTAssertEqual(viewModel.registration.displayName, "Custom MCP")
        XCTAssertEqual(viewModel.registration.id, "custom-mcp-2")
        XCTAssertEqual(try store.loadRegistrations(), [existing])

        viewModel.updateDisplayName("Local Docs MCP")
        viewModel.updateCommand("/usr/bin/env")
        viewModel.updateArgumentsText("node docs-server.js")
        viewModel.updateEnabled(true)
        viewModel.save()

        let saved = try store.loadRegistrations()
        XCTAssertEqual(saved.map(\.id), [existing.id, viewModel.registration.id])
        XCTAssertEqual(saved.map(\.displayName), ["First MCP", "Local Docs MCP"])
        XCTAssertEqual(viewModel.registrationRows.map(\.displayName), ["First MCP", "Local Docs MCP"])
        XCTAssertEqual(viewModel.selectedRegistrationID, viewModel.registration.id)
    }

    @MainActor
    func testExternalMCPSettingsViewModelParsesQuotedArgumentsWithoutBreakingSpacePaths() throws {
        let store = InMemoryMCPServerRegistrationStore()
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        viewModel.updateArgumentsText(#"node "/Users/me/MCP Servers/server.js" --label 'Alpha Project'"#)

        XCTAssertEqual(viewModel.registration.arguments, [
            "node",
            "/Users/me/MCP Servers/server.js",
            "--label",
            "Alpha Project"
        ])
        XCTAssertEqual(viewModel.argumentsText, #"node '/Users/me/MCP Servers/server.js' --label 'Alpha Project'"#)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testExternalMCPSettingsViewModelKeepsExistingArgumentsWhenQuotedInputIsInvalid() throws {
        let store = InMemoryMCPServerRegistrationStore()
        let viewModel = ExternalMCPSettingsViewModel(store: store)
        viewModel.updateArgumentsText("node server.js")

        viewModel.updateArgumentsText(#"node "unterminated path"#)

        XCTAssertEqual(viewModel.registration.arguments, ["node", "server.js"])
        XCTAssertEqual(viewModel.errorMessage, "MCP arguments are invalid: missing closing double quote.")
    }

    @MainActor
    func testExternalMCPSettingsViewModelEditsKeychainEnvironmentReferencesWithoutRawSecrets() throws {
        let store = InMemoryMCPServerRegistrationStore()
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        viewModel.updateDisplayName("GitHub MCP")
        viewModel.updateCommand("/usr/bin/env")
        viewModel.updateEnvironmentText("GITHUB_TOKEN=keychain:github_token")
        viewModel.updateEnabled(true)
        viewModel.save()

        let saved = try XCTUnwrap(try store.loadRegistrations().first)
        XCTAssertEqual(saved.environment, ["GITHUB_TOKEN": .keychain(.githubToken)])
        XCTAssertEqual(viewModel.environmentText, "GITHUB_TOKEN=keychain:github_token")
        let rows = viewModel.display.environmentRows
        XCTAssertEqual(rows, [
            MCPEnvironmentDisplayRow(name: "GITHUB_TOKEN", sourceLabel: "Keychain: github_token")
        ])

        viewModel.updateEnvironmentText("GITHUB_TOKEN=ghp_raw_secret")

        XCTAssertEqual(viewModel.environmentText, "GITHUB_TOKEN=ghp_raw_secret")
        XCTAssertEqual(viewModel.registration.environment, ["GITHUB_TOKEN": .keychain(.githubToken)])
        XCTAssertEqual(
            viewModel.errorMessage,
            "MCP environment values must reference Keychain entries using keychain:<secret_key>."
        )

        viewModel.save()

        XCTAssertEqual(try store.loadRegistrations().first?.environment, ["GITHUB_TOKEN": .keychain(.githubToken)])
        XCTAssertEqual(
            viewModel.errorMessage,
            "MCP environment values must reference Keychain entries using keychain:<secret_key>."
        )
    }

    func testSQLiteMCPRegistrationStorePersistsRegistrationsWithoutRawSecrets() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteMCPServerRegistrationStore(connection: connection)
        let registrations = [
            MCPServerRegistration(
                id: "git'hub",
                displayName: "Owner's GitHub MCP",
                command: "/usr/bin/env",
                arguments: ["node", "owner's server.js"],
                environment: ["GITHUB_TOKEN": .keychain(.githubToken)],
                workingDirectory: "/repo/owner's workspace",
                isEnabled: true
            ),
            MCPServerRegistration(
                id: "local",
                displayName: "Local MCP",
                command: "/usr/bin/env",
                arguments: ["python", "server.py"],
                environment: [:],
                workingDirectory: nil,
                isEnabled: false
            )
        ]

        try store.saveRegistrations(registrations)

        XCTAssertEqual(try store.loadRegistrations(), registrations)
        let rows = try connection.queryRows("SELECT environment_json FROM mcp_server_registrations ORDER BY sort_order ASC;")
        XCTAssertEqual(rows.first?["environment_json"]?.contains("github_token"), true)
        XCTAssertEqual(rows.first?["environment_json"]?.contains("actual-token-value"), false)

        try store.saveRegistrations([])

        XCTAssertEqual(try store.loadRegistrations(), [])
    }

    func testSQLiteMCPRegistrationStoreSurvivesDatabaseReopen() throws {
        let databaseURL = try temporaryDirectory().appendingPathComponent("SoloPM.sqlite")
        let registration = MCPServerRegistration(
            id: "local",
            displayName: "Local MCP",
            command: "/usr/bin/env",
            arguments: ["python", "server.py"],
            environment: [:],
            workingDirectory: "/tmp",
            isEnabled: true
        )

        do {
            let connection = try SQLiteConnection(path: databaseURL.path)
            try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
            try SQLiteMCPServerRegistrationStore(connection: connection).saveRegistrations([registration])
        }

        do {
            let reopenedConnection = try SQLiteConnection(path: databaseURL.path)
            try SQLiteMigrationRunner.migrate(connection: reopenedConnection, migrations: CoreMigrations.current)

            XCTAssertEqual(try SQLiteMCPServerRegistrationStore(connection: reopenedConnection).loadRegistrations(), [registration])
        }
    }

    func testSQLiteMCPRegistrationStoreUpsertsSingleRegistrationWithoutRewritingOtherRows() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteMCPServerRegistrationStore(connection: connection)
        let first = MCPServerRegistration(
            id: "first",
            displayName: "First MCP",
            command: "/usr/bin/env",
            arguments: ["node", "first.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let second = MCPServerRegistration(
            id: "second",
            displayName: "Second MCP",
            command: "/usr/bin/env",
            arguments: ["node", "second.js"],
            environment: ["SECOND_TOKEN": .keychain(.githubToken)],
            workingDirectory: "/tmp",
            isEnabled: false
        )
        try store.saveRegistrations([first, second])

        let updatedFirst = MCPServerRegistration(
            id: "first",
            displayName: "Updated First MCP",
            command: "/usr/bin/env",
            arguments: ["python3", "first.py"],
            environment: ["FIRST_TOKEN": .keychain(.openAIAPIKey)],
            workingDirectory: "/tmp",
            isEnabled: false
        )
        try store.saveRegistration(updatedFirst)

        XCTAssertEqual(try store.loadRegistrations(), [updatedFirst, second])

        let third = MCPServerRegistration(
            id: "third",
            displayName: "Third MCP",
            command: "/usr/bin/env",
            arguments: ["ruby", "third.rb"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        try store.saveRegistration(third)

        XCTAssertEqual(try store.loadRegistrations(), [updatedFirst, second, third])
    }

    func testSQLiteMCPRegistrationStoreDeletesSingleRegistrationWithoutTouchingOthers() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteMCPServerRegistrationStore(connection: connection)
        let first = MCPServerRegistration(
            id: "first",
            displayName: "First MCP",
            command: "/usr/bin/env",
            arguments: ["node", "first.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let second = MCPServerRegistration(
            id: "second",
            displayName: "Second MCP",
            command: "/usr/bin/env",
            arguments: ["node", "second.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        try store.saveRegistrations([first, second])

        try store.deleteRegistration(id: "first")

        XCTAssertEqual(try store.loadRegistrations(), [second])

        try store.deleteRegistration(id: "missing")

        XCTAssertEqual(try store.loadRegistrations(), [second])
    }

    @MainActor
    func testExternalMCPSettingsViewModelDeletesPersistedRegistration() throws {
        let store = InMemoryMCPServerRegistrationStore(registrations: [
            MCPServerRegistration(
                id: "local",
                displayName: "Local MCP",
                command: "/usr/bin/env",
                arguments: ["node", "server.js"],
                environment: [:],
                workingDirectory: "/tmp",
                isEnabled: true
            )
        ])
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        viewModel.deleteRegistration()

        XCTAssertEqual(try store.loadRegistrations(), [])
        XCTAssertEqual(viewModel.registration.displayName, "Custom MCP")
        XCTAssertEqual(viewModel.registration.command, "")
        XCTAssertEqual(viewModel.toolRows, [])
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testExternalMCPSettingsViewModelDeleteRemovesOnlyCurrentRegistration() throws {
        let first = MCPServerRegistration(
            id: "first",
            displayName: "First MCP",
            command: "/usr/bin/env",
            arguments: ["node", "first.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let second = MCPServerRegistration(
            id: "second",
            displayName: "Second MCP",
            command: "/usr/bin/env",
            arguments: ["node", "second.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let store = InMemoryMCPServerRegistrationStore(registrations: [first, second])
        let viewModel = ExternalMCPSettingsViewModel(store: store)

        viewModel.deleteRegistration()

        XCTAssertEqual(try store.loadRegistrations(), [second])
        XCTAssertEqual(viewModel.registration, second)
        XCTAssertEqual(viewModel.toolRows, [])
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testExternalMCPSettingsViewModelChecksConnectionAndRefreshesToolCatalog() async throws {
        let registration = MCPServerRegistration(
            id: "fake",
            displayName: "Fake MCP",
            command: "node",
            arguments: ["server.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let store = InMemoryMCPServerRegistrationStore(registrations: [registration])
        let transport = ExternalMCPTestKit.makeFakeServerTransport()
        let launcher = MCPStdioServerLauncher(
            validator: MCPServerRegistrationValidator(binaryLocator: StaticBinaryLocator(availableCommands: ["node"])),
            transportFactory: { _ in transport }
        )
        let viewModel = ExternalMCPSettingsViewModel(store: store, launcher: launcher)

        XCTAssertEqual(viewModel.protocolVersionLabel, "Not checked")

        await viewModel.checkConnection()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isCheckingConnection)
        XCTAssertEqual(viewModel.protocolVersionLabel, "2025-11-25")
        XCTAssertEqual(viewModel.connectionCheckResultLabel, "Connected")
        XCTAssertNil(viewModel.connectionFailureTaxonomyLabel)
        XCTAssertEqual(viewModel.toolRows.map(\.toolName), ["danger_delete", "invalid_response", "read_status", "slow_tool", "write_issue"])
        XCTAssertEqual(viewModel.toolRows.first { $0.toolName == "read_status" }?.serverName, "Fake MCP")
        XCTAssertEqual(transport.recordedMethods, ["initialize", "notifications/initialized", "tools/list"])
    }

    @MainActor
    func testExternalMCPSettingsViewModelChecksSpecificRegistrationFromInlineRow() async throws {
        let first = MCPServerRegistration(
            id: "first",
            displayName: "First MCP",
            command: "node",
            arguments: ["first.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let second = MCPServerRegistration(
            id: "second",
            displayName: "Second MCP",
            command: "node",
            arguments: ["second.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let store = InMemoryMCPServerRegistrationStore(registrations: [first, second])
        let checkedRegistrationRecorder = CheckedMCPRegistrationRecorder()
        let launcher = MCPStdioServerLauncher(
            validator: MCPServerRegistrationValidator(binaryLocator: StaticBinaryLocator(availableCommands: ["node"])),
            transportFactory: { registration in
                checkedRegistrationRecorder.record(registration.id)
                return ExternalMCPTestKit.makeFakeServerTransport()
            }
        )
        let viewModel = ExternalMCPSettingsViewModel(store: store, launcher: launcher)

        XCTAssertEqual(viewModel.registrationRows.map(\.connectionCheckResultLabel), ["Not checked", "Not checked"])
        XCTAssertEqual(viewModel.registrationRows.map(\.isSelected), [true, false])

        await viewModel.checkConnection(id: "second")

        XCTAssertEqual(checkedRegistrationRecorder.recordedIDs, ["second"])
        XCTAssertEqual(viewModel.selectedRegistrationID, "second")
        XCTAssertEqual(viewModel.connectionCheckResultLabel, "Connected")
        XCTAssertEqual(viewModel.registrationRows.map(\.id), ["first", "second"])
        XCTAssertEqual(viewModel.registrationRows.map(\.connectionCheckResultLabel), ["Not checked", "Connected"])
        XCTAssertEqual(viewModel.registrationRows.map(\.isSelected), [false, true])
        XCTAssertEqual(viewModel.toolRows.first { $0.toolName == "read_status" }?.serverName, "Second MCP")
    }

    @MainActor
    func testExternalMCPSettingsViewModelKeepsSelectedDetailsWhenInlineCheckCompletesAfterSelectionChanges() async throws {
        let first = MCPServerRegistration(
            id: "first",
            displayName: "First MCP",
            command: "node",
            arguments: ["first.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let second = MCPServerRegistration(
            id: "second",
            displayName: "Second MCP",
            command: "node",
            arguments: ["second.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let store = InMemoryMCPServerRegistrationStore(registrations: [first, second])
        let gatedSecondTransport = GatedMCPListTransport()
        let launcher = MCPStdioServerLauncher(
            validator: MCPServerRegistrationValidator(binaryLocator: StaticBinaryLocator(availableCommands: ["node"])),
            transportFactory: { registration in
                if registration.id == "second" {
                    return gatedSecondTransport
                }
                return ExternalMCPTestKit.makeFakeServerTransport()
            }
        )
        let viewModel = ExternalMCPSettingsViewModel(store: store, launcher: launcher)

        let checkTask = Task {
            await viewModel.checkConnection(id: "second")
        }
        await gatedSecondTransport.waitForListRequest()
        viewModel.selectRegistration(id: "first")
        gatedSecondTransport.releaseListResponse()
        await checkTask.value

        XCTAssertEqual(viewModel.selectedRegistrationID, "first")
        XCTAssertEqual(viewModel.connectionCheckResultLabel, "Not checked")
        XCTAssertEqual(viewModel.protocolVersionLabel, "Not checked")
        XCTAssertEqual(viewModel.toolRows, [])
        XCTAssertEqual(viewModel.registrationRows.map(\.id), ["first", "second"])
        XCTAssertEqual(viewModel.registrationRows.map(\.connectionCheckResultLabel), ["Not checked", "Connected"])
        XCTAssertEqual(viewModel.registrationRows.map(\.isSelected), [true, false])
    }

    @MainActor
    func testExternalMCPSettingsViewModelDoesNotCheckCurrentServerForMissingInlineRowID() async throws {
        let registration = MCPServerRegistration(
            id: "first",
            displayName: "First MCP",
            command: "node",
            arguments: ["first.js"],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let store = InMemoryMCPServerRegistrationStore(registrations: [registration])
        let checkedRegistrationRecorder = CheckedMCPRegistrationRecorder()
        let launcher = MCPStdioServerLauncher(
            validator: MCPServerRegistrationValidator(binaryLocator: StaticBinaryLocator(availableCommands: ["node"])),
            transportFactory: { registration in
                checkedRegistrationRecorder.record(registration.id)
                return ExternalMCPTestKit.makeFakeServerTransport()
            }
        )
        let viewModel = ExternalMCPSettingsViewModel(store: store, launcher: launcher)

        await viewModel.checkConnection(id: "missing")

        XCTAssertEqual(viewModel.errorMessage, "MCP registration was not found.")
        XCTAssertEqual(checkedRegistrationRecorder.recordedIDs, [])
        XCTAssertEqual(viewModel.connectionCheckResultLabel, "Not checked")
        XCTAssertEqual(viewModel.registrationRows.map(\.connectionCheckResultLabel), ["Not checked"])
    }

    @MainActor
    func testExternalMCPSettingsViewModelReportsDisabledAndMissingBinary() async throws {
        let disabledStore = InMemoryMCPServerRegistrationStore(registrations: [
            MCPServerRegistration(
                id: "disabled",
                displayName: "Disabled MCP",
                command: "node",
                arguments: [],
                environment: [:],
                workingDirectory: nil,
                isEnabled: false
            )
        ])
        let launcher = MCPStdioServerLauncher(
            validator: MCPServerRegistrationValidator(binaryLocator: StaticBinaryLocator(availableCommands: ["node"])),
            transportFactory: { _ in ExternalMCPTestKit.makeFakeServerTransport() }
        )
        let disabledViewModel = ExternalMCPSettingsViewModel(store: disabledStore, launcher: launcher)

        await disabledViewModel.checkConnection()

        XCTAssertEqual(disabledViewModel.errorMessage, "MCP server is disabled.")
        XCTAssertEqual(disabledViewModel.connectionCheckResultLabel, "Failed")
        XCTAssertNil(disabledViewModel.connectionFailureTaxonomyLabel)
        XCTAssertTrue(disabledViewModel.toolRows.isEmpty)

        let missingStore = InMemoryMCPServerRegistrationStore(registrations: [
            MCPServerRegistration(
                id: "missing",
                displayName: "Missing MCP",
                command: "missing-node",
                arguments: [],
                environment: [:],
                workingDirectory: nil,
                isEnabled: true
            )
        ])
        let missingViewModel = ExternalMCPSettingsViewModel(store: missingStore, launcher: launcher)

        await missingViewModel.checkConnection()

        XCTAssertEqual(missingViewModel.errorMessage, "MCP command binary was not found: missing-node")
        XCTAssertEqual(missingViewModel.connectionCheckResultLabel, "Failed")
        XCTAssertNil(missingViewModel.connectionFailureTaxonomyLabel)
        XCTAssertTrue(missingViewModel.toolRows.isEmpty)
    }

    @MainActor
    func testExternalMCPSettingsViewModelReportsInvalidToolsList() async throws {
        let registration = MCPServerRegistration(
            id: "fake",
            displayName: "Fake MCP",
            command: "node",
            arguments: [],
            environment: [:],
            workingDirectory: nil,
            isEnabled: true
        )
        let store = InMemoryMCPServerRegistrationStore(registrations: [registration])
        let launcher = MCPStdioServerLauncher(
            validator: MCPServerRegistrationValidator(binaryLocator: StaticBinaryLocator(availableCommands: ["node"])),
            transportFactory: { _ in ExternalMCPTestKit.makeInvalidListTransport() }
        )
        let viewModel = ExternalMCPSettingsViewModel(store: store, launcher: launcher)

        await viewModel.checkConnection()

        XCTAssertEqual(viewModel.errorMessage, "[invalid-schema] MCP tools/list response was invalid: Missing result.tools array.")
        XCTAssertEqual(viewModel.connectionFailureTaxonomyLabel, "invalid-schema")
        XCTAssertEqual(viewModel.connectionCheckResultLabel, "Failed: invalid-schema")
        XCTAssertEqual(viewModel.protocolVersionLabel, "2025-11-25")
        XCTAssertTrue(viewModel.toolRows.isEmpty)
    }

    @MainActor
    func testExternalMCPSettingsViewModelDisplaysInspectorFailureTaxonomy() async throws {
        let cases: [(name: String, transport: RecordingMCPTransport, taxonomy: String)] = [
            (
                "malformed-json",
                ExternalMCPTestKit.makeMalformedJSONTransport(),
                "malformed-json"
            ),
            (
                "mismatched-id",
                ExternalMCPTestKit.makeMismatchedIDTransport(),
                "mismatched-id"
            ),
            (
                "invalid-schema",
                ExternalMCPTestKit.makeInvalidToolSchemaTransport(),
                "invalid-schema"
            ),
            (
                "timeout",
                ExternalMCPTestKit.makeListTimeoutTransport(),
                "timeout"
            )
        ]

        for testCase in cases {
            let registration = MCPServerRegistration(
                id: "fake-\(testCase.name)",
                displayName: "Fake MCP",
                command: "node",
                arguments: [],
                environment: [:],
                workingDirectory: nil,
                isEnabled: true
            )
            let store = InMemoryMCPServerRegistrationStore(registrations: [registration])
            let launcher = MCPStdioServerLauncher(
                validator: MCPServerRegistrationValidator(binaryLocator: StaticBinaryLocator(availableCommands: ["node"])),
                transportFactory: { _ in testCase.transport }
            )
            let viewModel = ExternalMCPSettingsViewModel(store: store, launcher: launcher)

            await viewModel.checkConnection()

            XCTAssertEqual(viewModel.connectionFailureTaxonomyLabel, testCase.taxonomy, testCase.name)
            XCTAssertEqual(viewModel.connectionCheckResultLabel, "Failed: \(testCase.taxonomy)", testCase.name)
            XCTAssertTrue(viewModel.errorMessage?.contains("[\(testCase.taxonomy)]") == true, testCase.name)
            XCTAssertTrue(viewModel.toolRows.isEmpty, testCase.name)
        }
    }

    func testPermissionMappingDisablesUnknownAndBlocksDangerousTools() throws {
        let registry = ExternalMCPToolRegistry(
            server: MCPRegisteredServerDescriptor(id: "fake", displayName: "Fake MCP"),
            tools: ExternalMCPTestKit.fakeToolDefinitions(),
            classifier: ExternalMCPToolClassifier(explicitPolicies: [
                "read_status": .read,
                "write_issue": .writeWithApproval,
                "danger_delete": .dangerous
            ])
        )

        XCTAssertEqual(try registry.descriptor(named: "read_status").origin, .externalMCP(serverID: "fake", toolName: "read_status"))
        XCTAssertEqual(try registry.descriptor(named: "read_status").permissionLevel, .read)
        XCTAssertEqual(try registry.descriptor(named: "write_issue").permissionLevel, .writeWithApproval)
        XCTAssertEqual(try registry.descriptor(named: "danger_delete").permissionLevel, .dangerous)
        XCTAssertEqual(try registry.descriptor(named: "slow_tool").permissionLevel, .disabled)
        let catalogRows = ExternalMCPToolCatalog.rows(from: registry.allDescriptors)
        XCTAssertEqual(catalogRows.map(\.toolName), ["danger_delete", "invalid_response", "read_status", "slow_tool", "write_issue"])
        XCTAssertEqual(catalogRows.first { $0.toolName == "read_status" }?.title, "Read Status")
        XCTAssertEqual(catalogRows.first { $0.toolName == "read_status" }?.permissionLabel, "Read")
        XCTAssertEqual(catalogRows.first { $0.toolName == "write_issue" }?.permissionLabel, "Write with approval")
        XCTAssertEqual(catalogRows.first { $0.toolName == "slow_tool" }?.permissionLabel, "Disabled")
        XCTAssertTrue(catalogRows.first { $0.toolName == "write_issue" }?.requiresApproval ?? false)
        XCTAssertTrue(catalogRows.first { $0.toolName == "read_status" }?.inputSchemaSummary.contains("project") ?? false)

        XCTAssertThrowsError(try registry.assertExecutable(toolName: "danger_delete", context: ToolExecutionContext(source: .developerTool))) { error in
            XCTAssertEqual(error as? ExternalMCPExecutionError, .dangerousToolBlocked(serverID: "fake", toolName: "danger_delete"))
        }
        XCTAssertThrowsError(try registry.assertExecutable(toolName: "slow_tool", context: ToolExecutionContext(source: .developerTool))) { error in
            XCTAssertEqual(error as? ExternalMCPExecutionError, .toolDisabled(serverID: "fake", toolName: "slow_tool"))
        }
    }

    func testCatalogSummaryDoesNotHideMalformedRequiredSchema() {
        let descriptor = ExternalMCPToolDescriptor(
            origin: .externalMCP(serverID: "fake", toolName: "bad_required"),
            server: MCPRegisteredServerDescriptor(id: "fake", displayName: "Fake MCP"),
            definition: MCPToolDefinition(
                name: "bad_required",
                description: "Malformed schema",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object(["title": .object(["type": .string("string")])]),
                    "required": .array([.string("title"), .number(42)])
                ]
            ),
            permissionLevel: .read
        )

        let row = ExternalMCPToolCatalogRow(descriptor: descriptor)

        XCTAssertEqual(row.inputSchemaSummary, "Invalid schema: required must be an array of strings")
    }

    func testExecutionPreviewRedactsSecretsAndWriteRequiresApproval() async throws {
        let transport = ExternalMCPTestKit.makeFakeServerTransport()
        let executor = makeExecutor(transport: transport, policies: ["write_issue": .writeWithApproval])
        let arguments: [String: JSONValue] = [
            "title": .string("Bug"),
            "token": .string("redacted-github-token")
        ]

        let preview = try executor.preview(toolName: "write_issue", arguments: arguments)

        XCTAssertEqual(preview.serverID, "fake")
        XCTAssertEqual(preview.toolName, "write_issue")
        XCTAssertEqual(preview.permissionLevel, .writeWithApproval)
        XCTAssertTrue(preview.requiresApproval)
        XCTAssertFalse(preview.redactedArgumentSummary.contains("redacted-github-token"))
        XCTAssertTrue(preview.redactedArgumentSummary.contains("[REDACTED_SECRET]"))

        do {
            _ = try await executor.call(toolName: "write_issue", arguments: arguments, context: ToolExecutionContext(source: .developerTool))
            XCTFail("write MCP calls must require approval")
        } catch let error as ExternalMCPExecutionError {
            XCTAssertEqual(error, .approvalRequired(serverID: "fake", toolName: "write_issue"))
        }

        XCTAssertEqual(transport.recordedMethods, [])
    }

    func testExternalMCPExecutionRequiresPaidEntitlementBeforeToolCall() async throws {
        let logger = InMemoryAuditLogger()
        let transport = ExternalMCPTestKit.makeFakeServerTransport()
        let executor = makeExecutor(
            transport: transport,
            policies: ["read_status": .read],
            auditLogger: logger,
            entitlementStore: StaticMCPEntitlementStore(plan: .free)
        )

        do {
            _ = try await executor.call(
                toolName: "read_status",
                arguments: ["project": .string("soloPM")],
                context: ToolExecutionContext(source: .developerTool)
            )
            XCTFail("free plan must not execute external MCP tools")
        } catch let error as EntitlementError {
            XCTAssertEqual(error, .upgradeRequired(feature: .advancedMCPExecution, requiredPlan: .pro))
        }

        XCTAssertEqual(transport.recordedMethods, [])
        XCTAssertTrue(logger.recordedEvents.isEmpty)
    }

    func testPaidEntitlementDoesNotBypassDangerousOrApprovalGuards() async throws {
        let transport = ExternalMCPTestKit.makeFakeServerTransport()
        let executor = makeExecutor(
            transport: transport,
            policies: [
                "write_issue": .writeWithApproval,
                "danger_delete": .dangerous
            ],
            entitlementStore: StaticMCPEntitlementStore(plan: .pro)
        )

        do {
            _ = try await executor.call(
                toolName: "danger_delete",
                arguments: [:],
                context: ToolExecutionContext(approvalToken: ApprovalToken(id: "approved", sessionID: "session"), source: .developerTool)
            )
            XCTFail("paid entitlement must not make dangerous tools executable")
        } catch let error as ExternalMCPExecutionError {
            XCTAssertEqual(error, .dangerousToolBlocked(serverID: "fake", toolName: "danger_delete"))
        }

        do {
            _ = try await executor.call(
                toolName: "write_issue",
                arguments: ["title": .string("Bug")],
                context: ToolExecutionContext(source: .developerTool)
            )
            XCTFail("paid entitlement must not bypass write approval")
        } catch let error as ExternalMCPExecutionError {
            XCTAssertEqual(error, .approvalRequired(serverID: "fake", toolName: "write_issue"))
        }

        XCTAssertEqual(transport.recordedMethods, [])
    }

    func testExecutionPreviewRedactsSensitiveArgumentKeyEvenWhenValueHasSpaces() throws {
        let transport = ExternalMCPTestKit.makeFakeServerTransport()
        let executor = makeExecutor(transport: transport, policies: ["read_status": .read])
        let malformedSecret = "alpha beta gamma"

        let preview = try executor.preview(
            toolName: "read_status",
            arguments: [
                "api-key": .string(malformedSecret),
                "apiKey": .string(malformedSecret),
                "title": .string("Safe title")
            ]
        )

        XCTAssertFalse(preview.redactedArgumentSummary.contains("alpha"))
        XCTAssertFalse(preview.redactedArgumentSummary.contains("beta gamma"))
        XCTAssertTrue(preview.redactedArgumentSummary.contains("api-key=[REDACTED_SECRET]"))
        XCTAssertTrue(preview.redactedArgumentSummary.contains("apiKey=[REDACTED_SECRET]"))
        XCTAssertTrue(preview.redactedArgumentSummary.contains("title=string(\"Safe title\")"))
    }

    func testReadExecutionAuditsSuccessWithRedactedArguments() async throws {
        let logger = InMemoryAuditLogger()
        let transport = ExternalMCPTestKit.makeFakeServerTransport()
        let executor = makeExecutor(
            transport: transport,
            policies: ["read_status": .read],
            auditLogger: RedactingAuditLogger(base: logger)
        )

        let result = try await executor.call(
            toolName: "read_status",
            arguments: ["api_key": .string("redacted-test-secret")],
            context: ToolExecutionContext(source: .developerTool)
        )

        XCTAssertEqual(result.content.first?.text, "status: ok")
        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .succeeded])
        XCTAssertEqual(logger.recordedEvents.first?.category, "external_mcp")
        XCTAssertEqual(logger.recordedEvents.first?.metadata["server_id"], "fake")
        XCTAssertEqual(logger.recordedEvents.first?.metadata["server_name"], "Fake MCP")
        XCTAssertEqual(logger.recordedEvents.first?.metadata["tool_name"], "read_status")
        XCTAssertEqual(logger.recordedEvents.first?.metadata["risk"], "read")
        XCTAssertEqual(logger.recordedEvents.first?.metadata["permission"], "read")
        XCTAssertEqual(logger.recordedEvents.first?.metadata["approval"], "missing")
        XCTAssertEqual(logger.recordedEvents.first?.metadata["arguments"], "[REDACTED]")
        XCTAssertNotNil(logger.recordedEvents.last?.metadata["duration_ms"])
        XCTAssertEqual(logger.recordedEvents.last?.metadata["result"], "succeeded")
    }

    func testExternalMCPExecutionAcceptsStructuredContentMatchingOutputSchema() async throws {
        let logger = InMemoryAuditLogger()
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/call" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([
                            MCPContentItem(type: "text", text: "{\"status\":\"ok\",\"openTasks\":2}").jsonValue
                        ]),
                        "structuredContent": .object([
                            "status": .string("ok"),
                            "openTasks": .number(2)
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let executor = makeExecutor(
            transport: transport,
            policies: ["read_status": .read],
            auditLogger: logger,
            tools: [structuredReadStatusTool()]
        )

        let result = try await executor.call(
            toolName: "read_status",
            arguments: [:],
            context: ToolExecutionContext(source: .developerTool)
        )

        XCTAssertEqual(result.structuredContent?.objectValue?["status"], .string("ok"))
        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .succeeded])
        XCTAssertEqual(logger.recordedEvents.last?.metadata["result"], "succeeded")
    }

    func testExternalMCPExecutionRequiresStructuredContentWhenOutputSchemaProvided() async throws {
        let logger = InMemoryAuditLogger()
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/call" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([MCPContentItem(type: "text", text: "status: ok").jsonValue])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let executor = makeExecutor(
            transport: transport,
            policies: ["read_status": .read],
            auditLogger: logger,
            tools: [structuredReadStatusTool()]
        )

        do {
            _ = try await executor.call(
                toolName: "read_status",
                arguments: [:],
                context: ToolExecutionContext(source: .developerTool)
            )
            XCTFail("tools/call without structuredContent should fail when outputSchema exists")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "fake",
                    method: "tools/call",
                    reason: "Missing result.structuredContent for tool outputSchema."
                )
            )
        }

        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .failed])
        XCTAssertTrue(logger.recordedEvents.last?.metadata["error"]?.contains("Missing result.structuredContent") ?? false)
    }

    func testExternalMCPExecutionRejectsStructuredContentViolatingOutputSchema() async throws {
        let logger = InMemoryAuditLogger()
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/call" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([
                            MCPContentItem(type: "text", text: "{\"openTasks\":2}").jsonValue
                        ]),
                        "structuredContent": .object([
                            "openTasks": .number(2)
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let executor = makeExecutor(
            transport: transport,
            policies: ["read_status": .read],
            auditLogger: logger,
            tools: [structuredReadStatusTool()]
        )

        do {
            _ = try await executor.call(
                toolName: "read_status",
                arguments: [:],
                context: ToolExecutionContext(source: .developerTool)
            )
            XCTFail("structuredContent missing required output should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "fake",
                    method: "tools/call",
                    reason: "structuredContent missing required output field: status."
                )
            )
        }

        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .failed])
        XCTAssertTrue(logger.recordedEvents.last?.metadata["error"]?.contains("structuredContent missing required output field") ?? false)
    }

    func testExternalMCPExecutionRejectsStructuredContentTypeMismatch() async throws {
        let logger = InMemoryAuditLogger()
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/call" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([
                            MCPContentItem(type: "text", text: "{\"status\":42,\"openTasks\":2}").jsonValue
                        ]),
                        "structuredContent": .object([
                            "status": .number(42),
                            "openTasks": .number(2)
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let executor = makeExecutor(
            transport: transport,
            policies: ["read_status": .read],
            auditLogger: logger,
            tools: [structuredReadStatusTool()]
        )

        do {
            _ = try await executor.call(
                toolName: "read_status",
                arguments: [:],
                context: ToolExecutionContext(source: .developerTool)
            )
            XCTFail("structuredContent type mismatch should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "fake",
                    method: "tools/call",
                    reason: "structuredContent.status must match outputSchema type string."
                )
            )
        }

        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .failed])
    }

    func testExternalMCPExecutionSkipsOutputSchemaValidationForToolErrors() async throws {
        let logger = InMemoryAuditLogger()
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/call" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([MCPContentItem(type: "text", text: "Invalid input").jsonValue]),
                        "isError": .bool(true)
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let executor = makeExecutor(
            transport: transport,
            policies: ["read_status": .read],
            auditLogger: logger,
            tools: [structuredReadStatusTool()]
        )

        let result = try await executor.call(
            toolName: "read_status",
            arguments: [:],
            context: ToolExecutionContext(source: .developerTool)
        )

        XCTAssertTrue(result.isError)
        XCTAssertNil(result.structuredContent)
        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .succeeded])
        XCTAssertEqual(logger.recordedEvents.last?.metadata["result"], "tool_error")
    }

    func testReadExecutionAuditsSensitiveArgumentKeyEvenWhenValueHasSpaces() async throws {
        let logger = InMemoryAuditLogger()
        let transport = ExternalMCPTestKit.makeFakeServerTransport()
        let executor = makeExecutor(
            transport: transport,
            policies: ["read_status": .read],
            auditLogger: logger
        )
        let malformedSecret = "alpha beta gamma"

        _ = try await executor.call(
            toolName: "read_status",
            arguments: [
                "api-key": .string(malformedSecret),
                "apiKey": .string(malformedSecret),
                "title": .string("Safe title")
            ],
            context: ToolExecutionContext(source: .developerTool)
        )

        let arguments = try XCTUnwrap(logger.recordedEvents.first?.metadata["arguments"])
        XCTAssertFalse(arguments.contains("alpha"))
        XCTAssertFalse(arguments.contains("beta gamma"))
        XCTAssertTrue(arguments.contains("api-key=[REDACTED_SECRET]"))
        XCTAssertTrue(arguments.contains("apiKey=[REDACTED_SECRET]"))
        XCTAssertTrue(arguments.contains("title=string(\"Safe title\")"))
    }

    func testReadExecutionAuditsNoArgumentsExplicitly() async throws {
        let logger = InMemoryAuditLogger()
        let transport = ExternalMCPTestKit.makeFakeServerTransport()
        let executor = makeExecutor(
            transport: transport,
            policies: ["read_status": .read],
            auditLogger: RedactingAuditLogger(base: logger)
        )

        _ = try await executor.call(
            toolName: "read_status",
            arguments: [:],
            context: ToolExecutionContext(source: .developerTool)
        )

        XCTAssertEqual(logger.recordedEvents.first?.metadata["arguments"], "No arguments")
    }

    func testTimeoutKillsProcessAndAuditsFailure() async throws {
        let logger = InMemoryAuditLogger()
        let transport = ExternalMCPTestKit.makeHangingTransport()
        let processController = RecordingMCPProcessController()
        let executor = makeExecutor(
            client: MCPClient(serverID: "fake", transport: transport, timeout: 0.01),
            policies: ["read_status": .read],
            auditLogger: RedactingAuditLogger(base: logger),
            processController: processController
        )

        do {
            _ = try await executor.call(
                toolName: "read_status",
                arguments: [:],
                context: ToolExecutionContext(source: .developerTool)
            )
            XCTFail("timeout should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(error, .timeout(serverID: "fake", method: "tools/call"))
        }

        XCTAssertEqual(processController.killRequests, [.init(serverID: "fake", reason: .timeout)])
        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .failed])
        XCTAssertTrue(logger.recordedEvents.last?.metadata["error"]?.contains("timeout") ?? false)
    }

    func testProcessLifecycleManagerHandlesStartHealthCrashAndShutdown() async throws {
        let process = RecordingMCPServerProcess()
        let manager = MCPProcessLifecycleManager(serverID: "fake", process: process)

        try await manager.start()
        XCTAssertEqual(process.events, [.started])
        let runningState = await manager.healthCheck()
        XCTAssertEqual(runningState, .running)

        process.nextHealthCheck = false
        let crashedState = await manager.healthCheck()
        XCTAssertEqual(crashedState, .crashed)

        await manager.shutdown()
        XCTAssertEqual(process.events, [.started, .healthChecked, .healthChecked, .killed, .shutdown])
    }

    func testAuditHistoryRowsExposeExternalCallHistory() throws {
        let events = [
            AuditEvent(
                category: "external_mcp",
                action: "fake.read_status",
                status: .succeeded,
                metadata: [
                    "server_name": "Fake MCP",
                    "tool_name": "read_status",
                    "risk": "read",
                    "approval": "missing",
                    "duration_ms": "12",
                    "arguments": "[REDACTED_SECRET]"
                ]
            ),
            AuditEvent(
                category: "tool",
                action: "task.create",
                status: .succeeded
            )
        ]

        let rows = try ExternalMCPAuditHistory.rows(from: events)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.serverName, "Fake MCP")
        XCTAssertEqual(rows.first?.toolName, "read_status")
        XCTAssertEqual(rows.first?.status, .succeeded)
        XCTAssertEqual(rows.first?.redactedArgumentSummary, "[REDACTED_SECRET]")
        XCTAssertEqual(rows.first?.statusLabel, "Succeeded")
    }

    func testAuditHistoryAllowsStartedEventWithoutDurationOrError() throws {
        let events = [
            AuditEvent(
                category: "external_mcp",
                action: "fake.read_status",
                status: .started,
                metadata: [
                    "server_name": "Fake MCP",
                    "tool_name": "read_status",
                    "risk": "read",
                    "approval": "missing",
                    "arguments": "No arguments"
                ]
            )
        ]

        let rows = try ExternalMCPAuditHistory.rows(from: events)

        XCTAssertEqual(rows.first?.status, .started)
        XCTAssertNil(rows.first?.durationMilliseconds)
        XCTAssertNil(rows.first?.errorSummary)
    }

    func testAuditHistoryRejectsSucceededEventMissingDuration() {
        let events = [
            AuditEvent(
                category: "external_mcp",
                action: "fake.read_status",
                status: .succeeded,
                metadata: [
                    "server_name": "Fake MCP",
                    "tool_name": "read_status",
                    "risk": "read",
                    "approval": "missing",
                    "arguments": "No arguments"
                ]
            )
        ]

        XCTAssertThrowsError(try ExternalMCPAuditHistory.rows(from: events)) { error in
            XCTAssertEqual(error as? ExternalMCPAuditHistoryError, .missingMetadata("duration_ms"))
        }
    }

    func testAuditHistoryRejectsFailedEventMissingError() {
        let events = [
            AuditEvent(
                category: "external_mcp",
                action: "fake.read_status",
                status: .failed,
                metadata: [
                    "server_name": "Fake MCP",
                    "tool_name": "read_status",
                    "risk": "read",
                    "approval": "missing",
                    "duration_ms": "12",
                    "arguments": "No arguments"
                ]
            )
        ]

        XCTAssertThrowsError(try ExternalMCPAuditHistory.rows(from: events)) { error in
            XCTAssertEqual(error as? ExternalMCPAuditHistoryError, .missingMetadata("error"))
        }
    }

    func testAuditHistoryRejectsMissingRiskMetadataInsteadOfShowingUnknown() {
        let events = [
            AuditEvent(
                category: "external_mcp",
                action: "fake.read_status",
                status: .succeeded,
                metadata: [
                    "server_name": "Fake MCP",
                    "tool_name": "read_status",
                    "approval": "missing"
                ]
            )
        ]

        XCTAssertThrowsError(try ExternalMCPAuditHistory.rows(from: events)) { error in
            XCTAssertEqual(error as? ExternalMCPAuditHistoryError, .missingMetadata("risk"))
        }
    }

    func testAuditHistoryRejectsMissingArgumentsMetadataInsteadOfShowingBlankSummary() {
        let events = [
            AuditEvent(
                category: "external_mcp",
                action: "fake.read_status",
                status: .succeeded,
                metadata: [
                    "server_name": "Fake MCP",
                    "tool_name": "read_status",
                    "risk": "read",
                    "approval": "missing"
                ]
            )
        ]

        XCTAssertThrowsError(try ExternalMCPAuditHistory.rows(from: events)) { error in
            XCTAssertEqual(error as? ExternalMCPAuditHistoryError, .missingMetadata("arguments"))
        }
    }

    func testAuditHistoryRejectsMissingServerNameInsteadOfShowingGenericExternalMCP() {
        let events = [
            AuditEvent(
                category: "external_mcp",
                action: "fake.read_status",
                status: .succeeded,
                metadata: [
                    "tool_name": "read_status",
                    "risk": "read",
                    "approval": "missing",
                    "arguments": "No arguments"
                ]
            )
        ]

        XCTAssertThrowsError(try ExternalMCPAuditHistory.rows(from: events)) { error in
            XCTAssertEqual(error as? ExternalMCPAuditHistoryError, .missingMetadata("server_name"))
        }
    }

    func testAuditHistoryRejectsMissingToolNameInsteadOfFallingBackToAction() {
        let events = [
            AuditEvent(
                category: "external_mcp",
                action: "fake.read_status",
                status: .succeeded,
                metadata: [
                    "server_name": "Fake MCP",
                    "risk": "read",
                    "approval": "missing",
                    "arguments": "No arguments"
                ]
            )
        ]

        XCTAssertThrowsError(try ExternalMCPAuditHistory.rows(from: events)) { error in
            XCTAssertEqual(error as? ExternalMCPAuditHistoryError, .missingMetadata("tool_name"))
        }
    }

    func testInvalidJSONRPCResponseFailsWithoutCrashing() async throws {
        let client = MCPClient(serverID: "fake", transport: ExternalMCPTestKit.makeInvalidListTransport())

        do {
            _ = try await client.listTools()
            XCTFail("invalid response should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(error, .invalidResponse(serverID: "fake", method: "tools/list", reason: "Missing result.tools array."))
        }
    }

    func testToolsListRejectsInvalidToolInputSchema() async throws {
        let invalidSchemaTransport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("bad_schema"),
                                "description": .string("Malformed schema"),
                                "inputSchema": .string("not-an-object")
                            ])
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "fake", transport: invalidSchemaTransport)

        do {
            _ = try await client.listTools()
            XCTFail("invalid inputSchema should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(serverID: "fake", method: "tools/list", reason: "Tool entry inputSchema must be an object.")
            )
        }
    }

    func testToolsListRejectsInvalidToolNames() async throws {
        let cases: [(toolName: JSONValue, expectedReason: String)] = [
            (
                .string("bad tool"),
                "Tool entry name must use only ASCII letters, digits, underscore, hyphen, or dot."
            ),
            (
                .string(String(repeating: "a", count: 129)),
                "Tool entry name must be between 1 and 128 characters."
            ),
            (
                .number(42),
                "Tool entry missing name."
            )
        ]

        for testCase in cases {
            let transport = RecordingMCPTransport { request in
                if request.method == "tools/list" {
                    return MCPJSONRPCResponse(
                        id: request.id,
                        result: .object([
                            "tools": .array([
                                .object([
                                    "name": testCase.toolName,
                                    "description": .string("Invalid name."),
                                    "inputSchema": .object(["type": .string("object")])
                                ])
                            ])
                        ])
                    )
                }
                return MCPJSONRPCResponse(id: request.id, result: .object([:]))
            }
            let client = MCPClient(serverID: "fake", transport: transport)

            do {
                _ = try await client.listTools()
                XCTFail("invalid tool name should fail")
            } catch let error as MCPClientError {
                XCTAssertEqual(
                    error,
                    .invalidResponse(serverID: "fake", method: "tools/list", reason: testCase.expectedReason)
                )
            }
        }
    }

    func testToolsListRejectsDuplicateToolNamesAcrossPages() async throws {
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                let cursor = request.params?.objectValue?["cursor"]?.stringValue
                var result: [String: JSONValue] = [
                    "tools": .array([
                        .object([
                            "name": .string("read_status"),
                            "description": .string(cursor == nil ? "First page." : "Second page duplicate."),
                            "inputSchema": .object(["type": .string("object")])
                        ])
                    ])
                ]
                if cursor == nil {
                    result["nextCursor"] = .string("page-2")
                }
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object(result)
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "fake", transport: transport)

        do {
            _ = try await client.listTools()
            XCTFail("duplicate tool names should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    serverID: "fake",
                    method: "tools/list",
                    reason: "Duplicate tool name in tools/list response: read_status."
                )
            )
        }
        XCTAssertEqual(transport.recordedRequests.filter { $0.method == "tools/list" }.count, 2)
    }

    func testToolsListRequiresToolInputSchema() async throws {
        let missingSchemaTransport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("missing_schema"),
                                "description": .string("Missing schema")
                            ])
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "fake", transport: missingSchemaTransport)

        do {
            _ = try await client.listTools()
            XCTFail("missing inputSchema should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(serverID: "fake", method: "tools/list", reason: "Tool entry inputSchema is required.")
            )
        }
    }

    func testToolsListRequiresObjectRootInputSchemaType() async throws {
        let wrongRootTypeTransport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("wrong_root"),
                                "description": .string("Wrong root type"),
                                "inputSchema": .object([
                                    "type": .string("array")
                                ])
                            ])
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "fake", transport: wrongRootTypeTransport)

        do {
            _ = try await client.listTools()
            XCTFail("non-object root inputSchema should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(serverID: "fake", method: "tools/list", reason: "Tool entry inputSchema.type must be \"object\".")
            )
        }
    }

    func testToolsListRejectsUnsupportedInputSchemaDialect() async throws {
        let unsupportedDialectTransport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("draft4"),
                                "description": .string("Unsupported dialect"),
                                "inputSchema": .object([
                                    "$schema": .string("http://json-schema.org/draft-04/schema#"),
                                    "type": .string("object")
                                ])
                            ])
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "fake", transport: unsupportedDialectTransport)

        do {
            _ = try await client.listTools()
            XCTFail("unsupported inputSchema dialect should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(serverID: "fake", method: "tools/list", reason: "Tool entry inputSchema.$schema is not supported: http://json-schema.org/draft-04/schema#.")
            )
        }
    }

    func testToolsListRejectsMalformedRequiredSchema() async throws {
        let malformedRequiredTransport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("bad_required"),
                                "description": .string("Malformed required schema"),
                                "inputSchema": .object([
                                    "type": .string("object"),
                                    "required": .array([.string("title"), .number(42)])
                                ])
                            ])
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "fake", transport: malformedRequiredTransport)

        do {
            _ = try await client.listTools()
            XCTFail("malformed required schema should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(serverID: "fake", method: "tools/list", reason: "Tool entry inputSchema.required must be an array of strings.")
            )
        }
    }

    func testToolsListRejectsNonObjectPropertySchemas() async throws {
        let malformedPropertyTransport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("bad_property"),
                                "description": .string("Malformed property schema"),
                                "inputSchema": .object([
                                    "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
                                    "type": .string("object"),
                                    "properties": .object([
                                        "title": .string("string")
                                    ])
                                ])
                            ])
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "fake", transport: malformedPropertyTransport)

        do {
            _ = try await client.listTools()
            XCTFail("non-object property schema should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(serverID: "fake", method: "tools/list", reason: "Tool entry inputSchema.properties.title must be an object.")
            )
        }
    }

    func testToolsListAcceptsDefault202012InputSchemaDialect() async throws {
        let validSchemaTransport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("read_status"),
                                "description": .string("Read status"),
                                "inputSchema": .object([
                                    "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
                                    "type": .string("object"),
                                    "required": .array([.string("project")]),
                                    "properties": .object([
                                        "project": .object(["type": .string("string")])
                                    ])
                                ])
                            ])
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "fake", transport: validSchemaTransport)

        let tools = try await client.listTools()

        XCTAssertEqual(tools.map(\.name), ["read_status"])
        XCTAssertEqual(tools.first?.inputSchema["$schema"], .string("https://json-schema.org/draft/2020-12/schema"))
    }

    func testToolsListRejectsNonStringDescriptionMetadata() async throws {
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("bad_description"),
                                "description": .number(42),
                                "inputSchema": .object(["type": .string("object")])
                            ])
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "fake", transport: transport)

        do {
            _ = try await client.listTools()
            XCTFail("non-string tool description should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(serverID: "fake", method: "tools/list", reason: "Tool entry description must be a string when present.")
            )
        }
    }

    func testToolsListRejectsNonStringTitleMetadata() async throws {
        let transport = RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("bad_title"),
                                "title": .array([.string("Bad Title")]),
                                "description": .string("Bad title metadata."),
                                "inputSchema": .object(["type": .string("object")])
                            ])
                        ])
                    ])
                )
            }
            return MCPJSONRPCResponse(id: request.id, result: .object([:]))
        }
        let client = MCPClient(serverID: "fake", transport: transport)

        do {
            _ = try await client.listTools()
            XCTFail("non-string tool title should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(
                error,
                .invalidResponse(serverID: "fake", method: "tools/list", reason: "Tool entry title must be a string when present.")
            )
        }
    }

    func testMismatchedJSONRPCResponseIDAndVersionAreRejected() async throws {
        let mismatchedIDClient = MCPClient(serverID: "fake", transport: ExternalMCPTestKit.makeMismatchedIDTransport())
        do {
            _ = try await mismatchedIDClient.listTools()
            XCTFail("mismatched id should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(error, .invalidResponse(serverID: "fake", method: "tools/list", reason: "Mismatched response id."))
        }

        let invalidVersionClient = MCPClient(serverID: "fake", transport: ExternalMCPTestKit.makeInvalidJSONRPCVersionTransport())
        do {
            _ = try await invalidVersionClient.listTools()
            XCTFail("invalid JSON-RPC version should fail")
        } catch let error as MCPClientError {
            XCTAssertEqual(error, .invalidResponse(serverID: "fake", method: "tools/list", reason: "Invalid JSON-RPC version."))
        }
    }

    private func makeExecutor(
        transport: RecordingMCPTransport,
        policies: [String: ExternalMCPToolPermission],
        auditLogger: any AuditLogger = InMemoryAuditLogger(),
        processController: any MCPProcessController = RecordingMCPProcessController(),
        entitlementStore: any EntitlementStore = StaticMCPEntitlementStore(plan: .pro),
        tools: [MCPToolDefinition] = ExternalMCPTestKit.fakeToolDefinitions()
    ) -> ExternalMCPToolExecutor {
        makeExecutor(
            client: MCPClient(serverID: "fake", transport: transport),
            policies: policies,
            auditLogger: auditLogger,
            processController: processController,
            entitlementStore: entitlementStore,
            tools: tools
        )
    }

    private func makeExecutor(
        client: MCPClient,
        policies: [String: ExternalMCPToolPermission],
        auditLogger: any AuditLogger = InMemoryAuditLogger(),
        processController: any MCPProcessController = RecordingMCPProcessController(),
        entitlementStore: any EntitlementStore = StaticMCPEntitlementStore(plan: .pro),
        tools: [MCPToolDefinition] = ExternalMCPTestKit.fakeToolDefinitions()
    ) -> ExternalMCPToolExecutor {
        let server = MCPRegisteredServerDescriptor(id: "fake", displayName: "Fake MCP")
        let registry = ExternalMCPToolRegistry(
            server: server,
            tools: tools,
            classifier: ExternalMCPToolClassifier(explicitPolicies: policies)
        )
        return ExternalMCPToolExecutor(
            server: server,
            registry: registry,
            client: client,
            auditLogger: auditLogger,
            processController: processController,
            entitlementChecker: EntitlementChecker(store: entitlementStore)
        )
    }

    private func structuredReadStatusTool() -> MCPToolDefinition {
        MCPToolDefinition(
            name: "read_status",
            title: "Read Status",
            description: "Read structured project status.",
            inputSchema: ["type": .string("object")],
            outputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "status": .object(["type": .string("string")]),
                    "openTasks": .object(["type": .string("integer")])
                ]),
                "required": .array([.string("status")])
            ]
        )
    }

    private func makeStdioServerScript() throws -> URL {
        let directory = try temporaryDirectory()
        let scriptURL = directory.appendingPathComponent("fake-mcp.sh")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *\\"id\\":1*)
              printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"stdio-fake"}}}'
              ;;
            *\\"method\\":\\"notifications/initialized\\"*)
              ;;
            *\\"id\\":2*)
              printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"read_status","title":"Read Status","description":"Read status","inputSchema":{"type":"object"}}]}}'
              ;;
            *\\"id\\":3*)
              printf '%s\\n' '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"status: ok"}],"isError":false}}'
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func makeMalformedStdioServerScript() throws -> URL {
        let directory = try temporaryDirectory()
        let scriptURL = directory.appendingPathComponent("malformed-mcp.sh")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *\\"id\\":1*)
              printf '%s\\n' '{not json'
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct StaticMCPEntitlementStore: EntitlementStore {
    var plan: SubscriptionPlan

    func snapshot() throws -> EntitlementSnapshot {
        EntitlementSnapshot(plan: plan, source: .localLicense)
    }
}

private struct StaticBinaryLocator: MCPBinaryLocator {
    var availableCommands: Set<String>

    func isExecutableAvailable(command: String) -> Bool {
        availableCommands.contains(command)
    }
}

private final class CheckedMCPRegistrationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []

    var recordedIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return ids
    }

    func record(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        ids.append(id)
    }
}

private final class GatedMCPListTransport: MCPClientTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var hasStartedListRequest = false
    private var isListResponseReleased = false
    private var listStartedContinuation: CheckedContinuation<Void, Never>?
    private var listReleaseContinuation: CheckedContinuation<Void, Never>?

    func send(_ request: MCPJSONRPCRequest, timeout: TimeInterval) async throws -> MCPJSONRPCResponse {
        if request.method == "tools/list" {
            await waitForReleaseAfterMarkingListStarted()
        }

        switch request.method {
        case "initialize":
            return MCPJSONRPCResponse(
                id: request.id,
                result: .object([
                    "protocolVersion": .string(MCPProtocolVersion.v2025_11_25.rawValue),
                    "capabilities": .object(["tools": .object(["listChanged": .bool(true)])]),
                    "serverInfo": .object(["name": .string("gated-mcp")])
                ])
            )
        case "tools/list":
            return MCPJSONRPCResponse(
                id: request.id,
                result: .object(["tools": .array(ExternalMCPTestKit.fakeToolDefinitions().map(\.jsonValue))])
            )
        default:
            return MCPJSONRPCResponse(
                id: request.id,
                error: MCPJSONRPCError(code: -32601, message: "Unknown method: \(request.method)")
            )
        }
    }

    func notify(_ notification: MCPJSONRPCNotification) async throws {}

    func waitForListRequest() async {
        if hasStartedListRequestSnapshot() {
            return
        }

        await withCheckedContinuation { continuation in
            if storeListStartedContinuationIfNeeded(continuation) {
                continuation.resume()
            }
        }
    }

    func releaseListResponse() {
        lock.lock()
        isListResponseReleased = true
        let continuation = listReleaseContinuation
        listReleaseContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

    private func waitForReleaseAfterMarkingListStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            hasStartedListRequest = true
            let startedContinuation = listStartedContinuation
            listStartedContinuation = nil
            if isListResponseReleased {
                lock.unlock()
                startedContinuation?.resume()
                continuation.resume()
            } else {
                listReleaseContinuation = continuation
                lock.unlock()
                startedContinuation?.resume()
            }
        }
    }

    private func hasStartedListRequestSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasStartedListRequest
    }

    private func storeListStartedContinuationIfNeeded(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasStartedListRequest {
            return true
        }
        listStartedContinuation = continuation
        return false
    }
}

private final class ToggleFailingMCPServerRegistrationStore: MCPServerRegistrationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var registrations: [MCPServerRegistration]
    var shouldFailLoads = false
    var shouldFailSaves = false

    init(registrations: [MCPServerRegistration]) {
        self.registrations = registrations
    }

    func loadRegistrations() throws -> [MCPServerRegistration] {
        lock.lock()
        defer { lock.unlock() }
        if shouldFailLoads {
            throw MCPRegistrationStoreError.decodingFailed
        }
        return registrations
    }

    func saveRegistrations(_ registrations: [MCPServerRegistration]) throws {
        lock.lock()
        defer { lock.unlock() }
        if shouldFailSaves {
            throw MCPRegistrationStoreError.encodingFailed
        }
        self.registrations = registrations
    }
}

private final class RowLevelOnlyMCPServerRegistrationStore: MCPServerRegistrationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var registrations: [MCPServerRegistration]
    private(set) var savedRegistrationIDs: [String] = []
    private(set) var deletedRegistrationIDs: [String] = []
    private(set) var wholeTableSaveCount = 0

    init(registrations: [MCPServerRegistration]) {
        self.registrations = registrations
    }

    func loadRegistrations() throws -> [MCPServerRegistration] {
        lock.lock()
        defer { lock.unlock() }
        return registrations
    }

    func saveRegistrations(_ registrations: [MCPServerRegistration]) throws {
        lock.lock()
        defer { lock.unlock() }
        wholeTableSaveCount += 1
        throw MCPRegistrationStoreError.encodingFailed
    }

    func saveRegistration(_ registration: MCPServerRegistration) throws {
        lock.lock()
        defer { lock.unlock() }
        savedRegistrationIDs.append(registration.id)
        if let index = registrations.firstIndex(where: { $0.id == registration.id }) {
            registrations[index] = registration
        } else {
            registrations.append(registration)
        }
    }

    func deleteRegistration(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        deletedRegistrationIDs.append(id)
        registrations.removeAll { $0.id == id }
    }
}
