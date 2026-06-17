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
        let launchedClient = try launcher.client(for: valid)
        let tools = try await launchedClient.listTools()
        let result = try await launchedClient.callTool(name: "read_status", arguments: [:])
        XCTAssertTrue(tools.contains { $0.name == "read_status" })
        XCTAssertEqual(result.content.first?.text, "status: ok")

        XCTAssertThrowsError(try launcher.client(for: MCPServerRegistration(
            id: "disabled",
            displayName: "Disabled",
            command: "node",
            arguments: [],
            environment: [:],
            workingDirectory: nil,
            isEnabled: false
        ))) { error in
            XCTAssertEqual(error as? MCPRegistrationError, .serverDisabled)
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
        let transport = ExternalMCPTestKit.makeTimeoutTransport()
        let processController = RecordingMCPProcessController()
        let executor = makeExecutor(
            transport: transport,
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

    private func makeExecutor(
        transport: RecordingMCPTransport,
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
            client: MCPClient(serverID: "fake", transport: transport),
            auditLogger: auditLogger,
            processController: processController
        )
    }
}

private struct StaticBinaryLocator: MCPBinaryLocator {
    var availableCommands: Set<String>

    func isExecutableAvailable(command: String) -> Bool {
        availableCommands.contains(command)
    }
}
