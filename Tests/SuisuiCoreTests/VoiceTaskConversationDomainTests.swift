import Foundation
import XCTest
@testable import SuisuiCore

final class VoiceTaskConversationDomainTests: XCTestCase {
    private let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let turnID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let factID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private let createdAt = Date(timeIntervalSince1970: 1_753_401_600)

    func testGivenActiveSessionWhenPauseThenArchiveThenTransitionsRemainValid() throws {
        var session = VoiceTaskConversationSession(
            id: sessionID,
            title: "Release planning",
            entryPoint: .voiceCommand,
            createdAt: createdAt
        )

        try session.pause(at: createdAt.addingTimeInterval(10))
        XCTAssertEqual(session.state, .paused)

        try session.resume(at: createdAt.addingTimeInterval(20))
        XCTAssertEqual(session.state, .active)

        try session.pause(at: createdAt.addingTimeInterval(30))
        try session.archive(at: createdAt.addingTimeInterval(40))
        XCTAssertEqual(session.state, .archived)
        XCTAssertEqual(session.updatedAt, createdAt.addingTimeInterval(40))
    }

    func testGivenArchivedSessionWhenResumeThenRejectsInvalidTransition() throws {
        var session = VoiceTaskConversationSession(
            id: sessionID,
            title: "Release planning",
            entryPoint: .voiceCommand,
            createdAt: createdAt
        )
        try session.pause(at: createdAt.addingTimeInterval(10))
        try session.archive(at: createdAt.addingTimeInterval(20))

        XCTAssertThrowsError(try session.resume(at: createdAt.addingTimeInterval(30))) { error in
            XCTAssertEqual(error as? VoiceTaskConversationDomainError, .invalidStateTransition)
        }
    }

    func testGivenActiveSessionWhenArchiveThenRejectsSkippedPauseTransition() {
        var session = VoiceTaskConversationSession(
            id: sessionID,
            title: "Release planning",
            entryPoint: .voiceCommand,
            createdAt: createdAt
        )

        XCTAssertThrowsError(try session.archive(at: createdAt.addingTimeInterval(10))) { error in
            XCTAssertEqual(error as? VoiceTaskConversationDomainError, .invalidStateTransition)
        }
        XCTAssertEqual(session.state, .active)
    }

    func testGivenBlankConfirmedTextWhenCreateTurnThenRejects() {
        XCTAssertThrowsError(
            try VoiceTaskConversationTurn(
                id: turnID,
                sessionID: sessionID,
                author: .user,
                rawTranscript: "release notes",
                userConfirmedText: " \n ",
                createdAt: createdAt
            )
        ) { error in
            XCTAssertEqual(error as? VoiceTaskConversationDomainError, .blankConfirmedText)
        }
    }

    func testGivenNonUserTurnWhenConfirmedTextIsPresentThenRejectsProvenanceMismatch() {
        for author in [VoiceTaskConversationTurnAuthor.assistant, .system] {
            XCTAssertThrowsError(
                try VoiceTaskConversationTurn(
                    id: turnID,
                    sessionID: sessionID,
                    author: author,
                    rawTranscript: nil,
                    userConfirmedText: "Ship by July 31",
                    createdAt: createdAt
                )
            ) { error in
                XCTAssertEqual(
                    error as? VoiceTaskConversationDomainError,
                    .confirmedTextRequiresUserAuthor
                )
            }
        }
    }

    func testGivenConfidenceOutsideClosedRangeWhenCreateFactThenRejects() {
        for confidence in [-0.01, 1.01, .infinity, .nan] {
            XCTAssertThrowsError(
                try makeFact(id: factID, confidence: confidence)
            ) { error in
                XCTAssertEqual(error as? VoiceTaskConversationDomainError, .invalidConfidence)
            }
        }
    }

