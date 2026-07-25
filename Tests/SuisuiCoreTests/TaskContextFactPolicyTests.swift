import XCTest
@testable import SuisuiCore

final class TaskContextFactPolicyTests: XCTestCase {
    private let policy = TaskContextFactPolicy()
    private lazy var evidenceStore: SQLiteVoiceTaskConversationStore = {
        let connection = try! SQLiteConnection(path: ":memory:")
        try! SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        let store = SQLiteVoiceTaskConversationStore(connection: connection)
        let session = VoiceTaskConversationSession(
            id: sessionID,
            title: "Evidence fixture",
            entryPoint: .voiceCommand,
            createdAt: createdAt
        )
        try! store.createSession(session)
        return store
    }()
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
        XCTAssertEqual(
            fact.sourceExcerptDigest,
            candidate.sourceEvidence?.excerptDigest
        )
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

    func testGivenDeterministicObjectiveWhenEvaluateThenRequiresConfirmation() {
        let candidate = makeCandidate(
            kind: .goal,
            value: "Derived objective",
            author: .deterministic
        )

        guard case .requireConfirmation = policy.evaluate(candidate) else {
            return XCTFail("Expected deterministic Fact to require confirmation.")
        }
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

    func testGivenAssignedCredentialWhenEvaluateThenProhibitsWithoutEchoingValue() {
        for value in [
            "token: example-credential",
            "secret = example-credential",
            "password=example-credential",
        ] {
            let candidate = makeCandidate(
                kind: .constraint,
                value: value,
                author: .userExplicit
            )

            guard case let .prohibit(reason) = policy.evaluate(candidate) else {
                return XCTFail("Expected assigned credential to be prohibited.")
            }
            XCTAssertFalse(reason.contains(value))
        }
    }

    func testGivenShortProviderKeyWhenEvaluateThenProhibits() {
        let candidate = makeCandidate(
            kind: .constraint,
            value: "Use sk-12345678",
            author: .userExplicit
        )

        guard case .prohibit = policy.evaluate(candidate) else {
            return XCTFail("Expected short provider key to remain prohibited.")
        }
    }

    func testGivenOrdinaryWordEndingInSKWhenEvaluateThenDoesNotTreatItAsSecret() {
        let candidate = makeCandidate(
            kind: .constraint,
            value: "Use a risk-based rollout",
            author: .userExplicit
        )

        guard case .saveCandidate = policy.evaluate(candidate) else {
            return XCTFail("Expected an ordinary word to remain saveable.")
        }
    }

    func testGivenSymbolOnlyProviderKeyPlaceholderWhenEvaluateThenDoesNotTreatItAsSecret() {
        let candidate = makeCandidate(
            kind: .constraint,
            value: "Document the placeholder sk-________",
            author: .userExplicit
        )

        guard case .saveCandidate = policy.evaluate(candidate) else {
            return XCTFail("Expected a symbol-only placeholder to remain saveable.")
        }
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
            sourceTurnID: oldTurnID
        )
        let replacement = try makeFact(
            state: .proposed,
            value: "Launch Friday",
            sourceTurnID: replacementTurnID
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
        XCTAssertEqual(corrected.scope, replacement.scope)
        XCTAssertEqual(corrected.sourceTurnID, replacementTurnID)
        XCTAssertEqual(corrected.supersedesFactID, old.id)
        XCTAssertNotEqual(corrected.id, replacement.id)
    }

    func testGivenCrossTaskCorrectionWhenSupersedeThenRejectsTransition() throws {
        let old = try makeFact(state: .confirmed, scope: .task(42))
        let replacement = try makeFact(state: .proposed, scope: .task(43))

        XCTAssertThrowsError(
            try policy.supersede(
                old,
                with: replacement,
                at: createdAt.addingTimeInterval(10)
            )
        ) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationDomainError,
                .incompatibleFactTransition
            )
        }
    }

    func testGivenUntrustedFactWhenRequestPersistenceWriteThenRejects() throws {
        let fact = try makeFact(state: .proposed, authorized: false)

        XCTAssertThrowsError(try policy.persistenceWrite(for: fact)) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationDomainError,
                .unauthorizedFactPersistence
            )
        }
    }

    func testGivenPolicyCandidateWhenRequestPersistenceWriteThenReturnsCapability() throws {
        let candidate = makeCandidate(
            kind: .goal,
            value: "Ship safely",
            author: .userExplicit
        )
        guard case let .saveCandidate(fact) = policy.evaluate(candidate) else {
            return XCTFail("Expected policy-authorized candidate.")
        }

        let write = try policy.persistenceWrite(for: fact)

        XCTAssertEqual(write.fact, fact)
    }

    func testGivenSerializedPolicyFactWhenReauthorizeThenConfirmationCanContinue() throws {
        let candidate = makeCandidate(
            kind: .constraint,
            value: "Confirm this provider constraint",
            author: .providerInferred
        )
        guard case let .requireConfirmation(fact, _) = policy.evaluate(candidate) else {
            return XCTFail("Expected provider inference to require confirmation.")
        }
        let restored = try JSONDecoder().decode(
            TaskContextFact.self,
            from: JSONEncoder().encode(fact)
        )
        XCTAssertEqual(restored, fact)

        let reauthorized = try policy.reauthorize(restored, from: candidate)
        let confirmed = try policy.confirm(
            reauthorized,
            at: createdAt.addingTimeInterval(1)
        )

        XCTAssertEqual(confirmed.state, .confirmed)
        XCTAssertNoThrow(try policy.persistenceWrite(for: confirmed))

        let restoredConfirmed = try JSONDecoder().decode(
            TaskContextFact.self,
            from: JSONEncoder().encode(confirmed)
        )
        let reauthorizedConfirmed = try policy.reauthorize(
            restoredConfirmed,
            from: candidate,
            predecessor: restored
        )
        XCTAssertNoThrow(
            try policy.supersede(
                reauthorizedConfirmed,
                with: reauthorized,
                at: createdAt.addingTimeInterval(2)
            )
        )
    }

    func testGivenProhibitedCandidateWhenReauthorizeThenRejects() throws {
        let fact = try makeFact(state: .proposed, authorized: false)
        let prohibited = makeCandidate(
            kind: .constraint,
            value: fact.value,
            author: .userExplicit,
            contentCategory: .health
        )

        XCTAssertThrowsError(try policy.reauthorize(fact, from: prohibited)) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationDomainError,
                .unauthorizedFactPersistence
            )
        }
    }

    func testGivenHandBuiltSupersessionWhenReauthorizeThenRejects() throws {
        let candidate = makeCandidate(
            kind: .constraint,
            value: "Do not forge history",
            author: .userExplicit
        )
        let forged = try TaskContextFact(
            sessionID: candidate.sessionID,
            kind: candidate.kind,
            scope: candidate.scope,
            state: .proposed,
            value: candidate.value,
            sourceTurnID: try XCTUnwrap(candidate.sourceTurnID),
            sourceExcerptDigest: try XCTUnwrap(candidate.sourceExcerptDigest),
            confidence: candidate.confidence,
            author: candidate.author,
            supersedesFactID: UUID(),
            createdAt: candidate.createdAt
        )

        XCTAssertThrowsError(try policy.reauthorize(forged, from: candidate)) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationDomainError,
                .unauthorizedFactPersistence
            )
        }
    }

    func testGivenSerializedTransitionsWhenReauthorizeThenAllHistoryRemainsPersistable() throws {
        let oldCandidate = makeCandidate(
            kind: .constraint,
            value: "Launch Thursday",
            author: .userExplicit,
            expiresAt: createdAt.addingTimeInterval(5)
        )
        guard case let .saveCandidate(oldProposed) = policy.evaluate(oldCandidate) else {
            return XCTFail("Expected an authorized old proposal.")
        }
        let oldConfirmed = try policy.confirm(
            oldProposed,
            at: createdAt.addingTimeInterval(1)
        )
        let rejected = try policy.reject(
            oldProposed,
            at: createdAt.addingTimeInterval(1)
        )
        let expired = try policy.expire(
            oldConfirmed,
            at: createdAt.addingTimeInterval(5)
        )

        let replacementCandidate = makeCandidate(
            kind: .constraint,
            value: "Launch Friday",
            author: .userExplicit,
            sourceTurnID: UUID(),
            candidateCreatedAt: createdAt.addingTimeInterval(2)
        )
        guard case let .saveCandidate(replacement) = policy.evaluate(replacementCandidate) else {
            return XCTFail("Expected an authorized replacement proposal.")
        }
        let correction = try policy.supersede(
            oldConfirmed,
            with: replacement,
            at: createdAt.addingTimeInterval(3)
        )

        let restoredOldProposed = try roundTrip(oldProposed)
        let restoredOldConfirmed = try roundTrip(oldConfirmed)
        let restoredRejected = try roundTrip(rejected)
        let restoredExpired = try roundTrip(expired)
        let restoredReplacement = try roundTrip(replacement)
        let restoredSuperseded = try roundTrip(correction.0)
        let restoredCorrected = try roundTrip(correction.1)

        XCTAssertNoThrow(
            try policy.persistenceWrite(
                for: policy.reauthorize(
                    restoredRejected,
                    from: oldCandidate,
                    predecessor: restoredOldProposed
                )
            )
        )
        XCTAssertNoThrow(
            try policy.persistenceWrite(
                for: policy.reauthorizeExpiration(
                    restoredExpired,
                    confirmed: restoredOldConfirmed,
                    proposed: restoredOldProposed,
                    candidate: oldCandidate
                )
            )
        )
        let restoredCorrection = try policy.reauthorizeSupersession(
            superseded: restoredSuperseded,
            corrected: restoredCorrected,
            oldConfirmed: restoredOldConfirmed,
            oldProposed: restoredOldProposed,
            oldCandidate: oldCandidate,
            replacementProposed: restoredReplacement,
            replacementCandidate: replacementCandidate
        )
        XCTAssertThrowsError(try policy.persistenceWrite(for: restoredCorrection.0))
        XCTAssertThrowsError(try policy.persistenceWrite(for: restoredCorrection.1))
        XCTAssertNoThrow(
            try policy.persistenceSupersessionWrite(
                superseded: restoredCorrection.0,
                corrected: restoredCorrection.1
            )
        )
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

    func testGivenCrossPlatformAbsolutePathWhenEvaluateThenProhibits() {
        for value in [
            "/",
            "Inspect /tmp",
            "Read /secret.txt",
            "Read /home/alice/repo/config.json",
            "Inspect /tmp/suisui.log",
            "Resolve path:/tmp/secret.txt",
            "Open `/tmp/secret.txt`",
            "Inspect [/home/alice/key]",
            #"Open C:\Users\alice\repo\config.json"#,
            #"Resolve path:C:\Users\alice\repo\config.json"#,
            #"Read \\server\share\private.txt"#,
            #"Inspect [\\server\share\private.txt]"#,
        ] {
            let candidate = makeCandidate(
                kind: .constraint,
                value: value,
                author: .userExplicit
            )

            guard case .prohibit = policy.evaluate(candidate) else {
                return XCTFail("Expected absolute path to be prohibited.")
            }
        }
    }

    func testGivenPercentageOrFrequencyWhenEvaluateThenDoesNotTreatAsPath() {
        for value in ["Reach 80%/90%", "Run at 1%/day"] {
            let candidate = makeCandidate(
                kind: .constraint,
                value: value,
                author: .userExplicit
            )

            guard case .saveCandidate = policy.evaluate(candidate) else {
                return XCTFail("Expected percentage or frequency to remain persistable.")
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

    func testGivenConfirmedFactWhenRetractThenPreservesAppendOnlyHistory() throws {
        let proposed = try makeFact(state: .proposed)
        let confirmed = try policy.confirm(
            proposed,
            at: createdAt.addingTimeInterval(1)
        )

        let retracted = try policy.retract(
            confirmed,
            at: createdAt.addingTimeInterval(2)
        )

        XCTAssertEqual(retracted.state, .retracted)
        XCTAssertEqual(retracted.supersedesFactID, confirmed.id)
        XCTAssertNotEqual(retracted.id, confirmed.id)
        XCTAssertFalse(retracted.isEligibleForLongTermContext(at: retracted.createdAt))
        XCTAssertNoThrow(try policy.persistenceWrite(for: retracted))
    }

    func testGivenSerializedRetractionWhenReauthorizeThenRestoresWriteCapability() throws {
        let candidate = makeCandidate(
            kind: .constraint,
            value: "Release after signing",
            author: .userExplicit
        )
        guard case let .saveCandidate(proposed) = policy.evaluate(candidate) else {
            return XCTFail("Expected an authorized proposal.")
        }
        let confirmed = try policy.confirm(
            proposed,
            at: createdAt.addingTimeInterval(1)
        )
        let retracted = try policy.retract(
            confirmed,
            at: createdAt.addingTimeInterval(2)
        )

        let restored = try policy.reauthorizeRetraction(
            roundTrip(retracted),
            confirmed: roundTrip(confirmed),
            proposed: roundTrip(proposed),
            candidate: candidate
        )

        XCTAssertEqual(restored, retracted)
        XCTAssertNoThrow(try policy.persistenceWrite(for: restored))
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

    func testGivenNonPositiveScopeIdentifierWhenEvaluateThenProhibits() {
        for scope in [
            TaskContextFactScope.task(0),
            .project(-1),
        ] {
            let candidate = makeCandidate(
                kind: .goal,
                scope: scope,
                value: "Invalid scope",
                author: .userExplicit
            )

            guard case .prohibit = policy.evaluate(candidate) else {
                return XCTFail("Expected \(scope) to be prohibited.")
            }
        }
    }

    private func makeCandidate(
        kind: TaskContextFactKind,
        scope: TaskContextFactScope = .task(42),
        value: String,
        author: TaskContextFactAuthor,
        sourceTurnID: UUID? = nil,
        includeEvidence: Bool = true,
        scopeAssessment: TaskContextFactScopeAssessment = .unique,
        conflictingConfirmedFactIDs: [UUID] = [],
        contentCategory: TaskContextFactContentCategory = .taskContext,
        candidateCreatedAt: Date? = nil,
        expiresAt: Date? = nil
    ) -> TaskContextFactCandidate {
        TaskContextFactCandidate(
            sessionID: sessionID,
            kind: kind,
            scope: scope,
            scopeAssessment: scopeAssessment,
            value: value,
            sourceEvidence: includeEvidence
                ? verifiedEvidence(turnID: sourceTurnID ?? turnID)
                : nil,
            confidence: author == .providerInferred ? 0.7 : 1,
            author: author,
            conflictingConfirmedFactIDs: conflictingConfirmedFactIDs,
            contentCategory: contentCategory,
            createdAt: candidateCreatedAt ?? createdAt,
            expiresAt: expiresAt
        )
    }

    private func roundTrip(_ fact: TaskContextFact) throws -> TaskContextFact {
        try JSONDecoder().decode(
            TaskContextFact.self,
            from: JSONEncoder().encode(fact)
        )
    }

    private func makeFact(
        state: TaskContextFactState,
        scope: TaskContextFactScope = .task(42),
        value: String = "Release after signing",
        sourceTurnID: UUID? = nil,
        expiresAt: Date? = nil,
        authorized: Bool = true
    ) throws -> TaskContextFact {
        let evidence = verifiedEvidence(turnID: sourceTurnID ?? turnID)
        let fact = try TaskContextFact(
            sessionID: sessionID,
            kind: .constraint,
            scope: scope,
            state: authorized ? .proposed : state,
            value: value,
            sourceTurnID: evidence.turnID,
            sourceExcerptDigest: evidence.excerptDigest,
            confidence: 1,
            author: .userExplicit,
            expiresAt: expiresAt,
            createdAt: createdAt
        )
        guard authorized else {
            return fact
        }
        let candidate = TaskContextFactCandidate(
            sessionID: fact.sessionID,
            kind: fact.kind,
            scope: fact.scope,
            scopeAssessment: .unique,
            value: fact.value,
            sourceEvidence: evidence,
            confidence: fact.confidence,
            author: fact.author,
            conflictingConfirmedFactIDs: [],
            contentCategory: .taskContext,
            createdAt: fact.createdAt,
            expiresAt: fact.expiresAt
        )
        let authorizedFact = try policy.reauthorize(fact, from: candidate)
        switch state {
        case .proposed:
            return authorizedFact
        case .confirmed:
            return try policy.confirm(authorizedFact, at: createdAt)
        case .rejected:
            return try policy.reject(authorizedFact, at: createdAt)
        case .retracted, .superseded, .expired:
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }
    }

    private func verifiedEvidence(
        turnID: UUID
    ) -> TaskContextFactSourceEvidence {
        let excerpt = "Confirmed evidence for \(turnID.uuidString)"
        if let evidence = try? evidenceStore.verifyFactSourceEvidence(
            sessionID: sessionID,
            turnID: turnID,
            sourceExcerpt: excerpt
        ) {
            return evidence
        }
        let turn = try! VoiceTaskConversationTurn(
            id: turnID,
            sessionID: sessionID,
            author: .user,
            userConfirmedText: excerpt,
            createdAt: createdAt
        )
        try! evidenceStore.saveTurn(turn)
        return try! evidenceStore.verifyFactSourceEvidence(
            sessionID: sessionID,
            turnID: turnID,
            sourceExcerpt: excerpt
        )
    }
}
