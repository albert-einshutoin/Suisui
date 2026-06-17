import Foundation

public struct AuditEvent: Equatable, Sendable {
    public var timestamp: Date
    public var category: String
    public var action: String
    public var status: AuditStatus
    public var metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        category: String,
        action: String,
        status: AuditStatus,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.category = category
        self.action = action
        self.status = status
        self.metadata = metadata
    }
}

public enum AuditStatus: String, Equatable, Sendable {
    case started
    case succeeded
    case failed
    case skipped
}

public protocol AuditLogger: Sendable {
    func record(_ event: AuditEvent) throws
}

public final class InMemoryAuditLogger: AuditLogger, @unchecked Sendable {
    private var events: [AuditEvent]
    private let lock = NSLock()

    public init(events: [AuditEvent] = []) {
        self.events = events
    }

    public var recordedEvents: [AuditEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    public func record(_ event: AuditEvent) throws {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }
}

public struct RedactingAuditLogger: AuditLogger {
    private let base: AuditLogger

    public init(base: AuditLogger) {
        self.base = base
    }

    public func record(_ event: AuditEvent) throws {
        var redacted = event
        redacted.metadata = SecretRedactor.redact(metadata: event.metadata)
        try base.record(redacted)
    }
}

public enum SecretRedactor {
    private static let sensitiveFragments = [
        "api_key",
        "apikey",
        "authorization",
        "bearer",
        "secret",
        "token",
        "password"
    ]

    public static func redact(metadata: [String: String]) -> [String: String] {
        metadata.mapValues { value in
            containsSensitiveValue(value) ? "[REDACTED]" : value
        }.reduce(into: [:]) { result, pair in
            let key = pair.key
            let value = pair.value
            result[key] = containsSensitiveKey(key) ? "[REDACTED]" : value
        }
    }

    private static func containsSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return sensitiveFragments.contains { normalized.contains($0) }
    }

    private static func containsSensitiveValue(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.hasPrefix("bearer ") || normalized.contains("sk-") || normalized.contains("api_key=")
    }
}
