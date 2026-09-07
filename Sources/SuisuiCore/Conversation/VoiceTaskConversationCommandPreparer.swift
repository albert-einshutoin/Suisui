import Foundation

public struct VoiceTaskConversationPreparedBegin: Sendable {
    public let requiredSlots: [ClarificationSlot]
    public let intents: [ConversationTaskIntent]
    public let referenceRequest: VoiceTaskReferenceRequest?
    public let localAnswerItems: [VoiceTaskConversationAnswerItem]
    let listTurn: VoiceTaskConversationTurn?
    let listReferences: [ConversationReference]

    public init(
        requiredSlots: [ClarificationSlot] = [],
        intents: [ConversationTaskIntent],
        referenceRequest: VoiceTaskReferenceRequest? = nil,
        localAnswerItems: [VoiceTaskConversationAnswerItem] = [],
        listTurn: VoiceTaskConversationTurn? = nil,
        listReferences: [ConversationReference] = []
    ) {
        self.requiredSlots = requiredSlots
        self.intents = intents
        self.referenceRequest = referenceRequest
        self.localAnswerItems = localAnswerItems
        self.listTurn = listTurn
        self.listReferences = listReferences
    }

    static func taskCreation(
        transcript: String, triage: LocalTriageDecision, selectedProjectID: Int64?
    ) -> Self? {
        guard triage.operation == .taskCreate,
              triage.route == .deterministic || triage.route == .clarification,
              !triage.reasons.contains(.capabilityUnavailable),
              !triage.reasons.contains(.manualOnly)
        else { return nil }
        guard let title = LocalTriageRouter.taskCreationTitle(in: transcript) else { return nil }
        var arguments: [String: JSONValue] = [:]
        if !title.isEmpty { arguments["title"] = .string(title) }
        if let selectedProjectID { arguments["projectId"] = .number(Double(selectedProjectID)) }
        return VoiceTaskConversationPreparedBegin(
            requiredSlots: title.isEmpty ? [.taskTitle] : [],
            intents: [ConversationTaskIntent(
                utterance: transcript, operation: .create, tool: .taskCreate,
                arguments: arguments, summary: "Create task"
            )]
        )
    }
}

public protocol VoiceTaskConversationCommandPreparing: Sendable {
    func publish(_ prepared: VoiceTaskConversationPreparedBegin) throws
    func prepare(
        transcript: String,
        triage: LocalTriageDecision,
        explicitTaskID: Int64?,
        sessionID: UUID,
        sourceTurnID: UUID,
        selectedProjectID: Int64?,
        selectedTaskID: Int64?,
        at date: Date,
        timeZoneIdentifier: String
    ) throws -> VoiceTaskConversationPreparedBegin?
}

public enum VoiceTaskConversationCommandPreparerError: Error, Equatable, Sendable {
    case invalidTimeZoneIdentifier
}

