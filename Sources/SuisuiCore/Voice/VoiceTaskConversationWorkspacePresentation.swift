import Foundation

/// UIが会話・計画・Queueの実行正本を混同しないための、表示専用の
/// conversation workspace stateです。Providerの生出力は意図的に受け取らず、
/// ここを経由して表示できるのは確認済み入力と構造化済みの提案だけです。
public struct VoiceTaskConversationWorkspacePresentation: Equatable, Sendable {
    public enum SessionState: Equatable, Sendable {
        case ready
        case recording
        case transcribing
        case waitingForClarification
        case preparingReview
        case waitingForReview
        case paused
        case archived
        case blocked(message: String)

        public var title: String {
            switch self {
            case .ready:
                String(localized: "Ready")
            case .recording:
                String(localized: "Recording")
            case .transcribing:
                String(localized: "Transcribing")
            case .waitingForClarification:
                String(localized: "Needs clarification")
            case .preparingReview:
                String(localized: "Preparing review")
            case .waitingForReview:
                String(localized: "Waiting for approval")
            case .paused:
                String(localized: "Paused")
            case .archived:
                String(localized: "Archived")
            case .blocked:
                String(localized: "Blocked")
            }
        }

        public var systemImage: String {
            switch self {
            case .ready:
                "checkmark.circle"
            case .recording:
                "record.circle"
            case .transcribing:
                "waveform"
            case .waitingForClarification:
                "questionmark.circle"
            case .preparingReview:
                "sparkles"
            case .waitingForReview:
                "checkmark.shield"
            case .paused:
                "pause.circle"
            case .archived:
                "archivebox"
            case .blocked:
                "exclamationmark.triangle"
            }
        }

        public var blockedMessage: String? {
            guard case .blocked(let message) = self else { return nil }
            return message
        }
    }

    public struct Scope: Equatable, Sendable {
        public let projectName: String?
        public let taskName: String?
        public let sessionTitle: String

        public init(
            projectName: String? = nil,
            taskName: String? = nil,
            sessionTitle: String = String(localized: "Voice conversation")
        ) {
            self.projectName = Self.nonBlank(projectName)
            self.taskName = Self.nonBlank(taskName)
            self.sessionTitle = Self.nonBlank(sessionTitle)
                ?? String(localized: "Voice conversation")
        }

