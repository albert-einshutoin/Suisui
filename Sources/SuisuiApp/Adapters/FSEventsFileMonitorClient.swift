import CoreServices
import Foundation
import SuisuiCore

public enum FSEventsFileMonitorClientError: Error, Equatable {
    case streamCreationFailed
    case streamStartFailed
    case eventPayloadMismatch(expected: Int, actual: Int)
}

public final class FSEventsFileMonitorClient: FileMonitorClient, @unchecked Sendable {
    private let paths: [String]
    private let latency: CFTimeInterval
    private let eventQueue = DispatchQueue(label: "dev.suisui.fsevents")
    private let lock = NSLock()
    private var queuedEvents: [FileMonitorEvent] = []
    private var queuedErrors: [FSEventsFileMonitorClientError] = []
    private var stream: FSEventStreamRef?

    public init(paths: [String], latency: CFTimeInterval = 0.5) throws {
        self.paths = paths
        self.latency = latency
        try start()
    }

    deinit {
        stop()
    }

    public func nextEvent() throws -> FileMonitorEvent? {
        lock.lock()
        defer { lock.unlock() }

        if !queuedErrors.isEmpty {
            throw queuedErrors.removeFirst()
        }

        guard !queuedEvents.isEmpty else {
            return nil
        }
        return queuedEvents.removeFirst()
    }

    private func start() throws {
        guard stream == nil else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)

        guard let createdStream = FSEventStreamCreate(
            nil,
            Self.handleEvents,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            throw FSEventsFileMonitorClientError.streamCreationFailed
        }

        stream = createdStream
        FSEventStreamSetDispatchQueue(createdStream, eventQueue)

        guard FSEventStreamStart(createdStream) else {
            stop()
            throw FSEventsFileMonitorClientError.streamStartFailed
        }
    }

    private func stop() {
        guard let stream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func enqueue(_ events: [FileMonitorEvent]) {
        lock.lock()
        defer { lock.unlock() }
        queuedEvents.append(contentsOf: events)
    }

    private func enqueue(_ error: FSEventsFileMonitorClientError) {
        lock.lock()
        defer { lock.unlock() }
        queuedErrors.append(error)
    }

    private static let handleEvents: FSEventStreamCallback = { _, info, eventCount, eventPaths, eventFlags, _ in
        guard let info else {
            return
        }

        let client = Unmanaged<FSEventsFileMonitorClient>.fromOpaque(info).takeUnretainedValue()
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
            client.enqueue(.eventPayloadMismatch(expected: eventCount, actual: 0))
            return
        }
        guard paths.count >= eventCount else {
            client.enqueue(.eventPayloadMismatch(expected: eventCount, actual: paths.count))
            return
        }

        let now = Date()
        var events: [FileMonitorEvent] = []
        events.reserveCapacity(eventCount)
        for index in 0..<eventCount {
            events.append(FileMonitorEvent(
                path: paths[index],
                kind: eventKind(from: eventFlags[index]),
                modifiedAt: now
            ))
        }
        client.enqueue(events)
    }

    private static func eventKind(from flags: FSEventStreamEventFlags) -> FileMonitorEventKind {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
            return .deleted
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
            return .created
        }
        return .modified
    }
}
