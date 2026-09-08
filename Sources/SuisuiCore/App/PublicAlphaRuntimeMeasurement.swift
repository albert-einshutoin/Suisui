import CryptoKit
import Foundation

/// Minimal local-only bridge from the normal voice path to the closed alpha ledger.
public final class PublicAlphaRuntimeMeasurement: @unchecked Sendable {
    private let url: URL
    private let participantID: PublicAlphaParticipantID
    // ponytail: one process-wide lock; use SQLite if multi-process or high-volume writes appear.
    private static let fileLock = NSLock()

    public init(url: URL, participantSeed: String) throws {
        self.url = url
        self.participantID = try PublicAlphaParticipantID(seed: participantSeed)
    }

    /// Records an event using a stable, opaque source identifier. The source
    /// identifier is hashed and is never written to the ledger.
    public func record(
        _ stage: PublicAlphaStage,
        mark: PublicAlphaStageMark,
        sourceID: String,
        at date: Date = Date()
    ) {
        guard !sourceID.isEmpty else { return }
        Self.fileLock.lock(); defer { Self.fileLock.unlock() }
        do {
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
                stage: stage,
                mark: mark,
                occurredAt: date
            )
            guard updatedLedger.append(event) == .inserted else { return }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updatedLedger.encodedSnapshot().write(to: url, options: .atomic)
        } catch {
            // Measurement must never block the user's local workflow or replace
            // an unreadable ledger with an empty one.
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
