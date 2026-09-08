import Foundation

/// Minimal local-only bridge from the normal voice path to the closed alpha ledger.
public final class PublicAlphaRuntimeMeasurement: @unchecked Sendable {
    private let url: URL
    private let participantID: PublicAlphaParticipantID
    private let build: PublicAlphaBuildIdentity
    private let lock = NSLock()

    public init(url: URL, participantSeed: String, appVersion: String, sourceCommit: String) throws {
        self.url = url
        self.participantID = try PublicAlphaParticipantID(seed: participantSeed)
        self.build = try PublicAlphaBuildIdentity(appVersion: appVersion, sourceCommit: sourceCommit)
    }

    public func record(_ stage: PublicAlphaStage, mark: PublicAlphaStageMark, at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        do {
            var ledger = (try? PublicAlphaValidationLedger(recovering: Data(contentsOf: url))) ?? PublicAlphaValidationLedger()
            let event = try PublicAlphaStageEvent(participantID: participantID, stage: stage, mark: mark, occurredAt: date)
            guard ledger.append(event) == .inserted else { return }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ledger.encodedSnapshot().write(to: url, options: .atomic)
        } catch {
            // Measurement must never block the user's local workflow.
        }
    }
}
