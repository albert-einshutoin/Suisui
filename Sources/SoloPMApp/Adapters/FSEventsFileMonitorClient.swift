import CoreServices
import Foundation
import SoloPMCore

public enum FSEventsFileMonitorClientError: Error, Equatable {
    case streamCreationFailed
    case streamStartFailed
}

public final class FSEventsFileMonitorClient: FileMonitorClient, @unchecked Sendable {
    private let paths: [String]
    private let latency: CFTimeInterval
    private let eventQueue = DispatchQueue(label: "dev.solopm.fsevents")
    private let lock = NSLock()
    private var queuedEvents: [FileMonitorEvent] = []
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

    private static let handleEvents: FSEventStreamCallback = { _, info, eventCount, eventPaths, eventFlags, _ in
        guard let info else {
            return
        }

        let client = Unmanaged<FSEventsFileMonitorClient>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
        let now = Date()
        let events = (0..<eventCount).compactMap { index -> FileMonitorEvent? in
            guard index < paths.count else {
                return nil
            }

            return FileMonitorEvent(
                path: paths[index],
                kind: eventKind(from: eventFlags[index]),
                modifiedAt: now
            )
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
