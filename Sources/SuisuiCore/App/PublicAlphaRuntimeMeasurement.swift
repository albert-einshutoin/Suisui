import CryptoKit
import Foundation
import OSLog

public enum PublicAlphaRuntimeMeasurementResult: Equatable, Sendable {
    case inserted
    case duplicate
    case disabled
    case failed
}

/// Minimal local-only bridge from the normal voice path to the closed alpha ledger.
public final class PublicAlphaRuntimeMeasurement: @unchecked Sendable {
    private let url: URL
    private let participantID: PublicAlphaParticipantID
    private let build: PublicAlphaBuildIdentity?
    private let isEnabled: @Sendable () -> Bool
    // ponytail: one process-wide lock; use SQLite if multi-process or high-volume writes appear.
    private static let fileLock = NSLock()
    private static let logger = Logger(
        subsystem: "dev.suisui.app",
        category: "public-alpha-measurement"
    )

    public init(
        url: URL,
        participantSeed: String,
        build: PublicAlphaBuildIdentity? = nil,
        isEnabled: @escaping @Sendable () -> Bool = { true }
    ) throws {
        self.url = url
        self.participantID = try PublicAlphaParticipantID(seed: participantSeed)
        self.build = build
        self.isEnabled = isEnabled
    }

    /// Records an event using a stable, opaque source identifier. The source
    /// identifier is hashed and is never written to the ledger. `workID` is
    /// shared by the stages of one local job and is also hashed before storage.
    @discardableResult
    public func record(
        _ stage: PublicAlphaStage,
        mark: PublicAlphaStageMark,
        sourceID: String,
        workID: String? = nil,
        workReference: PublicAlphaWorkReference? = nil,
        sessionID: UUID? = nil,
        isRecovery: Bool = false,
        failureCategory: PublicAlphaFailureCategory? = nil,
        abandonReason: PublicAlphaAbandonReason? = nil,
        at date: Date = Date()
    ) -> PublicAlphaRuntimeMeasurementResult {
        guard isEnabled() else { return .disabled }
        guard !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Self.logger.error("Public Alpha measurement rejected an empty source identifier.")
            return .failed
        }
        Self.fileLock.lock(); defer { Self.fileLock.unlock() }
        do {
            let resolvedWorkReference = try workReference
                ?? PublicAlphaWorkReference(sourceID: workID ?? sourceID)
            let ledger = try loadLedger()
            guard !ledger.isDeleted(participantID: participantID) else { return .disabled }
            var updatedLedger = ledger
            let event = try PublicAlphaStageEvent(
                eventID: Self.eventID(
                    participantID: participantID,
                    stage: stage,
                    sourceID: sourceID
                ),
                participantID: participantID,
                workReference: resolvedWorkReference,
                sessionReference: try sessionID.map {
                    try reference(kind: "session", value: $0.uuidString)
                },
                sourceReference: try reference(kind: "source", value: sourceID),
                // A recovered receipt has no execution-time build evidence.
                build: isRecovery ? nil : build,
                stage: stage,
                mark: mark,
                occurredAt: date,
                failureCategory: failureCategory,
                abandonReason: abandonReason
            )
            switch updatedLedger.append(event) {
            case .inserted:
                try persist(updatedLedger)
            case .duplicate:
                return .duplicate
            case .participantDeleted:
                return .disabled
            }
            return .inserted
        } catch {
            // Measurement must never block the user's local workflow or replace
            // an unreadable ledger with an empty one. The fixed log message is
            // intentionally free of the source identifier, path, and error.
            Self.logger.error("Public Alpha measurement could not persist an event.")
            return .failed
        }
    }

    public func workReference(sessionID: UUID) throws -> PublicAlphaWorkReference? {
        guard isEnabled() else { return nil }
        Self.fileLock.lock(); defer { Self.fileLock.unlock() }
        let ledger = try loadLedger()
        guard !ledger.isDeleted(participantID: participantID) else { return nil }
        let sessionReference = try reference(kind: "session", value: sessionID.uuidString)
        return ledger.stageEvents
            .filter {
                $0.participantID == participantID
                    && $0.stage == .firstCapture
                    && $0.sessionReference == sessionReference
            }
            .max { $0.occurredAt < $1.occurredAt }?
            .workReference
    }

    public func workReference(
        sourceID: String,
        stage: PublicAlphaStage
    ) throws -> PublicAlphaWorkReference? {
        guard isEnabled() else { return nil }
        let sourceReference = try reference(kind: "source", value: sourceID)
        Self.fileLock.lock(); defer { Self.fileLock.unlock() }
        let ledger = try loadLedger()
        guard !ledger.isDeleted(participantID: participantID) else { return nil }
        return ledger.stageEvents
            .filter {
                $0.participantID == participantID
                    && $0.stage == stage
                    && $0.sourceReference == sourceReference
            }
            .max { $0.occurredAt < $1.occurredAt }?
            .workReference
    }

    public func deleteParticipant() throws {
        Self.fileLock.lock(); defer { Self.fileLock.unlock() }
        var ledger = try loadLedger()
        ledger.delete(participantID: participantID)
        try persist(ledger)
    }

    public func saveSnapshot(_ snapshot: PublicAlphaValidationSnapshot) throws {
        guard isEnabled() else { throw PublicAlphaValidationError.measurementDisabled }
        guard snapshot.participantID == participantID else {
            throw PublicAlphaValidationError.participantMismatch
        }
        Self.fileLock.lock(); defer { Self.fileLock.unlock() }
        var ledger = try loadLedger()
        guard !ledger.isDeleted(participantID: participantID) else {
            throw PublicAlphaValidationError.participantDeleted
        }
        switch ledger.append(snapshot) {
        case .inserted:
            try persist(ledger)
        case .duplicate:
            return
        case .participantDeleted:
            throw PublicAlphaValidationError.participantDeleted
        }
    }

    /// Only explicit participant confirmations may enter through the manual import path.
    public func saveConfirmedEvent(_ event: PublicAlphaStageEvent) throws {
        guard isEnabled() else { throw PublicAlphaValidationError.measurementDisabled }
        guard event.participantID == participantID else { throw PublicAlphaValidationError.participantMismatch }
        guard [.confirmedCommitment, .outcomeTracked, .outcomeClosed].contains(event.stage),
              event.mark == .completed, let work = event.workReference else {
            throw PublicAlphaValidationError.invalidSnapshot
        }
        Self.fileLock.lock(); defer { Self.fileLock.unlock() }
        var ledger = try loadLedger()
        guard !ledger.isDeleted(participantID: participantID) else {
            throw PublicAlphaValidationError.participantDeleted
        }
        guard ledger.stageEvents.contains(where: {
            $0.participantID == participantID && $0.workReference == work
        }) else { throw PublicAlphaValidationError.invalidWorkReference }
        switch ledger.append(event) {
        case .inserted: try persist(ledger)
        case .duplicate: return
        case .participantDeleted: throw PublicAlphaValidationError.participantDeleted
        }
    }

    public func exportWeek(containing date: Date) throws -> Data {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw PublicAlphaValidationError.invalidSnapshot
        }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            throw PublicAlphaValidationError.invalidSnapshot
        }
        Self.fileLock.lock(); defer { Self.fileLock.unlock() }
        let ledger = try loadLedger()
        let participantWasDeleted = ledger.isDeleted(participantID: participantID)
        let payload = PublicAlphaWeekExport(
            schemaVersion: 1,
            weekStart: week.start,
            participantID: participantWasDeleted ? nil : participantID,
            stageEvents: ledger.stageEvents.filter {
                !participantWasDeleted
                    && $0.participantID == participantID
                    && $0.occurredAt >= week.start
                    && $0.occurredAt < week.end
            },
            weeklySnapshots: ledger.weeklySnapshots.filter {
                !participantWasDeleted
                    && $0.participantID == participantID
                    && $0.weekStart == week.start
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private func loadLedger() throws -> PublicAlphaValidationLedger {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PublicAlphaValidationLedger()
        }
        return try PublicAlphaValidationLedger(recovering: Data(contentsOf: url))
    }

    private func persist(_ ledger: PublicAlphaValidationLedger) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ledger.encodedSnapshot().write(to: url, options: .atomic)
    }

    private func reference(kind: String, value: String) throws -> PublicAlphaWorkReference {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PublicAlphaValidationError.invalidWorkReference
        }
        return try PublicAlphaWorkReference(sourceID: "\(participantID.digest):\(kind):\(value)")
    }

    private static func eventID(
        participantID: PublicAlphaParticipantID,
        stage: PublicAlphaStage,
        sourceID: String
    ) -> UUID {
        let digest = SHA256.hash(
            data: Data("\(participantID.digest):\(stage.rawValue):\(sourceID)".utf8)
        )
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let characters = Array(hex)
        let groups = [
            String(characters[0..<8]), String(characters[8..<12]),
            String(characters[12..<16]), String(characters[16..<20]),
            String(characters[20..<32])
        ]
        return UUID(uuidString: groups.joined(separator: "-"))!
    }
}

private struct PublicAlphaWeekExport: Encodable {
    let schemaVersion: Int
    let weekStart: Date
    let participantID: PublicAlphaParticipantID?
    let stageEvents: [PublicAlphaStageEvent]
    let weeklySnapshots: [PublicAlphaValidationSnapshot]
}
