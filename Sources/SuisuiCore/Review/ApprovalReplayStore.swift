import Foundation

public enum ApprovalReplayState: String, Codable, Equatable, Sendable {
    case started
    case completed
    case failed
    case unknown
}

public protocol ApprovalReplayStore: Sendable {
    /// Atomically records first use of a nonce. A false result means another
    /// execution already claimed it, regardless of that execution's outcome.
    func claim(_ approval: ApprovedExecution, at: Date) throws -> Bool
    func finish(nonce: UUID, state: ApprovalReplayState, at: Date) throws
    func state(for nonce: UUID) throws -> ApprovalReplayState?
}

public final class InMemoryApprovalReplayStore: ApprovalReplayStore, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [UUID: ApprovalReplayState] = [:]

    public init() {}

    public func claim(_ approval: ApprovedExecution, at: Date) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard states[approval.nonce] == nil else {
            return false
        }
        states[approval.nonce] = .started
        return true
    }

    public func finish(nonce: UUID, state: ApprovalReplayState, at: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        guard states[nonce] != nil else {
            return
        }
        states[nonce] = state
    }

    public func state(for nonce: UUID) throws -> ApprovalReplayState? {
        lock.lock()
        defer { lock.unlock() }
        return states[nonce]
    }
}

public final class SQLiteApprovalReplayStore: ApprovalReplayStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()
    private let dateFormatter: ISO8601DateFormatter

    public init(connection: SQLiteConnection) {
        self.connection = connection
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter = formatter
    }

    public func claim(_ approval: ApprovedExecution, at: Date) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try connection.execute(
            """
            INSERT OR IGNORE INTO approval_execution_nonces (
                nonce,
                approval_id,
                session_id,
                plan_id,
                canonical_plan_digest,
                state,
                claimed_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, 'started', ?, ?);
            """,
            parameters: [
                .text(approval.nonce.uuidString),
                .text(approval.approvalID.uuidString),
                .text(approval.sessionID),
                .text(approval.planID),
                .blob(approval.canonicalPlanDigest),
                .text(dateFormatter.string(from: at)),
                .text(dateFormatter.string(from: at))
            ]
        )
        return connection.numberOfChanges == 1
    }

    public func finish(nonce: UUID, state: ApprovalReplayState, at: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        try connection.execute(
            """
            UPDATE approval_execution_nonces
            SET state = ?, updated_at = ?
            WHERE nonce = ?;
            """,
            parameters: [
                .text(state.rawValue),
                .text(dateFormatter.string(from: at)),
                .text(nonce.uuidString)
            ]
        )
    }

    public func state(for nonce: UUID) throws -> ApprovalReplayState? {
        lock.lock()
        defer { lock.unlock() }
        let rawState = try connection.queryStrings(
            "SELECT state FROM approval_execution_nonces WHERE nonce = ?;",
            parameters: [.text(nonce.uuidString)]
        ).first
        return rawState.flatMap(ApprovalReplayState.init(rawValue:))
    }
}
