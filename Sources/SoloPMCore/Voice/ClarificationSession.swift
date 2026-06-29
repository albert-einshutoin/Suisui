import Foundation

public enum ClarificationSlot: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case taskTitle = "task_title"
    case project
    case repository
    case dueDate = "due_date"
    case destination
    case documentSource = "document_source"
    case executionScope = "execution_scope"
    case executionApproval = "execution_approval"
}

public enum ClarificationValue: Codable, Equatable, Sendable {
    case text(String)
    case approval(Bool)

    public var planningValue: String {
        switch self {
        case .text(let value):
            value
        case .approval(let isApproved):
            isApproved ? "approved" : "not approved"
        }
    }
}

public enum ClarificationAnswerStatus: Equatable, Sendable {
    case needsClarification
    case resolved
}

public enum ClarificationInputMode: String, Codable, Equatable, Sendable {
    case typed
    case voice
}

public struct ClarificationQuestion: Codable, Equatable, Sendable {
    public var slot: ClarificationSlot
    public var prompt: String

    public init(slot: ClarificationSlot, prompt: String) {
        self.slot = slot
        self.prompt = prompt
    }
}

public struct ClarificationTurn: Codable, Equatable, Sendable {
    public var slot: ClarificationSlot
    public var question: ClarificationQuestion
    public var response: String
    public var answer: ClarificationValue
    public var inputMode: ClarificationInputMode

    public init(
        slot: ClarificationSlot,
        question: ClarificationQuestion,
        response: String,
        answer: ClarificationValue,
        inputMode: ClarificationInputMode = .typed
    ) {
        self.slot = slot
        self.question = question
        self.response = response
        self.answer = answer
        self.inputMode = inputMode
    }
}

public struct ClarificationResult: Codable, Equatable, Sendable {
    public var originalTranscript: String
    public var resolvedRoute: VoiceCommandRoutingResult
    public var answers: [ClarificationSlot: ClarificationValue]
    public var turns: [ClarificationTurn]

    public init(
        originalTranscript: String,
        resolvedRoute: VoiceCommandRoutingResult,
        answers: [ClarificationSlot: ClarificationValue],
        turns: [ClarificationTurn]
    ) {
        self.originalTranscript = originalTranscript
        self.resolvedRoute = resolvedRoute
        self.answers = answers
        self.turns = turns
    }
}

public struct ClarificationSession: Codable, Equatable, Sendable {
    public let route: VoiceCommandRoutingResult
    public let originalTranscript: String
    public let requiredSlots: [ClarificationSlot]
    public private(set) var answers: [ClarificationSlot: ClarificationValue]
    public private(set) var turns: [ClarificationTurn]

    public init(route: VoiceCommandRoutingResult, requiredSlots: [ClarificationSlot]? = nil) {
        self.route = route
        originalTranscript = route.originalTranscript
        self.requiredSlots = Self.unique(requiredSlots ?? Self.inferRequiredSlots(from: route))
        answers = [:]
        turns = []
    }

    public var currentQuestion: ClarificationQuestion? {
        remainingSlots.first.map(question(for:))
    }

    public var result: ClarificationResult? {
        guard remainingSlots.isEmpty else {
            return nil
        }
        return ClarificationResult(
            originalTranscript: originalTranscript,
            resolvedRoute: resolvedRoute(),
            answers: answers,
            turns: turns
        )
    }

    @discardableResult
    public mutating func answer(
        _ response: String,
        inputMode: ClarificationInputMode = .typed
    ) -> ClarificationAnswerStatus {
        guard let slot = remainingSlots.first else {
            return .resolved
        }
        let question = question(for: slot)
        guard let parsedAnswer = parseAnswer(response, for: slot) else {
            return .needsClarification
        }

        answers[slot] = parsedAnswer
        turns.append(
            ClarificationTurn(
                slot: slot,
                question: question,
                response: response.trimmedForClarification,
                answer: parsedAnswer,
                inputMode: inputMode
            )
        )

        return remainingSlots.isEmpty ? .resolved : .needsClarification
    }

