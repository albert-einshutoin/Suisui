import Foundation
@testable import SuisuiCore

public final class RecordingMCPTransport: MCPClientTransport, @unchecked Sendable {
    public typealias Handler = @Sendable (MCPJSONRPCRequest) throws -> MCPJSONRPCResponse

    private let handler: Handler
    private let lock = NSLock()
    private var requests: [MCPJSONRPCRequest] = []
    private var methods: [String] = []

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public var recordedRequests: [MCPJSONRPCRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    public var recordedMethods: [String] {
        lock.lock()
        defer { lock.unlock() }
        return methods
    }

    public func send(_ request: MCPJSONRPCRequest, timeout: TimeInterval) async throws -> MCPJSONRPCResponse {
        record(request: request)
        return try handler(request)
    }

    public func notify(_ notification: MCPJSONRPCNotification) async throws {
        record(method: notification.method)
    }

    private func record(request: MCPJSONRPCRequest) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        methods.append(request.method)
    }

    private func record(method: String) {
        lock.lock()
        defer { lock.unlock() }
        methods.append(method)
    }
}

public enum ExternalMCPTestKit {
    public static func fakeToolDefinitions() -> [MCPToolDefinition] {
        [
            MCPToolDefinition(
                name: "read_status",
                title: "Read Status",
                description: "Read local project status.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object(["project": .object(["type": .string("string")])])
                ]
            ),
            MCPToolDefinition(
                name: "write_issue",
                title: "Write Issue",
                description: "Create an external issue.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object(["title": .object(["type": .string("string")])]),
                    "required": .array([.string("title")])
                ]
            ),
            MCPToolDefinition(
                name: "danger_delete",
                title: "Delete",
                description: "Deletes external data.",
                inputSchema: ["type": .string("object")]
            ),
            MCPToolDefinition(
                name: "slow_tool",
                title: "Slow Tool",
                description: "Simulates a hung MCP call.",
                inputSchema: ["type": .string("object")]
            ),
            MCPToolDefinition(
                name: "invalid_response",
                title: "Invalid Response",
                description: "Returns malformed JSON-RPC data.",
                inputSchema: ["type": .string("object")]
            )
        ]
    }

    public static func makeFakeServerTransport() -> RecordingMCPTransport {
        RecordingMCPTransport { request in
            fakeResponse(for: request)
        }
    }

    public static func makeTimeoutTransport() -> RecordingMCPTransport {
        RecordingMCPTransport { request in
            if request.method == "tools/call" {
                throw MCPClientError.timeout(serverID: "fake", method: "tools/call")
            }
            return fakeResponse(for: request)
        }
    }

    public static func makeInvalidListTransport() -> RecordingMCPTransport {
        RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(id: request.id, result: .object(["notTools": .array([])]))
            }
            return fakeResponse(for: request)
        }
    }

    public static func makeMalformedJSONTransport() -> RecordingMCPTransport {
        RecordingMCPTransport { request in
            if request.method == "initialize" {
                throw MCPClientError.invalidResponse(
                    serverID: "fake",
                    method: "initialize",
                    reason: "Malformed JSON-RPC response."
                )
            }
            return fakeResponse(for: request)
        }
    }

    public static func makeInvalidToolSchemaTransport() -> RecordingMCPTransport {
        RecordingMCPTransport { request in
            if request.method == "tools/list" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("bad_schema"),
                                "description": .string("Invalid schema."),
                                "inputSchema": .string("not-an-object")
                            ])
                        ])
                    ])
                )
            }
            return fakeResponse(for: request)
        }
    }

    public static func makeListTimeoutTransport() -> RecordingMCPTransport {
        RecordingMCPTransport { request in
            if request.method == "tools/list" {
                throw MCPClientError.timeout(serverID: "fake", method: "tools/list")
            }
            return fakeResponse(for: request)
        }
    }

    public static func makeMismatchedIDTransport() -> RecordingMCPTransport {
        RecordingMCPTransport { request in
            MCPJSONRPCResponse(id: request.id + 1, result: .object(["tools": .array([])]))
        }
    }

    public static func makeInvalidJSONRPCVersionTransport() -> RecordingMCPTransport {
        RecordingMCPTransport { request in
            var response = MCPJSONRPCResponse(id: request.id, result: .object(["tools": .array([])]))
            response.jsonrpc = "1.0"
            return response
        }
    }

    public static func makeHangingTransport() -> HangingMCPTransport {
        HangingMCPTransport()
    }

    private static func fakeResponse(for request: MCPJSONRPCRequest) -> MCPJSONRPCResponse {
        switch request.method {
        case "initialize":
            return MCPJSONRPCResponse(
                id: request.id,
                result: .object([
                    "protocolVersion": .string(MCPProtocolVersion.v2025_11_25.rawValue),
                    "capabilities": .object(["tools": .object(["listChanged": .bool(true)])]),
                    "serverInfo": .object([
                        "name": .string("fake-mcp"),
                        "title": .string("Fake MCP"),
                        "version": .string("0.1.0")
                    ])
                ])
            )
        case "tools/list":
            return MCPJSONRPCResponse(
                id: request.id,
                result: .object(["tools": .array(fakeToolDefinitions().map(\.jsonValue))])
            )
        case "tools/call":
            let params = request.params?.objectValue ?? [:]
            let name = params["name"]?.stringValue ?? ""
            if name == "read_status" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([MCPContentItem(type: "text", text: "status: ok").jsonValue]),
                        "isError": .bool(false)
                    ])
                )
            }
            if name == "write_issue" {
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([MCPContentItem(type: "text", text: "issue created").jsonValue]),
                        "isError": .bool(false)
                    ])
                )
            }
            return MCPJSONRPCResponse(
                id: request.id,
                error: MCPJSONRPCError(code: -32602, message: "Unknown tool: \(name)")
            )
        default:
            return MCPJSONRPCResponse(
                id: request.id,
                error: MCPJSONRPCError(code: -32601, message: "Unknown method: \(request.method)")
            )
        }
    }
}

public final class HangingMCPTransport: MCPClientTransport, @unchecked Sendable {
    public init() {}

    public func send(_ request: MCPJSONRPCRequest, timeout: TimeInterval) async throws -> MCPJSONRPCResponse {
        try await Task.sleep(nanoseconds: 10_000_000_000)
        return MCPJSONRPCResponse(id: request.id, result: .object([:]))
    }

    public func notify(_ notification: MCPJSONRPCNotification) async throws {}
}
