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
        if !request.candidates.isEmpty {
            guard request.candidateOrderingFingerprint
                == Self.orderingFingerprint(for: request.candidates)
            else {
                return .unavailable(.invalidCandidateOrdering)
            }
        }

        if let explicitTarget = request.explicitTarget {
            return resolveKnownTarget(
                explicitTarget,
                reason: .explicitIdentifier,
                candidates: request.candidates
            )
        }

        let normalizedUtterance = normalize(request.utterance)
        let ordinal = ordinalIndex(in: normalizedUtterance)
        let isAnaphoric = isAnaphoricReference(normalizedUtterance)
        let isProjectReference = mentionsProjectReference(normalizedUtterance)
        let isRecentActionReference = mentionsRecentAction(normalizedUtterance)

        // A spoken ordinal or explicit recent-action phrase has its own stable
        // evidence. It must not be silently redirected to the current selection.
        if ordinal == nil, !isRecentActionReference {
            if isProjectReference, let selectedProject = request.selectedProject {
                return resolveKnownTarget(
                    selectedProject,
                    reason: .selectedProject,
                    candidates: request.candidates
                )
            }
            if isAnaphoric, let selectedTask = request.selectedTask {
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
            return resolveCandidate(candidate, reason: .previousActionLink)
        }

        if let ordinal {
            return resolveOrdinal(
                ordinal,
                request: request
            )
        }

        let titleMatches = request.candidates.filter {
            let normalizedTitle = normalize($0.title)
            return !normalizedTitle.isEmpty
                && (normalizedUtterance == normalizedTitle
                    || (normalizedTitle.count >= 3
                        && normalizedUtterance.contains(normalizedTitle)))
        }
        if titleMatches.count == 1, let candidate = titleMatches.first {
            return resolveCandidate(candidate, reason: .uniqueCandidate)
        }
        if titleMatches.count > 1 {
            return .needsClarification(titleMatches)
        }

        let factCandidates = confirmedFactCandidates(for: request)
        if factCandidates.count == 1, let candidate = factCandidates.first {
            return resolveCandidate(candidate, reason: .confirmedFact)
        }
        if factCandidates.count > 1 {
            return .needsClarification(factCandidates)
        }

        return .needsClarification(request.candidates)
    }

    private func resolveOrdinal(
        _ ordinal: Int,
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
        for request: VoiceTaskReferenceRequest
    ) -> [ConversationReferenceCandidate] {
        var result: [ConversationReferenceCandidate] = []

        for fact in request.confirmedFacts
            where fact.sessionID == request.sessionID && fact.state == .confirmed
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

            for candidate in matches where !result.contains(candidate) {
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

    private func ordinalIndex(in normalizedUtterance: String) -> Int? {
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
        if let ordinal = englishOrdinals.first(where: {
            normalizedUtterance == $0.0
                || matches(
                    #"\b\#(NSRegularExpression.escapedPattern(for: $0.0))\s+(?:one|task|item)\b"#,
                    in: normalizedUtterance
                )
        }) {
            return ordinal.1
        }

        for pattern in [
            #"([0-9]+)\s*(?:つ目|番目)"#,
            #"\b([0-9]+)(?:st|nd|rd|th)\s+(?:one|task|item)\b"#,
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

    private func isAnaphoricReference(_ value: String) -> Bool {
        isJapaneseAnaphor("それ", in: value)
            || isJapaneseAnaphor("あれ", in: value)
            || matches(#"\b(?:that|this one|that one)\b"#, in: value)
    }

    private func mentionsProjectReference(_ value: String) -> Bool {
        matches(#"\b(?:this|that|current)\s+project\b"#, in: value)
            || value.contains("このプロジェクト")
            || value.contains("そのプロジェクト")
            || value.contains("あのプロジェクト")
            || value.contains("この案件")
            || value.contains("その案件")
            || value.contains("あの案件")
    }

    private func mentionsRecentAction(_ value: String) -> Bool {
        value.contains("さっき")
            || matches(
                #"\b(?:task|one|item|thing|what)\s+(?:we\s+)?just\s+(?:added|created)\b"#,
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