        public var accessibilityValue: String {
            [projectName, taskName, sessionTitle]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        private static func nonBlank(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    public struct Turn: Identifiable, Equatable, Sendable {
        public enum Author: Equatable, Sendable {
            case user
            case assistant
            case system

            public var label: String {
                switch self {
                case .user: String(localized: "You")
                case .assistant: "Suisui"
                case .system: String(localized: "System")
                }
            }
        }

        public let id: UUID
        public let author: Author
        public let createdAt: Date
        /// Only explicitly confirmed text or concise structured summaries may
        /// enter a Turn. This avoids accidentally rendering raw STT/provider
        /// payloads in a conversation history surface.
        public let text: String

        public init(
            id: UUID = UUID(),
            author: Author,
            text: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.author = author
            self.text = VoiceTaskConversationWorkspacePresentation.redactedPreview(text)
            self.createdAt = createdAt
        }
    }

    public enum TurnListState: Equatable, Sendable {
        case empty
        case loaded(hasMore: Bool)
        case loadingMore
        case failed(message: String)
    }

    public struct Clarification: Equatable, Sendable {
        public let prompt: String

        public init(prompt: String) {
            self.prompt = VoiceTaskConversationWorkspacePresentation.redactedPreview(prompt)
        }
    }

    public struct ResolvedTarget: Equatable, Sendable {
        public let title: String
        public let reason: String

        public init(title: String, reason: String) {
            self.title = VoiceTaskConversationWorkspacePresentation.redactedPreview(title)
            self.reason = VoiceTaskConversationWorkspacePresentation.redactedPreview(reason)
        }
    }

    public struct Proposal: Equatable, Sendable {
        public let summary: String
        public let actionTitles: [String]
        public let requiresApproval: Bool

        public init(summary: String, actionTitles: [String], requiresApproval: Bool) {
            self.summary = VoiceTaskConversationWorkspacePresentation.redactedPreview(summary)
            self.actionTitles = actionTitles.map {
                VoiceTaskConversationWorkspacePresentation.redactedPreview($0)
            }
            self.requiresApproval = requiresApproval
        }
    }

    public struct FactCandidate: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let preview: String
        public let stateLabel: String
        public let sourceLabel: String

        public init(
            id: UUID = UUID(),
            preview: String,
            stateLabel: String,
            sourceLabel: String
        ) {
            self.id = id
            self.preview = VoiceTaskConversationWorkspacePresentation.redactedPreview(preview)
            self.stateLabel = VoiceTaskConversationWorkspacePresentation.redactedPreview(stateLabel)
            self.sourceLabel = VoiceTaskConversationWorkspacePresentation.redactedPreview(sourceLabel)
        }
    }

    public struct QueueHandoff: Equatable, Sendable {
        public let itemID: String
        public let stateLabel: String
        public let summary: String

        public init(itemID: String, stateLabel: String, summary: String) {
            self.itemID = itemID
            self.stateLabel = VoiceTaskConversationWorkspacePresentation.redactedPreview(stateLabel)
            self.summary = VoiceTaskConversationWorkspacePresentation.redactedPreview(summary)
        }
    }

    public struct Closeout: Equatable, Sendable {
        public let createdCount: Int
        public let changedCount: Int
        public let pendingCount: Int
        public let unresolvedCount: Int

        public init(
            createdCount: Int = 0,
            changedCount: Int = 0,
            pendingCount: Int = 0,
            unresolvedCount: Int = 0
        ) {
            self.createdCount = max(0, createdCount)
            self.changedCount = max(0, changedCount)
            self.pendingCount = max(0, pendingCount)
            self.unresolvedCount = max(0, unresolvedCount)
        }
    }

    public let scope: Scope
    public let sessionState: SessionState
    public let turns: [Turn]
    public let turnListState: TurnListState
    public let clarification: Clarification?
    public let resolvedTarget: ResolvedTarget?
    public let proposal: Proposal?
    public let factCandidates: [FactCandidate]
    public let queueHandoff: QueueHandoff?
    public let closeout: Closeout

    public init(
        scope: Scope = Scope(),
        sessionState: SessionState = .ready,
        turns: [Turn] = [],
        turnListState: TurnListState? = nil,
        clarification: Clarification? = nil,
        resolvedTarget: ResolvedTarget? = nil,
        proposal: Proposal? = nil,
        factCandidates: [FactCandidate] = [],
        queueHandoff: QueueHandoff? = nil,
        closeout: Closeout = Closeout()
    ) {
        self.scope = scope
        self.sessionState = sessionState
        self.turns = turns
        self.turnListState = turnListState ?? (turns.isEmpty ? .empty : .loaded(hasMore: false))
        self.clarification = clarification
        self.resolvedTarget = resolvedTarget
        self.proposal = proposal
        self.factCandidates = factCandidates
        self.queueHandoff = queueHandoff
        self.closeout = closeout
    }

    public static func make(
        phase: VoiceCapturePhase,
        scope: Scope = Scope(),
        confirmedTranscript: String = "",
        clarificationQuestion: ClarificationQuestion? = nil,
        planningResponse: PlanningResponse? = nil,
        assistantQueueItem: AssistantQueueItem? = nil,
        resolvedTarget: ResolvedTarget? = nil,
        factCandidates: [FactCandidate] = [],
        closeout: Closeout = Closeout()
    ) -> Self {
        let state = sessionState(for: phase)
        let userTurns = confirmedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [Turn(author: .user, text: confirmedTranscript)]
        let assistantTurns = planningResponse?.actionPlan.map {
            [Turn(author: .assistant, text: $0.summary)]
        } ?? []
        let proposal = planningResponse?.actionPlan.map { plan in
            Proposal(
                summary: plan.summary,
                actionTitles: plan.actions.indices.map {
                    String(
                        localized: "Proposed change \($0 + 1)"
                    )
                },
                requiresApproval: plan.requiresApproval
            )
        }
        let queueHandoff = assistantQueueItem.map {
            QueueHandoff(
                itemID: $0.id,
                stateLabel: queueStateLabel($0.state),
                summary: $0.redactedSummary
            )
        }
        return Self(
            scope: scope,
            sessionState: state,
            turns: userTurns + assistantTurns,
            clarification: clarificationQuestion.map { Clarification(prompt: $0.prompt) },
            resolvedTarget: resolvedTarget,
            proposal: proposal,
            factCandidates: factCandidates,
            queueHandoff: queueHandoff,
            closeout: closeout
        )
    }

    private static func sessionState(for phase: VoiceCapturePhase) -> SessionState {
        switch phase {
        case .idle: .ready
        case .recording: .recording
        case .transcribing: .transcribing
        case .needsClarification: .waitingForClarification
        case .generatingPlan: .preparingReview
        case .reviewReady: .waitingForReview
        case .failed(let message): .blocked(message: redactedPreview(message))
        }
    }

    private static func queueStateLabel(_ state: AssistantQueueState) -> String {
        switch state {
        case .captured: String(localized: "Captured")
        case .interpreted: String(localized: "Interpreted")
        case .drafted: String(localized: "Drafted")
        case .waitingReview: String(localized: "Waiting for review")
        case .approved: String(localized: "Approved")
        case .running: String(localized: "Running")
        case .blocked: String(localized: "Blocked")
        case .done: String(localized: "Done")
        case .failed: String(localized: "Failed")
        case .rejected: String(localized: "Rejected")
        case .deferred: String(localized: "Deferred")
        }
    }

    /// Context/facts can originate from users or a provider. Redacting at the
    /// presentation boundary keeps accidental secret echoes from becoming a
    /// second durable/displayable provider transcript.
    public static func redactedPreview(_ value: String, maxLength: Int = 240) -> String {
        let redacted = LocalPathRedactor.redact(DeveloperSecretRedactor().redact(value).text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard redacted.count > maxLength else { return redacted }
        return String(redacted.prefix(maxLength)) + "…"
    }
}