    private var remainingSlots: [ClarificationSlot] {
        requiredSlots.filter { answers[$0] == nil }
    }

    private func resolvedRoute() -> VoiceCommandRoutingResult {
        let resolvedIntent = route.intent == .clarify ? Self.inferResolvedIntent(slots: requiredSlots, transcript: originalTranscript) : route.intent
        let trail = turns.map {
            VoiceCommandClarificationTrailItem(
                slot: $0.slot.rawValue,
                question: $0.question.prompt,
                answer: $0.answer.planningValue,
                inputMode: $0.inputMode.rawValue
            )
        }
        return VoiceCommandRoutingResult(
            originalTranscript: route.originalTranscript,
            normalizedTranscript: route.normalizedTranscript,
            intent: resolvedIntent,
            interpretationSummary: "Resolved \(resolvedIntent.rawValue) after clarification.",
            confidence: max(route.confidence, 0.78),
            decision: .reviewOnly,
            clarificationReason: route.clarificationReason,
            reviewOnly: true,
            matchedSignals: route.matchedSignals,
            clarificationTrail: trail
        )
    }

    private func question(for slot: ClarificationSlot) -> ClarificationQuestion {
        switch slot {
        case .taskTitle:
            ClarificationQuestion(slot: .taskTitle, prompt: "What should the task be called?")
        case .project:
            ClarificationQuestion(slot: .project, prompt: "Which project should this belong to?")
        case .repository:
            ClarificationQuestion(slot: .repository, prompt: "Which repository or project directory should this use?")
        case .dueDate:
            ClarificationQuestion(slot: .dueDate, prompt: "When is the due date?")
        case .destination:
            ClarificationQuestion(slot: .destination, prompt: "Which destination should receive the draft?")
        case .documentSource:
            ClarificationQuestion(slot: .documentSource, prompt: "Which source documents should be used?")
        case .executionScope:
            ClarificationQuestion(slot: .executionScope, prompt: "What scope should SoloPM prepare for review?")
        case .executionApproval:
            ClarificationQuestion(slot: .executionApproval, prompt: "Should SoloPM keep this as a reviewed draft?")
        }
    }

    private func parseAnswer(_ response: String, for slot: ClarificationSlot) -> ClarificationValue? {
        let trimmed = response.trimmedForClarification
        guard !trimmed.isClarificationFallback else {
            return nil
        }

        switch slot {
        case .taskTitle, .project, .repository, .destination, .documentSource, .executionScope:
            return trimmed.isEmpty ? nil : .text(trimmed)
        case .dueDate:
            return trimmed.isDateClarificationAnswer ? .text(trimmed) : nil
        case .executionApproval:
            return trimmed.executionApprovalClarification
        }
    }

    private static func inferRequiredSlots(from route: VoiceCommandRoutingResult) -> [ClarificationSlot] {
        let transcript = route.normalizedTranscript.voiceClarificationNormalized
        switch route.intent {
        case .taskCreate, .taskTriage:
            return taskSlots(for: transcript)
        case .dailyPlanningReview:
            return [.project]
        case .schedulePlan:
            return transcript.containsDateSignal ? [.project] : [.dueDate, .project]
        case .documentBrief:
            return [.documentSource]
        case .developmentPRWorkflow:
            return [.repository, .executionScope]
        case .notificationDraft:
            return [.destination]
        case .statusAsk:
            return [.project]
        case .clarify:
            return clarifySlots(for: transcript)
        }
    }

    private static func clarifySlots(for transcript: String) -> [ClarificationSlot] {
        if transcript.containsAny(["pr", "pull request", "branch", "ブランチ", "プルリク"]) {
            return [.repository, .executionScope]
        }
        if transcript.containsAny(["資料", "document", "docs", "brief", "meeting", "mtg", "まとめ"]) {
            return [.documentSource]
        }
        if transcript.containsAny(["通知", "slack", "line", "discord", "連絡"]) {
            return [.destination]
        }
        if transcript.containsAny(["run", "execute", "実行", "承認", "approval", "review"]) {
            return [.executionScope, .executionApproval]
        }
        return taskSlots(for: transcript)
    }

