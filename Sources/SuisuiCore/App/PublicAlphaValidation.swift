import CryptoKit
import Foundation

/// Errors raised while constructing the privacy-preserving Public Alpha
/// validation contract. The contract intentionally has no free-form payload.
public enum PublicAlphaValidationError: Error, Equatable, Sendable {
    case emptyParticipantSeed
    case invalidParticipantDigest
    case invalidAppVersion
    case invalidSourceCommit
    case invalidStageMetadata
    case invalidCount(String)
    case invalidRate(String)
    case invalidSnapshot
}

private func totalPublicAlphaCounts(_ counts: [Int]) throws -> Int {
    try counts.reduce(0) { total, count in
        let (sum, overflow) = total.addingReportingOverflow(count)
        guard count >= 0, !overflow else {
            throw PublicAlphaValidationError.invalidCount("aggregate")
        }
        return sum
    }
}

public struct PublicAlphaParticipantID: Codable, Equatable, Hashable, Sendable {
    public let digest: String

    public init(digest: String) throws {
        let normalized = digest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.range(of: #"^sha256:[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw PublicAlphaValidationError.invalidParticipantDigest
        }
        self.digest = normalized
    }

    /// Hashes an operator-provided seed immediately; the seed is never stored
    /// in the validation record or returned by this initializer.
    public init(seed: String) throws {
        guard !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PublicAlphaValidationError.emptyParticipantSeed
        }
        let digest = SHA256.hash(data: Data(seed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        self.digest = "sha256:\(digest)"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(digest: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(digest)
    }

    public var redactedValue: String { digest }
}

public struct PublicAlphaBuildIdentity: Codable, Equatable, Hashable, Sendable {
    public let appVersion: String
    public let sourceCommit: String

    public init(appVersion: String, sourceCommit: String) throws {
        let normalizedVersion = appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCommit = sourceCommit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedVersion.range(of: #"^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$"#, options: .regularExpression) != nil else {
            throw PublicAlphaValidationError.invalidAppVersion
        }
        guard normalizedCommit.range(of: #"^[a-f0-9]{7,64}$"#, options: .regularExpression) != nil else {
            throw PublicAlphaValidationError.invalidSourceCommit
        }
        self.appVersion = normalizedVersion
        self.sourceCommit = normalizedCommit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            appVersion: container.decode(String.self, forKey: .appVersion),
            sourceCommit: container.decode(String.self, forKey: .sourceCommit)
        )
    }
}

public enum PublicAlphaPersonaFlag: String, Codable, CaseIterable, Hashable, Sendable {
    case individualContractor = "individual_contractor"
    case smallWebAppStudio = "small_web_app_studio"
    case multiClientSoloBusiness = "multi_client_solo_business"
    case macPrimary = "mac_primary"
    case outOfCohort = "out_of_cohort"
}

public enum PublicAlphaStage: String, Codable, CaseIterable, Hashable, Sendable {
    case signedInstall = "signed_notarized_install"
    case firstLaunch = "first_launch"
    case readinessComplete = "readiness_complete"
    case readinessSkipped = "readiness_skipped"
    case firstCapture = "first_capture"
    case clarification = "clarification"
    case reviewableActionPlan = "reviewable_action_plan"
    case approvedLocalAction = "approved_local_action"
    case followUpWaiting = "follow_up_waiting"
    case outcomeTracked = "outcome_tracked"
    case outcomeClosed = "outcome_closed"
}

public enum PublicAlphaStageMark: String, Codable, CaseIterable, Sendable {
    case started
    case completed
    case failed
    case abandoned
}

public enum PublicAlphaFailureCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case install
    case readiness
    case capture
    case interpretation
    case review
    case approval
    case followUp
    case outcome
    case reliability
    case privacy
}

public enum PublicAlphaAbandonReason: String, Codable, CaseIterable, Hashable, Sendable {
    case personaFit = "persona_fit"
    case onboarding
    case workflow
    case reliability
    case positioning
    case unknown
}

public enum PublicAlphaFeedbackCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case helpfulNow = "helpful_now"
    case helpfulLater = "helpful_later"
    case wrongTiming = "wrong_timing"
    case wrongScope = "wrong_scope"
    case notHelpful = "not_helpful"
    case notDelivered = "not_delivered"
}

public enum PublicAlphaTrustIncidentCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case criticalSafety = "critical_safety"
    case privacy
    case scope
    case duplicate
    case wrongDestination = "wrong_destination"
}

