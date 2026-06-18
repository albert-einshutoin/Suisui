import Foundation

public enum MCPProtocolVersion: String, Equatable, Sendable {
    case v2025_11_25 = "2025-11-25"
}

public struct MCPJSONRPCRequest: Codable, Equatable, Sendable {
    public var jsonrpc: String
    public var id: Int
    public var method: String
    public var params: JSONValue?

    public init(id: Int, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct MCPJSONRPCNotification: Codable, Equatable, Sendable {
    public var jsonrpc: String
    public var method: String
    public var params: JSONValue?

    public init(method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

public struct MCPJSONRPCResponse: Codable, Equatable, Sendable {
    public var jsonrpc: String
    public var id: Int
    public var result: JSONValue?
    public var error: MCPJSONRPCError?

    public init(id: Int, result: JSONValue? = nil, error: MCPJSONRPCError? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct MCPJSONRPCError: Codable, Equatable, Sendable {
    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct MCPInitializeResult: Equatable, Sendable {
    public var protocolVersion: String
    public var serverName: String?

    public init(protocolVersion: String, serverName: String?) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
    }
}

public struct MCPToolDefinition: Equatable, Sendable {
    public var name: String
    public var title: String?
    public var description: String
    public var inputSchema: [String: JSONValue]

    public init(name: String, title: String? = nil, description: String, inputSchema: [String: JSONValue]) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
    }

    public var jsonValue: JSONValue {
        var object: [String: JSONValue] = [
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object(inputSchema)
        ]
        if let title {
            object["title"] = .string(title)
        }
        return .object(object)
    }

    static func parse(_ value: JSONValue) throws -> MCPToolDefinition {
        let object = try value.requireObject(reason: "Tool entry must be an object.")
        guard let name = object["name"]?.stringValue, !name.isEmpty else {
            throw MCPClientError.invalidResponse(serverID: "", method: "tools/list", reason: "Tool entry missing name.")
        }
        let description = object["description"]?.stringValue ?? ""
        let inputSchema: [String: JSONValue]
        if let inputSchemaValue = object["inputSchema"] {
            guard let schemaObject = inputSchemaValue.objectValue else {
                throw MCPClientError.invalidResponse(serverID: "", method: "tools/list", reason: "Tool entry inputSchema must be an object.")
            }
            try validateInputSchema(schemaObject)
            inputSchema = schemaObject
        } else {
            inputSchema = ["type": .string("object")]
        }
        return MCPToolDefinition(
            name: name,
            title: object["title"]?.stringValue,
            description: description,
            inputSchema: inputSchema
        )
    }

    private static func validateInputSchema(_ inputSchema: [String: JSONValue]) throws {
        if let required = inputSchema["required"] {
            guard case .array(let values) = required else {
                throw MCPClientError.invalidResponse(
                    serverID: "",
                    method: "tools/list",
                    reason: "Tool entry inputSchema.required must be an array of strings."
                )
            }
            for value in values where value.stringValue == nil {
                throw MCPClientError.invalidResponse(
                    serverID: "",
                    method: "tools/list",
                    reason: "Tool entry inputSchema.required must be an array of strings."
                )
            }
        }

        if let properties = inputSchema["properties"], properties.objectValue == nil {
            throw MCPClientError.invalidResponse(
                serverID: "",
                method: "tools/list",
                reason: "Tool entry inputSchema.properties must be an object."
            )
        }
    }
}

public struct MCPContentItem: Equatable, Sendable {
    public var type: String
    public var text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }

    public var jsonValue: JSONValue {
        var object: [String: JSONValue] = ["type": .string(type)]
        if let text {
            object["text"] = .string(text)
        }
        return .object(object)
    }

    static func parse(_ value: JSONValue) throws -> MCPContentItem {
        let object = try value.requireObject(reason: "Content entry must be an object.")
        guard let type = object["type"]?.stringValue else {
            throw MCPClientError.invalidResponse(serverID: "", method: "tools/call", reason: "Content entry missing type.")
        }
        return MCPContentItem(type: type, text: object["text"]?.stringValue)
    }
}

public struct MCPToolCallResult: Equatable, Sendable {
    public var content: [MCPContentItem]
    public var isError: Bool
    public var structuredContent: JSONValue?

    public init(content: [MCPContentItem], isError: Bool = false, structuredContent: JSONValue? = nil) {
        self.content = content
        self.isError = isError
        self.structuredContent = structuredContent
    }
}

extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else {
            return nil
        }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else {
            return nil
        }
        return value
    }

    func requireObject(reason: String) throws -> [String: JSONValue] {
        guard let object = objectValue else {
            throw MCPClientError.invalidResponse(serverID: "", method: "", reason: reason)
        }
        return object
    }
}
