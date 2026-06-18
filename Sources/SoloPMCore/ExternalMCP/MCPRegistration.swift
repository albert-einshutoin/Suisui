import Combine
import Foundation

public enum MCPEnvironmentReference: Codable, Equatable, Sendable {
    case keychain(SecretKey)

    private enum CodingKeys: String, CodingKey {
        case type
        case key
    }

    private enum ReferenceType: String, Codable {
        case keychain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ReferenceType.self, forKey: .type)
        switch type {
        case .keychain:
            self = .keychain(SecretKey(try container.decode(String.self, forKey: .key)))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keychain(let key):
            try container.encode(ReferenceType.keychain, forKey: .type)
            try container.encode(key.rawValue, forKey: .key)
        }
    }
}

public struct MCPServerRegistration: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var command: String
    public var arguments: [String]
    public var environment: [String: MCPEnvironmentReference]
    public var workingDirectory: String?
    public var isEnabled: Bool

    public init(
        id: String,
        displayName: String,
        command: String,
        arguments: [String],
        environment: [String: MCPEnvironmentReference],
        workingDirectory: String?,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.isEnabled = isEnabled
    }
}

public enum MCPRegistrationStoreError: Error, Equatable, Sendable {
    case encodingFailed
    case decodingFailed
}

public protocol MCPServerRegistrationStore: Sendable {
    func loadRegistrations() throws -> [MCPServerRegistration]
    func saveRegistrations(_ registrations: [MCPServerRegistration]) throws
}

public final class SQLiteMCPServerRegistrationStore: MCPServerRegistrationStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func loadRegistrations() throws -> [MCPServerRegistration] {
        lock.lock()
        defer { lock.unlock() }

