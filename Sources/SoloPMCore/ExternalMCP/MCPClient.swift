import Foundation

public enum MCPClientError: Error, Equatable, Sendable {
    case timeout(serverID: String, method: String)
    case invalidResponse(serverID: String, method: String, reason: String)
    case protocolError(serverID: String, method: String, code: Int, message: String)
    case transportFailed(serverID: String, method: String, message: String)
}

public protocol MCPClientTransport: Sendable {
    func send(_ request: MCPJSONRPCRequest, timeout: TimeInterval) async throws -> MCPJSONRPCResponse
    func notify(_ notification: MCPJSONRPCNotification) async throws
}

public final class MCPClient: @unchecked Sendable {
    private let serverID: String
    private let transport: any MCPClientTransport
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var nextRequestID = 1

    public init(serverID: String, transport: any MCPClientTransport, timeout: TimeInterval = 10) {
        self.serverID = serverID
        self.transport = transport
        self.timeout = timeout
    }

    public func initialize() async throws -> MCPInitializeResult {
        let request = makeRequest(
            method: "initialize",
            params: .object([
                "protocolVersion": .string(MCPProtocolVersion.v2025_11_25.rawValue),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("SoloPM"),
                    "title": .string("SoloPM"),
                    "version": .string("0.1.0")
                ])
            ])
        )
        let result = try await send(request)
        let object = try result.requireResultObject(serverID: serverID, method: "initialize")
        guard let protocolVersion = object["protocolVersion"]?.stringValue else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "initialize", reason: "Missing result.protocolVersion.")
        }
        let serverName: String?
        if let serverInfoValue = object["serverInfo"] {
            guard let serverInfo = serverInfoValue.objectValue else {
                throw MCPClientError.invalidResponse(
                    serverID: serverID,
                    method: "initialize",
                    reason: "result.serverInfo must be an object when present."
                )
            }
            if let serverNameValue = serverInfo["name"] {
                guard let parsedServerName = serverNameValue.stringValue else {
                    throw MCPClientError.invalidResponse(
                        serverID: serverID,
                        method: "initialize",
                        reason: "result.serverInfo.name must be a string when present."
                    )
                }
                serverName = parsedServerName
            } else {
                serverName = nil
            }
        } else {
            serverName = nil
        }
        try await transport.notify(MCPJSONRPCNotification(method: "notifications/initialized"))
        return MCPInitializeResult(protocolVersion: protocolVersion, serverName: serverName)
    }

    public func listTools() async throws -> [MCPToolDefinition] {
        let request = makeRequest(method: "tools/list", params: .object([:]))
        let result = try await send(request)
        let object = try result.requireResultObject(serverID: serverID, method: "tools/list")
        guard let tools = object["tools"]?.arrayValue else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "tools/list", reason: "Missing result.tools array.")
        }
        do {
            return try tools.map(MCPToolDefinition.parse)
        } catch let error as MCPClientError {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "tools/list", reason: error.responseReason)
        }
    }

    public func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPToolCallResult {
        let request = makeRequest(
            method: "tools/call",
            params: .object([
                "name": .string(name),
                "arguments": .object(arguments)
            ])
        )
        let result = try await send(request)
        let object = try result.requireResultObject(serverID: serverID, method: "tools/call")
        guard let contentValues = object["content"]?.arrayValue else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "tools/call", reason: "Missing result.content array.")
        }
        let content: [MCPContentItem]
        do {
            content = try contentValues.map(MCPContentItem.parse)
        } catch let error as MCPClientError {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "tools/call", reason: error.responseReason)
        }
        let isError: Bool
        if let isErrorValue = object["isError"] {
            guard let parsedIsError = isErrorValue.boolValue else {
                throw MCPClientError.invalidResponse(
                    serverID: serverID,
                    method: "tools/call",
                    reason: "result.isError must be a boolean when present."
                )
            }
            isError = parsedIsError
        } else {
            isError = false
        }
        return MCPToolCallResult(
            content: content,
            isError: isError,
            structuredContent: object["structuredContent"]
        )
    }

    private func makeRequest(method: String, params: JSONValue? = nil) -> MCPJSONRPCRequest {
        lock.lock()
        defer { lock.unlock() }
        let id = nextRequestID
        nextRequestID += 1
        return MCPJSONRPCRequest(id: id, method: method, params: params)
    }

    private func send(_ request: MCPJSONRPCRequest) async throws -> JSONValue {
        do {
            let response = try await sendWithTimeout(request)
            guard response.jsonrpc == "2.0" else {
                throw MCPClientError.invalidResponse(serverID: serverID, method: request.method, reason: "Invalid JSON-RPC version.")
            }
            guard response.id == request.id else {
                throw MCPClientError.invalidResponse(serverID: serverID, method: request.method, reason: "Mismatched response id.")
            }
            if let error = response.error {
                throw MCPClientError.protocolError(
                    serverID: serverID,
                    method: request.method,
                    code: error.code,
                    message: error.message
                )
            }
            guard let result = response.result else {
                throw MCPClientError.invalidResponse(serverID: serverID, method: request.method, reason: "Missing result.")
            }
            return result
        } catch let error as MCPClientError {
            throw error
        } catch {
            throw MCPClientError.transportFailed(serverID: serverID, method: request.method, message: String(describing: error))
        }
    }

    private func sendWithTimeout(_ request: MCPJSONRPCRequest) async throws -> MCPJSONRPCResponse {
        guard timeout > 0 else {
            throw MCPClientError.timeout(serverID: serverID, method: request.method)
        }

        return try await withThrowingTaskGroup(of: MCPJSONRPCResponse.self) { group in
            group.addTask { [transport, timeout] in
                try await transport.send(request, timeout: timeout)
            }
            group.addTask { [serverID, timeout] in
                let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
                try await Task.sleep(nanoseconds: nanoseconds)
                throw MCPClientError.timeout(serverID: serverID, method: request.method)
            }

            guard let response = try await group.next() else {
                throw MCPClientError.timeout(serverID: serverID, method: request.method)
            }
            group.cancelAll()
            return response
        }
    }
}

private extension JSONValue {
    func requireResultObject(serverID: String, method: String) throws -> [String: JSONValue] {
        guard let object = objectValue else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: method, reason: "Result must be an object.")
        }
        return object
    }
}

private extension MCPClientError {
    var responseReason: String {
        switch self {
        case .invalidResponse(_, _, let reason):
            return reason
        case .timeout:
            return "Timed out."
        case .protocolError(_, _, _, let message),
             .transportFailed(_, _, let message):
            return message
        }
    }
}