/// Converts an authorized local decision into existing conversation intents.
/// Unrecognized arguments remain unresolved; they never select a provider.
public final class SQLiteVoiceTaskConversationCommandPreparer:
    VoiceTaskConversationCommandPreparing,
    @unchecked Sendable
{
    private let taskStore: SQLiteTaskStore
    private let projectStore: SQLiteProjectStore
    private let conversationStore: SQLiteVoiceTaskConversationStore

    public init(
        taskStore: SQLiteTaskStore,
        projectStore: SQLiteProjectStore,
        conversationStore: SQLiteVoiceTaskConversationStore
    ) {
        self.taskStore = taskStore
        self.projectStore = projectStore
        self.conversationStore = conversationStore
    }

    public func prepare(
        transcript: String,
        triage: LocalTriageDecision,
        explicitTaskID: Int64?,
        sessionID: UUID,
        sourceTurnID: UUID,
        selectedProjectID: Int64?,
        selectedTaskID: Int64?,
        at date: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> VoiceTaskConversationPreparedBegin? {
        let normalized = transcript
            .folding(
                options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        guard triage.route == .deterministic || triage.route == .clarification,
              !triage.reasons.contains(.capabilityUnavailable),
              !triage.reasons.contains(.manualOnly)
        else { return nil }

        guard triage.operation == .read || triage.operation == .taskDueDate else { return nil }
        if triage.operation == .read && !Self.isTaskListRequest(normalized) { return nil }
        let references = triage.operation == .taskDueDate
            ? try conversationStore.listReferences(sessionID: sessionID, limit: 500) : []
        let latestSourceTurnID = references.first?.sourceTurnID
        let latestReferences = references.filter { $0.sourceTurnID == latestSourceTurnID }
        let requestedOrdinal = Self.requestedOrdinal(in: normalized)
        let tasks: [TaskRecord]
        if triage.operation == .read {
            tasks = try (selectedProjectID.map {
                try taskStore.listForProjectBoard(projectIDs: [$0], includeDanglingReferences: false)
                    .filter { $0.projectID == selectedProjectID }
            } ?? taskStore.listAll()).filter { $0.status != "completed" }.sorted { $0.id < $1.id }
        } else if let taskID = explicitTaskID ?? selectedTaskID,
                  explicitTaskID != nil || requestedOrdinal == nil {
            tasks = [try taskStore.get(id: taskID)]
        } else if latestReferences.isEmpty {
            tasks = []
        } else {
            let referencedTasks: [TaskRecord] = try latestReferences.compactMap {
                guard case .task(let id) = $0.target else { return nil }
                return try taskStore.get(id: id)
            }
            // Compare only the projects represented by the prior list. Unrelated
            // projects must not participate in ordinal resolution.
            tasks = try taskStore.listForProjectBoard(
                projectIDs: Set(referencedTasks.compactMap(\.projectID)),
                includeDanglingReferences: false
            ).filter { $0.status != "completed" && (selectedProjectID == nil || $0.projectID == selectedProjectID) }.sorted { $0.id < $1.id }
        }
        let visibleProjectIDs = Set(try Set(tasks.compactMap(\.projectID)).filter {
            try projectStore.get(id: $0).status != "archived"
        })
        let visibleTasks = tasks.filter {
            $0.status != "completed" && ($0.projectID.map(visibleProjectIDs.contains) ?? true)
        }
        let candidates = visibleTasks.map {
            ConversationReferenceCandidate(
                target: .task(id: $0.id, projectID: $0.projectID),
                title: $0.title,
                stableSortKey: String(format: "%020lld", $0.id)
            )
        }

        if Self.isTaskListRequest(normalized) {
            let (turn, references) = try makeListReferenceSet(
                transcript: transcript,
                sessionID: sessionID,
                sourceTurnID: sourceTurnID,
                tasks: visibleTasks,
                candidates: candidates,
                at: date
            )
            return VoiceTaskConversationPreparedBegin(
                intents: [
                    ConversationTaskIntent(
                        utterance: transcript,
                        operation: .list,
                        tool: .taskList,
                        arguments: selectedProjectID.map {
                            ["projectId": .number(Double($0))]
                        } ?? [:],
                        summary: "List current tasks"
                    )
                ],
                localAnswerItems: visibleTasks.map {
                    VoiceTaskConversationAnswerItem(
                        id: "task:\($0.id)",
                        label: $0.title
                    )
                },
                listTurn: turn,
                listReferences: references
            )
        }

        guard Self.requestsDueDateChange(normalized),
              selectedTaskID != nil || Self.refersToTask(normalized)
        else {
            return nil
        }

        let fingerprint = explicitTaskID == nil && requestedOrdinal != nil
            ? latestReferences.first?.orderingFingerprint
            : nil
        let ordinal = requestedOrdinal
        let ordinalReference = ordinal.flatMap { requested in
            latestReferences.first { $0.ordinal == requested }
        }
        let selectedTask = selectedTaskID.flatMap { id in
            visibleTasks.first(where: { $0.id == id }).map {
                ConversationResolvedTarget.task(
                    id: $0.id,
                    projectID: $0.projectID
                )
            }
        }
        let selectedProject = selectedProjectID.map(
            ConversationResolvedTarget.project
        )
        var arguments: [String: JSONValue] = [:]
        if let priority = Self.requestedPriority(in: normalized) {
            arguments["priority"] = .string(priority)
        }
        let dueDate = try (
            isoDate(in: normalized)
            ?? naturalDueDate(
                in: normalized,
                at: date,
                timeZoneIdentifier: timeZoneIdentifier
            )
        )
        if let dueDate {
            arguments["dueAt"] = .string(dueDate)
        }
        let intent = ConversationTaskIntent(
            utterance: transcript,
            operation: .updateDueDate,
            tool: .taskUpdate,
            arguments: arguments,
            summary: arguments["priority"] == nil
                ? "Update task due date"
                : "Update task due date and priority"
        )
        return VoiceTaskConversationPreparedBegin(
            requiredSlots: dueDate == nil ? [.dueDate] : [],
            intents: [intent],
            referenceRequest: VoiceTaskReferenceRequest(
                sessionID: sessionID,
                utterance: transcript,
                explicitTarget: explicitTaskID.flatMap { id in
                    visibleTasks.first(where: { $0.id == id }).map { .task(id: $0.id, projectID: $0.projectID) }
                },
                selectedTask: selectedTask,
                selectedProject: selectedProject,
                ordinalReference: ordinalReference,
                candidateOrderingFingerprint: fingerprint,
                candidates: candidates
            )
        )
    }

    private func makeListReferenceSet(
        transcript: String,
        sessionID: UUID,
        sourceTurnID: UUID,
        tasks: [TaskRecord],
        candidates: [ConversationReferenceCandidate],
        at date: Date
    ) throws -> (VoiceTaskConversationTurn, [ConversationReference]) {
        let turn = try VoiceTaskConversationTurn(
            id: sourceTurnID,
            sessionID: sessionID,
            author: .user,
            // Listing is a read-only voice command, not an explicit approval.
            // Keep its STT body in the short-lived field so routine retention
            // cannot accidentally preserve recognition output indefinitely.
            rawTranscript: transcript,
            userConfirmedText: nil,
            createdAt: date
        )
        let fingerprint = VoiceTaskReferenceResolver.orderingFingerprint(
            for: candidates
        )
        let references = try tasks.enumerated().map { ordinal, task in
            try ConversationReference(
                    sessionID: sessionID,
                    target: .task(task.id),
                    sourceTurnID: sourceTurnID,
                    ordinal: ordinal,
                    orderingFingerprint: fingerprint,
                    expiresAt: date.addingTimeInterval(24 * 60 * 60),
                    createdAt: date
                )
        }
        return (turn, references)
    }

    public func publish(_ prepared: VoiceTaskConversationPreparedBegin) throws {
        guard let turn = prepared.listTurn else { return }
        if try conversationStore.loadSession(id: turn.sessionID) == nil {
            try conversationStore.createSession(VoiceTaskConversationSession(
                id: turn.sessionID, title: "Voice task conversation", entryPoint: .voiceCommand, createdAt: turn.createdAt
            ))
        }
        try conversationStore.saveTurnAndReferences(turn: turn, references: prepared.listReferences)
    }

    static func supportedOperations(
        for text: String,
        hasSelectedTask: Bool = false
    ) -> Set<LocalTriageOperation> {
        var operations: Set<LocalTriageOperation> = [.taskCreate, .frontier, .externalWrite]
        if isTaskListRequest(text) { operations.insert(.read) }
        if requestsDueDateChange(text) && (hasSelectedTask || refersToTask(text)) {
            operations.insert(.taskDueDate)
        }
        return operations
    }

    private static func isTaskListRequest(_ text: String) -> Bool {
        text.contains("task list")
            || text.contains("list tasks")
            || text.contains("show tasks")
            || text.contains("タスク一覧")
            || text.contains("タスクを一覧")
            || text.contains("タスクを見せ")
    }

    private static func requestsDueDateChange(_ text: String) -> Bool {
        text.contains("due")
            || text.contains("deadline")
            || text.contains("期限")
            || text.contains("締切")
    }

    private static func refersToTask(_ text: String) -> Bool {
        LocalTriageRouter.explicitTaskID(in: text) != nil
            || text.contains("task")
            || text.contains("タスク")
            || text.contains("それ")
            || text.contains("that")
            || requestedOrdinal(in: text) != nil
    }

    private static func requestedPriority(in text: String) -> String? {
        if text.contains("high priority")
            || text.contains("priority high")
            || text.contains("優先度を高")
            || text.contains("優先度高")
        {
            return "high"
        }
        if text.contains("medium priority")
            || text.contains("priority medium")
            || text.contains("優先度を中")
            || text.contains("優先度中")
        {
            return "medium"
        }
        if text.contains("low priority")
            || text.contains("priority low")
            || text.contains("優先度を低")
            || text.contains("優先度低")
        {
            return "low"
        }
        return nil
    }

    private static func requestedOrdinal(in text: String) -> Int? {
        let tokens: [(String, Int)] = [
            ("first", 0), ("1st", 0), ("一つ目", 0), ("1つ目", 0),
            ("second", 1), ("2nd", 1), ("二つ目", 1), ("2つ目", 1),
            ("third", 2), ("3rd", 2), ("三つ目", 2), ("3つ目", 2),
        ]
        return tokens.first { text.contains($0.0) }?.1
    }

    private func isoDate(in text: String) -> String? {
        let pattern = #"\b\d{4}-\d{2}-\d{2}\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range, in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    private func naturalDueDate(
        in text: String,
        at date: Date,
        timeZoneIdentifier: String
    ) throws -> String? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw VoiceTaskConversationCommandPreparerError.invalidTimeZoneIdentifier
        }
        return QuickAddDueDateParser.parse(
            "task \(text)",
            now: date,
            timeZone: timeZone
        ).dueAt.map(DeadlineDateParser.string(from:))
    }
}
