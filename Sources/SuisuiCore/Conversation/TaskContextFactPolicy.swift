import Foundation

public enum TaskContextFactScopeAssessment: String, Codable, Equatable, Sendable {
    case unique
    case ambiguous
    case outsideAllowedScope = "outside_allowed_scope"
}

public enum TaskContextFactContentCategory: String, Codable, Equatable, Sendable {
    case taskContext = "task_context"
    case secret
    case authentication
    case payment
    case health
    case familyProfile
    case rawAudio
    case localPath
    case binary
}

public struct TaskContextFactCandidate: Equatable, Sendable {
    public let sessionID: UUID
    public let kind: TaskContextFactKind
    public let scope: TaskContextFactScope
    public let scopeAssessment: TaskContextFactScopeAssessment
    public let value: String
    public let sourceEvidence: TaskContextFactSourceEvidence?
    public let confidence: Double
    public let author: TaskContextFactAuthor
    public let conflictingConfirmedFactIDs: [UUID]
    public let contentCategory: TaskContextFactContentCategory
    public let createdAt: Date
    public let expiresAt: Date?

    public init(
        sessionID: UUID,
        kind: TaskContextFactKind,
        scope: TaskContextFactScope,
        scopeAssessment: TaskContextFactScopeAssessment,
        value: String,
        sourceEvidence: TaskContextFactSourceEvidence?,
        confidence: Double,
        author: TaskContextFactAuthor,
        conflictingConfirmedFactIDs: [UUID],
        contentCategory: TaskContextFactContentCategory,
        createdAt: Date,
        expiresAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.scope = scope
        self.scopeAssessment = scopeAssessment
        self.value = value
        self.sourceEvidence = sourceEvidence
        self.confidence = confidence
        self.author = author
        self.conflictingConfirmedFactIDs = conflictingConfirmedFactIDs
        self.contentCategory = contentCategory
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public var sourceTurnID: UUID? {
        sourceEvidence?.turnID
    }

    public var sourceExcerptDigest: String? {
        sourceEvidence?.excerptDigest
    }
}

public enum TaskContextFactStorageDecision: Equatable, Sendable {
    case saveCandidate(TaskContextFact)
    case requireConfirmation(TaskContextFact, reason: String)
    case prohibit(reason: String)
}

/// Capability accepted by the Store. Its initializer is intentionally hidden
/// so prohibited or hand-constructed Facts cannot cross the write boundary.
public struct TaskContextFactWrite: Equatable, Sendable {
    public let fact: TaskContextFact
    let storeIdentifier: UUID

    fileprivate init(fact: TaskContextFact, storeIdentifier: UUID) {
        self.fact = fact
        self.storeIdentifier = storeIdentifier
    }
}

/// Atomic Store capability for the two records produced by a correction.
public struct TaskContextFactSupersessionWrite: Equatable, Sendable {
    public let superseded: TaskContextFact
    public let corrected: TaskContextFact
    let storeIdentifier: UUID

    fileprivate init(
        superseded: TaskContextFact,
        corrected: TaskContextFact,
        storeIdentifier: UUID
    ) {
        self.superseded = superseded
        self.corrected = corrected
        self.storeIdentifier = storeIdentifier
    }
}

/// Only policy code in this file can construct this token. Keeping the token
/// separate from the Fact prevents other SuisuiCore components and tests from
/// blessing hand-built or prohibited payloads.
struct TaskContextFactAuthorizationToken: Sendable {
    fileprivate init() {}
}

public struct TaskContextFactPolicy: Sendable {
    public init() {}

