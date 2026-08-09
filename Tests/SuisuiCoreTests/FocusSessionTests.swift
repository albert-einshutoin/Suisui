import XCTest
@testable import SuisuiCore

@MainActor
final class FocusSessionTests: XCTestCase {
    func testTransitionsPersistOnlyOnTransitionsAndCompletion() {
        let clock = MutableFocusClock("2026-08-09T09:00:00Z")
        let persistence = InMemoryFocusPersistence()
        let store = TodayFocusSessionStore(clock: clock, persistence: persistence)

        XCTAssertEqual(store.start(taskID: 42, durationSeconds: 60), .success(FocusSessionRecord(taskID: 42, durationSeconds: 60, accumulatedSeconds: 0, resumedAt: clock.now(), state: .running)))
        XCTAssertEqual(persistence.saveCount, 1)
        clock.advance(by: 10)
        store.tick()
        XCTAssertEqual(store.elapsedSeconds, 10)
        XCTAssertEqual(persistence.saveCount, 1)

        XCTAssertEqual(store.pause(), .success(FocusSessionRecord(taskID: 42, durationSeconds: 60, accumulatedSeconds: 10, resumedAt: nil, state: .paused)))
        XCTAssertEqual(store.resume(), .success(FocusSessionRecord(taskID: 42, durationSeconds: 60, accumulatedSeconds: 10, resumedAt: clock.now(), state: .running)))
        clock.advance(by: 50)
        store.tick()

        XCTAssertEqual(store.record.state, .completed)
        XCTAssertEqual(store.elapsedSeconds, 60)
        XCTAssertEqual(persistence.saveCount, 4)
        XCTAssertEqual(store.end(), .success(.idle))
        XCTAssertEqual(store.record, .idle)
    }

    func testRestoreRecoversRunningTimeButPausedTimeDoesNotAdvance() {
        let startedAt = date("2026-08-09T09:00:00Z")
        let clock = MutableFocusClock("2026-08-09T09:16:14Z")
        let runningPersistence = InMemoryFocusPersistence(record: FocusSessionRecord(taskID: 42, durationSeconds: 1_800, accumulatedSeconds: 0, resumedAt: startedAt, state: .running))
        let runningStore = TodayFocusSessionStore(clock: clock, persistence: runningPersistence)

        XCTAssertEqual(runningStore.elapsedSeconds, 974)
        XCTAssertEqual(runningStore.record.state, .running)

        let pausedPersistence = InMemoryFocusPersistence(record: FocusSessionRecord(taskID: 42, durationSeconds: 1_800, accumulatedSeconds: 120, resumedAt: nil, state: .paused))
        let pausedStore = TodayFocusSessionStore(clock: clock, persistence: pausedPersistence)
        XCTAssertEqual(pausedStore.elapsedSeconds, 120)
    }

    func testRestoreCompletesExpiredRunningSessionOnceAndClampsElapsedToDuration() {
        let startedAt = date("2026-08-09T09:00:00Z")
        let clock = MutableFocusClock("2026-08-09T09:05:00Z")
        let persistence = InMemoryFocusPersistence(
            record: FocusSessionRecord(
                taskID: 42,
                durationSeconds: 60,
                accumulatedSeconds: 30,
                resumedAt: startedAt,
                state: .running
            )
        )

        let store = TodayFocusSessionStore(clock: clock, persistence: persistence)

        XCTAssertEqual(store.record.state, .completed)
        XCTAssertEqual(store.elapsedSeconds, 60)
        XCTAssertEqual(store.record.accumulatedSeconds, 60)
        XCTAssertNil(store.record.resumedAt)
        XCTAssertEqual(persistence.saveCount, 1)
        XCTAssertEqual(persistence.record, store.record)

        XCTAssertEqual(store.restore(), store.record)
        XCTAssertEqual(persistence.saveCount, 1)
    }

    func testFocusProtectsActiveSessionAndClampsBackwardClock() {
        let clock = MutableFocusClock("2026-08-09T09:00:00Z")
        let persistence = InMemoryFocusPersistence()
        let store = TodayFocusSessionStore(clock: clock, persistence: persistence)

        XCTAssertNotNil(try? store.start(taskID: 1, durationSeconds: 120).get())
        XCTAssertEqual(store.start(taskID: 2, durationSeconds: 120), .failure(.requiresReplacement(existingTaskID: 1)))
        XCTAssertNotNil(try? store.start(taskID: 2, durationSeconds: 120, replaceExisting: true).get())
        clock.advance(by: -60)
        store.tick()

        XCTAssertEqual(store.elapsedSeconds, 0)
        XCTAssertEqual(store.pause(), .success(FocusSessionRecord(taskID: 2, durationSeconds: 120, accumulatedSeconds: 0, resumedAt: nil, state: .paused)))
        XCTAssertEqual(store.resume(), .success(FocusSessionRecord(taskID: 2, durationSeconds: 120, accumulatedSeconds: 0, resumedAt: clock.now(), state: .running)))
    }

    func testFeatureViewModelsShareOneFocusSessionAndRejectUnconfirmedReplacement() {
        let clock = MutableFocusClock("2026-08-09T09:00:00Z")
        let persistence = InMemoryFocusPersistence()
        let registry = TodayFocusSessionStoreRegistry {
            TodayFocusSessionStore(clock: clock, persistence: persistence)
        }
        let firstBoard = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        let secondBoard = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        let first = TodayFeatureViewModel(board: firstBoard, focusSessionRegistry: registry)
        let second = TodayFeatureViewModel(board: secondBoard, focusSessionRegistry: registry)

        XCTAssertTrue(first.focusSession === second.focusSession)
        XCTAssertNotNil(try? first.focusSession.start(taskID: 1, durationSeconds: 120).get())
        XCTAssertEqual(
            second.focusSession.start(taskID: 2, durationSeconds: 120),
            .failure(.requiresReplacement(existingTaskID: 1))
        )
        XCTAssertEqual(second.focusSession.record.taskID, 1)
        XCTAssertEqual(persistence.record?.taskID, 1)
    }

    private func date(_ rawValue: String) -> Date {
        ISO8601DateFormatter().date(from: rawValue)!
    }
}

private final class MutableFocusClock: FocusSessionClock {
    private var value: Date

    init(_ rawValue: String) {
        value = ISO8601DateFormatter().date(from: rawValue)!
    }

    func now() -> Date { value }

    func advance(by seconds: TimeInterval) {
        value = value.addingTimeInterval(seconds)
    }
}

private final class InMemoryFocusPersistence: FocusSessionPersistence {
    private(set) var record: FocusSessionRecord?
    private(set) var saveCount = 0

    init(record: FocusSessionRecord? = nil) {
        self.record = record
    }

    func load() -> FocusSessionRecord? { record }

    func save(_ record: FocusSessionRecord?) {
        self.record = record
        saveCount += 1
    }
}
