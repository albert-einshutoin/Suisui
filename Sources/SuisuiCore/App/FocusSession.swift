import Combine
import Foundation

public enum FocusSessionState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case paused
    case completed
}

public struct FocusSessionRecord: Codable, Equatable, Sendable {
    public var taskID: Int64?
    public var durationSeconds: Int
    public var accumulatedSeconds: Int
    public var resumedAt: Date?
    public var state: FocusSessionState

    public init(
        taskID: Int64? = nil,
        durationSeconds: Int = 0,
        accumulatedSeconds: Int = 0,
        resumedAt: Date? = nil,
        state: FocusSessionState = .idle
    ) {
        self.taskID = taskID
        self.durationSeconds = durationSeconds
        self.accumulatedSeconds = accumulatedSeconds
        self.resumedAt = resumedAt
        self.state = state
    }

    public static let idle = FocusSessionRecord()
}

public enum FocusSessionError: Error, Equatable, Sendable {
    case invalidDuration
    case invalidState(FocusSessionState)
    case requiresReplacement(existingTaskID: Int64?)
}

public protocol FocusSessionClock {
    func now() -> Date
}

public struct SystemFocusSessionClock: FocusSessionClock {
    public init() {}

    public func now() -> Date { Date() }
}

public protocol FocusSessionPersistence {
    func load() -> FocusSessionRecord?
    func save(_ record: FocusSessionRecord?)
}

public final class UserDefaultsFocusSessionPersistence: FocusSessionPersistence {
    public static let recordKey = "dev.suisui.today-focus-session"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> FocusSessionRecord? {
        guard let data = defaults.data(forKey: Self.recordKey) else { return nil }
        return try? JSONDecoder().decode(FocusSessionRecord.self, from: data)
    }

    public func save(_ record: FocusSessionRecord?) {
        guard let record else {
            defaults.removeObject(forKey: Self.recordKey)
            return
        }
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.recordKey)
    }
}

/// Owns the one local Focus session for every Today scene in this process.
/// UserDefaults provides restart recovery, while this registry prevents two
/// independently constructed scene view models from racing to replace it.
@MainActor
public final class TodayFocusSessionStoreRegistry {
    public static let shared = TodayFocusSessionStoreRegistry()

    private let makeStore: () -> TodayFocusSessionStore
    private var storedFocusSession: TodayFocusSessionStore?

    public init(makeStore: @escaping () -> TodayFocusSessionStore = { TodayFocusSessionStore() }) {
        self.makeStore = makeStore
    }

    public var focusSession: TodayFocusSessionStore {
        if let storedFocusSession { return storedFocusSession }
        let focusSession = makeStore()
        storedFocusSession = focusSession
        return focusSession
    }
}

@MainActor
public final class TodayFocusSessionStore: ObservableObject {
    @Published public private(set) var record: FocusSessionRecord
    @Published public private(set) var elapsedSeconds: Int

    private let clock: any FocusSessionClock
    private let persistence: any FocusSessionPersistence

    public init(
        clock: any FocusSessionClock = SystemFocusSessionClock(),
        persistence: any FocusSessionPersistence = UserDefaultsFocusSessionPersistence()
    ) {
        self.clock = clock
        self.persistence = persistence
        let loadedRecord = persistence.load()
        let repairedRecord = Self.repairedRecord(loadedRecord)
        record = repairedRecord
        elapsedSeconds = 0
        // A missing persisted record is already the canonical idle state; do
        // not issue a redundant delete during construction. Persist only when
        // an actual malformed record was repaired so normal state transitions
        // retain their one-save-per-transition contract.
        if let loadedRecord, loadedRecord != repairedRecord {
            persistence.save(repairedRecord.state == .idle ? nil : repairedRecord)
        }
        _ = restore()
    }