    func testGivenFactSupersessionCycleWhenValidateThenRejects() throws {
        let firstID = UUID(uuidString: "30000000-0000-0000-0000-000000000010")!
        let secondID = UUID(uuidString: "30000000-0000-0000-0000-000000000011")!
        let first = try makeFact(id: firstID, supersedesFactID: secondID)
        let second = try makeFact(id: secondID, supersedesFactID: firstID)

        XCTAssertThrowsError(try TaskContextFact.validateSupersessionGraph([first, second])) { error in
            XCTAssertEqual(error as? VoiceTaskConversationDomainError, .cyclicSupersession)
        }
    }

    func testGivenExpiredReferenceWhenResolveEligibilityThenRejects() throws {
        let reference = try ConversationReference(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            sessionID: sessionID,
            target: .task(42),
            sourceTurnID: turnID,
            ordinal: 0,
            orderingFingerprint: "sha256:reference-order",
            expiresAt: createdAt.addingTimeInterval(60),
            createdAt: createdAt
        )

        XCTAssertThrowsError(
            try reference.requireEligible(at: createdAt.addingTimeInterval(61))
        ) { error in
            XCTAssertEqual(error as? VoiceTaskConversationDomainError, .expiredReference)
        }
    }

    func testCodableRoundTripWithFixedUUIDAndUTCDates() throws {
        var session = VoiceTaskConversationSession(
            id: sessionID,
            title: "Release planning",
            entryPoint: .voiceCommand,
            activeProjectID: 7,
            activeTaskID: 42,
            resumeSummary: "Review the confirmed release constraint.",
            createdAt: createdAt
        )
        try session.recordTurn(at: createdAt.addingTimeInterval(5))

        let fixture = Fixture(
            session: session,
            turn: try VoiceTaskConversationTurn(
                id: turnID,
                sessionID: sessionID,
                author: .user,
                rawTranscript: "来週までに出す",
                userConfirmedText: "7月31日までにリリースする",
                createdAt: createdAt.addingTimeInterval(5)
            ),
            reference: try ConversationReference(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
                sessionID: sessionID,
                target: .task(42),
                sourceTurnID: turnID,
                ordinal: 0,
                orderingFingerprint: "sha256:reference-order",
                expiresAt: createdAt.addingTimeInterval(300),
                createdAt: createdAt.addingTimeInterval(5)
            ),
            fact: try makeFact(id: factID, confidence: 1),
            actionLink: try ConversationActionLink(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
                sessionID: sessionID,
                sourceTurnID: turnID,
                actionPlanID: "plan-1",
                assistantQueueItemID: "queue-1",
                taskID: 42,
                executionReceiptID: "receipt-1",
                reviewedFingerprint: "sha256:reviewed-content",
                createdAt: createdAt.addingTimeInterval(10)
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(fixture)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(Fixture.self, from: data), fixture)
    }

    func testConfirmedFactsDoNotImplicitlyCopyRawTranscript() throws {
        let turn = try VoiceTaskConversationTurn(
            id: turnID,
            sessionID: sessionID,
            author: .user,
            rawTranscript: "ええと来週かな、いや今月末",
            userConfirmedText: "7月31日",
            createdAt: createdAt
        )
        let fact = try TaskContextFact(
            id: factID,
            sessionID: sessionID,
            kind: .constraint,
            scope: .task(42),
            state: .confirmed,
            value: turn.userConfirmedText!,
            sourceTurnID: turn.id,
            sourceExcerptDigest: String(repeating: "a", count: 64),
            confidence: 1,
            author: .userExplicit,
            createdAt: createdAt
        )

        XCTAssertEqual(fact.value, "7月31日")
        XCTAssertNotEqual(fact.value, turn.rawTranscript)
        XCTAssertEqual(fact.author, .userExplicit)
    }

    func testInvalidReferenceMetadataAndActionLinksAreRejected() {
        XCTAssertThrowsError(
            try ConversationReference(
                sessionID: sessionID,
                target: .task(42),
                sourceTurnID: turnID,
            ordinal: -1,
            orderingFingerprint: "sha256:reference-order",
            expiresAt: createdAt.addingTimeInterval(60),
            createdAt: createdAt
        )
        ) { error in
            XCTAssertEqual(error as? VoiceTaskConversationDomainError, .invalidReferenceOrdinal)
        }

        XCTAssertThrowsError(
            try ConversationReference(
                sessionID: sessionID,
                target: .task(42),
                sourceTurnID: turnID,
                ordinal: 0,
                orderingFingerprint: "sha256:reference-order",
                expiresAt: Date(timeIntervalSinceReferenceDate: .infinity),
                createdAt: createdAt
            )
        ) { error in
            XCTAssertEqual(error as? VoiceTaskConversationDomainError, .invalidReferenceExpiration)
        }

        XCTAssertThrowsError(
            try ConversationActionLink(
                sessionID: sessionID,
                sourceTurnID: turnID,
                reviewedFingerprint: "sha256:reviewed-content",
                createdAt: createdAt
            )
        ) { error in
            XCTAssertEqual(error as? VoiceTaskConversationDomainError, .missingActionTarget)
        }
    }

    func testFactEvidenceDigestAndExpirationAreValidated() {
        XCTAssertThrowsError(
            try TaskContextFact(
                sessionID: sessionID,
                kind: .goal,
                scope: .task(42),
                state: .proposed,
                value: "Ship safely",
                sourceTurnID: turnID,
                sourceExcerptDigest: "not-a-sha256-digest",
                confidence: 1,
                author: .userExplicit,
                createdAt: createdAt
            )
        ) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationDomainError,
                .invalidFactEvidenceDigest
            )
        }