    public func evaluate(
        _ candidate: TaskContextFactCandidate
    ) -> TaskContextFactStorageDecision {
        // Prohibitions are checked before confirmation rules so sensitive input
        // can never be reflected in a prompt or persisted as a proposal.
        if candidate.scopeAssessment == .outsideAllowedScope {
            return .prohibit(reason: "outside allowed Task Context scope")
        }
        if case .session = candidate.scope {
            return .prohibit(reason: "Task Context requires task or project scope")
        }
        guard candidate.contentCategory == .taskContext else {
            return .prohibit(reason: "content category is prohibited from Task Context")
        }
        guard !Self.containsSecretOrRawPath(candidate.value) else {
            return .prohibit(reason: "secret or local data is prohibited from Task Context")
        }
        guard let sourceEvidence = candidate.sourceEvidence,
              sourceEvidence.sessionID == candidate.sessionID
        else {
            return .prohibit(reason: "source evidence is required")
        }

        let fact: TaskContextFact
        do {
            fact = try TaskContextFact(
                sessionID: candidate.sessionID,
                kind: candidate.kind,
                scope: candidate.scope,
                state: .proposed,
                value: candidate.value,
                sourceTurnID: sourceEvidence.turnID,
                sourceExcerptDigest: sourceEvidence.excerptDigest,
                confidence: candidate.confidence,
                author: candidate.author,
                expiresAt: candidate.expiresAt,
                createdAt: candidate.createdAt
            ).authorizingPersistence(
                using: TaskContextFactAuthorizationToken(),
                sourceStoreIdentifier: sourceEvidence.storeIdentifier
            )
        } catch {
            return .prohibit(reason: "candidate failed Task Context validation")
        }

        if candidate.scopeAssessment == .ambiguous {
            return .requireConfirmation(fact, reason: "scope requires confirmation")
        }
        if !candidate.conflictingConfirmedFactIDs.isEmpty {
            return .requireConfirmation(fact, reason: "conflict requires confirmation")
        }
        if candidate.author == .providerInferred {
            return .requireConfirmation(fact, reason: "provider inference requires confirmation")
        }
        if candidate.author == .deterministic {
            return .requireConfirmation(fact, reason: "deterministic inference requires confirmation")
        }
        if candidate.kind == .decision {
            return .requireConfirmation(fact, reason: "long-term decision requires confirmation")
        }
        if [.dueDateReason, .priorityReason].contains(candidate.kind),
           candidate.author != .userExplicit
        {
            return .requireConfirmation(fact, reason: "inferred scheduling reason requires confirmation")
        }
        guard [
            .goal,
            .constraint,
            .acceptanceCriterion,
            .openQuestion,
            .followUp,
        ].contains(candidate.kind) else {
            return .requireConfirmation(fact, reason: "fact kind requires confirmation")
        }
        return .saveCandidate(fact)
    }

    public func persistenceWrite(
        for fact: TaskContextFact
    ) throws -> TaskContextFactWrite {
        guard fact.persistenceAuthorized,
              fact.sourceEvidenceVerified,
              let storeIdentifier = fact.sourceStoreIdentifier,
              !fact.requiresAtomicSupersession
        else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }
        return TaskContextFactWrite(
            fact: fact,
            storeIdentifier: storeIdentifier
        )
    }

