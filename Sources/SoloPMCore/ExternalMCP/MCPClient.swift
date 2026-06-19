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
    private var initializeResult: MCPInitializeResult?

    public init(serverID: String, transport: any MCPClientTransport, timeout: TimeInterval = 10) {
        self.serverID = serverID
        self.transport = transport
        self.timeout = timeout
    }

    public func initialize() async throws -> MCPInitializeResult {
        if let initializeResult = cachedInitializeResult() {
            return initializeResult
        }

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
        guard MCPProtocolVersion(rawValue: protocolVersion) != nil else {
            throw MCPClientError.invalidResponse(
                serverID: serverID,
                method: "initialize",
                reason: "Unsupported result.protocolVersion: \(protocolVersion)."
            )
        }
        guard let capabilitiesValue = object["capabilities"] else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "initialize", reason: "Missing result.capabilities.")
        }
        guard let capabilities = capabilitiesValue.objectValue else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "initialize", reason: "result.capabilities must be an object.")
        }
        guard let serverInfoValue = object["serverInfo"] else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "initialize", reason: "Missing result.serverInfo.")
        }
        guard let serverInfo = serverInfoValue.objectValue else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "initialize", reason: "result.serverInfo must be an object.")
        }
        guard let serverNameValue = serverInfo["name"] else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "initialize", reason: "Missing result.serverInfo.name.")
        }
        guard let serverName = serverNameValue.stringValue else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "initialize", reason: "result.serverInfo.name must be a string.")
        }
        guard let serverVersionValue = serverInfo["version"] else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "initialize", reason: "Missing result.serverInfo.version.")
        }
        guard let serverVersion = serverVersionValue.stringValue else {
            throw MCPClientError.invalidResponse(serverID: serverID, method: "initialize", reason: "result.serverInfo.version must be a string.")
        }
        try await transport.notify(MCPJSONRPCNotification(method: "notifications/initialized"))
        let initializeResult = MCPInitializeResult(
            protocolVersion: protocolVersion,
            serverName: serverName,
            serverVersion: serverVersion,
            serverCapabilities: capabilities
        )
        cacheInitializeResult(initializeResult)
        return initializeResult
    }

    public func listTools() async throws -> [MCPToolDefinition] {
        var cursor: String?
        var seenCursors = Set<String>()
        var seenToolNames = Set<String>()
        var definitions: [MCPToolDefinition] = []

        repeat {
            var params: [String: JSONValue] = [:]
            if let cursor {
                params["cursor"] = .string(cursor)
            }

            let request = makeRequest(method: "tools/list", params: .object(params))
            let result = try await send(request)
            let object = try result.requireResultObject(serverID: serverID, method: "tools/list")
            guard let tools = object["tools"]?.arrayValue else {
                throw MCPClientError.invalidResponse(serverID: serverID, method: "tools/list", reason: "Missing result.tools array.")
            }
            do {
                let pageDefinitions = try tools.map(MCPToolDefinition.parse)
                for definition in pageDefinitions {
                    guard seenToolNames.insert(definition.name).inserted else {
                        throw MCPClientError.invalidResponse(
                            serverID: serverID,
                            method: "tools/list",
                            reason: "Duplicate tool name in tools/list response: \(definition.name)."
                        )
                    }
                }
                definitions.append(contentsOf: pageDefinitions)
            } catch let error as MCPClientError {
                throw MCPClientError.invalidResponse(serverID: serverID, method: "tools/list", reason: error.responseReason)
            }

            cursor = try nextToolsListCursor(from: object, seenCursors: &seenCursors)
        } while cursor != nil

        return definitions
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
        let structuredContent: JSONValue?
        if let structuredContentValue = object["structuredContent"] {
            guard structuredContentValue.objectValue != nil else {
                throw MCPClientError.invalidResponse(
                    serverID: serverID,
                    method: "tools/call",
                    reason: "result.structuredContent must be an object when present."
                )
            }
            structuredContent = structuredContentValue
        } else {
            structuredContent = nil
        }
        return MCPToolCallResult(
            content: content,
            isError: isError,
            structuredContent: structuredContent
        )
    }

    private func makeRequest(method: String, params: JSONValue? = nil) -> MCPJSONRPCRequest {
        lock.lock()
        defer { lock.unlock() }
        let id = nextRequestID
        nextRequestID += 1
        return MCPJSONRPCRequest(id: id, method: method, params: params)
    }

    private func cachedInitializeResult() -> MCPInitializeResult? {
        lock.lock()
        defer { lock.unlock() }
        return initializeResult
    }

    private func cacheInitializeResult(_ result: MCPInitializeResult) {
        lock.lock()
        defer { lock.unlock() }
        initializeResult = result
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
            throw MCPClientError.transportFailed(serverID: serverID, method: request.method, message: "transport request failed.")
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

    private func nextToolsListCursor(
        from object: [String: JSONValue],
        seenCursors: inout Set<String>
    ) throws -> String? {
        guard let nextCursorValue = object["nextCursor"] else {
            return nil
        }
        guard let nextCursor = nextCursorValue.stringValue else {
            throw MCPClientError.invalidResponse(
                serverID: serverID,
                method: "tools/list",
                reason: "result.nextCursor must be a string when present."
            )
        }
        guard !nextCursor.isEmpty else {
            throw MCPClientError.invalidResponse(
                serverID: serverID,
                method: "tools/list",
                reason: "result.nextCursor must not be empty."
            )
        }
        guard seenCursors.insert(nextCursor).inserted else {
            throw MCPClientError.invalidResponse(
                serverID: serverID,
                method: "tools/list",
                reason: "result.nextCursor repeated a previously seen cursor."
            )
        }
        return nextCursor
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