        XCTAssertThrowsError(
            try TaskContextFact(
                sessionID: sessionID,
                kind: .goal,
                scope: .task(42),
                state: .confirmed,
                value: "Ship safely",
                sourceTurnID: turnID,
                sourceExcerptDigest: String(repeating: "a", count: 64),
                confidence: 1,
                author: .userExplicit,
                expiresAt: createdAt,
                createdAt: createdAt
            )
        ) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationDomainError,
                .invalidFactExpiration
            )
        }
    }

    func testLegacyFactPayloadDecodesAsUnverifiedAndCannotEnterLongTermContext() throws {
        let fact = try makeFact(id: factID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(fact)
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        payload.removeValue(forKey: "sourceExcerptDigest")
        payload.removeValue(forKey: "sourceEvidenceVerified")
        payload["author"] = "system_derived"

        let legacyData = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TaskContextFact.self, from: legacyData)

        XCTAssertEqual(decoded.author, .deterministic)
        XCTAssertFalse(decoded.sourceEvidenceVerified)
        XCTAssertFalse(decoded.isEligibleForLongTermContext(at: createdAt))

        let roundTripped = try decoder.decode(
            TaskContextFact.self,
            from: encoder.encode(decoded)
        )
        XCTAssertFalse(roundTripped.sourceEvidenceVerified)
        XCTAssertFalse(roundTripped.isEligibleForLongTermContext(at: createdAt))
    }

    private func makeFact(
        id: UUID,
        confidence: Double = 0.8,
        supersedesFactID: UUID? = nil
    ) throws -> TaskContextFact {
        try TaskContextFact(
            id: id,
            sessionID: sessionID,
            kind: .constraint,
            scope: .task(42),
            state: .confirmed,
            value: "Release by July 31",
            sourceTurnID: turnID,
            sourceExcerptDigest: String(repeating: "b", count: 64),
            confidence: confidence,
            author: .providerInferred,
            supersedesFactID: supersedesFactID,
            createdAt: createdAt
        )
    }
}

private struct Fixture: Codable, Equatable {
    let session: VoiceTaskConversationSession
    let turn: VoiceTaskConversationTurn
    let reference: ConversationReference
    let fact: TaskContextFact
    let actionLink: ConversationActionLink
}