    @discardableResult
    public func start(
        taskID: Int64?,
        durationSeconds: Int,
        replaceExisting: Bool = false
    ) -> Result<FocusSessionRecord, FocusSessionError> {
        guard durationSeconds > 0 else { return .failure(.invalidDuration) }
        guard record.state != .running && record.state != .paused || replaceExisting else {
            return .failure(.requiresReplacement(existingTaskID: record.taskID))
        }

        record = FocusSessionRecord(
            taskID: taskID,
            durationSeconds: durationSeconds,
            accumulatedSeconds: 0,
            resumedAt: clock.now(),
            state: .running
        )
        elapsedSeconds = 0
        persist()
        return .success(record)
    }

    @discardableResult
    public func pause() -> Result<FocusSessionRecord, FocusSessionError> {
        guard record.state == .running else { return .failure(.invalidState(record.state)) }
        return pauseOrComplete(at: clock.now())
    }

    @discardableResult
    public func resume() -> Result<FocusSessionRecord, FocusSessionError> {
        guard record.state == .paused else { return .failure(.invalidState(record.state)) }
        record.resumedAt = clock.now()
        record.state = .running
        elapsedSeconds = record.accumulatedSeconds
        persist()
        return .success(record)
    }

    @discardableResult
    public func end() -> Result<FocusSessionRecord, FocusSessionError> {
        guard record.state != .idle else { return .failure(.invalidState(.idle)) }
        record = .idle
        elapsedSeconds = 0
        persist()
        return .success(record)
    }

    public func tick() {
        guard record.state == .running else { return }
        _ = pauseOrComplete(at: clock.now(), pausesWhenIncomplete: false)
    }

    @discardableResult
    public func restore() -> FocusSessionRecord {
        guard record.state == .running else {
            let clampedElapsed = min(max(record.accumulatedSeconds, 0), record.durationSeconds)
            if clampedElapsed != record.accumulatedSeconds {
                record.accumulatedSeconds = clampedElapsed
                persist()
            }
            elapsedSeconds = clampedElapsed
            return record
        }
        _ = pauseOrComplete(at: clock.now(), pausesWhenIncomplete: false)
        return record
    }

    private func pauseOrComplete(
        at now: Date,
        pausesWhenIncomplete: Bool = true
    ) -> Result<FocusSessionRecord, FocusSessionError> {
        let elapsed = elapsed(at: now)
        if elapsed >= record.durationSeconds {
            record.accumulatedSeconds = record.durationSeconds
            record.resumedAt = nil
            record.state = .completed
            elapsedSeconds = record.durationSeconds
            persist()
            return .success(record)
        }

        elapsedSeconds = elapsed
        guard pausesWhenIncomplete else { return .success(record) }
        record.accumulatedSeconds = elapsed
        record.resumedAt = nil
        record.state = .paused
        persist()
        return .success(record)
    }

    private func elapsed(at now: Date) -> Int {
        guard record.state == .running, let resumedAt = record.resumedAt else {
            return record.accumulatedSeconds
        }
        // A backward wall-clock adjustment must not create negative Focus time.
        // Persisted records can outlive app updates and wall-clock changes, so
        // never expose elapsed work beyond the session's requested capacity.
        return min(
            record.durationSeconds,
            record.accumulatedSeconds + max(0, Int(now.timeIntervalSince(resumedAt)))
        )
    }

    private func persist() {
        persistence.save(record.state == .idle ? nil : record)
    }

    private static func repairedRecord(_ candidate: FocusSessionRecord?) -> FocusSessionRecord {
        guard let candidate,
              candidate.durationSeconds > 0,
              candidate.accumulatedSeconds >= 0,
              candidate.accumulatedSeconds <= candidate.durationSeconds else {
            return .idle
        }
        switch candidate.state {
        case .idle:
            return .idle
        case .running:
            guard candidate.resumedAt?.timeIntervalSince1970.isFinite == true else { return .idle }
        case .paused, .completed:
            guard candidate.resumedAt == nil else { return .idle }
        }
        return candidate
    }
}
