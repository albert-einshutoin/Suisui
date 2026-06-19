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
        try validateName(name)
        let description: String
        if let descriptionValue = object["description"] {
            guard let parsedDescription = descriptionValue.stringValue else {
                throw MCPClientError.invalidResponse(
                    serverID: "",
                    method: "tools/list",
                    reason: "Tool entry description must be a string when present."
                )
            }
            description = parsedDescription
        } else {
            description = ""
        }
        let title: String?
        if let titleValue = object["title"] {
            guard let parsedTitle = titleValue.stringValue else {
                throw MCPClientError.invalidResponse(
                    serverID: "",
                    method: "tools/list",
                    reason: "Tool entry title must be a string when present."
                )
            }
            title = parsedTitle
        } else {
            title = nil
        }
        let inputSchema: [String: JSONValue]
        guard let inputSchemaValue = object["inputSchema"] else {
            throw MCPClientError.invalidResponse(serverID: "", method: "tools/list", reason: "Tool entry inputSchema is required.")
        }
        guard let schemaObject = inputSchemaValue.objectValue else {
            throw MCPClientError.invalidResponse(serverID: "", method: "tools/list", reason: "Tool entry inputSchema must be an object.")
        }
        try validateInputSchema(schemaObject)
        inputSchema = schemaObject
        return MCPToolDefinition(
            name: name,
            title: title,
            description: description,
            inputSchema: inputSchema
        )
    }

    private static func validateInputSchema(_ inputSchema: [String: JSONValue]) throws {
        if let dialect = inputSchema["$schema"] {
            guard let dialectString = dialect.stringValue else {
                throw MCPClientError.invalidResponse(
                    serverID: "",
                    method: "tools/list",
                    reason: "Tool entry inputSchema.$schema must be a string when present."
                )
            }
            guard isSupportedInputSchemaDialect(dialectString) else {
                throw MCPClientError.invalidResponse(
                    serverID: "",
                    method: "tools/list",
                    reason: "Tool entry inputSchema.$schema is not supported: \(dialectString)."
                )
            }
        }

        guard inputSchema["type"] == .string("object") else {
            throw MCPClientError.invalidResponse(
                serverID: "",
                method: "tools/list",
                reason: "Tool entry inputSchema.type must be \"object\"."
            )
        }

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

        if let properties = inputSchema["properties"] {
            guard let propertySchemas = properties.objectValue else {
                throw MCPClientError.invalidResponse(
                    serverID: "",
                    method: "tools/list",
                    reason: "Tool entry inputSchema.properties must be an object."
                )
            }

            for (propertyName, propertySchema) in propertySchemas where propertySchema.objectValue == nil {
                throw MCPClientError.invalidResponse(
                    serverID: "",
                    method: "tools/list",
                    reason: "Tool entry inputSchema.properties.\(propertyName) must be an object."
                )
            }
        }
    }

    private static func validateName(_ name: String) throws {
        guard name.count <= 128 else {
            throw MCPClientError.invalidResponse(
                serverID: "",
                method: "tools/list",
                reason: "Tool entry name must be between 1 and 128 characters."
            )
        }
        guard name.unicodeScalars.allSatisfy(Self.isAllowedNameScalar) else {
            throw MCPClientError.invalidResponse(
                serverID: "",
                method: "tools/list",
                reason: "Tool entry name must use only ASCII letters, digits, underscore, hyphen, or dot."
            )
        }
    }

    private static func isAllowedNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        case 45, 46, 95:
            return true
        default:
            return false
        }
    }

    private static func isSupportedInputSchemaDialect(_ dialect: String) -> Bool {
        switch dialect {
        case "https://json-schema.org/draft/2020-12/schema",
             "https://json-schema.org/draft/2020-12/schema#",
             "http://json-schema.org/draft/2020-12/schema",
             "http://json-schema.org/draft/2020-12/schema#":
            return true
        default:
            return false
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
        let text: String?
        if let textValue = object["text"] {
            guard let parsedText = textValue.stringValue else {
                throw MCPClientError.invalidResponse(
                    serverID: "",
                    method: "tools/call",
                    reason: "Content entry text must be a string when present."
                )
            }
            text = parsedText
        } else {
            text = nil
        }
        return MCPContentItem(type: type, text: text)
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