        do {
            return try connection
                .queryRows("SELECT * FROM mcp_server_registrations ORDER BY sort_order ASC, id ASC;")
                .map(Self.registration(row:))
        } catch let error as MCPRegistrationStoreError {
            throw error
        } catch {
            throw MCPRegistrationStoreError.decodingFailed
        }
    }

    public func saveRegistrations(_ registrations: [MCPServerRegistration]) throws {
        lock.lock()
        defer { lock.unlock() }

        do {
            try connection.transaction {
                try connection.execute("DELETE FROM mcp_server_registrations;")
                for (index, registration) in registrations.enumerated() {
                    try insertLocked(registration, sortOrder: index)
                }
            }
        } catch let error as MCPRegistrationStoreError {
            throw error
        } catch {
            throw MCPRegistrationStoreError.encodingFailed
        }
    }

    private func insertLocked(_ registration: MCPServerRegistration, sortOrder: Int) throws {
        let argumentsJSON = try Self.jsonString(registration.arguments)
        let environmentJSON = try Self.jsonString(registration.environment)
        try connection.execute(
            """
            INSERT INTO mcp_server_registrations (
              id,
              sort_order,
              display_name,
              command,
              arguments_json,
              environment_json,
              working_directory,
              is_enabled
            )
            VALUES (
              '\(MCPRegistrationSQL.escape(registration.id))',
              \(sortOrder),
              '\(MCPRegistrationSQL.escape(registration.displayName))',
              '\(MCPRegistrationSQL.escape(registration.command))',
              '\(MCPRegistrationSQL.escape(argumentsJSON))',
              '\(MCPRegistrationSQL.escape(environmentJSON))',
              \(MCPRegistrationSQL.optional(registration.workingDirectory)),
              \(registration.isEnabled ? 1 : 0)
            );
            """
        )
    }

    private static func registration(row: [String: String]) throws -> MCPServerRegistration {
        guard let id = row["id"],
              let displayName = row["display_name"],
              let command = row["command"],
              let argumentsJSON = row["arguments_json"],
              let environmentJSON = row["environment_json"] else {
            throw MCPRegistrationStoreError.decodingFailed
        }

        return MCPServerRegistration(
            id: id,
            displayName: displayName,
            command: command,
            arguments: try jsonValue(argumentsJSON),
            environment: try jsonValue(environmentJSON),
            workingDirectory: row["working_directory"]?.nilIfEmpty,
            isEnabled: row["is_enabled"] == "1"
        )
    }

    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        do {
            let data = try JSONEncoder().encode(value)
            guard let string = String(data: data, encoding: .utf8) else {
                throw MCPRegistrationStoreError.encodingFailed
            }
            return string
        } catch let error as MCPRegistrationStoreError {
            throw error
        } catch {
            throw MCPRegistrationStoreError.encodingFailed
        }
    }

    private static func jsonValue<T: Decodable>(_ string: String) throws -> T {
        do {
            guard let data = string.data(using: .utf8) else {
                throw MCPRegistrationStoreError.decodingFailed
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as MCPRegistrationStoreError {
            throw error
        } catch {
            throw MCPRegistrationStoreError.decodingFailed
        }
    }
}

@MainActor
public final class ExternalMCPSettingsViewModel: ObservableObject {
    @Published public private(set) var registration: MCPServerRegistration
    @Published public private(set) var toolRows: [ExternalMCPToolCatalogRow]
    @Published public private(set) var auditRows: [ExternalMCPAuditHistoryRow]
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isCheckingConnection: Bool

    private let store: any MCPServerRegistrationStore
    private let launcher: MCPStdioServerLauncher
    private let registrationValidator: MCPServerRegistrationValidator
    private var registrations: [MCPServerRegistration]

    public init(
        store: any MCPServerRegistrationStore,
        launcher: MCPStdioServerLauncher = MCPStdioServerLauncher(),
        registrationValidator: MCPServerRegistrationValidator = MCPServerRegistrationValidator(),
        toolRows: [ExternalMCPToolCatalogRow] = [],
        auditRows: [ExternalMCPAuditHistoryRow] = []
    ) {
        self.store = store
        self.launcher = launcher
        self.registrationValidator = registrationValidator
        self.toolRows = toolRows
        self.auditRows = auditRows
        self.errorMessage = nil
        self.isCheckingConnection = false
        self.registrations = []
        self.registration = Self.blankRegistration()
        refresh()
    }

    public var display: MCPServerRegistrationDisplayModel {
        MCPServerRegistrationDisplayModel(registration: registration)
    }

    public var argumentsText: String {
        MCPArgumentTextCodec.format(registration.arguments)
    }

    public func refresh() {
        do {
            registrations = try store.loadRegistrations()
            registration = registrations.first ?? Self.blankRegistration()
            errorMessage = nil
        } catch {
            registrations = []
            registration = Self.blankRegistration()
            errorMessage = String(describing: error)
        }
    }

    public func updateEnabled(_ isEnabled: Bool) {
        var updated = registration
        updated.isEnabled = isEnabled
        registration = updated
    }

    public func updateDisplayName(_ displayName: String) {
        var updated = registration
        updated.displayName = displayName
        registration = updated
    }

    public func updateCommand(_ command: String) {
        var updated = registration
        updated.command = command
        registration = updated
    }

    public func updateArgumentsText(_ argumentsText: String) {
        do {
            var updated = registration
            updated.arguments = try MCPArgumentTextCodec.parse(argumentsText)
            registration = updated
            errorMessage = nil
        } catch {
            errorMessage = Self.argumentErrorMessage(error)
        }
    }

    public func updateWorkingDirectory(_ workingDirectory: String) {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = registration
        updated.workingDirectory = trimmed.isEmpty ? nil : trimmed
        registration = updated
    }

    public func save() {
        do {
            try registrationValidator.validate(registration)
            let updatedRegistrations = Self.replacing(registration, in: registrations)
            try store.saveRegistrations(updatedRegistrations)
            registrations = updatedRegistrations
            errorMessage = nil
        } catch {
            errorMessage = Self.connectionErrorMessage(error)
        }
    }

    public func deleteRegistration() {
        do {
            let remainingRegistrations = registrations.filter { $0.id != registration.id }
            try store.saveRegistrations(remainingRegistrations)
            registrations = remainingRegistrations
            registration = remainingRegistrations.first ?? Self.blankRegistration()
            toolRows = []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func checkConnection() async {
        isCheckingConnection = true
        defer {
            isCheckingConnection = false
        }

        do {
            let client = try await launcher.client(for: registration)
            _ = try await client.initialize()
            let tools = try await client.listTools()
            let server = MCPRegisteredServerDescriptor(id: registration.id, displayName: registration.displayName)
            let registry = ExternalMCPToolRegistry(
                server: server,
                tools: tools,
                classifier: ExternalMCPToolClassifier()
            )
            toolRows = ExternalMCPToolCatalog.rows(from: registry.allDescriptors)
            errorMessage = nil
        } catch {
            toolRows = []
            errorMessage = Self.connectionErrorMessage(error)
        }
    }

    private static func blankRegistration() -> MCPServerRegistration {
        MCPServerRegistration(
            id: "custom-mcp",
            displayName: "Custom MCP",
            command: "",
            arguments: [],
            environment: [:],
            workingDirectory: nil,
            isEnabled: false
        )
    }

    private static func connectionErrorMessage(_ error: Error) -> String {
        switch error {
        case MCPRegistrationError.serverDisabled:
            return "MCP server is disabled."
        case MCPRegistrationError.invalidCommand:
            return "MCP command is required."
        case MCPRegistrationError.missingBinary(let command):
            return "MCP command binary was not found: \(command)"
        case MCPRegistrationError.invalidWorkingDirectory(let path):
            return "MCP working directory was not found: \(path)"
        case MCPRegistrationError.missingSecret(let name):
            return "MCP environment secret is missing: \(name)"
        case MCPClientError.invalidResponse(_, "tools/list", let reason):
            return "MCP tools/list response was invalid: \(reason)"
        case MCPClientError.invalidResponse(_, "initialize", let reason):
            return "MCP initialize response was invalid: \(reason)"
        case MCPClientError.protocolError(_, let method, _, let message):
            return "MCP \(method) failed: \(message)"
        case MCPClientError.timeout(_, let method):
            return "MCP \(method) timed out."
        case MCPClientError.transportFailed(_, let method, let message):
            return "MCP \(method) transport failed: \(message)"
        default:
            return String(describing: error)
        }
    }

    private static func argumentErrorMessage(_ error: Error) -> String {
        switch error {
        case MCPArgumentTextError.unterminatedDoubleQuote:
            return "MCP arguments are invalid: missing closing double quote."
        case MCPArgumentTextError.unterminatedSingleQuote:
            return "MCP arguments are invalid: missing closing single quote."
        case MCPArgumentTextError.danglingEscape:
            return "MCP arguments are invalid: trailing escape character."
        default:
            return "MCP arguments are invalid: \(error)"
        }
    }

    private static func replacing(
        _ registration: MCPServerRegistration,
        in registrations: [MCPServerRegistration]
    ) -> [MCPServerRegistration] {
        guard let index = registrations.firstIndex(where: { $0.id == registration.id }) else {
            return registrations + [registration]
        }

        var updatedRegistrations = registrations
        updatedRegistrations[index] = registration
        return updatedRegistrations
    }
}

public enum MCPArgumentTextError: Error, Equatable, Sendable {
    case unterminatedSingleQuote
    case unterminatedDoubleQuote
    case danglingEscape
}

public enum MCPArgumentTextCodec {
    public static func parse(_ text: String) throws -> [String] {
        enum QuoteMode {
            case single
            case double
        }

        var arguments: [String] = []
        var current = ""
        var quoteMode: QuoteMode?
        var isEscaping = false
        var hasCurrentArgument = false

        for character in text {
            if isEscaping {
                current.append(character)
                isEscaping = false
                hasCurrentArgument = true
                continue
            }

            switch quoteMode {
            case .single:
                if character == "'" {
                    quoteMode = nil
                } else {
                    current.append(character)
                    hasCurrentArgument = true
                }
            case .double:
                if character == "\"" {
                    quoteMode = nil
                } else if character == "\\" {
                    isEscaping = true
                    hasCurrentArgument = true
                } else {
                    current.append(character)
                    hasCurrentArgument = true
                }
            case nil:
                if character == "'" {
                    quoteMode = .single
                    hasCurrentArgument = true
                } else if character == "\"" {
                    quoteMode = .double
                    hasCurrentArgument = true
                } else if character == "\\" {
                    isEscaping = true
                    hasCurrentArgument = true
                } else if character.isWhitespace {
                    if hasCurrentArgument {
                        arguments.append(current)
                        current = ""
                        hasCurrentArgument = false
                    }
                } else {
                    current.append(character)
                    hasCurrentArgument = true
                }
            }
        }

        if isEscaping {
            throw MCPArgumentTextError.danglingEscape
        }
        switch quoteMode {
        case .single:
            throw MCPArgumentTextError.unterminatedSingleQuote
        case .double:
            throw MCPArgumentTextError.unterminatedDoubleQuote
        case nil:
            break
        }
        if hasCurrentArgument {
            arguments.append(current)
        }

        return arguments
    }

    public static func format(_ arguments: [String]) -> String {
        arguments.map(formatArgument).joined(separator: " ")
    }

    private static func formatArgument(_ argument: String) -> String {
        if argument.isEmpty {
            return "''"
        }

        let needsQuoting = argument.contains { character in
            character.isWhitespace || character == "'" || character == "\"" || character == "\\"
        }
        guard needsQuoting else {
            return argument
        }

        return "'\(argument.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private enum MCPRegistrationSQL {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    static func optional(_ value: String?) -> String {
        guard let value else {
            return "NULL"
        }

        return "'\(escape(value))'"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public struct MCPEnvironmentDisplayRow: Equatable, Sendable {
    public var name: String
    public var sourceLabel: String

    public init(name: String, sourceLabel: String) {
        self.name = name
        self.sourceLabel = sourceLabel
    }
}

public struct MCPServerRegistrationDisplayModel: Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var commandLine: String
    public var transportLabel: String
    public var workingDirectoryLabel: String
    public var environmentRows: [MCPEnvironmentDisplayRow]
    public var isEnabled: Bool
    public var statusLabel: String

    public init(registration: MCPServerRegistration) {
        self.id = registration.id
        self.displayName = registration.displayName
        self.commandLine = MCPArgumentTextCodec.format([registration.command] + registration.arguments)
        self.transportLabel = "stdio"
        self.workingDirectoryLabel = registration.workingDirectory ?? "Default"
        self.environmentRows = registration.environment
            .map { key, reference in
                MCPEnvironmentDisplayRow(name: key, sourceLabel: reference.displayLabel)
            }
            .sorted { $0.name < $1.name }
        self.isEnabled = registration.isEnabled
        self.statusLabel = registration.isEnabled ? "Enabled" : "Disabled"
    }
}

private extension MCPEnvironmentReference {
    var displayLabel: String {
        switch self {
        case .keychain(let key):
            return "Keychain: \(key.rawValue)"
        }
    }
}

public enum MCPRegistrationError: Error, Equatable, Sendable {
    case invalidCommand
    case missingBinary(String)
    case invalidWorkingDirectory(String)
    case serverDisabled
    case missingSecret(String)
}

public protocol MCPEnvironmentResolver: Sendable {
    func resolve(_ environment: [String: MCPEnvironmentReference]) throws -> [String: String]
}

public struct SecretStoreMCPEnvironmentResolver: MCPEnvironmentResolver {
    private let secretStore: any SecretStore

    public init(secretStore: any SecretStore) {
        self.secretStore = secretStore
    }

    public func resolve(_ environment: [String: MCPEnvironmentReference]) throws -> [String: String] {
        try environment.reduce(into: [:]) { result, pair in
            switch pair.value {
            case .keychain(let key):
                guard let value = try secretStore.read(key), !value.isEmpty else {
                    throw MCPRegistrationError.missingSecret(pair.key)
                }
                result[pair.key] = value
            }
        }
    }
}

public struct NoSecretMCPEnvironmentResolver: MCPEnvironmentResolver {
    public init() {}

    public func resolve(_ environment: [String: MCPEnvironmentReference]) throws -> [String: String] {
        guard environment.isEmpty else {
            let firstMissingSecret = environment.keys.sorted().first ?? "MCP_ENV"
            throw MCPRegistrationError.missingSecret(firstMissingSecret)
        }
        return [:]
    }
}

public protocol MCPBinaryLocator: Sendable {
    func isExecutableAvailable(command: String) -> Bool
}

public struct PATHMCPBinaryLocator: MCPBinaryLocator {
    public init() {}

    public func isExecutableAvailable(command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        if trimmed.contains("/") {
            return FileManager.default.isExecutableFile(atPath: trimmed)
        }

        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin")
            .split(separator: ":")
            .map(String.init)
        return paths.contains { directory in
            FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: directory).appendingPathComponent(trimmed).path)
        }
    }
}

public struct MCPServerRegistrationValidator: Sendable {
    private let binaryLocator: any MCPBinaryLocator

    public init(binaryLocator: any MCPBinaryLocator = PATHMCPBinaryLocator()) {
        self.binaryLocator = binaryLocator
    }

    public func validate(_ registration: MCPServerRegistration) throws {
        let command = registration.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw MCPRegistrationError.invalidCommand
        }
        guard binaryLocator.isExecutableAvailable(command: command) else {
            throw MCPRegistrationError.missingBinary(command)
        }
        if let workingDirectory = registration.workingDirectory {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw MCPRegistrationError.invalidWorkingDirectory(workingDirectory)
            }
        }
    }
}

