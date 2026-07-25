import CryptoKit
import Foundation

public enum ConversationResolvedTarget: Equatable, Hashable, Sendable {
    case task(id: Int64, projectID: Int64?)
    case project(id: Int64)
}

public enum ConversationReferenceCandidateAvailability: Equatable, Hashable, Sendable {
    case available
    case deleted
    case stale
}

public struct ConversationReferenceCandidate: Equatable, Sendable {
    public let target: ConversationResolvedTarget
    public let title: String
    /// Stable, caller-defined ordering identity. The resolver preserves the
    /// presented order for ordinal references, but rejects lists that do not
    /// carry a stable key for every candidate.
    public let stableSortKey: String
    public let availability: ConversationReferenceCandidateAvailability

    public init(
        target: ConversationResolvedTarget,
        title: String,
        stableSortKey: String,
        availability: ConversationReferenceCandidateAvailability = .available
    ) {
        self.target = target
        self.title = title
        self.stableSortKey = stableSortKey
        self.availability = availability
    }
}

public enum VoiceTaskReferenceResolutionReason: Equatable, Hashable, Sendable {
    case explicitIdentifier
    case selectedTask
    case selectedProject
    case previousActionLink
    case stableOrdinal
    case uniqueCandidate
    case confirmedFact
}

public enum VoiceTaskReferenceUnavailableReason: Equatable, Sendable {
    case deletedTarget(ConversationResolvedTarget)
    case staleTarget(ConversationResolvedTarget)
    case expiredReference
    case staleReference
    case invalidCandidateOrdering
    case unsupportedReferenceTarget
}

public enum VoiceTaskReferenceResolution: Equatable, Sendable {
    case resolved(
        ConversationResolvedTarget,
        reason: VoiceTaskReferenceResolutionReason
    )
    case needsClarification([ConversationReferenceCandidate])
    case unavailable(VoiceTaskReferenceUnavailableReason)
}

public struct VoiceTaskReferenceRequest: Equatable, Sendable {
    public let sessionID: UUID
    public let utterance: String
    public let explicitTarget: ConversationResolvedTarget?
    public let selectedTask: ConversationResolvedTarget?
    public let selectedProject: ConversationResolvedTarget?
    public let previousActionLink: ConversationActionLink?
    public let ordinalReference: ConversationReference?
    public let candidateOrderingFingerprint: String?
    public let candidates: [ConversationReferenceCandidate]
    public let confirmedFacts: [TaskContextFact]

    public init(
        sessionID: UUID,
        utterance: String,
        explicitTarget: ConversationResolvedTarget? = nil,
        selectedTask: ConversationResolvedTarget? = nil,
        selectedProject: ConversationResolvedTarget? = nil,
        previousActionLink: ConversationActionLink? = nil,
        ordinalReference: ConversationReference? = nil,
        candidateOrderingFingerprint: String? = nil,
        candidates: [ConversationReferenceCandidate] = [],
        confirmedFacts: [TaskContextFact] = []
    ) {
        self.sessionID = sessionID
        self.utterance = utterance
        self.explicitTarget = explicitTarget
        self.selectedTask = selectedTask
        self.selectedProject = selectedProject
        self.previousActionLink = previousActionLink
        self.ordinalReference = ordinalReference
        self.candidateOrderingFingerprint = candidateOrderingFingerprint
        self.candidates = candidates
        self.confirmedFacts = confirmedFacts
    }
}

