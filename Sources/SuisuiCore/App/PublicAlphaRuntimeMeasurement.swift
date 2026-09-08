import CryptoKit
import Foundation
import OSLog

public enum PublicAlphaRuntimeMeasurementResult: Equatable, Sendable {
    case inserted
    case duplicate
    case failed
}

/// Minimal local-only bridge from the normal voice path to the closed alpha ledger.
public final class PublicAlphaRuntimeMeasurement: @unchecked Sendable {
    private let url: URL
    private let participantID: PublicAlphaParticipantID
    // ponytail: one process-wide lock; use SQLite if multi-process or high-volume writes appear.
    private static let fileLock = NSLock()
    private static let logger = Logger(
        subsystem: "dev.suisui.app",
        category: "public-alpha-measurement"
    )

    public init(url: URL, participantSeed: String) throws {
        self.url = url
        self.participantID = try PublicAlphaParticipantID(seed: participantSeed)
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
        at date: Date = Date()
    ) -> PublicAlphaRuntimeMeasurementResult {
        guard !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Self.logger.error("Public Alpha measurement rejected an empty source identifier.")
            return .failed
        }
        Self.fileLock.lock(); defer { Self.fileLock.unlock() }
        do {
            let workReference = try PublicAlphaWorkReference(sourceID: workID ?? sourceID)
            let ledger: PublicAlphaValidationLedger
            if FileManager.default.fileExists(atPath: url.path) {
                ledger = try PublicAlphaValidationLedger(recovering: Data(contentsOf: url))
            } else {
                ledger = PublicAlphaValidationLedger()
            }
            var updatedLedger = ledger
            let event = try PublicAlphaStageEvent(
                eventID: Self.eventID(
                    participantID: participantID,
                    stage: stage,
                    sourceID: sourceID
                ),
                participantID: participantID,
                workReference: workReference,
                stage: stage,
                mark: mark,
                occurredAt: date
            )
            guard updatedLedger.append(event) == .inserted else { return .duplicate }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updatedLedger.encodedSnapshot().write(to: url, options: .atomic)
            return .inserted
        } catch {
            // Measurement must never block the user's local workflow or replace
            // an unreadable ledger with an empty one. The fixed log message is
            // intentionally free of the source identifier, path, and error.
            Self.logger.error("Public Alpha measurement could not persist an event.")
            return .failed
        }
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