    public func persistenceSupersessionWrite(
        superseded: TaskContextFact,
        corrected: TaskContextFact
    ) throws -> TaskContextFactSupersessionWrite {
        guard superseded.persistenceAuthorized,
              corrected.persistenceAuthorized,
              superseded.sourceEvidenceVerified,
              corrected.sourceEvidenceVerified,
              let storeIdentifier = superseded.sourceStoreIdentifier,
              corrected.sourceStoreIdentifier == storeIdentifier,
              superseded.requiresAtomicSupersession,
              corrected.requiresAtomicSupersession,
              superseded.state == .superseded,
              corrected.state == .confirmed,
              superseded.sessionID == corrected.sessionID,
              superseded.kind == corrected.kind,
              superseded.scope == corrected.scope,
              superseded.supersedesFactID == corrected.supersedesFactID,
              superseded.createdAt == corrected.createdAt
        else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }
        return TaskContextFactSupersessionWrite(
            superseded: superseded,
            corrected: corrected,
            storeIdentifier: storeIdentifier
        )
    }

    /// Restores the non-serializable Store binding from a verified persisted
    /// record. The Store calls this only after decoding a confirmed Fact from
    /// its own database, so a deleted conversation Turn never needs to be
    /// recreated merely to record the user's later withdrawal.
    func reauthorizePersistedConfirmedFact(
        _ fact: TaskContextFact,
        sourceStoreIdentifier: UUID
    ) throws -> TaskContextFact {
        guard !fact.persistenceAuthorized,
              fact.sourceEvidenceVerified,
              fact.state == .confirmed,
              fact.supersedesFactID != nil
        else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }
        return fact.authorizingPersistence(
            using: TaskContextFactAuthorizationToken(),
            sourceStoreIdentifier: sourceStoreIdentifier
        )
    }

    /// Re-evaluates serialized confirmation work before restoring its write
    /// capability. Authorization itself is intentionally not Codable because
    /// a payload must never be able to declare that it passed policy checks.
    public func reauthorize(
        _ fact: TaskContextFact,
        from candidate: TaskContextFactCandidate,
        predecessor: TaskContextFact? = nil
    ) throws -> TaskContextFact {
        guard !fact.persistenceAuthorized,
              fact.sourceEvidenceVerified
        else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }

        switch fact.state {
        case .proposed:
            guard predecessor == nil,
                  let reevaluated = evaluatedFact(for: candidate),
                  factMatches(reevaluated, fact)
            else {
                throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
            }
        case .confirmed, .rejected:
            guard let predecessor,
                  predecessor.id == fact.supersedesFactID,
                  predecessor.state == .proposed
            else {
                throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
            }
            let authorizedPredecessor = predecessor.persistenceAuthorized
                ? predecessor
                : try reauthorize(predecessor, from: candidate)
            let expected = if fact.state == .confirmed {
                try confirm(authorizedPredecessor, at: fact.createdAt)
            } else {
                try reject(authorizedPredecessor, at: fact.createdAt)
            }
            guard factMatches(expected, fact) else {
                throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
            }
        case .retracted, .superseded, .expired:
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }

        guard let storeIdentifier = candidate.sourceEvidence?.storeIdentifier else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }
        return fact.authorizingPersistence(
            using: TaskContextFactAuthorizationToken(),
            sourceStoreIdentifier: storeIdentifier
        )
    }

    /// Replays the confirmed predecessor and expiry transition so a serialized
    /// expiry record can regain a Store capability without trusting its payload.
    public func reauthorizeExpiration(
        _ expired: TaskContextFact,
        confirmed: TaskContextFact,
        proposed: TaskContextFact,
        candidate: TaskContextFactCandidate
    ) throws -> TaskContextFact {
        guard !expired.persistenceAuthorized,
              expired.sourceEvidenceVerified,
              expired.state == .expired,
              expired.supersedesFactID == confirmed.id
        else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }
        let authorizedConfirmed = confirmed.persistenceAuthorized
            ? confirmed
            : try reauthorize(
                confirmed,
                from: candidate,
                predecessor: proposed
            )
        let expected = try expire(authorizedConfirmed, at: expired.createdAt)
        guard factMatches(expected, expired) else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }
        return expired.authorizingPersistence(
            using: TaskContextFactAuthorizationToken(),
            sourceStoreIdentifier: authorizedConfirmed.sourceStoreIdentifier
        )
    }

    /// Replays the complete proposal-confirmation-retraction chain before
    /// restoring persistence authority. This keeps user withdrawal append-only
    /// without trusting authorization serialized alongside the payload.
    public func reauthorizeRetraction(
        _ retracted: TaskContextFact,
        confirmed: TaskContextFact,
        proposed: TaskContextFact,
        candidate: TaskContextFactCandidate
    ) throws -> TaskContextFact {
        guard !retracted.persistenceAuthorized,
              retracted.sourceEvidenceVerified,
              retracted.state == .retracted,
              retracted.supersedesFactID == confirmed.id
        else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }
        let authorizedConfirmed = confirmed.persistenceAuthorized
            ? confirmed
            : try reauthorize(
                confirmed,
                from: candidate,
                predecessor: proposed
            )
        let expected = try retract(authorizedConfirmed, at: retracted.createdAt)
        guard factMatches(expected, retracted) else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }
        return retracted.authorizingPersistence(
            using: TaskContextFactAuthorizationToken(),
            sourceStoreIdentifier: authorizedConfirmed.sourceStoreIdentifier
        )
    }

    /// Replays both sides of a correction. Returning both capabilities together
    /// prevents a corrected Fact from being detached from the superseded record
    /// whose scope, kind, and provenance authorized it.
    public func reauthorizeSupersession(
        superseded: TaskContextFact,
        corrected: TaskContextFact,
        oldConfirmed: TaskContextFact,
        oldProposed: TaskContextFact,
        oldCandidate: TaskContextFactCandidate,
        replacementProposed: TaskContextFact,
        replacementCandidate: TaskContextFactCandidate
    ) throws -> (TaskContextFact, TaskContextFact) {
        guard !superseded.persistenceAuthorized,
              !corrected.persistenceAuthorized,
              superseded.sourceEvidenceVerified,
              corrected.sourceEvidenceVerified,
              superseded.state == .superseded,
              corrected.state == .confirmed,
              superseded.createdAt == corrected.createdAt
        else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }
        let authorizedOld = oldConfirmed.persistenceAuthorized
            ? oldConfirmed
            : try reauthorize(
                oldConfirmed,
                from: oldCandidate,
                predecessor: oldProposed
            )
        let authorizedReplacement = replacementProposed.persistenceAuthorized
            ? replacementProposed
            : try reauthorize(replacementProposed, from: replacementCandidate)
        let expected = try supersede(
            authorizedOld,
            with: authorizedReplacement,
            at: superseded.createdAt
        )
        guard factMatches(expected.0, superseded),
              factMatches(expected.1, corrected)
        else {
            throw VoiceTaskConversationDomainError.unauthorizedFactPersistence
        }
        return (
            superseded.authorizingPersistence(
                using: TaskContextFactAuthorizationToken(),
                sourceStoreIdentifier: expected.0.sourceStoreIdentifier,
                requiresAtomicSupersession: true
            ),
            corrected.authorizingPersistence(
                using: TaskContextFactAuthorizationToken(),
                sourceStoreIdentifier: expected.1.sourceStoreIdentifier,
                requiresAtomicSupersession: true
            )
        )
    }

    public func confirm(
        _ fact: TaskContextFact,
        at date: Date
    ) throws -> TaskContextFact {
        guard fact.persistenceAuthorized,
              fact.state == .proposed,
              date >= fact.createdAt
        else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }
        guard fact.expiresAt.map({ date < $0 }) ?? true else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }
        return try transition(fact, to: .confirmed, at: date)
    }

    public func reject(
        _ fact: TaskContextFact,
        at date: Date
    ) throws -> TaskContextFact {
        guard fact.persistenceAuthorized,
              fact.state == .proposed,
              date >= fact.createdAt
        else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }
        return try transition(fact, to: .rejected, at: date)
    }

    public func retract(
        _ fact: TaskContextFact,
        at date: Date
    ) throws -> TaskContextFact {
        guard fact.persistenceAuthorized,
              fact.state == .confirmed,
              date >= fact.createdAt
        else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }
        return try transition(fact, to: .retracted, at: date)
    }

    public func expire(
        _ fact: TaskContextFact,
        at date: Date
    ) throws -> TaskContextFact {
        guard fact.persistenceAuthorized,
              fact.state == .confirmed,
              let expiresAt = fact.expiresAt,
              date >= expiresAt
        else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }
        return try transition(fact, to: .expired, at: date, preserveExpiration: false)
    }

    public func supersede(
        _ old: TaskContextFact,
        with replacement: TaskContextFact,
        at date: Date
    ) throws -> (TaskContextFact, TaskContextFact) {
        guard old.state == .confirmed,
              replacement.state == .proposed,
              old.persistenceAuthorized,
              replacement.persistenceAuthorized,
              let storeIdentifier = old.sourceStoreIdentifier,
              replacement.sourceStoreIdentifier == storeIdentifier,
              old.sessionID == replacement.sessionID,
              old.kind == replacement.kind,
              old.scope == replacement.scope,
              date >= old.createdAt,
              date >= replacement.createdAt
        else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }

        let supersession = try transition(
            old,
            to: .superseded,
            at: date
        ).authorizingPersistence(
            using: TaskContextFactAuthorizationToken(),
            sourceStoreIdentifier: storeIdentifier,
            requiresAtomicSupersession: true
        )
        let corrected = try TaskContextFact(
            sessionID: replacement.sessionID,
            kind: replacement.kind,
            scope: replacement.scope,
            state: .confirmed,
            value: replacement.value,
            sourceTurnID: replacement.sourceTurnID,
            sourceExcerptDigest: replacement.sourceExcerptDigest,
            confidence: replacement.confidence,
            author: replacement.author,
            supersedesFactID: old.id,
            expiresAt: replacement.expiresAt,
            createdAt: date
        ).authorizingPersistence(
            using: TaskContextFactAuthorizationToken(),
            sourceStoreIdentifier: storeIdentifier,
            requiresAtomicSupersession: true
        )
        return (supersession, corrected)
    }

    private func transition(
        _ fact: TaskContextFact,
        to state: TaskContextFactState,
        at date: Date,
        preserveExpiration: Bool = true
    ) throws -> TaskContextFact {
        let expiration = preserveExpiration
            ? fact.expiresAt.flatMap { $0 > date ? $0 : nil }
            : nil
        return try TaskContextFact(
            sessionID: fact.sessionID,
            kind: fact.kind,
            scope: fact.scope,
            state: state,
            value: fact.value,
            sourceTurnID: fact.sourceTurnID,
            sourceExcerptDigest: fact.sourceExcerptDigest,
            confidence: fact.confidence,
            author: fact.author,
            supersedesFactID: fact.id,
            expiresAt: expiration,
            createdAt: date
        ).authorizingPersistence(
            using: TaskContextFactAuthorizationToken(),
            sourceStoreIdentifier: fact.sourceStoreIdentifier
        )
    }

    private func evaluatedFact(
        for candidate: TaskContextFactCandidate
    ) -> TaskContextFact? {
        switch evaluate(candidate) {
        case let .saveCandidate(fact),
             let .requireConfirmation(fact, _):
            return fact
        case .prohibit:
            return nil
        }
    }

    private func factMatches(
        _ expected: TaskContextFact,
        _ actual: TaskContextFact
    ) -> Bool {
        expected.sessionID == actual.sessionID
            && expected.kind == actual.kind
            && expected.scope == actual.scope
            && expected.state == actual.state
            && expected.value == actual.value
            && expected.sourceTurnID == actual.sourceTurnID
            && expected.sourceExcerptDigest == actual.sourceExcerptDigest
            && expected.sourceEvidenceVerified == actual.sourceEvidenceVerified
            && expected.confidence == actual.confidence
            && expected.author == actual.author
            && expected.supersedesFactID == actual.supersedesFactID
            && expected.expiresAt == actual.expiresAt
            && expected.createdAt == actual.createdAt
    }

    private static func containsSecretOrRawPath(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let redactionReport = DeveloperSecretRedactor().redact(value).report
        if redactionReport.matchedPatternNames.contains(where: { $0 != "openai" }) {
            return true
        }
        // A provider key needs a token boundary and realistic length. Plain
        // substring matching would reject ordinary words such as "risk-based";
        // the shared redactor still owns all other credential formats.
        let providerKeyPattern = #"(?i)(?:^|[^a-z0-9])sk-[a-z0-9][a-z0-9_-]{7,}"#
        if redactionReport.matchedPatternNames.contains("openai"),
           value.range(of: providerKeyPattern, options: .regularExpression) != nil
        {
            return true
        }
        let highSignalMarkers = [
            "bearer ", "authorization:",
            "file://", "/users/", "/private/", "/volumes/",
        ]
        if highSignalMarkers.contains(where: { lowered.contains($0) }) {
            return true
        }
        // Voice input commonly expresses credentials as natural language
        // instead of key/value syntax. Keep these patterns here, after the
        // shared redactor, so phrases such as "password is ..." cannot cross
        // the Task Context persistence boundary merely by omitting "=".
        if containsSpokenCredentialValue(value) {
            return true
        }
        // Task Context is cross-platform even though Suisui currently runs on
        // macOS. Detect generic POSIX, drive-letter, and UNC absolute paths so
        // content cannot become persistable merely because it came from a
        // Linux or Windows workspace.
        let absolutePathPatterns = [
            #"(?:^|[^a-zA-Z0-9/%])/(?:$|[^/\s]+(?:/[^/\s]*)*)"#,
            #"(?:^|[^a-zA-Z0-9\\])[a-zA-Z]:\\(?:[^\\\r\n]+\\)*[^\\\r\n]*"#,
            #"(?:^|[^a-zA-Z0-9\\])\\\\[^\\\s]+\\[^\\\s]+"#,
        ]
        return absolutePathPatterns.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func containsSpokenCredentialValue(_ value: String) -> Bool {
        let englishCredential = #"(?:api[\s_-]?keys?|access[\s_-]?tokens?|auth(?:entication|orization)?[\s_-]?(?:keys?|tokens?|codes?)|private[\s_-]?keys?|verification[\s_-]?codes?|confirmation[\s_-]?codes?|recovery[\s_-]?codes?|2fa[\s_-]?codes?|one[\s_-]?time[\s_-]?codes?|otps?|tokens?|passwords?|passcodes?|passphrases?|credentials?|secrets?|pins?)"#
        let englishNonPINCredential = #"(?:api[\s_-]?keys?|access[\s_-]?tokens?|auth(?:entication|orization)?[\s_-]?(?:keys?|tokens?|codes?)|private[\s_-]?keys?|verification[\s_-]?codes?|confirmation[\s_-]?codes?|recovery[\s_-]?codes?|2fa[\s_-]?codes?|one[\s_-]?time[\s_-]?codes?|otps?|tokens?|passwords?|passcodes?|passphrases?|credentials?|secrets?)"#
        let japaneseCredential = #"(?:api\s*キー|アクセス\s*トークン|認証\s*トークン|認証\s*コード|確認\s*コード|ワンタイム\s*パスワード|(?<![a-z0-9])otp(?![a-z0-9])|トークン|パスワード|パスコード|パスフレーズ|暗証番号|認証情報|秘密鍵|シークレット)"#
        let spokenNumber = #"(?:zero|oh|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand)"#
        let assignedPINValue = #"(?:[\p{L}\p{Nd}_-]*\p{Nd}[\p{L}\p{Nd}_-]*|"#
            + spokenNumber + #"(?:[-\s]+"# + spokenNumber + #"){0,7})"#
        let englishCredentialScope = #"(?:\s+(?:for|of)\s+(?:the\s+|our\s+|my\s+|your\s+|their\s+)?[a-z0-9_@.'-]+(?:\s+[a-z0-9_@.'-]+){0,7})?"#
        let englishRelativeClause = #"(?:\s+(?:(?:that|which)\s+)?(?:i|we|you|they)\s+(?:use|need|have)|\s+to\s+(?:use|deploy|rotate))?"#
        let credentialAssignmentPatterns = [
            #"\b"# + englishCredential
                + #"\b(?:'s)?"# + englishCredentialScope
                + englishRelativeClause + englishCredentialScope
                + #"(?:\s+value)?"#
                + #"\s+(?:is|are|was|were|equals?|should\s+be|must\s+be|will\s+be)\s+\S+"#,
            #"\b(?:the\s+|our\s+|my\s+|your\s+|their\s+)?"# + englishCredential
                + #"'s\s+\S+"#,
            #"\b"# + englishCredential
                + #"\b"# + englishCredentialScope + #"\s*(?::|=)\s*\S+"#,
            #"^\s*use\s+(?:the\s+|my\s+)?"# + englishCredential
                + #"\s+(?!authentication\b|authorization\b|bucket\b|budget\b|count\b|flow\b|handling\b|management\b|policy\b|reset\b|rotation\b|storage\b|support\b|validation\b)\S+[.!]?\s*$"#,
            #"\b(?:set|change|update|assign)\s+(?:the\s+|my\s+)?"# + englishCredential
                + englishCredentialScope + #"\s+(?:to|as)\s+\S+"#,
            #"\b(?:set|change|update|assign)\s+(?:the\s+|my\s+)?"# + englishCredential
                + #"\s+(?!authentication\b|authorization\b|daily\b|friday\b|monday\b|monthly\b|policy\b|reset\b|rotation\b|saturday\b|sunday\b|thursday\b|today\b|tomorrow\b|tuesday\b|wednesday\b|weekly\b)\S+[.!]?\s*$"#,
            #"\b(?:i|we|you|they)\s+(?:set|changed|updated|assigned)\s+"#
                + #"(?:the\s+|my\s+|our\s+|your\s+|their\s+)?"# + englishCredential
                + englishCredentialScope + #"\s+(?:to|as)\s+\S+"#,
            #"\b"# + englishCredential
                + #"\s+(?:has|have|had)\s+been\s+(?:set|changed|updated|assigned)"#
                + #"\s+(?:to|as)\s+\S+"#,
            #"\b(?:use|set|store|save)\s+\S+\s+(?:as|for)\s+(?:the\s+|my\s+)?"#
                + englishCredential + #"\b"#,
            #"\S+\s+(?:is|was|equals?|as|should\s+be|must\s+be|will\s+be)\s+"#
                + #"(?:the\s+|our\s+|my\s+|your\s+|their\s+)?"#
                + englishCredential + englishCredentialScope + #"[.!]?\s*$"#,
            // Speech recognition may drop the delimiter in "password: value".
            // Treat it as an assignment only when the entire utterance is the
            // credential label plus one value, never from a word inside a task.
            #"^\s*(?:(?:remember|note|record)\s+)?(?:the\s+|our\s+|my\s+|your\s+|their\s+)?"#
                + englishNonPINCredential
                + #"\s+(?!authentication\b|authorization\b|bucket\b|budget\b|count\b|expires?\b|flow\b|handling\b|length\b|management\b|must\b|policy\b|reset\b|rotation\b|santa\b|should\b|storage\b|support\b|this\b|urgent\b|validation\b)"#
                + #"[^\s.!?]{3,}(?:\s+[^\s.!?]{2,}){0,3}[.!]?\s*$"#,
            #"^\s*"# + japaneseCredential
                + #"\s+[^\s。.!?]{3,}(?:\s+[^\s。.!?]{2,}){0,3}[。.!]?\s*$"#,
            #"\b"# + englishNonPINCredential + #"\s+"# + assignedPINValue
                + #"\b[.!]?\s*$"#,
            // A PIN may be alphabetic. An explicit assignment delimiter is
            // sufficient evidence of a credential value without guessing its shape.
            #"\bpins?\b(?:\s+(?:code|number))?\s*(?::|=)\s*\S+"#,
            #"\bpins?\b(?:\s+(?:code|number))?(?:\s+(?:for|of)\s+(?:the\s+)?[a-z0-9_-]+(?:\s+[a-z0-9_-]+){0,2})?\s+(?:is|are|was|were|equals?|should\s+be)\b"#,
            #"\bpins?\b(?:\s+(?:code|number))?\s+(?:is\s+|was\s+|has\s+been\s+)?"#
                + #"(?:set|changed|updated|assigned)\s+(?:to|as)\s+\S+"#,
            #"^\s*(?:the\s+|my\s+)?pins?\b(?:\s+(?:code|number))?\s+"# + spokenNumber
                + #"(?:[-\s]+"# + spokenNumber + #"){0,7}[.!]?\s*$"#,
            #"^\s*(?:the\s+|my\s+)?pins?\b(?:\s+(?:code|number))?\s+"#
                + assignedPINValue + #"[.!]?\s*$"#,
            #"^\s*(?:the\s+|my\s+)?pins?\b(?:\s+(?:code|number))?\s+"#
                + #"(?!issue\b|release\b|task\b|this\b|today\b|tomorrow\b)[a-z][a-z0-9_-]{3,}[.!]?\s*$"#,
            #"\bpins?\b(?:\s+(?:code|number))?(?:\s+(?:for|of)\s+(?:the\s+)?[a-z0-9_-]+){0,2}\s*(?:(?:is|are|was|were|equals?|should\s+be|:|=)\s*)?[0-9](?:[ -]?[0-9]){2,}\b"#,
            #"\b[0-9](?:[ -]?[0-9]){2,}\s+(?:is|was|equals?|as)\s+(?:my\s+|the\s+)?pins?\b"#,
            #"\b(?:set|change|update)\s+(?:the\s+|my\s+)?pins?\s+(?:to|as)\s+"#
                + assignedPINValue + #"\b"#,
            #"\buse\s+"# + assignedPINValue + #"\s+for\s+(?:the\s+|my\s+)?pins?\b"#,
            #"[PpＰｐ][IiＩｉ][NnＮｎ](?:\s*コード)?\s*(?:は|が|を|:|：|=)\s*\S+"#,
            #"[PpＰｐ][IiＩｉ][NnＮｎ]\s*コード\s*"# + assignedPINValue,
            #"トークン\s*(?:は|が|を|:|：|=)\s*\S+"#,
            #"シークレット\s*(?:は|が|を|:|：|=)\s*\S+"#,
            #"\S+\s*を\s*"# + japaneseCredential
                + #"\s*(?:に\s*(?:する|設定|変更|更新|使用)|として\s*(?:使う|使用する))"#,
            #"\S+\s*(?:が|は)\s*"# + japaneseCredential
                + #"\s*(?:です|である|となる)?[。.!]?\s*$"#,
            japaneseCredential + #"(?:\s*の\s*値)?\s*(?:は|が|を|:|：|=)\s*\S+"#,
            japaneseCredential + #"\s+"# + assignedPINValue,
        ]
        let hasCredentialAssignment = credentialAssignmentPatterns.contains(where: {
            value.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        })
        guard hasCredentialAssignment else {
            return false
        }

        // Assignment-shaped wording can also describe a value-free requirement,
        // such as "password is required". Permit only anchored requirement
        // grammars so an appended secret cannot hide behind a benign first clause.
        let englishState = #"(?:required|needed|optional|available|configured|disabled|enabled|encrypted|expired|managed|missing|rotated|stored|supported|valid|invalid)"#
        let englishTopic = #"(?:authentication|authorization|exchange|flow|handling|management|policy|refresh|reset|rotation|storage|support|validation)"#
        let contextWord = #"(?:authentication|authorization|build|deployment|development|environment|integration|keychain|production|release|runtime|security|staging|workflow)"#
        let englishOwner = #"(?:the\s+|our\s+|my\s+|your\s+|their\s+)?"#
        let englishPurpose = #"(?:\s+to\s+(?:(?:log|sign)\s+(?:in|into|on)|(?:authenticate|build|connect|deploy|release|run)|access\s+(?:the\s+)?(?:build|deployment|environment|integration|production|release|runtime|staging)|(?:reset|verify)\s+(?:the\s+)?(?:account|identity|login|user)))?"#
        let englishStateQualifier = #"(?:\s+(?:at\s+rest|in\s+transit|in\s+(?:the\s+)?(?:system\s+)?keychain))?"#
        let englishContext = #"(?:\s+(?:for|during|in)\s+(?:the\s+)?"# + contextWord
            + #"(?:\s+"# + contextWord + #")*)?"# + englishPurpose
        let japaneseState = #"(?:必要|必須|設定済み?|未設定|有効|無効|暗号化済み?|管理済み?|保存済み?)"#
        let safeRequirementPatterns = [
            #"^\s*"# + englishOwner + englishCredential + englishCredentialScope
                + #"\s+(?:is|was|are|were|should\s+be|must\s+be|will\s+be)\s+"#
                + englishState
                + englishContext + englishStateQualifier + #"[.!]?\s*$"#,
            #"^\s*"# + englishOwner + englishCredential + englishCredentialScope
                + #"\s+(?:is|was|are|were|should\s+be|must\s+be|will\s+be)\s+not\s+"#
                + englishState
                + englishContext + englishStateQualifier + #"[.!]?\s*$"#,
            #"^\s*(?:the\s+)?pins?\s+(?:code|number)\s+"#
                + #"(?:is|was|should\s+be|must\s+be|will\s+be)\s+"#
                + englishState + englishContext + #"[.!]?\s*$"#,
            #"^\s*(?:do|will)\s+(?:we|you|they)\s+(?:need|require|use)\s+"#
                + #"(?:an?\s+|the\s+)?"# + englishCredential
                + englishContext + #"\?\s*$"#,
            #"^\s*(?:use|support|implement|document)\s+(?:the\s+)?"#
                + englishCredential + #"\s+"# + englishTopic
                + #"(?:\s+(?:flow|policy|process|support|handling))?[.!]?\s*$"#,
            #"^\s*(?:use|support|implement|design|require)\s+token[-\s]+based\s+"#
                + #"(?:authentication|authorization)(?:\s+(?:flow|policy|process))?[.!]?\s*$"#,
            #"^\s*(?:the\s+)?"# + englishCredential + #"\s+"# + englishTopic
                + #"\s+(?:is|was|are|were|should\s+be)\s+"# + englishState
                + englishContext + #"[.!]?\s*$"#,
            #"^\s*(?:the\s+)?passwords?\s+(?:must|should)\s+"#
                + #"(?:contain|include|have)\s+(?:at\s+least\s+)?\d+\s+"#
                + #"(?:characters|chars|letters|digits|symbols)[.!]?\s*$"#,
            #"^\s*(?:the\s+)?passwords?\s+(?:is|are|should\s+be|must\s+be)\s+"#
                + #"(?:at\s+least\s+)?\d+\s+(?:characters|letters|digits|symbols)"#
                + #"[.!]?\s*$"#,
            #"^\s*"# + englishOwner + englishCredential + englishCredentialScope
                + #"\s+(?:is|are|should\s+be|must\s+be|will\s+be)\s+"#
                + #"(?:rotated|refreshed|replaced)\s+every\s+\d+\s+"#
                + #"(?:hours?|days?|weeks?|months?)[.!]?\s*$"#,
            #"^\s*(?:implement|design|build|test|review|fix|update|document|support)"#
                + #"\s+(?:the\s+)?"# + englishCredential + #"\s+"# + englishTopic
                + #"(?:\s+(?:screen|flow|policy|process|support|handling|view|interface|workflow|feature|test|tests)){0,2}[.!]?\s*$"#,
            #"^\s*(?:store|save)\s+(?:the\s+)?"# + englishCredential
                + #"\s+(?:in|with)\s+(?:keychain|secret\s+manager|secure\s+storage)[.!]?\s*$"#,
            #"^\s*(?:rotate|refresh|revoke|replace|generate|delete)\s+(?:the\s+)?"#
                + englishCredential
                + #"(?:\s+every\s+\d+\s+(?:hours?|days?|weeks?|months?))?[.!]?\s*$"#,
            #"^\s*"# + japaneseCredential + #"\s*(?:は|が)\s*"#
                + japaneseState + #"(?:です|である|となる)?[。！!]?\s*$"#,
            #"^\s*"# + japaneseCredential + #"\s*(?:は|が)\s*\d+\s*文字以上[。！!]?\s*$"#,
            #"^\s*[PpＰｐ][IiＩｉ][NnＮｎ]\s*コード\s*(?:は|が)\s*"#
                + japaneseState + #"(?:です|である|となる)?[。！!]?\s*$"#,
            #"^\s*"# + japaneseCredential + #"\s*(?:は|が)\s*"#
                + #"(?:必要|必須)(?:です)?(?:か|でしょうか)[？?]\s*$"#,
            #"^\s*"# + japaneseCredential
                + #"\s*(?:の\s*)?(?:再設定|ローテーション|管理|保存|暗号化|更新|認証|検証)"#
                + #"\s*(?:が|は)?\s*"# + japaneseState
                + #"(?:です|である|となる)?[。！!]?\s*$"#,
            #"^\s*"# + japaneseCredential + #"\s*(?:を|の)?\s*"#
                + #"(?:再設定|ローテーション|管理|保存|暗号化|更新|認証|検証)"#
                + #"(?:画面|フロー|ポリシー|処理|機能|対応)?\s*(?:を)?\s*"#
                + #"(?:実装|設計|構築|テスト|レビュー|修正|更新|文書化|確認)?"#
                + #"(?:する|します|してください|が必要)?[。！!]?\s*$"#,
        ]
        if safeRequirementPatterns.contains(where: {
            value.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            return false
        }

        // Task Context is durable. Once a credential assignment is recognized,
        // fail closed unless the entire sentence is a value-free requirement.
        return true
    }
}
