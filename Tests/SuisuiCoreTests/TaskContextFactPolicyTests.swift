import XCTest
@testable import SuisuiCore

final class TaskContextFactPolicyTests: XCTestCase {
    private let policy = TaskContextFactPolicy()
    private let sessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let turnID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let digest = String(repeating: "a", count: 64)
    private let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testGivenExplicitObjectiveWhenEvaluateThenReturnsCandidate() throws {
        let candidate = makeCandidate(
            kind: .goal,
            value: "Ship the signed release",
            author: .userExplicit
        )

        guard case let .saveCandidate(fact) = policy.evaluate(candidate) else {
            return XCTFail("Expected an automatically saveable candidate.")
        }
        XCTAssertEqual(fact.state, .proposed)
        XCTAssertEqual(fact.scope, .task(42))
        XCTAssertEqual(fact.sourceTurnID, turnID)
        XCTAssertEqual(fact.sourceExcerptDigest, digest)
    }

    func testGivenExplicitTaskContextKindsWhenEvaluateThenSavesCandidates() {
        for kind in [
            TaskContextFactKind.goal,
            .constraint,
            .acceptanceCriterion,
            .openQuestion,
            .followUp,
        ] {
            let candidate = makeCandidate(
                kind: kind,
                value: "Explicit task context",
                author: .userExplicit
            )

            guard case .saveCandidate = policy.evaluate(candidate) else {
                return XCTFail("Expected \(kind) to be automatically saveable.")
            }
        }
    }

    func testGivenProviderInferredConstraintWhenEvaluateThenRequiresConfirmation() {
        let candidate = makeCandidate(
            kind: .constraint,
            value: "Release only after signing",
            author: .providerInferred
        )

        guard case let .requireConfirmation(fact, reason) = policy.evaluate(candidate) else {
            return XCTFail("Expected provider inference to require confirmation.")
        }
        XCTAssertEqual(fact.author, .providerInferred)
        XCTAssertEqual(fact.state, .proposed)
        XCTAssertFalse(reason.contains(fact.value))
    }

    func testGivenSecretLikeValueWhenEvaluateThenProhibitsWithoutEchoingSecret() {
        let secret = "sk-example-do-not-persist-1234567890"
        let candidate = makeCandidate(
            kind: .constraint,
            value: "Use \(secret)",
            author: .userExplicit
        )

        guard case let .prohibit(reason) = policy.evaluate(candidate) else {
            return XCTFail("Expected secret-like content to be prohibited.")
        }
        XCTAssertFalse(reason.contains(secret))
        XCTAssertFalse(reason.contains(candidate.value))
    }

    func testGivenConflictingDecisionWhenEvaluateThenRequiresConfirmation() {
        let candidate = makeCandidate(
            kind: .decision,
            value: "Move launch to Friday",
            author: .userExplicit,
            conflictingConfirmedFactIDs: [UUID()]
        )

        guard case let .requireConfirmation(_, reason) = policy.evaluate(candidate) else {
            return XCTFail("Expected a conflicting decision to require confirmation.")
        }
        XCTAssertTrue(reason.contains("conflict"))
    }

    func testGivenCorrectionWhenSupersedeThenPreservesOldSourceAndNewFact() throws {
        let oldTurnID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let replacementTurnID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        let old = try makeFact(
            state: .confirmed,
            value: "Launch Thursday",
            sourceTurnID: oldTurnID,
            digest: String(repeating: "b", count: 64)
        )
        let replacement = try makeFact(
            state: .proposed,
            value: "Launch Friday",
            sourceTurnID: replacementTurnID,
            digest: String(repeating: "c", count: 64)
        )

        let (supersession, corrected) = try policy.supersede(
            old,
            with: replacement,
            at: createdAt.addingTimeInterval(10)
        )

        XCTAssertEqual(supersession.state, .superseded)
        XCTAssertEqual(supersession.supersedesFactID, old.id)
        XCTAssertEqual(supersession.sourceTurnID, oldTurnID)
        XCTAssertEqual(supersession.sourceExcerptDigest, old.sourceExcerptDigest)
        XCTAssertNotEqual(supersession.id, old.id)
        XCTAssertEqual(corrected.state, .confirmed)
        XCTAssertEqual(corrected.value, replacement.value)
        XCTAssertEqual(corrected.sourceTurnID, replacementTurnID)
        XCTAssertEqual(corrected.supersedesFactID, old.id)
        XCTAssertNotEqual(corrected.id, replacement.id)
    }

    func testGivenRejectedFactWhenAssembleContextThenIsNotEligible() throws {
        let proposed = try makeFact(state: .proposed)

        let rejected = try policy.reject(
            proposed,
            at: createdAt.addingTimeInterval(10)
        )

        XCTAssertEqual(rejected.state, .rejected)
        XCTAssertEqual(rejected.supersedesFactID, proposed.id)
        XCTAssertFalse(rejected.isEligibleForLongTermContext(at: rejected.createdAt))
    }

    func testGivenExpiredFactWhenEvaluateEligibilityThenIsNotEligible() throws {
        let confirmed = try makeFact(
            state: .confirmed,
            expiresAt: createdAt.addingTimeInterval(5)
        )

        XCTAssertTrue(confirmed.isEligibleForLongTermContext(at: createdAt))
        XCTAssertFalse(
            confirmed.isEligibleForLongTermContext(
                at: createdAt.addingTimeInterval(5)
            )
        )

        let expired = try policy.expire(
            confirmed,
            at: createdAt.addingTimeInterval(5)
        )
        XCTAssertEqual(expired.state, .expired)
        XCTAssertEqual(expired.supersedesFactID, confirmed.id)
        XCTAssertFalse(expired.isEligibleForLongTermContext(at: expired.createdAt))
    }

