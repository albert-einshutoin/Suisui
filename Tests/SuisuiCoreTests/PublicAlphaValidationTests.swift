import Foundation
import XCTest
@testable import SuisuiCore

final class PublicAlphaValidationTests: XCTestCase {
    func testClosedSchemaDoesNotEncodeSeedOrProhibitedContent() throws {
        let seed = UUID().uuidString
        let participantID = try PublicAlphaParticipantID(seed: seed)
        let snapshot = try makeSnapshot(participantID: participantID)
        let encoded = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(json.contains(seed))
        for prohibited in [
            "customerName", "emailAddress", "rawTranscript", "rawPrompt",
            "rawOutput", "localPath", "repositoryName", "privateSourceText",
            "freeFormMetadata"
        ] {
            XCTAssertFalse(json.contains(prohibited), "closed schema must not expose \(prohibited)")
        }
        XCTAssertTrue(json.contains(participantID.digest))
    }

    func testStageMetadataRequiresClosedFailureAndAbandonmentCodes() throws {
        let participantID = try PublicAlphaParticipantID(seed: "stage-seed")

        XCTAssertThrowsError(
            try PublicAlphaStageEvent(
                participantID: participantID,
                stage: .firstCapture,
                mark: .failed,
                occurredAt: Date()
            )
        ) { error in
            XCTAssertEqual(error as? PublicAlphaValidationError, .invalidStageMetadata)
        }

        XCTAssertThrowsError(
            try PublicAlphaStageEvent(
                participantID: participantID,
                stage: .firstCapture,
                mark: .completed,
                occurredAt: Date(),
                failureCategory: .capture
            )
        ) { error in
            XCTAssertEqual(error as? PublicAlphaValidationError, .invalidStageMetadata)
        }

        XCTAssertNoThrow(
            try PublicAlphaStageEvent(
                participantID: participantID,
                stage: .firstCapture,
                mark: .abandoned,
                occurredAt: Date(),
                abandonReason: .onboarding
            )
        )
    }

    func testBuildSnapshotAndGateRejectOutOfContractValues() throws {
        XCTAssertThrowsError(
            try PublicAlphaBuildIdentity(appVersion: "1.0.0\nprivate", sourceCommit: "abcdef1")
        )
        XCTAssertThrowsError(
            try PublicAlphaBuildIdentity(appVersion: "1.0.0", sourceCommit: "not-a-commit")
        )

        let participantID = try PublicAlphaParticipantID(seed: "invalid-count-seed")
        XCTAssertThrowsError(
            try PublicAlphaValidationSnapshot(
                participantID: participantID,
                personaFlags: [.macPrimary],
                build: try PublicAlphaBuildIdentity(appVersion: "1.0.0", sourceCommit: "abcdef1"),
                weekStart: Date(),
                weeklyActiveDays: 8,
                capturedItemCount: 0,
                confirmedCommitmentCount: 0,
                outcomeTrackedCount: 0,
                outcomeClosedCount: 0,
                manualReplanningCount: 0,
                continuationState: .active
            )
        )
        XCTAssertThrowsError(
            try PublicAlphaGateMetrics(
                fourWeekActivatedUsers: 10,
                weekFourRetentionRate: 1.1,
                medianCommitmentsPerActiveUser: 2,
                outcomeTrackingRate: 0.5,
                helpfulFeedbackRate: 0.5,
                criticalTrustIncidentCount: 0,
                nonSubstitutableReasonRate: 0.3,
                willingnessToPayRate: 0.2
            )
        )
    }

