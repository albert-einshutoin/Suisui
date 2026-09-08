import Foundation
import XCTest
@testable import SuisuiCore

final class PublicAlphaValidationTests: XCTestCase {
    func testConfirmedEventRequiresExistingParticipantWorkAndDeduplicates() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alpha-confirmation-\(UUID().uuidString)/ledger.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let measurement = try PublicAlphaRuntimeMeasurement(url: url, participantSeed: "participant")
        let participant = try PublicAlphaParticipantID(seed: "participant")
        let work = try PublicAlphaWorkReference(sourceID: "work")
        let event = try PublicAlphaStageEvent(participantID: participant, workReference: work,
                                             stage: .outcomeClosed, mark: .completed, occurredAt: Date())
        XCTAssertThrowsError(try measurement.saveConfirmedEvent(event))
        XCTAssertEqual(measurement.record(.firstCapture, mark: .completed, sourceID: "capture", workReference: work), .inserted)
        try measurement.saveConfirmedEvent(event)
        try measurement.saveConfirmedEvent(event)
        XCTAssertEqual(try PublicAlphaValidationLedger(recovering: Data(contentsOf: url)).stageEvents.count, 2)
        let automatic = try PublicAlphaStageEvent(participantID: participant, workReference: work,
                                                 stage: .localExecution, mark: .completed, occurredAt: Date())
        XCTAssertThrowsError(try measurement.saveConfirmedEvent(automatic))
        try measurement.deleteParticipant()
        XCTAssertThrowsError(try measurement.saveConfirmedEvent(event))
    }

    func testRuntimeMeasurementPersistsClosedEventsWithoutRawContent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("public-alpha-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("ledger.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let measurement = try PublicAlphaRuntimeMeasurement(url: url, participantSeed: "opaque-seed")
        XCTAssertEqual(
            measurement.record(.firstCapture, mark: .completed, sourceID: "capture-1", workID: "job-1"),
            .inserted
        )
        XCTAssertEqual(
            measurement.record(.firstCapture, mark: .completed, sourceID: "capture-1", workID: "job-1"),
            .duplicate
        )
        XCTAssertEqual(
            measurement.record(.reviewableActionPlan, mark: .completed, sourceID: "queue-1", workID: "job-1"),
            .inserted
        )
        let ledger = try PublicAlphaValidationLedger(recovering: Data(contentsOf: url))
        XCTAssertEqual(ledger.stageEvents.count, 2)
        XCTAssertEqual(Set(ledger.stageEvents.compactMap(\.workReference)).count, 1)
        let encoded = String(decoding: try ledger.encodedSnapshot(), as: UTF8.self)
        XCTAssertFalse(encoded.contains("opaque-seed"))
        XCTAssertFalse(encoded.contains("job-1"))
    }

    func testRuntimeMeasurementDoesNotOverwriteUnreadableLedger() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("public-alpha-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("ledger.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalidData = Data("not-json".utf8)
        try invalidData.write(to: url)

        let measurement = try PublicAlphaRuntimeMeasurement(url: url, participantSeed: "opaque-seed")
        XCTAssertEqual(
            measurement.record(.firstCapture, mark: .completed, sourceID: "capture-1"),
            .failed
        )

        XCTAssertEqual(try Data(contentsOf: url), invalidData)
    }

    func testRuntimeMeasurementRecoversOpaqueWorkIdentityAcrossInstances() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("public-alpha-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("ledger.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionID = UUID()
        let build = try PublicAlphaBuildIdentity(appVersion: "1.2.3", sourceCommit: "abcdef1")
        let first = try PublicAlphaRuntimeMeasurement(
            url: url,
            participantSeed: "recovery-seed",
            build: build
        )
        XCTAssertEqual(
            first.record(
                .firstCapture,
                mark: .completed,
                sourceID: "capture-id",
                workID: "job-id",
                sessionID: sessionID
            ),
            .inserted
        )

        let reopened = try PublicAlphaRuntimeMeasurement(url: url, participantSeed: "recovery-seed")
        let recovered = try XCTUnwrap(reopened.workReference(sessionID: sessionID))
        XCTAssertEqual(
            reopened.record(
                .localExecution,
                mark: .failed,
                sourceID: "receipt-id",
                workReference: recovered,
                failureCategory: .reliability
            ),
            .inserted
        )
        XCTAssertEqual(
            try reopened.workReference(sourceID: "receipt-id", stage: .localExecution),
            recovered
        )
        let ledger = try PublicAlphaValidationLedger(recovering: Data(contentsOf: url))
        XCTAssertEqual(ledger.stageEvents.first?.build, build)
        XCTAssertEqual(ledger.stageEvents.last?.failureCategory, .reliability)
        let encoded = String(decoding: try ledger.encodedSnapshot(), as: UTF8.self)
        for rawValue in ["recovery-seed", "capture-id", "job-id", "receipt-id", sessionID.uuidString] {
            XCTAssertFalse(encoded.contains(rawValue))
        }
    }

    func testParticipantDeletionTombstoneBlocksStaleInstancesAndSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("public-alpha-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("ledger.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let deleting = try PublicAlphaRuntimeMeasurement(url: url, participantSeed: "delete-seed")
        let stale = try PublicAlphaRuntimeMeasurement(url: url, participantSeed: "delete-seed")
        XCTAssertEqual(
            stale.record(.firstCapture, mark: .completed, sourceID: "before-delete"),
            .inserted
        )

        try deleting.deleteParticipant()

        XCTAssertEqual(
            stale.record(.resultDisplayed, mark: .completed, sourceID: "stale-event"),
            .disabled
        )
        XCTAssertNil(try stale.workReference(sourceID: "before-delete", stage: .firstCapture))
        XCTAssertThrowsError(
            try stale.saveSnapshot(makeSnapshot(participantID: PublicAlphaParticipantID(seed: "delete-seed")))
        ) { error in
            XCTAssertEqual(error as? PublicAlphaValidationError, .participantDeleted)
        }
        let ledger = try PublicAlphaValidationLedger(recovering: Data(contentsOf: url))
        XCTAssertTrue(ledger.stageEvents.isEmpty)
        XCTAssertTrue(ledger.weeklySnapshots.isEmpty)
        XCTAssertTrue(ledger.isDeleted(participantID: try PublicAlphaParticipantID(seed: "delete-seed")))
    }

    func testDisabledMeasurementDoesNotCreateLedger() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("public-alpha-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("ledger.json")
        let measurement = try PublicAlphaRuntimeMeasurement(
            url: url,
            participantSeed: "disabled-seed",
            isEnabled: { false }
        )

        XCTAssertEqual(
            measurement.record(.firstCapture, mark: .completed, sourceID: "capture"),
            .disabled
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testWeeklyExportContainsOnlyCurrentParticipantAndUTCWeek() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("public-alpha-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("ledger.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = try PublicAlphaRuntimeMeasurement(url: url, participantSeed: "current-seed")
        let other = try PublicAlphaRuntimeMeasurement(url: url, participantSeed: "deleted-seed")
        let selectedWeek = Date(timeIntervalSince1970: 0)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let nextWeekStart = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: selectedWeek)?.end)
        XCTAssertEqual(
            current.record(
                .firstCapture,
                mark: .completed,
                sourceID: "current-source",
                at: selectedWeek
            ),
            .inserted
        )
        XCTAssertEqual(
            current.record(
                .resultDisplayed,
                mark: .completed,
                sourceID: "outside-source",
                at: nextWeekStart
            ),
            .inserted
        )
        try current.saveSnapshot(
            makeSnapshot(
                participantID: PublicAlphaParticipantID(seed: "current-seed"),
                weekStart: selectedWeek
            )
        )
        XCTAssertEqual(
            other.record(.firstCapture, mark: .completed, sourceID: "deleted-source", at: selectedWeek),
            .inserted
        )
        try other.deleteParticipant()

        let export = try current.exportWeek(containing: selectedWeek)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: export) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["participantID"] as? String, try PublicAlphaParticipantID(seed: "current-seed").digest)
        XCTAssertEqual((object["stageEvents"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((object["weeklySnapshots"] as? [[String: Any]])?.count, 1)
        let json = String(decoding: export, as: UTF8.self)
        XCTAssertTrue(json.contains(try PublicAlphaParticipantID(seed: "current-seed").digest))
        XCTAssertFalse(json.contains(try PublicAlphaParticipantID(seed: "deleted-seed").digest))
        for rawValue in ["current-source", "outside-source", "deleted-source"] {
            XCTAssertFalse(json.contains(rawValue))
        }

        let deletedExport = try other.exportWeek(containing: selectedWeek)
        let deletedJSON = String(decoding: deletedExport, as: UTF8.self)
        XCTAssertFalse(deletedJSON.contains(try PublicAlphaParticipantID(seed: "deleted-seed").digest))
    }

    func testEmptyWeeklyExportCarriesCurrentParticipantIdentity() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("public-alpha-\(UUID().uuidString)/ledger.json")
        let measurement = try PublicAlphaRuntimeMeasurement(url: url, participantSeed: "empty-week-seed")

        let export = try measurement.exportWeek(containing: Date(timeIntervalSince1970: 0))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: export) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            object["participantID"] as? String,
            try PublicAlphaParticipantID(seed: "empty-week-seed").digest
        )
        XCTAssertEqual((object["stageEvents"] as? [Any])?.count, 0)
        XCTAssertEqual((object["weeklySnapshots"] as? [Any])?.count, 0)
    }

    func testSnapshotSaveRejectsAnotherParticipant() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("public-alpha-\(UUID().uuidString)/ledger.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let measurement = try PublicAlphaRuntimeMeasurement(url: url, participantSeed: "current-seed")

        XCTAssertThrowsError(
            try measurement.saveSnapshot(
                makeSnapshot(participantID: PublicAlphaParticipantID(seed: "other-seed"))
            )
        ) { error in
            XCTAssertEqual(error as? PublicAlphaValidationError, .participantMismatch)
        }
    }

    func testWorkReferenceRejectsRawOrMalformedPersistedValues() throws {
        XCTAssertThrowsError(try PublicAlphaWorkReference(sourceID: ""))
        XCTAssertThrowsError(try PublicAlphaWorkReference(digest: "job-1"))
    }

    func testLegacyLedgerWithoutNewOptionalFieldsRemainsRecoverable() throws {
        let participantID = try PublicAlphaParticipantID(seed: "legacy-seed")
        var ledger = PublicAlphaValidationLedger()
        _ = ledger.append(
            try PublicAlphaStageEvent(
                participantID: participantID,
                stage: .firstCapture,
                mark: .completed,
                occurredAt: Date(timeIntervalSince1970: 0)
            )
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: ledger.encodedSnapshot()) as? [String: Any]
        )
        object.removeValue(forKey: "deletedParticipantIDs")
        var events = try XCTUnwrap(object["stageEvents"] as? [[String: Any]])
        for key in ["workReference", "sessionReference", "sourceReference", "build"] {
            events[0].removeValue(forKey: key)
        }
        object["stageEvents"] = events

        let recovered = try PublicAlphaValidationLedger(
            recovering: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(recovered.stageEvents.count, 1)
        XCTAssertNil(recovered.stageEvents[0].workReference)
        XCTAssertNil(recovered.stageEvents[0].sessionReference)
        XCTAssertNil(recovered.stageEvents[0].sourceReference)
        XCTAssertNil(recovered.stageEvents[0].build)
        XCTAssertTrue(recovered.deletedParticipantIDs.isEmpty)
    }

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

    func testReportCountsEventOnlyParticipantsWithoutDoubleCountingSnapshotOwners() throws {
        let earlyDropOff = try PublicAlphaParticipantID(seed: "early-drop-off")
        let active = try PublicAlphaParticipantID(seed: "active")
        var ledger = PublicAlphaValidationLedger()
        for participantID in [earlyDropOff, active] {
            _ = ledger.append(try PublicAlphaStageEvent(
                participantID: participantID, stage: .firstLaunch,
                mark: .completed, occurredAt: Date()
            ))
        }
        _ = ledger.append(try makeSnapshot(participantID: active))
        XCTAssertEqual(try ledger.report().participantCount, 2)
        ledger.delete(participantID: earlyDropOff)
        XCTAssertEqual(try ledger.report().participantCount, 1)
    }

    func testOutOfCohortQualificationSurvivesSnapshotRecovery() throws {
        let snapshot = try makeSnapshot(
            participantID: PublicAlphaParticipantID(seed: "outside-target-persona"),
            personaFlags: [.outOfCohort, .macPrimary]
        )
        let recovered = try JSONDecoder().decode(
            PublicAlphaValidationSnapshot.self, from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(recovered.personaFlags, [.outOfCohort, .macPrimary])
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
        personaFlags: Set<PublicAlphaPersonaFlag> = [.individualContractor, .macPrimary],
        weekStart: Date = Date(timeIntervalSince1970: 0),
        proactiveFeedbackCounts: [PublicAlphaFeedbackCategory: Int] = [.helpfulNow: 1],
        confirmedCommitmentCount: Int = 0,
        outcomeTrackedCount: Int = 0,
        outcomeClosedCount: Int = 0
    ) throws -> PublicAlphaValidationSnapshot {
        try PublicAlphaValidationSnapshot(
            participantID: participantID,
            personaFlags: personaFlags,
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