public enum PublicAlphaInterviewCode: String, Codable, CaseIterable, Hashable, Sendable {
    case nonSubstitutableReason = "non_substitutable_reason"
    case reviewBurden = "review_burden"
    case naturalWorkFit = "natural_work_fit"
    case missingWork = "missing_work"
    case proactiveHelpful = "proactive_helpful"
    case proactiveIntrusive = "proactive_intrusive"
    case localFirstPurchaseReason = "local_first_purchase_reason"
    case willingToPay = "willing_to_pay"
    case substitution
    case stoppedUse = "stopped_use"
}

public enum PublicAlphaContinuationState: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case stopped
    case completed
}

public enum PublicAlphaConsentMode: String, Codable, CaseIterable, Sendable {
    case localOnly = "local_only"
    case aggregatedDiagnosticsOptIn = "aggregated_diagnostics_opt_in"
    case researchDatasetOptIn = "research_dataset_opt_in"
}

public struct PublicAlphaStageEvent: Codable, Equatable, Sendable {
    public let eventID: UUID
    public let participantID: PublicAlphaParticipantID
    public let stage: PublicAlphaStage
    public let mark: PublicAlphaStageMark
    public let occurredAt: Date
    public let failureCategory: PublicAlphaFailureCategory?
    public let abandonReason: PublicAlphaAbandonReason?

    public init(
        eventID: UUID = UUID(),
        participantID: PublicAlphaParticipantID,
        stage: PublicAlphaStage,
        mark: PublicAlphaStageMark,
        occurredAt: Date,
        failureCategory: PublicAlphaFailureCategory? = nil,
        abandonReason: PublicAlphaAbandonReason? = nil
    ) throws {
        guard (mark == .failed) == (failureCategory != nil),
              (mark == .abandoned) == (abandonReason != nil)
        else {
            throw PublicAlphaValidationError.invalidStageMetadata
        }
        self.eventID = eventID
        self.participantID = participantID
        self.stage = stage
        self.mark = mark
        self.occurredAt = occurredAt
        self.failureCategory = failureCategory
        self.abandonReason = abandonReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            eventID: container.decode(UUID.self, forKey: .eventID),
            participantID: container.decode(PublicAlphaParticipantID.self, forKey: .participantID),
            stage: container.decode(PublicAlphaStage.self, forKey: .stage),
            mark: container.decode(PublicAlphaStageMark.self, forKey: .mark),
            occurredAt: container.decode(Date.self, forKey: .occurredAt),
            failureCategory: container.decodeIfPresent(PublicAlphaFailureCategory.self, forKey: .failureCategory),
            abandonReason: container.decodeIfPresent(PublicAlphaAbandonReason.self, forKey: .abandonReason)
        )
    }
}

/// One weekly, closed-schema participant snapshot. It carries counts and
/// coded categories only; task, person, transcript, prompt, path, and note
/// content have no representable field.
public struct PublicAlphaValidationSnapshot: Codable, Equatable, Sendable {
    public let snapshotID: UUID
    public let participantID: PublicAlphaParticipantID
    public let personaFlags: Set<PublicAlphaPersonaFlag>
    public let build: PublicAlphaBuildIdentity
    public let weekStart: Date
    public let weeklyActiveDays: Int
    public let capturedItemCount: Int
    public let confirmedCommitmentCount: Int
    public let outcomeTrackedCount: Int
    public let outcomeClosedCount: Int
    public let manualReplanningCount: Int
    public let proactiveFeedbackCounts: [PublicAlphaFeedbackCategory: Int]
    public let trustIncidentCategories: Set<PublicAlphaTrustIncidentCategory>
    public let interviewCodes: Set<PublicAlphaInterviewCode>
    public let continuationState: PublicAlphaContinuationState