    func testLedgerReplayIsIdempotentAndRecoversFromLocalSnapshot() throws {
        let participantID = try PublicAlphaParticipantID(seed: "replay-seed")
        let eventID = UUID()
        let event = try PublicAlphaStageEvent(
            eventID: eventID,
            participantID: participantID,
            stage: .firstCapture,
            mark: .completed,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let snapshot = try makeSnapshot(participantID: participantID)
        var ledger = PublicAlphaValidationLedger()

        XCTAssertEqual(ledger.append(event), .inserted)
        XCTAssertEqual(ledger.append(event), .duplicate)
        XCTAssertEqual(ledger.append(snapshot), .inserted)
        XCTAssertEqual(ledger.append(snapshot), .duplicate)

        let recovered = try PublicAlphaValidationLedger(recovering: ledger.encodedSnapshot())
        XCTAssertEqual(recovered.stageEvents.map(\.eventID), [eventID])
        XCTAssertEqual(recovered.weeklySnapshots.map(\.snapshotID), [snapshot.snapshotID])
        XCTAssertEqual(try recovered.report().participantCount, 1)
    }

    func testWeeklyReplayUsesParticipantAndUTCWeekAcrossAllDecodeEntrypoints() throws {
        let participantID = try PublicAlphaParticipantID(seed: "weekly-replay")
        let first = try makeSnapshot(participantID: participantID)
        let replay = try makeSnapshot(participantID: participantID, weekStart: Date(timeIntervalSince1970: 86_400))
        var ledger = PublicAlphaValidationLedger()
        XCTAssertEqual(ledger.append(first), .inserted)
        XCTAssertEqual(ledger.append(replay), .duplicate)
        XCTAssertEqual(try ledger.report().capturedItemCount, 1)

        let invalid = ["stageEvents": [], "weeklySnapshots": try [first, replay].map {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
        }]
        let data = try JSONSerialization.data(withJSONObject: invalid)
        XCTAssertThrowsError(try PublicAlphaValidationLedger(recovering: data))
        XCTAssertThrowsError(try JSONDecoder().decode(PublicAlphaValidationLedger.self, from: data))
    }

    func testFeedbackRetainsFrequencyAndDenominatorAndRejectsInvalidCounts() throws {
        let participantID = try PublicAlphaParticipantID(seed: "feedback-counts")
        var ledger = PublicAlphaValidationLedger()
        _ = ledger.append(try makeSnapshot(participantID: participantID, proactiveFeedbackCounts: [.helpfulNow: 100, .wrongTiming: 2]))
        _ = ledger.append(try makeSnapshot(participantID: participantID, weekStart: Date(timeIntervalSince1970: 604_800), proactiveFeedbackCounts: [.helpfulNow: 1, .notHelpful: 3]))
        let report = try ledger.report()
        XCTAssertEqual(report.feedbackCounts[.helpfulNow], 101)
        XCTAssertEqual(report.feedbackCount, 106)
        XCTAssertEqual(try PublicAlphaValidationLedger(recovering: ledger.encodedSnapshot()).report(), report)
        XCTAssertThrowsError(try makeSnapshot(participantID: participantID, proactiveFeedbackCounts: [.helpfulNow: -1]))
        XCTAssertThrowsError(try makeSnapshot(participantID: participantID, proactiveFeedbackCounts: [.helpfulNow: Int.max, .wrongTiming: 1]))
        var overflowing = PublicAlphaValidationLedger()
        _ = overflowing.append(try makeSnapshot(participantID: participantID, proactiveFeedbackCounts: [.helpfulNow: Int.max]))
        _ = overflowing.append(try makeSnapshot(participantID: participantID, weekStart: Date(timeIntervalSince1970: 604_800)))
        XCTAssertThrowsError(try overflowing.report())
    }

    func testTaskCompletionWithoutOutcomeClosureDoesNotCountOutcome() throws {
        let participantID = try PublicAlphaParticipantID(seed: "outcome-seed")
        var ledger = PublicAlphaValidationLedger()
        for stage: PublicAlphaStage in [.firstCapture, .reviewableActionPlan, .approvedLocalAction, .followUpWaiting] {
            _ = ledger.append(
                try PublicAlphaStageEvent(
                    participantID: participantID,
                    stage: stage,
                    mark: .completed,
                    occurredAt: Date()
                )
            )
        }
        _ = ledger.append(
            try makeSnapshot(
                participantID: participantID,
                confirmedCommitmentCount: 1,
                outcomeTrackedCount: 0,
                outcomeClosedCount: 0
            )
        )

        let report = try ledger.report()
        XCTAssertEqual(report.confirmedCommitmentCount, 1)
        XCTAssertEqual(report.outcomeTrackedCount, 0)
        XCTAssertEqual(report.outcomeClosedCount, 0)
        XCTAssertNil(report.stageCompletionCounts[.outcomeClosed])
    }

    func testParticipantDeletionRemovesPendingEventsAndSnapshots() throws {
        let participantID = try PublicAlphaParticipantID(seed: "delete-seed")
        let otherParticipantID = try PublicAlphaParticipantID(seed: "keep-seed")
        var ledger = PublicAlphaValidationLedger()
        _ = ledger.append(
            try PublicAlphaStageEvent(
                participantID: participantID,
                stage: .firstLaunch,
                mark: .completed,
                occurredAt: Date()
            )
        )
        _ = ledger.append(try makeSnapshot(participantID: participantID))
        _ = ledger.append(try makeSnapshot(participantID: otherParticipantID))

        ledger.delete(participantID: participantID)

        XCTAssertTrue(ledger.stageEvents.allSatisfy { $0.participantID != participantID })
        XCTAssertEqual(ledger.weeklySnapshots.map(\.participantID), [otherParticipantID])
    }

    func testOptOutProducesNoRemotePayloadAndOptInExportsOnlyAggregate() throws {
        let participantID = try PublicAlphaParticipantID(seed: "remote-seed")
        var ledger = PublicAlphaValidationLedger()
        _ = ledger.append(try makeSnapshot(participantID: participantID))

        XCTAssertNil(try ledger.remotePayload(consent: .localOnly))
        XCTAssertNil(try ledger.remotePayload(consent: .researchDatasetOptIn))

        let payload = try XCTUnwrap(try ledger.remotePayload(consent: .aggregatedDiagnosticsOptIn))
        let json = try XCTUnwrap(String(data: payload, encoding: .utf8))
        XCTAssertFalse(json.contains(participantID.digest))
        XCTAssertTrue(json.contains("participantCount"))
        XCTAssertTrue(json.contains("capturedItemCount"))
        let report = try JSONDecoder().decode(PublicAlphaValidationReport.self, from: payload)
        XCTAssertEqual(report.participantCount, 1)
    }

    func testGateNeverReturnsGoForInsufficientSample() throws {
        let insufficient = try makeGateMetrics(fourWeekActivatedUsers: 9)
        XCTAssertEqual(PublicAlphaGateEvaluator.evaluate(insufficient), .insufficientSample)

        let passing = try makeGateMetrics(fourWeekActivatedUsers: 10)
        XCTAssertEqual(PublicAlphaGateEvaluator.evaluate(passing), .go)
    }

    func testCriticalTrustIncidentStopsEvenWithPassingUsageMetrics() throws {
        for count in [0, 9, 10] {
            let metrics = try makeGateMetrics(fourWeekActivatedUsers: count, criticalTrustIncidentCount: 1)
            XCTAssertEqual(PublicAlphaGateEvaluator.evaluate(metrics), .stop)
        }
    }

    func testRunbookKeepsExternalValidationAsAnOpenGate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runbook = try String(
            contentsOf: root.appendingPathComponent("docs/product/public-alpha-validation.md"),
            encoding: .utf8
        )

        XCTAssertTrue(runbook.contains("has **not started**"))
        XCTAssertTrue(runbook.contains("therefore do not close Issue"))
        XCTAssertTrue(runbook.contains("A missing sample is"))
        XCTAssertTrue(runbook.contains("Interview notes remain in a separate encrypted"))
    }