    func testGivenCrossTaskScopeWhenEvaluateThenProhibits() {
        let candidate = makeCandidate(
            kind: .constraint,
            value: "Reuse another task's private context",
            author: .userExplicit,
            scopeAssessment: .outsideAllowedScope
        )

        guard case let .prohibit(reason) = policy.evaluate(candidate) else {
            return XCTFail("Expected cross-scope content to be prohibited.")
        }
        XCTAssertTrue(reason.contains("scope"))
        XCTAssertFalse(reason.contains(candidate.value))
    }

    func testGivenAmbiguousScopeWhenEvaluateThenRequiresConfirmation() {
        let candidate = makeCandidate(
            kind: .openQuestion,
            value: "Which release owns this question?",
            author: .userExplicit,
            scopeAssessment: .ambiguous
        )

        guard case let .requireConfirmation(_, reason) = policy.evaluate(candidate) else {
            return XCTFail("Expected ambiguous scope to require confirmation.")
        }
        XCTAssertTrue(reason.contains("scope"))
    }

    func testGivenProviderInferenceWithoutSourceWhenEvaluateThenProhibits() {
        let candidate = makeCandidate(
            kind: .constraint,
            value: "Provider guess",
            author: .providerInferred,
            includeEvidence: false
        )

        guard case let .prohibit(reason) = policy.evaluate(candidate) else {
            return XCTFail("Expected ungrounded provider inference to be prohibited.")
        }
        XCTAssertTrue(reason.contains("source"))
        XCTAssertFalse(reason.contains(candidate.value))
    }

    func testGivenSensitiveOrRawContentWhenEvaluateThenProhibits() {
        for category in [
            TaskContextFactContentCategory.secret,
            .authentication,
            .payment,
            .health,
            .familyProfile,
            .rawAudio,
            .localPath,
            .binary,
        ] {
            let candidate = makeCandidate(
                kind: .constraint,
                value: "content that must remain outside Task Context",
                author: .userExplicit,
                contentCategory: category
            )

            guard case .prohibit = policy.evaluate(candidate) else {
                return XCTFail("Expected \(category) to be prohibited.")
            }
        }
    }

    func testGivenConfirmedFactWhenEvaluateEligibilityThenIsEligible() throws {
        let proposed = try makeFact(state: .proposed)

        let confirmed = try policy.confirm(
            proposed,
            at: createdAt.addingTimeInterval(10)
        )

        XCTAssertEqual(confirmed.state, .confirmed)
        XCTAssertEqual(confirmed.supersedesFactID, proposed.id)
        XCTAssertNotEqual(confirmed.id, proposed.id)
        XCTAssertTrue(confirmed.isEligibleForLongTermContext(at: confirmed.createdAt))
    }

    func testGivenInferredDueDateReasonWhenEvaluateThenRequiresConfirmation() {
        let candidate = makeCandidate(
            kind: .dueDateReason,
            value: "Likely needed before the event",
            author: .deterministic
        )

        guard case .requireConfirmation = policy.evaluate(candidate) else {
            return XCTFail("Expected inferred scheduling rationale to require confirmation.")
        }
    }

    func testGivenSessionScopeWhenEvaluateThenProhibits() {
        let candidate = makeCandidate(
            kind: .constraint,
            scope: .session,
            value: "Unbounded session memory",
            author: .userExplicit
        )

        guard case .prohibit = policy.evaluate(candidate) else {
            return XCTFail("Expected policy facts to require Task or Project scope.")
        }
    }

    private func makeCandidate(
        kind: TaskContextFactKind,
        scope: TaskContextFactScope = .task(42),
        value: String,
        author: TaskContextFactAuthor,
        sourceTurnID: UUID? = nil,
        sourceExcerptDigest: String? = nil,
        includeEvidence: Bool = true,
        scopeAssessment: TaskContextFactScopeAssessment = .unique,
        conflictingConfirmedFactIDs: [UUID] = [],
        contentCategory: TaskContextFactContentCategory = .taskContext
    ) -> TaskContextFactCandidate {
        TaskContextFactCandidate(
            sessionID: sessionID,
            kind: kind,
            scope: scope,
            scopeAssessment: scopeAssessment,
            value: value,
            sourceTurnID: includeEvidence ? (sourceTurnID ?? turnID) : nil,
            sourceExcerptDigest: includeEvidence ? (sourceExcerptDigest ?? digest) : nil,
            confidence: author == .providerInferred ? 0.7 : 1,
            author: author,
            conflictingConfirmedFactIDs: conflictingConfirmedFactIDs,
            contentCategory: contentCategory,
            createdAt: createdAt
        )
    }

    private func makeFact(
        state: TaskContextFactState,
        value: String = "Release after signing",
        sourceTurnID: UUID? = nil,
        digest: String? = nil,
        expiresAt: Date? = nil
    ) throws -> TaskContextFact {
        try TaskContextFact(
            sessionID: sessionID,
            kind: .constraint,
            scope: .task(42),
            state: state,
            value: value,
            sourceTurnID: sourceTurnID ?? turnID,
            sourceExcerptDigest: digest ?? self.digest,
            confidence: 1,
            author: .userExplicit,
            expiresAt: expiresAt,
            createdAt: createdAt
        )
    }
}
