import Foundation

public enum MCPEnvironmentReference: Equatable, Sendable {
    case keychain(SecretKey)
}

public struct MCPServerRegistration: Equatable, Sendable {
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
        transportFactory: @escaping @Sendable (MCPServerRegistration) throws -> any MCPClientTransport
    ) {
        self.validator = validator
        self.transportFactory = transportFactory
    }

    public func client(for registration: MCPServerRegistration) throws -> MCPClient {
        guard registration.isEnabled else {
            throw MCPRegistrationError.serverDisabled
        }
        try validator.validate(registration)
        return MCPClient(serverID: registration.id, transport: try transportFactory(registration))
    }
}