    private func makeSnapshot(
        participantID: PublicAlphaParticipantID,
        weekStart: Date = Date(timeIntervalSince1970: 0),
        proactiveFeedbackCounts: [PublicAlphaFeedbackCategory: Int] = [.helpfulNow: 1],
        confirmedCommitmentCount: Int = 0,
        outcomeTrackedCount: Int = 0,
        outcomeClosedCount: Int = 0
    ) throws -> PublicAlphaValidationSnapshot {
        try PublicAlphaValidationSnapshot(
            participantID: participantID,
            personaFlags: [.individualContractor, .macPrimary],
            build: try PublicAlphaBuildIdentity(appVersion: "1.0.0", sourceCommit: "abcdef1234567"),
            weekStart: weekStart,
            weeklyActiveDays: 2,
            capturedItemCount: 1,
            confirmedCommitmentCount: confirmedCommitmentCount,
            outcomeTrackedCount: outcomeTrackedCount,
            outcomeClosedCount: outcomeClosedCount,
            manualReplanningCount: 0,
            proactiveFeedbackCounts: proactiveFeedbackCounts,
            interviewCodes: [.naturalWorkFit],
            continuationState: .active
        )
    }

    private func makeGateMetrics(
        fourWeekActivatedUsers: Int = 10,
        criticalTrustIncidentCount: Int = 0
    ) throws -> PublicAlphaGateMetrics {
        try PublicAlphaGateMetrics(
            fourWeekActivatedUsers: fourWeekActivatedUsers,
            weekFourRetentionRate: 0.35,
            medianCommitmentsPerActiveUser: 2,
            outcomeTrackingRate: 0.50,
            helpfulFeedbackRate: 0.50,
            criticalTrustIncidentCount: criticalTrustIncidentCount,
            nonSubstitutableReasonRate: 0.30,
            willingnessToPayRate: 0.20
        )
    }
}