    private static func taskSlots(for transcript: String) -> [ClarificationSlot] {
        var slots: [ClarificationSlot] = []
        if !transcript.containsTaskSpecificTitleSignal {
            slots.append(.taskTitle)
        }
        if !transcript.containsProjectSignal {
            slots.append(.project)
        }
        return slots.isEmpty ? [.project] : slots
    }

    private static func inferResolvedIntent(slots: [ClarificationSlot], transcript: String) -> VoiceCommandIntentKind {
        if slots.contains(.destination) {
            return .notificationDraft
        }
        if slots.contains(.documentSource) {
            return .documentBrief
        }
        if slots.contains(.repository) || slots.contains(.executionScope) || transcript.voiceClarificationNormalized.containsAny(["pr", "branch", "プルリク"]) {
            return .developmentPRWorkflow
        }
        return .taskCreate
    }

    private static func unique(_ slots: [ClarificationSlot]) -> [ClarificationSlot] {
        var seen = Set<ClarificationSlot>()
        return slots.filter { seen.insert($0).inserted }
    }
}

private extension String {
    var trimmedForClarification: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var voiceClarificationNormalized: String {
        trimmedForClarification
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var isClarificationFallback: Bool {
        let normalized = voiceClarificationNormalized
        return ["", "?", "？", "わからない", "分からない", "不明", "なんとなく", "maybe", "not sure", "idk"].contains(normalized)
    }

    var isDateClarificationAnswer: Bool {
        let normalized = voiceClarificationNormalized
        let dateSignals = [
            "today", "tomorrow", "next week", "this week", "monday", "tuesday", "wednesday",
            "thursday", "friday", "saturday", "sunday", "今日", "明日", "明後日", "今週", "来週",
            "月曜", "火曜", "水曜", "木曜", "金曜", "土曜", "日曜"
        ]
        if normalized.containsAny(dateSignals) {
            return true
        }
        let patterns = [
            #"\d{4}[-/]\d{1,2}[-/]\d{1,2}"#,
            #"\d{1,2}/\d{1,2}"#,
            #"\d{1,2}月\d{1,2}日"#
        ]
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            return regex.firstMatch(in: normalized, range: NSRange(location: 0, length: normalized.utf16.count)) != nil
        }
    }

    var executionApprovalClarification: ClarificationValue? {
        let normalized = voiceClarificationNormalized
        let noSignals = [
            "no", "nah", "nope", "not now", "not yet", "not approved", "do not approve",
            "don't approve", "reject", "rejected", "やめ", "不要", "だめ", "承認しない",
            "承認しません", "承認はしない", "承認はしません", "実行しない"
        ]
        let yesSignals = [
            "yes", "yeah", "ok", "okay", "approve", "approved", "sure", "go ahead",
            "はい", "承認", "承認する", "大丈夫"
        ]

        // Rejection phrases often contain "approved" or "承認"; check them first
        // so a denial cannot be converted into an approval by substring order.
        if normalized.containsAny(noSignals) {
            return .approval(false)
        }
        if normalized.containsAny(yesSignals) {
            return .approval(true)
        }
        return nil
    }

    var containsDateSignal: Bool {
        isDateClarificationAnswer
    }

    var containsProjectSignal: Bool {
        containsAny(["project", "プロジェクト"])
    }

    var containsTaskSpecificTitleSignal: Bool {
        containsAny(["task", "todo", "タスク", "やること", "作成", "create"])
    }

    func containsAny(_ signals: [String]) -> Bool {
        let normalized = voiceClarificationNormalized
        return signals.contains { normalized.contains($0) }
    }
}
