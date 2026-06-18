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

public struct MCPServerRegistrationRow: Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var commandLine: String
    public var statusLabel: String
    public var connectionCheckResultLabel: String
    public var protocolVersionLabel: String
    public var isSelected: Bool
    public var isCheckingConnection: Bool

    public init(
        registration: MCPServerRegistration,
        connectionSnapshot: MCPServerConnectionSnapshot = .notChecked,
        isSelected: Bool = false,
        isCheckingConnection: Bool = false
    ) {
        self.id = registration.id
        self.displayName = registration.displayName
        self.commandLine = MCPArgumentTextCodec.format([registration.command] + registration.arguments)
        self.statusLabel = registration.isEnabled ? "Enabled" : "Disabled"
        self.connectionCheckResultLabel = connectionSnapshot.resultLabel
        self.protocolVersionLabel = connectionSnapshot.protocolVersionLabel
        self.isSelected = isSelected
        self.isCheckingConnection = isCheckingConnection
    }
}

public struct MCPServerConnectionSnapshot: Equatable, Sendable {
    public var resultLabel: String
    public var protocolVersionLabel: String
    public var failureTaxonomyLabel: String?

    public init(resultLabel: String, protocolVersionLabel: String, failureTaxonomyLabel: String? = nil) {
        self.resultLabel = resultLabel
        self.protocolVersionLabel = protocolVersionLabel
        self.failureTaxonomyLabel = failureTaxonomyLabel
    }

    public static let notChecked = MCPServerConnectionSnapshot(
        resultLabel: "Not checked",
        protocolVersionLabel: "Not checked",
        failureTaxonomyLabel: nil
    )
}

public enum MCPRegistrationStoreError: Error, Equatable, Sendable {
    case encodingFailed
    case decodingFailed
}

public protocol MCPServerRegistrationStore: Sendable {
    func loadRegistrations() throws -> [MCPServerRegistration]
    func saveRegistrations(_ registrations: [MCPServerRegistration]) throws
    func saveRegistration(_ registration: MCPServerRegistration) throws
    func deleteRegistration(id: String) throws
}

public extension MCPServerRegistrationStore {
    func saveRegistration(_ registration: MCPServerRegistration) throws {
        let updatedRegistrations = replacing(registration, in: try loadRegistrations())
        try saveRegistrations(updatedRegistrations)
    }

    func deleteRegistration(id: String) throws {
        try saveRegistrations(try loadRegistrations().filter { $0.id != id })
    }

