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

    func testServerRegistrationValidatesCommandBinaryDisabledAndKeychainEnvReferences() async throws {
        let validator = MCPServerRegistrationValidator(binaryLocator: StaticBinaryLocator(availableCommands: ["node"]))
        let valid = MCPServerRegistration(
            id: "github",
            displayName: "GitHub MCP",
            command: "node",
            arguments: ["server.js"],
            environment: ["GITHUB_TOKEN": .keychain(.githubToken)],
            workingDirectory: "/repo",
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

    func testDefaultMCPEnvironmentResolverDoesNotReadFromInMemorySecrets() throws {
        let resolver = NoSecretMCPEnvironmentResolver()

        XCTAssertEqual(try resolver.resolve([:]), [:])
        XCTAssertThrowsError(try resolver.resolve(["GITHUB_TOKEN": .keychain(.githubToken)])) { error in
            XCTAssertEqual(error as? MCPRegistrationError, .missingSecret("GITHUB_TOKEN"))
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
        XCTAssertEqual(rows.first?["environment_json"]?.contains("ghp_secret"), false)

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

        await viewModel.checkConnection()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isCheckingConnection)
        XCTAssertEqual(viewModel.toolRows.map(\.toolName), ["danger_delete", "invalid_response", "read_status", "slow_tool", "write_issue"])
        XCTAssertEqual(viewModel.toolRows.first { $0.toolName == "read_status" }?.serverName, "Fake MCP")
        XCTAssertEqual(transport.recordedMethods, ["initialize", "notifications/initialized", "tools/list"])
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

        XCTAssertEqual(viewModel.errorMessage, "MCP tools/list response was invalid: Missing result.tools array.")
        XCTAssertTrue(viewModel.toolRows.isEmpty)
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

        XCTAssertThrowsError(try registry.assertExecutable(toolName: "danger_delete", context: ToolExecutionContext(source: .test))) { error in
            XCTAssertEqual(error as? ExternalMCPExecutionError, .dangerousToolBlocked(serverID: "fake", toolName: "danger_delete"))
        }
        XCTAssertThrowsError(try registry.assertExecutable(toolName: "slow_tool", context: ToolExecutionContext(source: .test))) { error in
            XCTAssertEqual(error as? ExternalMCPExecutionError, .toolDisabled(serverID: "fake", toolName: "slow_tool"))
        }
    }

    func testExecutionPreviewRedactsSecretsAndWriteRequiresApproval() async throws {
        let transport = ExternalMCPTestKit.makeFakeServerTransport()
        let executor = makeExecutor(transport: transport, policies: ["write_issue": .writeWithApproval])
        let arguments: [String: JSONValue] = [
            "title": .string("Bug"),
            "token": .string("github_pat_SECRETSECRET")
        ]

        let preview = try executor.preview(toolName: "write_issue", arguments: arguments)

        XCTAssertEqual(preview.serverID, "fake")
        XCTAssertEqual(preview.toolName, "write_issue")
        XCTAssertEqual(preview.permissionLevel, .writeWithApproval)
        XCTAssertTrue(preview.requiresApproval)
        XCTAssertFalse(preview.redactedArgumentSummary.contains("github_pat_SECRETSECRET"))
        XCTAssertTrue(preview.redactedArgumentSummary.contains("[REDACTED_SECRET]"))

        do {
            _ = try await executor.call(toolName: "write_issue", arguments: arguments, context: ToolExecutionContext(source: .test))
            XCTFail("write MCP calls must require approval")
        } catch let error as ExternalMCPExecutionError {
            XCTAssertEqual(error, .approvalRequired(serverID: "fake", toolName: "write_issue"))
        }

        XCTAssertEqual(transport.recordedMethods, [])
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
            arguments: ["api_key": .string("sk-test-secret")],
            context: ToolExecutionContext(source: .test)
        )

        XCTAssertEqual(result.content.first?.text, "status: ok")
        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .succeeded])
        XCTAssertEqual(logger.recordedEvents.first?.category, "external_mcp")
        XCTAssertEqual(logger.recordedEvents.first?.metadata["server_name"], "Fake MCP")
        XCTAssertEqual(logger.recordedEvents.first?.metadata["arguments"], "[REDACTED_SECRET]")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["result"], "succeeded")
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
                context: ToolExecutionContext(source: .test)
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

    func testAuditHistoryRowsExposeExternalCallHistory() {
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

        let rows = ExternalMCPAuditHistory.rows(from: events)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.serverName, "Fake MCP")
        XCTAssertEqual(rows.first?.toolName, "read_status")
        XCTAssertEqual(rows.first?.status, .succeeded)
        XCTAssertEqual(rows.first?.redactedArgumentSummary, "[REDACTED_SECRET]")
        XCTAssertEqual(rows.first?.statusLabel, "Succeeded")
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
        processController: any MCPProcessController = NoopMCPProcessController()
    ) -> ExternalMCPToolExecutor {
        makeExecutor(
            client: MCPClient(serverID: "fake", transport: transport),
            policies: policies,
            auditLogger: auditLogger,
            processController: processController
        )
    }

    private func makeExecutor(
        client: MCPClient,
        policies: [String: ExternalMCPToolPermission],
        auditLogger: any AuditLogger = InMemoryAuditLogger(),
        processController: any MCPProcessController = NoopMCPProcessController()
    ) -> ExternalMCPToolExecutor {
        let server = MCPRegisteredServerDescriptor(id: "fake", displayName: "Fake MCP")
        let registry = ExternalMCPToolRegistry(
            server: server,
            tools: ExternalMCPTestKit.fakeToolDefinitions(),
            classifier: ExternalMCPToolClassifier(explicitPolicies: policies)
        )
        return ExternalMCPToolExecutor(
            server: server,
            registry: registry,
            client: client,
            auditLogger: auditLogger,
            processController: processController
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

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct StaticBinaryLocator: MCPBinaryLocator {
    var availableCommands: Set<String>

    func isExecutableAvailable(command: String) -> Bool {
        availableCommands.contains(command)
    }
}