    public init(
        snapshotID: UUID = UUID(),
        participantID: PublicAlphaParticipantID,
        personaFlags: Set<PublicAlphaPersonaFlag>,
        build: PublicAlphaBuildIdentity,
        weekStart: Date,
        weeklyActiveDays: Int,
        capturedItemCount: Int,
        confirmedCommitmentCount: Int,
        outcomeTrackedCount: Int,
        outcomeClosedCount: Int,
        manualReplanningCount: Int,
        proactiveFeedbackCounts: [PublicAlphaFeedbackCategory: Int] = [:],
        trustIncidentCategories: Set<PublicAlphaTrustIncidentCategory> = [],
        interviewCodes: Set<PublicAlphaInterviewCode> = [],
        continuationState: PublicAlphaContinuationState
    ) throws {
        guard !personaFlags.isEmpty else {
            throw PublicAlphaValidationError.invalidSnapshot
        }
        try Self.validateCount(weeklyActiveDays, named: "weeklyActiveDays", range: 0...7)
        try Self.validateCount(capturedItemCount, named: "capturedItemCount")
        try Self.validateCount(confirmedCommitmentCount, named: "confirmedCommitmentCount")
        try Self.validateCount(outcomeTrackedCount, named: "outcomeTrackedCount")
        try Self.validateCount(outcomeClosedCount, named: "outcomeClosedCount")
        try Self.validateCount(manualReplanningCount, named: "manualReplanningCount")
        guard outcomeTrackedCount <= confirmedCommitmentCount,
              outcomeClosedCount <= outcomeTrackedCount
        else {
            throw PublicAlphaValidationError.invalidSnapshot
        }
        self.snapshotID = snapshotID
        self.participantID = participantID
        self.personaFlags = personaFlags
        self.build = build
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard weekStart.timeIntervalSinceReferenceDate.isFinite,
              let week = calendar.dateInterval(of: .weekOfYear, for: weekStart) else {
            throw PublicAlphaValidationError.invalidSnapshot
        }
        self.weekStart = week.start
        self.weeklyActiveDays = weeklyActiveDays
        self.capturedItemCount = capturedItemCount
        self.confirmedCommitmentCount = confirmedCommitmentCount
        self.outcomeTrackedCount = outcomeTrackedCount
        self.outcomeClosedCount = outcomeClosedCount
        self.manualReplanningCount = manualReplanningCount
        _ = try totalPublicAlphaCounts(Array(proactiveFeedbackCounts.values))
        self.proactiveFeedbackCounts = proactiveFeedbackCounts
        self.trustIncidentCategories = trustIncidentCategories
        self.interviewCodes = interviewCodes
        self.continuationState = continuationState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            snapshotID: container.decode(UUID.self, forKey: .snapshotID),
            participantID: container.decode(PublicAlphaParticipantID.self, forKey: .participantID),
            personaFlags: container.decode(Set<PublicAlphaPersonaFlag>.self, forKey: .personaFlags),
            build: container.decode(PublicAlphaBuildIdentity.self, forKey: .build),
            weekStart: container.decode(Date.self, forKey: .weekStart),
            weeklyActiveDays: container.decode(Int.self, forKey: .weeklyActiveDays),
            capturedItemCount: container.decode(Int.self, forKey: .capturedItemCount),
            confirmedCommitmentCount: container.decode(Int.self, forKey: .confirmedCommitmentCount),
            outcomeTrackedCount: container.decode(Int.self, forKey: .outcomeTrackedCount),
            outcomeClosedCount: container.decode(Int.self, forKey: .outcomeClosedCount),
            manualReplanningCount: container.decode(Int.self, forKey: .manualReplanningCount),
            proactiveFeedbackCounts: container.decode([PublicAlphaFeedbackCategory: Int].self, forKey: .proactiveFeedbackCounts),
            trustIncidentCategories: container.decode(Set<PublicAlphaTrustIncidentCategory>.self, forKey: .trustIncidentCategories),
            interviewCodes: container.decode(Set<PublicAlphaInterviewCode>.self, forKey: .interviewCodes),
            continuationState: container.decode(PublicAlphaContinuationState.self, forKey: .continuationState)
        )
    }

    private static func validateCount(_ value: Int, named name: String, range: ClosedRange<Int>? = nil) throws {
        guard value >= 0, range?.contains(value) ?? true else {
            throw PublicAlphaValidationError.invalidCount(name)
        }
    }
}

public enum PublicAlphaLedgerAppendResult: Equatable, Sendable {
    case inserted
    case duplicate
}

/// Local append-only ledger used by the validation program. It is Codable so
/// callers can persist and recover it from the existing local diagnostics
/// boundary without adding a network or database dependency.
public struct PublicAlphaValidationLedger: Codable, Equatable, Sendable {
    public private(set) var stageEvents: [PublicAlphaStageEvent]
    public private(set) var weeklySnapshots: [PublicAlphaValidationSnapshot]

    public init() {
        self.stageEvents = []
        self.weeklySnapshots = []
    }

    public init(recovering data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stageEvents = try container.decode([PublicAlphaStageEvent].self, forKey: .stageEvents)
        self.weeklySnapshots = try container.decode([PublicAlphaValidationSnapshot].self, forKey: .weeklySnapshots)
        try validateUniqueIDs()
    }