public struct VoiceTaskReferenceResolver: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public static func orderingFingerprint(
        for candidates: [ConversationReferenceCandidate]
    ) -> String {
        let canonicalCandidates = candidates.map { candidate in
            let target: String
            switch candidate.target {
            case .task(let id, let projectID):
                target = "task:\(id):project:\(projectID.map(String.init) ?? "none")"
            case .project(let id):
                target = "project:\(id)"
            }
            let key = candidate.stableSortKey
            return "\(target.utf8.count):\(target)|\(key.utf8.count):\(key)"
        }
        let canonicalList = canonicalCandidates
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        // Swift's `Hasher` is intentionally randomized per process. A SHA-256
        // digest keeps persisted ordinal evidence reproducible across launches.
        let digest = SHA256.hash(data: Data(canonicalList.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "sha256:\(digest)"
    }

    public func resolve(_ request: VoiceTaskReferenceRequest) -> VoiceTaskReferenceResolution {
        var stableKeys = Set<String>()
        var targetKeys = Set<String>()
        guard request.candidates.allSatisfy({ candidate in
            let stableKey = candidate.stableSortKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !stableKey.isEmpty
                && candidate.target.hasValidIdentifier
                && stableKeys.insert(stableKey).inserted
                && targetKeys.insert(candidate.target.stableIdentityKey).inserted
        }) else {
            return .unavailable(.invalidCandidateOrdering)
        }
        if let candidateOrderingFingerprint = request.candidateOrderingFingerprint {
            guard candidateOrderingFingerprint
                == Self.orderingFingerprint(for: request.candidates)
            else {
                return .unavailable(.invalidCandidateOrdering)
            }
        }
        guard request.selectedTask?.isTask ?? true,
              request.selectedProject?.isProject ?? true
        else {
            return .unavailable(.unsupportedReferenceTarget)
        }

        if let explicitTarget = request.explicitTarget {
            return resolveKnownTarget(
                explicitTarget,
                reason: .explicitIdentifier,
                candidates: request.candidates
            )
        }

        let normalizedUtterance = normalize(request.utterance)
        let requestedTargetKind = requestedTargetKind(in: normalizedUtterance)
        let isAnaphoric = isAnaphoricReference(normalizedUtterance)
        // The noun identifies the target kind even when a modifier separates
        // the demonstrative from it ("this old project").
        let isProjectContainerClause = mentionsProjectContainerClause(
            normalizedUtterance
        )
        // Bind ordinals to the requested leaf kind. This keeps "first task"
        // authoritative in "... from this project", while ignoring "first
        // project" when a pronoun is the actual mutation target.
        let ordinal = ordinalIndex(
            in: normalizedUtterance,
            targetKind: requestedTargetKind,
            isProjectContainerClause: isProjectContainerClause
        )
        let isProjectReference = !isProjectContainerClause
            && (
                mentionsProjectReference(normalizedUtterance)
                    || (requestedTargetKind == .project && isAnaphoric)
            )
        let isRecentActionReference = mentionsRecentAction(normalizedUtterance)
        let allLexicalNamedCandidateMatches = request.candidates.filter {
            isStrongNamedCandidate($0, in: normalizedUtterance)
        }
        let explicitDirectTargetKind = explicitDirectTargetKind(
            in: normalizedUtterance,
            candidates: allLexicalNamedCandidateMatches
        )
        let lexicalNamedCandidateMatches = allLexicalNamedCandidateMatches.filter {
            requestedTargetKind.matches($0.target)
        }
        let broadNamedCandidateMatches = isProjectContainerClause
            ? lexicalNamedCandidateMatches.filter { !$0.target.isProject }
            : lexicalNamedCandidateMatches
        let namedCandidateMatches = isAnaphoric
            ? broadNamedCandidateMatches.filter {
                isDirectNamedCommand($0, in: normalizedUtterance)
            }
            : broadNamedCandidateMatches
        let directNamedCandidateMatches = allLexicalNamedCandidateMatches.filter {
            isDirectNamedCommand($0, in: normalizedUtterance)
                && (explicitDirectTargetKind?.matches($0.target) ?? true)
        }

        // A direct command object is the strongest lexical evidence. Resolve it
        // before conversational-reference parsing so legitimate names such as
        // "First task" and "Task we just added" are not treated as ordinal or
        // recent-action references.
        if directNamedCandidateMatches.count == 1,
           let candidate = directNamedCandidateMatches.first
        {
            return resolveCandidate(candidate, reason: .uniqueCandidate)
        }
        if directNamedCandidateMatches.count > 1 {
            return .needsClarification(directNamedCandidateMatches)
        }

        // A full candidate name is stronger evidence than incidental lexical
        // overlap, provided the utterance does not explicitly request a
        // conversational reference.
        if ordinal == nil,
           !isRecentActionReference,
           namedCandidateMatches.count == 1,
           let candidate = namedCandidateMatches.first
        {
            return resolveCandidate(candidate, reason: .uniqueCandidate)
        }
        if ordinal == nil,
           !isRecentActionReference,
           namedCandidateMatches.count > 1
        {
            return .needsClarification(namedCandidateMatches)
        }

        if ordinal == nil,
           isProjectReference,
           !isRecentActionReference,
           requestedTargetKind != .task
        {
            if let selectedProject = request.selectedProject {
                return resolveKnownTarget(
                    selectedProject,
                    reason: .selectedProject,
                    candidates: request.candidates
                )
            }
            // An explicit project qualifier must never fall through to a Task
            // selection or Task-only Action Link.
            return .needsClarification(
                request.candidates.filter(\.target.isProject)
            )
        }

        // A spoken ordinal or explicit recent-action phrase has its own stable
        // evidence. It must not be silently redirected to the current selection.
        if ordinal == nil, !isRecentActionReference {
            if isAnaphoric, let selectedTask = request.selectedTask {
                guard requestedTargetKind.matches(selectedTask) else {
                    return .needsClarification(
                        request.candidates.filter {
                            requestedTargetKind.matches($0.target)
                        }
                    )
                }
                return resolveKnownTarget(
                    selectedTask,
                    reason: .selectedTask,
                    candidates: request.candidates
                )
            }
        }

        if isRecentActionReference || (isAnaphoric && request.selectedTask == nil),
           let previousActionLink = request.previousActionLink,
           let taskID = previousActionLink.taskID
        {
            guard previousActionLink.sessionID == request.sessionID else {
                return .unavailable(.staleReference)
            }
            guard let candidate = request.candidates.first(where: {
                $0.target.taskID == taskID
            }) else {
                return .unavailable(.staleTarget(.task(id: taskID, projectID: nil)))
            }
            guard requestedTargetKind.matches(candidate.target) else {
                return .needsClarification(
                    request.candidates.filter {
                        requestedTargetKind.matches($0.target)
                    }
                )
            }
            // "Just created" is stronger than a generic previous-action
            // reference and must be backed by creation-specific evidence.
            guard !isRecentActionReference
                || previousActionLink.operation == .taskCreated
            else {
                return .needsClarification(
                    request.candidates.filter {
                        requestedTargetKind.matches($0.target)
                    }
                )
            }
            return resolveCandidate(candidate, reason: .previousActionLink)
        }

        if isRecentActionReference {
            // "Just created" claims require an Action Link. Falling through
            // to a selected task or remembered fact could redirect a
            // destructive command to an unrelated target.
            return .needsClarification(
                request.candidates.filter {
                    requestedTargetKind.matches($0.target)
                }
            )
        }

        if let ordinal {
            return resolveOrdinal(
                ordinal,
                targetKind: requestedTargetKind,
                request: request
            )
        }

        if isAnaphoric {
            let factCandidates = confirmedFactCandidates(
                for: request,
                targetKind: requestedTargetKind
            )
            if factCandidates.count == 1, let candidate = factCandidates.first {
                return resolveCandidate(candidate, reason: .confirmedFact)
            }
            if factCandidates.count > 1 {
                return .needsClarification(factCandidates)
            }
        }

        let fallbackCandidates = isProjectContainerClause
            ? request.candidates.filter { !$0.target.isProject }
            : request.candidates
        return .needsClarification(fallbackCandidates)
    }

    private func resolveOrdinal(
        _ ordinal: Int,
        targetKind: RequestedTargetKind,
        request: VoiceTaskReferenceRequest
    ) -> VoiceTaskReferenceResolution {
        guard let reference = request.ordinalReference else {
            return .needsClarification(request.candidates)
        }
        guard reference.sessionID == request.sessionID else {
            return .unavailable(.staleReference)
        }
        guard now() < reference.expiresAt else {
            return .unavailable(.expiredReference)
        }
        guard reference.target.isResolvableTaskOrProject else {
            return .unavailable(.unsupportedReferenceTarget)
        }
        guard ordinal == reference.ordinal,
              request.candidateOrderingFingerprint == reference.orderingFingerprint,
              request.candidates.indices.contains(ordinal)
        else {
            return .needsClarification(request.candidates)
        }

        let candidate = request.candidates[ordinal]
        guard targetKind.matches(candidate.target) else {
            return .needsClarification(
                request.candidates.filter {
                    targetKind.matches($0.target)
                }
            )
        }
        guard candidate.target.matches(reference.target) else {
            return .needsClarification(request.candidates)
        }
        return resolveCandidate(candidate, reason: .stableOrdinal)
    }

    private func resolveKnownTarget(
        _ target: ConversationResolvedTarget,
        reason: VoiceTaskReferenceResolutionReason,
        candidates: [ConversationReferenceCandidate]
    ) -> VoiceTaskReferenceResolution {
        guard let candidate = candidates.first(where: {
            $0.target.sameStableIdentity(as: target)
        }) else {
            return .unavailable(.staleTarget(target))
        }
        return resolveCandidate(candidate, reason: reason)
    }

    private func resolveCandidate(
        _ candidate: ConversationReferenceCandidate,
        reason: VoiceTaskReferenceResolutionReason
    ) -> VoiceTaskReferenceResolution {
        switch candidate.availability {
        case .available:
            return .resolved(candidate.target, reason: reason)
        case .deleted:
            return .unavailable(.deletedTarget(candidate.target))
        case .stale:
            return .unavailable(.staleTarget(candidate.target))
        }
    }

    private func confirmedFactCandidates(
        for request: VoiceTaskReferenceRequest,
        targetKind: RequestedTargetKind
    ) -> [ConversationReferenceCandidate] {
        var result: [ConversationReferenceCandidate] = []
        let sessionFacts = request.confirmedFacts.filter {
            $0.sessionID == request.sessionID
        }
        do {
            try TaskContextFact.validateSupersessionGraph(sessionFacts)
        } catch {
            return []
        }
        let supersededFactIDs = Set(
            sessionFacts
                .filter {
                    $0.state == .confirmed || $0.state == .retracted
                }
                .compactMap(\.supersedesFactID)
        )

        for fact in sessionFacts
            where fact.state == .confirmed && !supersededFactIDs.contains(fact.id)
        {
            let matches: [ConversationReferenceCandidate]
            switch fact.scope {
            case .session:
                continue
            case .project(let projectID):
                matches = request.candidates.filter {
                    $0.target.projectID == projectID && $0.target.isProject
                }
            case .task(let taskID):
                matches = request.candidates.filter {
                    $0.target.taskID == taskID
                }
            }

            for candidate in matches
                where targetKind.matches(candidate.target)
                    && !result.contains(candidate)
            {
                result.append(candidate)
            }
        }

        return result
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isStrongNamedCandidate(
        _ candidate: ConversationReferenceCandidate,
        in normalizedUtterance: String
    ) -> Bool {
        let normalizedTitle = normalize(candidate.title)
        guard !normalizedTitle.isEmpty,
              !Self.genericReferenceTitles.contains(normalizedTitle)
        else {
            return false
        }
        if normalizedUtterance == normalizedTitle {
            return true
        }

        if normalizedTitle.unicodeScalars.allSatisfy(\.isASCII) {
            let escapedTitle = NSRegularExpression.escapedPattern(
                for: normalizedTitle
            )
            // Phrase boundaries prevent short titles such as "App" from
            // resolving inside unrelated words such as "apply". Japanese
            // command particles remain valid boundaries for mixed-language
            // utterances such as "Releaseを削除して".
            return matches(
                #"(?<![\p{L}\p{N}_])\#(escapedTitle)(?=$|[\sをにのはがへでと、。！？]|[^\p{L}\p{N}_])"#,
                in: normalizedUtterance
            )
        }

        // Japanese titles generally have no whitespace token boundary. A
        // command particle supplies the trailing boundary for every title
        // length, preventing matches inside longer compounds such as
        // "会議室" in "会議室予約".
        let escapedTitle = NSRegularExpression.escapedPattern(
            for: normalizedTitle
        )
        return matches(
            #"(?<![\p{L}\p{N}_])\#(escapedTitle)(?=$|[\sをにのはがへでと、。！？])"#,
            in: normalizedUtterance
        )
    }

    private func isDirectNamedCommand(
        _ candidate: ConversationReferenceCandidate,
        in normalizedUtterance: String
    ) -> Bool {
        let normalizedTitle = normalize(candidate.title)
        if normalizedUtterance == normalizedTitle {
            return true
        }
        let escapedTitle = NSRegularExpression.escapedPattern(
            for: normalizedTitle
        )
        // Contextual pronouns outrank incidental words. A title containing
        // "this"/"that" remains usable when it begins the direct command
        // object. The boundary permits only a complete command, a bounded
        // subordinate clause, or container metadata. This preserves
        // "delete Release because that task..." without treating the
        // incidental Release in "delete this task after Release" as a target.
        return matches(
            #"^\#(Self.englishPoliteCommandPrefixPattern)\#(Self.englishTargetOperationPattern)\s+(?:(?:the\s+)?(?:task|project)\s+)?\#(escapedTitle)(?=(?:\s+please)?$|[,;:]?\s+(?:because|since|as|so\s+that|after|before|when|while|if|in|within|under|to|into|from)\b)"#,
            in: normalizedUtterance
        )
    }

    private func explicitDirectTargetKind(
        in normalizedUtterance: String,
        candidates: [ConversationReferenceCandidate]
    ) -> RequestedTargetKind? {
        // Treat a leading kind word as a qualifier only when the remaining
        // direct object is itself a candidate title. Otherwise names such as
        // "Task Force" must remain whole instead of being parsed as
        // "task" + "Force".
        for (noun, kind) in [
            ("task", RequestedTargetKind.task),
            ("project", RequestedTargetKind.project),
        ] {
            if candidates.contains(where: {
                isDirectQualifiedNamedCommand(
                    $0,
                    noun: noun,
                    in: normalizedUtterance
                )
            }) {
                return kind
            }
        }
        return nil
    }

    private func isDirectQualifiedNamedCommand(
        _ candidate: ConversationReferenceCandidate,
        noun: String,
        in normalizedUtterance: String
    ) -> Bool {
        let escapedTitle = NSRegularExpression.escapedPattern(
            for: normalize(candidate.title)
        )
        return matches(
            #"^\#(Self.englishPoliteCommandPrefixPattern)\#(Self.englishTargetOperationPattern)\s+(?:the\s+)?\#(noun)\s+\#(escapedTitle)(?=(?:\s+please)?$|[,;:]?\s+(?:because|since|as|so\s+that|after|before|when|while|if|in|within|under|to|into|from)\b)"#,
            in: normalizedUtterance
        )
    }

    // These fragments are shared by all English target-position checks so
    // politeness variants and supported operations cannot drift apart.
    private static let englishPoliteCommandPrefixPattern =
        #"(?:(?:please|(?:could|can|would)\s+you(?:\s+please)?)\s+)?"#
    private static let englishTargetOperationPattern =
        #"(?:open|show|delete|complete|finish|update|rename|move|archive)"#

    private static let genericReferenceTitles: Set<String> = [
        "it",
        "one",
        "item",
        "thing",
        "that",
        "this",
        "this one",
        "that one",
        "this task",
        "that task",
        "this project",
        "that project",
        "current",
        "current one",
        "current item",
        "current thing",
        "current task",
        "current project",
        "the current task",
        "the current project",
        "task",
        "project",
        "これ",
        "それ",
        "あれ",
        "タスク",
        "プロジェクト",
        "案件",
    ]

    private func ordinalIndex(
        in normalizedUtterance: String,
        targetKind: RequestedTargetKind,
        isProjectContainerClause: Bool
    ) -> Int? {
        let englishOrdinals: [(String, Int)] = [
            ("first", 0),
            ("second", 1),
            ("third", 2),
            ("fourth", 3),
            ("fifth", 4),
            ("sixth", 5),
            ("seventh", 6),
            ("eighth", 7),
            ("ninth", 8),
            ("tenth", 9),
        ]
        if let exact = englishOrdinals.first(where: {
            normalizedUtterance == $0.0
        }) {
            return exact.1
        }

        let targetNounPattern: String
        switch targetKind {
        case .task:
            targetNounPattern = #"(?:one|task|item)"#
        case .project:
            targetNounPattern = #"project"#
        case .any:
            // A project noun in a container clause is metadata about the
            // direct object, not the object selected by the ordinal.
            targetNounPattern = isProjectContainerClause
                ? #"(?:one|task|item)"#
                : #"(?:one|task|item|project)"#
        }

        let locatedOrdinals = englishOrdinals.compactMap {
            ordinal -> (location: Int, ordinal: Int)? in
            guard let expression = try? NSRegularExpression(
                pattern: #"^\#(Self.englishPoliteCommandPrefixPattern)(?:\#(Self.englishTargetOperationPattern)\s+)?(?:the\s+)?\#(NSRegularExpression.escapedPattern(for: ordinal.0))\s+\#(targetNounPattern)\b"#
            ),
            let match = expression.firstMatch(
                in: normalizedUtterance,
                range: NSRange(
                    normalizedUtterance.startIndex...,
                    in: normalizedUtterance
                )
            )
            else {
                return nil
            }
            return (match.range.location, ordinal.1)
        }
        if let firstMention = locatedOrdinals.min(by: {
            $0.location < $1.location
        }) {
            return firstMention.ordinal
        }

        if let oneBased = firstPositiveIntegerCapture(
            #"^\#(Self.englishPoliteCommandPrefixPattern)(?:\#(Self.englishTargetOperationPattern)\s+)?(?:the\s+)?([0-9]+)(?:st|nd|rd|th)\s+\#(targetNounPattern)\b"#,
            in: normalizedUtterance
        ) {
            return oneBased - 1
        }

        let canUseUnqualifiedNumericOrdinal =
            targetKind != .any || !isProjectContainerClause
        guard canUseUnqualifiedNumericOrdinal else {
            return nil
        }
        for pattern in [
            #"^([0-9]+)\s*(?:つ目|番目)"#,
            #"^([0-9]+)(?:st|nd|rd|th)$"#,
        ] {
            if let oneBased = firstPositiveIntegerCapture(
                pattern,
                in: normalizedUtterance
            ) {
                return oneBased - 1
            }
        }
        return nil
    }

    private func requestedTargetKind(
        in normalizedUtterance: String
    ) -> RequestedTargetKind {
        // An explicit direct-object qualifier is stronger than a noun that
        // merely appears inside the target's title ("project Task Force").
        if matches(
            #"^\#(Self.englishPoliteCommandPrefixPattern)(?:\#(Self.englishTargetOperationPattern)\s+(?:the\s+)?)?(?:the\s+)?(?:(?:this|that|current)(?:\s+(?!(?:we|i|you|they|he|she|it|the|a|an|so|which|who|to|for|because)\b)[\p{L}\p{N}_-]+){0,3}\s+)?project\b"#,
            in: normalizedUtterance
        ) {
            return .project
        }
        // A task may legitimately be qualified by its containing project
        // ("second task in project Alpha"), so the leaf target wins.
        if matches(#"\btask\b"#, in: normalizedUtterance)
            || normalizedUtterance.contains("タスク")
        {
            return .task
        }
        // A trailing containment or destination clause describes where the
        // direct object lives or moves; it does not turn that object into a
        // project.
        if mentionsProjectContainerClause(normalizedUtterance) {
            return .any
        }
        if matches(#"\bproject\b"#, in: normalizedUtterance)
            || normalizedUtterance.contains("プロジェクト")
            || normalizedUtterance.contains("案件")
        {
            return .project
        }
        return .any
    }

    private func isAnaphoricReference(_ value: String) -> Bool {
        isJapaneseAnaphor("これ", in: value)
            || isJapaneseAnaphor("それ", in: value)
            || isJapaneseAnaphor("あれ", in: value)
            // Japanese demonstratives attach directly to the target noun.
            // Treating them as selection evidence prevents an unrelated
            // confirmed fact from silently winning the fallback chain.
            || value.contains("このタスク")
            || value.contains("そのタスク")
            || value.contains("あのタスク")
            || matches(#"\bcurrent\s+task\b"#, in: value)
            // English "it" is only selection evidence when it is the direct
            // object of a supported target operation, not wherever it appears.
            || matches(
                #"\b\#(Self.englishTargetOperationPattern)\s+it\b"#,
                in: value
            )
            // Bare "that"/"this" inside relative clauses or due-date phrases
            // is not target evidence. A target noun, "one", or object position
            // at the end of the utterance is required.
            || matches(
                #"\b(?:this|that)\s+(?:task|project|one|item|thing)\b"#,
                in: value
            )
            || matches(#"\b(?:this|that)\b$"#, in: value)
    }

    private func mentionsProjectReference(_ value: String) -> Bool {
        // Anchor English project anaphors to the command object. Without this,
        // a subordinate clause such as "so that we unblock the project" can
        // turn a preceding task command into a project mutation.
        matches(
            #"^\#(Self.englishPoliteCommandPrefixPattern)(?:\#(Self.englishTargetOperationPattern)\s+(?:the\s+)?)?(?:the\s+)?(?:this|that|current)(?:\s+(?!(?:we|i|you|they|he|she|it|the|a|an|so|which|who|to|for|because)\b)[\p{L}\p{N}_-]+){0,3}\s+project\b"#,
            in: value
        )
            || value.contains("このプロジェクト")
            || value.contains("そのプロジェクト")
            || value.contains("あのプロジェクト")
            || value.contains("この案件")
            || value.contains("その案件")
            || value.contains("あの案件")
    }

    private func mentionsProjectContainerClause(_ value: String) -> Bool {
        // English project names may appear on either side of the noun
        // ("project Alpha" / "the Alpha project"). Both forms describe the
        // selected task's container or destination, not a new action target.
        matches(
            #"\b(?:in|within|under|to|into|from)\s+(?:(?:this|that|the|current)\s+)?(?:project\b|[\p{L}\p{N}_-]+(?:\s+[\p{L}\p{N}_-]+){0,3}\s+project\b)"#,
            in: value
        ) || matches(
            #"(?:プロジェクト|案件)(?:へ|に)(?:移動|動か)"#,
            in: value
        ) || matches(
            #"(?:プロジェクト|案件)(?:から|内(?:の|で)?|にある|の中(?:から|の|で)?)(?:これ|それ|あれ|(?:この|その|あの)?(?:タスク|もの))(?:を|に|は|が|へ)?"#,
            in: value
        )
    }

    private func mentionsRecentAction(_ value: String) -> Bool {
        // The creation verb must belong to the clause introduced by さっき.
        // It must also modify a task-like referent; creation of a memo or
        // another nested object must not steal the selected task.
        let isJapaneseCreatedReference = matches(
            #"^さっき\s*(?:(?:追加|作成)\s*した|作った|(?:added|created)\s*した)\s*(?:(?:この|その|あの)?(?:もの|タスク|プロジェクト|案件)|\b(?:task|project|one|item|thing)\b)"#,
            in: value
        )
        return isJapaneseCreatedReference
            || matches(
                #"^\#(Self.englishPoliteCommandPrefixPattern)(?:\#(Self.englishTargetOperationPattern)\s+)?(?:the\s+)?(?:task|one|item|thing|what)\s+(?:that\s+)?(?:(?:we|i)\s+)?just\s+(?:added|created)\b"#,
                in: value
            )
    }

    private func isJapaneseAnaphor(_ anaphor: String, in value: String) -> Bool {
        if value == anaphor {
            return true
        }
        return ["を", "に", "の", "は", "が", "へ"].contains {
            value.contains(anaphor + $0)
        }
    }

    private func matches(_ pattern: String, in value: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        return expression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) != nil
    }

    private func firstPositiveIntegerCapture(
        _ pattern: String,
        in value: String
    ) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: value,
                  range: NSRange(value.startIndex..., in: value)
              ),
              let numberRange = Range(match.range(at: 1), in: value),
              let number = Int(value[numberRange]),
              number > 0
        else {
            return nil
        }
        return number
    }
}

private enum RequestedTargetKind: Equatable {
    case any
    case task
    case project

    func matches(_ target: ConversationResolvedTarget) -> Bool {
        switch self {
        case .any:
            true
        case .task:
            target.isTask
        case .project:
            target.isProject
        }
    }
}

private extension ConversationResolvedTarget {
    var stableIdentityKey: String {
        switch self {
        case .task(let id, _):
            "task:\(id)"
        case .project(let id):
            "project:\(id)"
        }
    }

    var hasValidIdentifier: Bool {
        switch self {
        case .task(let id, let projectID):
            id > 0 && (projectID.map { $0 > 0 } ?? true)
        case .project(let id):
            id > 0
        }
    }

    var taskID: Int64? {
        guard case .task(let id, _) = self else {
            return nil
        }
        return id
    }

    var projectID: Int64? {
        switch self {
        case .task(_, let projectID):
            projectID
        case .project(let id):
            id
        }
    }

    var isProject: Bool {
        guard case .project = self else {
            return false
        }
        return true
    }

    var isTask: Bool {
        guard case .task = self else {
            return false
        }
        return true
    }

    func sameStableIdentity(as other: ConversationResolvedTarget) -> Bool {
        switch (self, other) {
        case (.task(let lhsID, _), .task(let rhsID, _)):
            lhsID == rhsID
        case (.project(let lhsID), .project(let rhsID)):
            lhsID == rhsID
        default:
            false
        }
    }

    func matches(_ stableTarget: ConversationStableTargetID) -> Bool {
        switch (self, stableTarget) {
        case (.task(let id, _), .task(let stableID)):
            id == stableID
        case (.project(let id), .project(let stableID)):
            id == stableID
        default:
            false
        }
    }
}

private extension ConversationStableTargetID {
    var isResolvableTaskOrProject: Bool {
        switch self {
        case .project, .task:
            true
        case .actionPlan, .assistantQueueItem, .executionReceipt:
            false
        }
    }
}
