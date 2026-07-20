import Foundation
@testable import SuisuiCore

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [SecretKey: String]
    private let lock = NSLock()

    init(values: [SecretKey: String] = [:]) {
        self.values = values
    }

    func save(_ value: String, for key: SecretKey) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func read(_ key: SecretKey) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func delete(_ key: SecretKey) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

final class InMemoryAuditLogger: AuditLogger, @unchecked Sendable {
    private var events: [AuditEvent]
    private let lock = NSLock()

    init(events: [AuditEvent] = []) {
        self.events = events
    }

    var recordedEvents: [AuditEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func record(_ event: AuditEvent) throws {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }
}

final class InMemoryMCPServerRegistrationStore: MCPServerRegistrationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var registrations: [MCPServerRegistration]

    init(registrations: [MCPServerRegistration] = []) {
        self.registrations = registrations
    }

    func loadRegistrations() throws -> [MCPServerRegistration] {
        lock.lock()
        defer { lock.unlock() }
        return registrations
    }

    func saveRegistrations(_ registrations: [MCPServerRegistration]) throws {
        lock.lock()
        defer { lock.unlock() }
        self.registrations = registrations
    }
}