    public mutating func append(_ event: PublicAlphaStageEvent) -> PublicAlphaLedgerAppendResult {
        guard !stageEvents.contains(where: { $0.eventID == event.eventID }) else {
            return .duplicate
        }
        stageEvents.append(event)
        return .inserted
    }

    public mutating func append(_ snapshot: PublicAlphaValidationSnapshot) -> PublicAlphaLedgerAppendResult {
        guard !weeklySnapshots.contains(where: {
            $0.snapshotID == snapshot.snapshotID
                || ($0.participantID == snapshot.participantID && $0.weekStart == snapshot.weekStart)
        }) else {
            return .duplicate
        }
        weeklySnapshots.append(snapshot)
        return .inserted
    }

    public func encodedSnapshot() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public mutating func delete(participantID: PublicAlphaParticipantID) {
        stageEvents.removeAll { $0.participantID == participantID }
        weeklySnapshots.removeAll { $0.participantID == participantID }
    }

    public func report() throws -> PublicAlphaValidationReport {
        let feedbackCounts = try Dictionary(uniqueKeysWithValues: PublicAlphaFeedbackCategory.allCases.map { category in
            (category, try totalPublicAlphaCounts(weeklySnapshots.map { $0.proactiveFeedbackCounts[category, default: 0] }))
        })
        return PublicAlphaValidationReport(
            participantCount: Set(weeklySnapshots.map(\.participantID)).union(stageEvents.map(\.participantID)).count,
            stageCompletionCounts: stageEvents.filter { $0.mark == .completed }.reduce(into: [PublicAlphaStage: Int]()) { counts, event in
                counts[event.stage, default: 0] += 1
            },
            capturedItemCount: try totalPublicAlphaCounts(weeklySnapshots.map(\.capturedItemCount)),
            confirmedCommitmentCount: try totalPublicAlphaCounts(weeklySnapshots.map(\.confirmedCommitmentCount)),
            outcomeTrackedCount: try totalPublicAlphaCounts(weeklySnapshots.map(\.outcomeTrackedCount)),
            outcomeClosedCount: try totalPublicAlphaCounts(weeklySnapshots.map(\.outcomeClosedCount)),
            manualReplanningCount: try totalPublicAlphaCounts(weeklySnapshots.map(\.manualReplanningCount)),
            feedbackCounts: feedbackCounts,
            feedbackCount: try totalPublicAlphaCounts(Array(feedbackCounts.values)),
            trustIncidentCategories: Set(weeklySnapshots.flatMap(\.trustIncidentCategories)),
            continuationStates: Set(weeklySnapshots.map(\.continuationState)),
            builds: Set(weeklySnapshots.map(\.build))
        )
    }

    /// Returns only aggregated data when the user explicitly opted in. Both
    /// local-only and research-dataset consent produce no remote payload; the
    /// latter belongs to a separate encrypted research store.
    public func remotePayload(consent: PublicAlphaConsentMode) throws -> Data? {
        guard consent == .aggregatedDiagnosticsOptIn else {
            return nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(report())
    }

    private func validateUniqueIDs() throws {
        for snapshots in Dictionary(grouping: weeklySnapshots, by: \.participantID).values {
            guard Set(snapshots.map(\.weekStart)).count == snapshots.count else {
                throw PublicAlphaValidationError.invalidSnapshot
            }
        }
        let eventIDs = stageEvents.map(\.eventID)
        let snapshotIDs = weeklySnapshots.map(\.snapshotID)
        guard Set(eventIDs).count == eventIDs.count,
              Set(snapshotIDs).count == snapshotIDs.count
        else {
            throw PublicAlphaValidationError.invalidSnapshot
        }
    }
}

public struct PublicAlphaValidationReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let participantCount: Int
    public let stageCompletionCounts: [PublicAlphaStage: Int]
    public let capturedItemCount: Int
    public let confirmedCommitmentCount: Int
    public let outcomeTrackedCount: Int
    public let outcomeClosedCount: Int
    public let manualReplanningCount: Int
    public let feedbackCounts: [PublicAlphaFeedbackCategory: Int]
    public let feedbackCount: Int
    public let trustIncidentCategories: Set<PublicAlphaTrustIncidentCategory>
    public let continuationStates: Set<PublicAlphaContinuationState>
    public let builds: Set<PublicAlphaBuildIdentity>