    private func replacing(
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

    public func saveRegistration(_ registration: MCPServerRegistration) throws {
        lock.lock()
        defer { lock.unlock() }

        do {
            try connection.transaction {
                let sortOrder = try sortOrderLocked(for: registration.id)
                try upsertLocked(registration, sortOrder: sortOrder)
            }
        } catch let error as MCPRegistrationStoreError {
            throw error
        } catch {
            throw MCPRegistrationStoreError.encodingFailed
        }
    }

    public func deleteRegistration(id: String) throws {
        lock.lock()
        defer { lock.unlock() }

        do {
            try connection.execute(
                "DELETE FROM mcp_server_registrations WHERE id = '\(MCPRegistrationSQL.escape(id))';"
            )
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

    private func upsertLocked(_ registration: MCPServerRegistration, sortOrder: Int) throws {
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
            )
            ON CONFLICT(id) DO UPDATE SET
              display_name = excluded.display_name,
              command = excluded.command,
              arguments_json = excluded.arguments_json,
              environment_json = excluded.environment_json,
              working_directory = excluded.working_directory,
              is_enabled = excluded.is_enabled,
              updated_at = CURRENT_TIMESTAMP;
            """
        )
    }

    private func sortOrderLocked(for id: String) throws -> Int {
        if let existingValue = try connection
            .queryRows("SELECT sort_order FROM mcp_server_registrations WHERE id = '\(MCPRegistrationSQL.escape(id))' LIMIT 1;")
            .first?["sort_order"],
           let existingSortOrder = Int(existingValue) {
            return existingSortOrder
        }

        let maxValue = try connection
            .queryRows("SELECT COALESCE(MAX(sort_order), -1) AS max_sort_order FROM mcp_server_registrations;")
            .first?["max_sort_order"]
        return (Int(maxValue ?? "-1") ?? -1) + 1
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
    @Published public private(set) var registrationRows: [MCPServerRegistrationRow]
    @Published public private(set) var selectedRegistrationID: String?
    @Published public private(set) var environmentText: String
    @Published public private(set) var toolRows: [ExternalMCPToolCatalogRow]
    @Published public private(set) var auditRows: [ExternalMCPAuditHistoryRow]
    @Published public private(set) var auditErrorMessage: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isCheckingConnection: Bool
    @Published public private(set) var protocolVersionLabel: String
    @Published public private(set) var connectionCheckResultLabel: String
    @Published public private(set) var connectionFailureTaxonomyLabel: String?

    private let store: any MCPServerRegistrationStore
    private let launcher: MCPStdioServerLauncher
    private let registrationValidator: MCPServerRegistrationValidator
    private var registrations: [MCPServerRegistration]
    private var connectionSnapshotsByRegistrationID: [String: MCPServerConnectionSnapshot]
    private var toolRowsByRegistrationID: [String: [ExternalMCPToolCatalogRow]]
    private var checkingRegistrationID: String?

    public init(
        store: any MCPServerRegistrationStore,
        launcher: MCPStdioServerLauncher = MCPStdioServerLauncher(),
        registrationValidator: MCPServerRegistrationValidator = MCPServerRegistrationValidator(),
        toolRows: [ExternalMCPToolCatalogRow] = [],
        auditRows: [ExternalMCPAuditHistoryRow] = [],
        auditErrorMessage: String? = nil
    ) {
        self.store = store
        self.launcher = launcher
        self.registrationValidator = registrationValidator
        self.toolRows = toolRows
        self.auditRows = auditRows
        self.auditErrorMessage = auditErrorMessage
        self.errorMessage = nil
        self.isCheckingConnection = false
        self.protocolVersionLabel = "Not checked"
        self.connectionCheckResultLabel = "Not checked"
        self.connectionFailureTaxonomyLabel = nil
        self.registrations = []
        self.connectionSnapshotsByRegistrationID = [:]
        self.toolRowsByRegistrationID = [:]
        self.checkingRegistrationID = nil
        self.registration = Self.blankRegistration(existingIDs: [])
        self.registrationRows = []
        self.selectedRegistrationID = nil
        self.environmentText = ""
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
            let loadedRegistrations = try store.loadRegistrations()
            registrations = loadedRegistrations
            let preferredID = selectedRegistrationID ?? registration.id
            if let selected = loadedRegistrations.first(where: { $0.id == preferredID }) ?? loadedRegistrations.first {
                registration = selected
                selectedRegistrationID = selected.id
            } else {
                registration = Self.blankRegistration(existingIDs: [])
                selectedRegistrationID = registration.id
            }
            syncEnvironmentTextFromRegistration()
            refreshRegistrationRows()
            errorMessage = nil
        } catch {
            errorMessage = Self.storeErrorMessage(error)
        }
    }

    public func selectRegistration(id: String) {
        guard let selected = registrations.first(where: { $0.id == id }) else {
            errorMessage = "MCP registration was not found."
            return
        }

        registration = selected
        selectedRegistrationID = selected.id
        syncEnvironmentTextFromRegistration()
        applySelectedConnectionSnapshot()
        refreshRegistrationRows()
        errorMessage = nil
    }

    public func createRegistration() {
        registration = Self.blankRegistration(existingIDs: Set(registrations.map(\.id)))
        selectedRegistrationID = registration.id
        syncEnvironmentTextFromRegistration()
        resetConnectionSnapshot(for: registration.id)
        refreshRegistrationRows()
        errorMessage = nil
    }

    public func updateEnabled(_ isEnabled: Bool) {
        var updated = registration
        updated.isEnabled = isEnabled
        registration = updated
        resetConnectionSnapshot(for: registration.id)
        refreshRegistrationRows()
    }

    public func updateDisplayName(_ displayName: String) {
        var updated = registration
        updated.displayName = displayName
        registration = updated
        refreshRegistrationRows()
    }

    public func updateCommand(_ command: String) {
        var updated = registration
        updated.command = command
        registration = updated
        resetConnectionSnapshot(for: registration.id)
        refreshRegistrationRows()
    }

    public func updateArgumentsText(_ argumentsText: String) {
        do {
            var updated = registration
            updated.arguments = try MCPArgumentTextCodec.parse(argumentsText)
            registration = updated
            resetConnectionSnapshot(for: registration.id)
            refreshRegistrationRows()
            errorMessage = nil
        } catch {
            errorMessage = Self.argumentErrorMessage(error)
        }
    }

    public func updateEnvironmentText(_ environmentText: String) {
        self.environmentText = environmentText
        do {
            var updated = registration
            updated.environment = try MCPEnvironmentTextCodec.parse(environmentText)
            registration = updated
            resetConnectionSnapshot(for: registration.id)
            refreshRegistrationRows()
            errorMessage = nil
        } catch {
            errorMessage = Self.environmentErrorMessage(error)
        }
    }

    public func updateWorkingDirectory(_ workingDirectory: String) {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = registration
        updated.workingDirectory = trimmed.isEmpty ? nil : trimmed
        registration = updated
        resetConnectionSnapshot(for: registration.id)
        refreshRegistrationRows()
    }

    public func save() {
        do {
            var registrationToSave = registration
            registrationToSave.environment = try MCPEnvironmentTextCodec.parse(environmentText)
            try registrationValidator.validate(registrationToSave)
            try store.saveRegistration(registrationToSave)
            registrations = Self.replacing(registrationToSave, in: registrations)
            registration = registrationToSave
            selectedRegistrationID = registrationToSave.id
            syncEnvironmentTextFromRegistration()
            resetConnectionSnapshot(for: registrationToSave.id)
            refreshRegistrationRows()
            errorMessage = nil
        } catch let error as MCPEnvironmentTextError {
            errorMessage = Self.environmentErrorMessage(error)
        } catch let error as MCPRegistrationStoreError {
            errorMessage = Self.storeErrorMessage(error)
        } catch {
            errorMessage = Self.connectionErrorMessage(error)
        }
    }

    public func deleteRegistration() {
        do {
            let deletedRegistrationID = registration.id
            let remainingRegistrations = registrations.filter { $0.id != registration.id }
            try store.deleteRegistration(id: registration.id)
            registrations = remainingRegistrations
            registration = remainingRegistrations.first ?? Self.blankRegistration(existingIDs: [])
            selectedRegistrationID = registration.id
            syncEnvironmentTextFromRegistration()
            connectionSnapshotsByRegistrationID.removeValue(forKey: deletedRegistrationID)
            toolRowsByRegistrationID.removeValue(forKey: deletedRegistrationID)
            refreshRegistrationRows()
            applySelectedConnectionSnapshot()
            errorMessage = nil
        } catch let error as MCPRegistrationStoreError {
            errorMessage = Self.storeErrorMessage(error)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func checkConnection() async {
        await checkConnection(registration)
    }

    public func checkConnection(id registrationID: String) async {
        if registration.id != registrationID {
            selectRegistration(id: registrationID)
            guard registration.id == registrationID else {
                return
            }
        }
        await checkConnection(registration)
    }

    private func checkConnection(_ targetRegistration: MCPServerRegistration) async {
        checkingRegistrationID = targetRegistration.id
        isCheckingConnection = true
        let checkingSnapshot = MCPServerConnectionSnapshot(
            resultLabel: "Checking",
            protocolVersionLabel: connectionSnapshotsByRegistrationID[targetRegistration.id]?.protocolVersionLabel ?? "Not checked",
            failureTaxonomyLabel: nil
        )
        connectionSnapshotsByRegistrationID[targetRegistration.id] = checkingSnapshot
        if registration.id == targetRegistration.id {
            protocolVersionLabel = checkingSnapshot.protocolVersionLabel
            connectionCheckResultLabel = checkingSnapshot.resultLabel
            connectionFailureTaxonomyLabel = nil
            toolRows = toolRowsByRegistrationID[targetRegistration.id] ?? []
        }
        refreshRegistrationRows()
        defer {
            checkingRegistrationID = nil
            isCheckingConnection = false
            refreshRegistrationRows()
        }

        var negotiatedProtocolVersion: String?
        do {
            let client = try await launcher.client(for: targetRegistration)
            let initialize = try await client.initialize()
            negotiatedProtocolVersion = initialize.protocolVersion
            let tools = try await client.listTools()
            let server = MCPRegisteredServerDescriptor(id: targetRegistration.id, displayName: targetRegistration.displayName)
            let registry = ExternalMCPToolRegistry(
                server: server,
                tools: tools,
                classifier: ExternalMCPToolClassifier()
            )
            let rows = ExternalMCPToolCatalog.rows(from: registry.allDescriptors)
            let connectedSnapshot = MCPServerConnectionSnapshot(
                resultLabel: "Connected",
                protocolVersionLabel: initialize.protocolVersion
            )
            connectionSnapshotsByRegistrationID[targetRegistration.id] = connectedSnapshot
            toolRowsByRegistrationID[targetRegistration.id] = rows
            if registration.id == targetRegistration.id {
                protocolVersionLabel = connectedSnapshot.protocolVersionLabel
                connectionCheckResultLabel = connectedSnapshot.resultLabel
                connectionFailureTaxonomyLabel = nil
                toolRows = rows
                errorMessage = nil
            } else {
                applySelectedConnectionSnapshot()
            }
        } catch {
            toolRowsByRegistrationID.removeValue(forKey: targetRegistration.id)
            let failedProtocolVersionLabel = negotiatedProtocolVersion ?? "Not checked"
            let failureTaxonomy = Self.inspectorFailureTaxonomy(for: error)
            let failedSnapshot = MCPServerConnectionSnapshot(
                resultLabel: failureTaxonomy.map { "Failed: \($0)" } ?? "Failed",
                protocolVersionLabel: failedProtocolVersionLabel,
                failureTaxonomyLabel: failureTaxonomy
            )
            connectionSnapshotsByRegistrationID[targetRegistration.id] = failedSnapshot
            if registration.id == targetRegistration.id {
                protocolVersionLabel = failedSnapshot.protocolVersionLabel
                connectionCheckResultLabel = failedSnapshot.resultLabel
                connectionFailureTaxonomyLabel = failedSnapshot.failureTaxonomyLabel
                toolRows = []
                errorMessage = Self.connectionErrorMessage(error, failureTaxonomy: failureTaxonomy)
            } else {
                applySelectedConnectionSnapshot()
            }
        }
    }

    private static func blankRegistration(existingIDs: Set<String>) -> MCPServerRegistration {
        let baseID = "custom-mcp"
        let id: String
        if existingIDs.contains(baseID) {
            var suffix = 2
            while existingIDs.contains("\(baseID)-\(suffix)") {
                suffix += 1
            }
            id = "\(baseID)-\(suffix)"
        } else {
            id = baseID
        }

        return MCPServerRegistration(
            id: id,
            displayName: "Custom MCP",
            command: "",
            arguments: [],
            environment: [:],
            workingDirectory: nil,
            isEnabled: false
        )
    }

    private func refreshRegistrationRows() {
        var rows = registrations.map { saved in
            let rowRegistration = saved.id == registration.id ? registration : saved
            return MCPServerRegistrationRow(
                registration: rowRegistration,
                connectionSnapshot: connectionSnapshotsByRegistrationID[rowRegistration.id] ?? .notChecked,
                isSelected: rowRegistration.id == registration.id,
                isCheckingConnection: checkingRegistrationID == rowRegistration.id
            )
        }
        if !registrations.contains(where: { $0.id == registration.id }) {
            rows.append(
                MCPServerRegistrationRow(
                    registration: registration,
                    connectionSnapshot: connectionSnapshotsByRegistrationID[registration.id] ?? .notChecked,
                    isSelected: true,
                    isCheckingConnection: checkingRegistrationID == registration.id
                )
            )
        }
        registrationRows = rows
    }

    private func syncEnvironmentTextFromRegistration() {
        environmentText = MCPEnvironmentTextCodec.format(registration.environment)
    }

    private func resetConnectionSnapshot(for registrationID: String) {
        connectionSnapshotsByRegistrationID.removeValue(forKey: registrationID)
        toolRowsByRegistrationID.removeValue(forKey: registrationID)
        applySelectedConnectionSnapshot()
    }

    private func applySelectedConnectionSnapshot() {
        let snapshot = connectionSnapshotsByRegistrationID[registration.id] ?? .notChecked
        protocolVersionLabel = snapshot.protocolVersionLabel
        connectionCheckResultLabel = snapshot.resultLabel
        connectionFailureTaxonomyLabel = snapshot.failureTaxonomyLabel
        toolRows = toolRowsByRegistrationID[registration.id] ?? []
    }

    private static func connectionErrorMessage(_ error: Error, failureTaxonomy: String? = nil) -> String {
        let message: String
        switch error {
        case MCPRegistrationError.serverDisabled:
            message = "MCP server is disabled."
        case MCPRegistrationError.invalidCommand:
            message = "MCP command is required."
        case MCPRegistrationError.missingBinary(let command):
            message = "MCP command binary was not found: \(command)"
        case MCPRegistrationError.invalidWorkingDirectory(let path):
            message = "MCP working directory was not found: \(path)"
        case MCPRegistrationError.missingSecret(let name):
            message = "MCP environment secret is missing: \(name)"
        case MCPClientError.invalidResponse(_, "tools/list", let reason):
            message = "MCP tools/list response was invalid: \(reason)"
        case MCPClientError.invalidResponse(_, "initialize", let reason):
            message = "MCP initialize response was invalid: \(reason)"
        case MCPClientError.protocolError(_, let method, _, let protocolMessage):
            message = "MCP \(method) failed: \(protocolMessage)"
        case MCPClientError.timeout(_, let method):
            message = "MCP \(method) timed out."
        case MCPClientError.transportFailed(_, let method, let transportMessage):
            message = "MCP \(method) transport failed: \(transportMessage)"
        default:
            message = String(describing: error)
        }

        if let failureTaxonomy {
            return "[\(failureTaxonomy)] \(message)"
        }
        return message
    }

    private static func inspectorFailureTaxonomy(for error: Error) -> String? {
        switch error {
        case MCPClientError.timeout:
            return "timeout"
        case MCPClientError.invalidResponse(_, _, let reason) where reason == "Malformed JSON-RPC response.":
            return "malformed-json"
        case MCPClientError.invalidResponse(_, _, let reason) where reason == "Mismatched response id.":
            return "mismatched-id"
        case MCPClientError.invalidResponse(_, "tools/list", let reason)
            where reason.contains("result.tools") ||
            reason.contains("Tool entry") ||
            reason.contains("inputSchema"):
            return "invalid-schema"
        default:
            return nil
        }
    }

    private static func storeErrorMessage(_ error: Error) -> String {
        switch error {
        case MCPRegistrationStoreError.decodingFailed:
            return "MCP registrations could not be loaded from the local database."
        case MCPRegistrationStoreError.encodingFailed:
            return "MCP registrations could not be saved to the local database."
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

    private static func environmentErrorMessage(_ error: Error) -> String {
        switch error {
        case MCPEnvironmentTextError.rawValueNotAllowed:
            return "MCP environment values must reference Keychain entries using keychain:<secret_key>."
        case MCPEnvironmentTextError.missingAssignment(let line):
            return "MCP environment line \(line) must use NAME=keychain:<secret_key>."
        case MCPEnvironmentTextError.invalidName(let line, let name):
            return "MCP environment line \(line) has an invalid variable name: \(name)."
        case MCPEnvironmentTextError.missingKeychainKey(let line):
            return "MCP environment line \(line) is missing a Keychain secret key."
        case MCPEnvironmentTextError.invalidKeychainKey(let line, let name):
            return "MCP environment line \(line) has an invalid Keychain secret key: \(name)."
        default:
            return "MCP environment references are invalid: \(error)"
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

public enum MCPEnvironmentTextError: Error, Equatable, Sendable {
    case missingAssignment(line: Int)
    case invalidName(line: Int, name: String)
    case rawValueNotAllowed(line: Int)
    case missingKeychainKey(line: Int)
    case invalidKeychainKey(line: Int, name: String)
}

public enum MCPEnvironmentTextCodec {
    public static func parse(_ text: String) throws -> [String: MCPEnvironmentReference] {
        var environment: [String: MCPEnvironmentReference] = [:]
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            guard let separatorIndex = line.firstIndex(of: "=") else {
                throw MCPEnvironmentTextError.missingAssignment(line: lineNumber)
            }

            let rawName = String(line[..<separatorIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidEnvironmentName(rawName) else {
                throw MCPEnvironmentTextError.invalidName(line: lineNumber, name: rawName)
            }

            let rawValue = String(line[line.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard rawValue.hasPrefix("keychain:") else {
                throw MCPEnvironmentTextError.rawValueNotAllowed(line: lineNumber)
            }

            let rawKeyName = String(rawValue.dropFirst("keychain:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawKeyName.isEmpty else {
                throw MCPEnvironmentTextError.missingKeychainKey(line: lineNumber)
            }
            let keyName: String
            do {
                keyName = try SecretKeyNameValidator.normalize(rawKeyName)
            } catch {
                throw MCPEnvironmentTextError.invalidKeychainKey(line: lineNumber, name: rawKeyName)
            }

            environment[rawName] = .keychain(SecretKey(keyName))
        }
        return environment
    }

    public static func format(_ environment: [String: MCPEnvironmentReference]) -> String {
        environment
            .sorted { $0.key < $1.key }
            .map { name, reference in
                switch reference {
                case .keychain(let key):
                    return "\(name)=keychain:\(key.rawValue)"
                }
            }
            .joined(separator: "\n")
    }

    private static func isValidEnvironmentName(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard let first = scalars.first,
              first == "_" || isASCIIAlpha(first) else {
            return false
        }
        return scalars.allSatisfy { scalar in
            scalar == "_" || isASCIIAlpha(scalar) || isASCIIDigit(scalar)
        }
    }

    private static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar)
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
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