public struct MCPRegisteredServerDescriptor: Equatable, Sendable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct MCPStdioServerLauncher: Sendable {
    private let validator: MCPServerRegistrationValidator
    private let transportFactory: @Sendable (MCPServerRegistration) throws -> any MCPClientTransport

    public init(
        validator: MCPServerRegistrationValidator = MCPServerRegistrationValidator(),
        environmentResolver: any MCPEnvironmentResolver = NoSecretMCPEnvironmentResolver()
    ) {
        self.validator = validator
        self.transportFactory = { registration in
            let resolvedEnvironment = try environmentResolver.resolve(registration.environment)
            return MCPStdioTransport(registration: registration, resolvedEnvironment: resolvedEnvironment)
        }
    }

    public init(
        validator: MCPServerRegistrationValidator = MCPServerRegistrationValidator(),
        transportFactory: @escaping @Sendable (MCPServerRegistration) throws -> any MCPClientTransport
    ) {
        self.validator = validator
        self.transportFactory = transportFactory
    }

    public func client(for registration: MCPServerRegistration) async throws -> MCPClient {
        guard registration.isEnabled else {
            throw MCPRegistrationError.serverDisabled
        }
        try validator.validate(registration)
        let transport = try transportFactory(registration)
        if let process = transport as? any MCPServerProcess {
            try await process.start()
        }
        return MCPClient(serverID: registration.id, transport: transport)
    }
}