    init(
        participantCount: Int,
        stageCompletionCounts: [PublicAlphaStage: Int],
        capturedItemCount: Int,
        confirmedCommitmentCount: Int,
        outcomeTrackedCount: Int,
        outcomeClosedCount: Int,
        manualReplanningCount: Int,
        feedbackCounts: [PublicAlphaFeedbackCategory: Int],
        feedbackCount: Int,
        trustIncidentCategories: Set<PublicAlphaTrustIncidentCategory>,
        continuationStates: Set<PublicAlphaContinuationState>,
        builds: Set<PublicAlphaBuildIdentity>
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.participantCount = participantCount
        self.stageCompletionCounts = stageCompletionCounts
        self.capturedItemCount = capturedItemCount
        self.confirmedCommitmentCount = confirmedCommitmentCount
        self.outcomeTrackedCount = outcomeTrackedCount
        self.outcomeClosedCount = outcomeClosedCount
        self.manualReplanningCount = manualReplanningCount
        self.feedbackCounts = feedbackCounts
        self.feedbackCount = feedbackCount
        self.trustIncidentCategories = trustIncidentCategories
        self.continuationStates = continuationStates
        self.builds = builds
    }
}

public struct PublicAlphaGateMetrics: Equatable, Sendable {
    public let fourWeekActivatedUsers: Int
    public let weekFourRetentionRate: Double
    public let medianCommitmentsPerActiveUser: Double
    public let outcomeTrackingRate: Double
    public let helpfulFeedbackRate: Double
    public let criticalTrustIncidentCount: Int
    public let nonSubstitutableReasonRate: Double
    public let willingnessToPayRate: Double

    public init(
        fourWeekActivatedUsers: Int,
        weekFourRetentionRate: Double,
        medianCommitmentsPerActiveUser: Double,
        outcomeTrackingRate: Double,
        helpfulFeedbackRate: Double,
        criticalTrustIncidentCount: Int,
        nonSubstitutableReasonRate: Double,
        willingnessToPayRate: Double
    ) throws {
        guard fourWeekActivatedUsers >= 0,
              criticalTrustIncidentCount >= 0
        else {
            throw PublicAlphaValidationError.invalidCount("gate")
        }
        for (name, value) in [
            ("weekFourRetentionRate", weekFourRetentionRate),
            ("outcomeTrackingRate", outcomeTrackingRate),
            ("helpfulFeedbackRate", helpfulFeedbackRate),
            ("nonSubstitutableReasonRate", nonSubstitutableReasonRate),
            ("willingnessToPayRate", willingnessToPayRate)
        ] {
            guard value.isFinite, (0...1).contains(value) else {
                throw PublicAlphaValidationError.invalidRate(name)
            }
        }
        guard medianCommitmentsPerActiveUser.isFinite, medianCommitmentsPerActiveUser >= 0 else {
            throw PublicAlphaValidationError.invalidRate("medianCommitmentsPerActiveUser")
        }
        self.fourWeekActivatedUsers = fourWeekActivatedUsers
        self.weekFourRetentionRate = weekFourRetentionRate
        self.medianCommitmentsPerActiveUser = medianCommitmentsPerActiveUser
        self.outcomeTrackingRate = outcomeTrackingRate
        self.helpfulFeedbackRate = helpfulFeedbackRate
        self.criticalTrustIncidentCount = criticalTrustIncidentCount
        self.nonSubstitutableReasonRate = nonSubstitutableReasonRate
        self.willingnessToPayRate = willingnessToPayRate
    }
}

public enum PublicAlphaGateDecision: String, Codable, Equatable, CaseIterable, Sendable {
    case insufficientSample = "insufficient_sample"
    case go
    case iterate
    case narrow
    case stop
}

public enum PublicAlphaGateEvaluator {
    public static func evaluate(_ metrics: PublicAlphaGateMetrics) -> PublicAlphaGateDecision {
        guard metrics.criticalTrustIncidentCount == 0 else {
            return .stop
        }
        guard metrics.fourWeekActivatedUsers >= 10 else {
            return .insufficientSample
        }
        let coreGatesPass = metrics.weekFourRetentionRate >= 0.35
            && metrics.medianCommitmentsPerActiveUser >= 2
            && metrics.outcomeTrackingRate >= 0.50
            && metrics.helpfulFeedbackRate >= 0.50
            && metrics.nonSubstitutableReasonRate >= 0.30
            && metrics.willingnessToPayRate >= 0.20
        if coreGatesPass {
            return .go
        }
        if metrics.nonSubstitutableReasonRate >= 0.30,
           metrics.willingnessToPayRate >= 0.20 {
            return .narrow
        }
        return .iterate
    }
}
