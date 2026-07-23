import Foundation
import XCTest
@testable import SuisuiCore

final class ExternalSideEffectJournalTests: XCTestCase {
    func testSucceededClaimReturnsPersistedResultWithoutReexecution() throws {
        let store = try makeStore()
        let request = makeRequest()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expected = ToolResult(
            tool: .calendarCreateEvent,
            status: .succeeded,
            summary: "Created calendar event",
            output: ["eventId": .string("event-1")]
        )

        guard case .execute(let prepared) = try store.claim(request, at: now) else {
            return XCTFail("First claim must be executable.")
        }
        try store.markStarted(id: prepared.id, at: now)
        try store.markSucceeded(
            id: prepared.id,
            externalResourceID: "event-1",
            result: expected,
            at: now
        )

        XCTAssertEqual(try store.claim(request, at: now), .returnSucceeded(expected))
    }

    func testUnknownClaimBlocksBlindRetry() throws {
        let store = try makeStore()
        let request = makeRequest()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        guard case .execute(let prepared) = try store.claim(request, at: now) else {
            return XCTFail("First claim must be executable.")
        }
        try store.markStarted(id: prepared.id, at: now)
        try store.markUnknown(
            id: prepared.id,
            externalResourceID: nil,
            failureCategory: "external_result_uncertain",
            at: now
        )

        XCTAssertEqual(
            try store.claim(request, at: now),
            .requiresReconciliation(try XCTUnwrap(store.record(id: prepared.id)))
        )
    }

    func testFailedBeforeSideEffectCanRetryWithIncrementedAttempt() throws {
        let store = try makeStore()
        let request = makeRequest()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        guard case .execute(let first) = try store.claim(request, at: now) else {
            return XCTFail("First claim must be executable.")
        }
        try store.markStarted(id: first.id, at: now)
        try store.markFailedBeforeSideEffect(
            id: first.id,
            failureCategory: "permission_denied",
            at: now
        )

        guard case .execute(let retry) = try store.claim(request, at: now) else {
            return XCTFail("A known-safe failure must be retryable.")
        }
        XCTAssertEqual(retry.id, first.id)
        XCTAssertEqual(retry.attempt, 2)
        XCTAssertEqual(retry.state, .prepared)
    }

    func testRecoveryMovesStartedRecordsToUnknownAcrossRestart() throws {
        let root = temporaryDirectory()
        let databaseURL = root.appendingPathComponent("journal.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        let request = makeRequest()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recordID: String

        do {
            let store = try makeStore(path: databaseURL.path)
            guard case .execute(let prepared) = try store.claim(request, at: now) else {
                return XCTFail("First claim must be executable.")
            }
            recordID = prepared.id
            try store.markStarted(id: prepared.id, at: now)
        }

        let reopened = try makeStore(path: databaseURL.path)
        XCTAssertEqual(try reopened.recoverStartedAsUnknown(at: now), 1)
        XCTAssertEqual(try reopened.record(id: recordID)?.state, .unknown)
        guard case .requiresReconciliation = try reopened.claim(request, at: now) else {
            return XCTFail("Recovered uncertain work must not be retried.")
        }
    }

    func testConcurrentClaimsAllowOneExternalExecution() throws {
        let store = try makeStore()
        let request = makeRequest()
        let queue = DispatchQueue(label: "journal-claim", attributes: .concurrent)
        let group = DispatchGroup()
        let executableCount = LockedCounter()

        for _ in 0..<20 {
            group.enter()
            queue.async {
                defer { group.leave() }
                if case .execute = try? store.claim(request, at: Date()) {
                    executableCount.increment()
                }
            }
        }
        group.wait()

        XCTAssertEqual(executableCount.value, 1)
    }

    func testBulkItemsRoundTripIndependently() throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstRequest = makeRequest(itemIndex: 0, idempotencyKey: "bulk-key:0")
        let secondRequest = makeRequest(itemIndex: 1, idempotencyKey: "bulk-key:1")

        guard case .execute(let first) = try store.claim(firstRequest, at: now),
              case .execute(let second) = try store.claim(secondRequest, at: now) else {
            return XCTFail("Each bulk item must have an independent claim.")
        }
        try store.markStarted(id: first.id, at: now)
        try store.markSucceeded(
            id: first.id,
            externalResourceID: "reminder-1",
            result: ToolResult(tool: .remindersBulkCreate, status: .succeeded, summary: "Created reminder"),
            at: now
        )
        try store.markStarted(id: second.id, at: now)
        try store.markUnknown(
            id: second.id,
            externalResourceID: nil,
            failureCategory: "external_result_uncertain",
            at: now
        )

        let records = try store.records(executionID: "execution-1")
        XCTAssertEqual(records.map(\.itemIndex), [0, 1])
        XCTAssertEqual(records.map(\.state), [.succeeded, .unknown])
    }

    private func makeStore(path: String = ":memory:") throws -> SQLiteExternalSideEffectJournal {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return SQLiteExternalSideEffectJournal(connection: connection)
    }

    private func makeRequest(
        itemIndex: Int? = nil,
        idempotencyKey: String = "calendar-key"
    ) -> ExternalSideEffectRequest {
        ExternalSideEffectRequest(
            executionID: "execution-1",
            reviewSessionID: "session-1",
            actionID: "action-1",
            itemIndex: itemIndex,
            tool: .calendarCreateEvent,
            canonicalArgumentsDigest: Data(repeating: 7, count: 32),
            idempotencyKey: idempotencyKey
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuisuiJournalTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
