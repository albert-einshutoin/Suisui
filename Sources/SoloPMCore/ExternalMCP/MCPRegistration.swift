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

public final class UserDefaultsMCPServerRegistrationStore: MCPServerRegistrationStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "external_mcp.registrations") {
        self.defaults = defaults
        self.key = key
    }

    public func loadRegistrations() throws -> [MCPServerRegistration] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        do {
            return try JSONDecoder().decode([MCPServerRegistration].self, from: data)
        } catch {
            throw MCPRegistrationStoreError.decodingFailed
        }
    }

    public func saveRegistrations(_ registrations: [MCPServerRegistration]) throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            let data = try JSONEncoder().encode(registrations)
            defaults.set(data, forKey: key)
        } catch {
            throw MCPRegistrationStoreError.encodingFailed
        }
    }
}

public final class InMemoryMCPServerRegistrationStore: MCPServerRegistrationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var registrations: [MCPServerRegistration]

    public init(registrations: [MCPServerRegistration] = []) {
        self.registrations = registrations
    }

    public func loadRegistrations() throws -> [MCPServerRegistration] {
        lock.lock()
        defer { lock.unlock() }
        return registrations
    }

    public func saveRegistrations(_ registrations: [MCPServerRegistration]) throws {
        lock.lock()
        defer { lock.unlock() }
        self.registrations = registrations
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

    public init(
        store: any MCPServerRegistrationStore,
        launcher: MCPStdioServerLauncher = MCPStdioServerLauncher(),
        toolRows: [ExternalMCPToolCatalogRow] = [],
        auditRows: [ExternalMCPAuditHistoryRow] = []
    ) {
        self.store = store
        self.launcher = launcher
        self.toolRows = toolRows
        self.auditRows = auditRows
        self.errorMessage = nil
        self.isCheckingConnection = false
        self.registration = Self.blankRegistration()
        refresh()
    }

    public var display: MCPServerRegistrationDisplayModel {
        MCPServerRegistrationDisplayModel(registration: registration)
    }

    public func refresh() {
        do {
            registration = try store.loadRegistrations().first ?? Self.blankRegistration()
            errorMessage = nil
        } catch {
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
        var updated = registration
        updated.arguments = argumentsText
            .split(separator: " ")
            .map(String.init)
        registration = updated
    }

    public func updateWorkingDirectory(_ workingDirectory: String) {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = registration
        updated.workingDirectory = trimmed.isEmpty ? nil : trimmed
        registration = updated
    }

    public func save() {
        do {
            try store.saveRegistrations([registration])
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
        self.commandLine = ([registration.command] + registration.arguments)
            .map(Self.displayArgument)
            .joined(separator: " ")
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

    private static func displayArgument(_ argument: String) -> String {
        guard argument.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return argument
        }
        return "'\(argument.replacingOccurrences(of: "'", with: "'\\''"))'"
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
