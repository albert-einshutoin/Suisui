import Foundation

public enum VoiceCommandIntentKind: String, Codable, CaseIterable, Equatable, Sendable {
    case taskCreate = "task.create"
    case taskTriage = "task.triage"
    case schedulePlan = "schedule.plan"
    case documentBrief = "document.brief"
    case developmentPRWorkflow = "development.pr_workflow"
    case notificationDraft = "notification.draft"
    case statusAsk = "status.ask"
    case clarify

    public var displayName: String {
        switch self {
        case .taskCreate:
            "Create task"
        case .taskTriage:
            "Triage tasks"
        case .schedulePlan:
            "Plan schedule"
        case .documentBrief:
            "Draft brief"
        case .developmentPRWorkflow:
            "Prepare PR workflow"
        case .notificationDraft:
            "Draft notification"
        case .statusAsk:
            "Ask status"
        case .clarify:
            "Needs clarification"
        }
    }
}

public enum VoiceCommandRoutingDecision: String, Codable, Equatable, Sendable {
    case reviewOnly = "review_only"
    case clarifyRequired = "clarify_required"
}

public struct VoiceCommandRoutingResult: Codable, Equatable, Sendable {
    public var originalTranscript: String
    public var normalizedTranscript: String
    public var intent: VoiceCommandIntentKind
    public var interpretationSummary: String
    public var confidence: Double
    public var decision: VoiceCommandRoutingDecision
    public var clarificationReason: String?
    public var reviewOnly: Bool
    public var matchedSignals: [String]

    public var needsClarification: Bool {
        decision == .clarifyRequired
    }

    public init(
        originalTranscript: String,
        normalizedTranscript: String,
        intent: VoiceCommandIntentKind,
        interpretationSummary: String,
        confidence: Double,
        decision: VoiceCommandRoutingDecision,
        clarificationReason: String? = nil,
        reviewOnly: Bool = true,
        matchedSignals: [String] = []
    ) {
        self.originalTranscript = originalTranscript
        self.normalizedTranscript = normalizedTranscript
        self.intent = intent
        self.interpretationSummary = interpretationSummary
        self.confidence = confidence
        self.decision = decision
        self.clarificationReason = clarificationReason
        self.reviewOnly = reviewOnly
        self.matchedSignals = matchedSignals
    }

    public var planningInput: String {
        let reason = clarificationReason.map { "\nClarification reason: \($0)" } ?? ""
        let signals = matchedSignals.isEmpty ? "none" : matchedSignals.joined(separator: ", ")
        return """
        Voice command intent: \(intent.rawValue)
        Confidence: \(String(format: "%.2f", confidence))
        Review boundary: \(reviewOnly ? "review-only" : "none")
        Interpretation summary: \(interpretationSummary)\(reason)
        Matched signals: \(signals)

        Original transcript:
        \(originalTranscript)
        """
    }
}

public protocol VoiceCommandRouting: Sendable {
    func route(transcript: String) -> VoiceCommandRoutingResult
}

public struct VoiceCommandRouter: VoiceCommandRouting {
    private struct WeightedSignal: Sendable {
        var phrase: String
        var weight: Double
    }

    private struct RouteCandidate: Sendable {
        var intent: VoiceCommandIntentKind
        var signals: [WeightedSignal]
        var summary: String
    }

    private struct RouteScore: Sendable {
        var intent: VoiceCommandIntentKind
        var score: Double
        var matchedSignals: [String]
        var summary: String
    }

    private let candidates: [RouteCandidate]
    private let unsafeExternalSignals: [String]
    private let unsafeDestructiveSignals: [String]
    private let unsafeExecutionSignals: [String]

    public init() {
        candidates = [
            RouteCandidate(
                intent: .taskCreate,
                signals: [
                    .init(phrase: "task", weight: 1.6),
                    .init(phrase: "todo", weight: 1.4),
                    .init(phrase: "タスク", weight: 1.8),
                    .init(phrase: "やること", weight: 1.6),
                    .init(phrase: "作成", weight: 1.3),
                    .init(phrase: "追加", weight: 1.2),
                    .init(phrase: "create", weight: 1.2),
                    .init(phrase: "add", weight: 1.0)
                ],
                summary: "Route as task.create for a reviewable local task draft."
            ),
            RouteCandidate(
                intent: .taskTriage,
                signals: [
                    .init(phrase: "triage", weight: 1.8),
                    .init(phrase: "prioritize", weight: 1.7),
                    .init(phrase: "priority", weight: 1.3),
                    .init(phrase: "inbox", weight: 1.5),
                    .init(phrase: "インボックス", weight: 1.6),
                    .init(phrase: "整理", weight: 1.5),
                    .init(phrase: "仕分け", weight: 1.8),
                    .init(phrase: "優先順位", weight: 1.7)
                ],
                summary: "Route as task.triage for an Inbox or priority review."
            ),
            RouteCandidate(
                intent: .schedulePlan,
                signals: [
                    .init(phrase: "schedule", weight: 1.7),
                    .init(phrase: "calendar", weight: 1.3),
                    .init(phrase: "plan my", weight: 1.5),
                    .init(phrase: "today", weight: 1.0),
                    .init(phrase: "tomorrow", weight: 1.0),
                    .init(phrase: "予定", weight: 1.7),
                    .init(phrase: "スケジュール", weight: 1.7),
                    .init(phrase: "日程", weight: 1.5),
                    .init(phrase: "今日", weight: 1.0),
                    .init(phrase: "明日", weight: 1.0),
                    .init(phrase: "時間", weight: 1.0),
                    .init(phrase: "カレンダー", weight: 1.3)
                ],
                summary: "Route as schedule.plan for a reviewable day or calendar plan."
            ),
            RouteCandidate(
                intent: .documentBrief,
                signals: [
                    .init(phrase: "document", weight: 1.6),
                    .init(phrase: "brief", weight: 1.8),
                    .init(phrase: "meeting", weight: 1.3),
                    .init(phrase: "minutes", weight: 1.6),
                    .init(phrase: "doc", weight: 1.1),
                    .init(phrase: "資料", weight: 1.7),
                    .init(phrase: "ドキュメント", weight: 1.7),
                    .init(phrase: "議事録", weight: 1.8),
                    .init(phrase: "会議", weight: 1.3),
                    .init(phrase: "mtg", weight: 1.4),
                    .init(phrase: "まとめ", weight: 1.0)
                ],
                summary: "Route as document.brief for a reviewable document or meeting brief."
            ),
            RouteCandidate(
                intent: .developmentPRWorkflow,
                signals: [
                    .init(phrase: "pull request", weight: 2.0),
                    .init(phrase: "pr", weight: 1.6),
                    .init(phrase: "branch", weight: 1.5),
                    .init(phrase: "github", weight: 1.3),
                    .init(phrase: "issue", weight: 1.2),
                    .init(phrase: "workflow", weight: 1.0),
                    .init(phrase: "ブランチ", weight: 1.6),
                    .init(phrase: "プルリク", weight: 1.8),
                    .init(phrase: "開発", weight: 1.4),
                    .init(phrase: "実装", weight: 1.4),
                    .init(phrase: "コード", weight: 1.1)
                ],
                summary: "Route as development.pr_workflow for a reviewable branch or PR workflow."
            ),
            RouteCandidate(
                intent: .notificationDraft,
                signals: [
                    .init(phrase: "notification", weight: 1.7),
                    .init(phrase: "notify", weight: 1.4),
                    .init(phrase: "message", weight: 1.2),
                    .init(phrase: "draft", weight: 1.7),
                    .init(phrase: "slack", weight: 1.4),
                    .init(phrase: "line", weight: 1.2),
                    .init(phrase: "discord", weight: 1.4),
                    .init(phrase: "通知", weight: 1.7),
                    .init(phrase: "連絡", weight: 1.3),
                    .init(phrase: "下書き", weight: 1.8)
                ],
                summary: "Route as notification.draft without sending to external services."
            ),
            RouteCandidate(
                intent: .statusAsk,
                signals: [
                    .init(phrase: "status", weight: 1.6),
                    .init(phrase: "progress", weight: 1.6),
                    .init(phrase: "how many", weight: 1.7),
                    .init(phrase: "show", weight: 0.9),
                    .init(phrase: "状況", weight: 1.7),
                    .init(phrase: "進捗", weight: 1.7),
                    .init(phrase: "何件", weight: 1.8),
                    .init(phrase: "件", weight: 1.0),
                    .init(phrase: "どう", weight: 0.9),
                    .init(phrase: "確認", weight: 1.0)
                ],
                summary: "Route as status.ask for a read-oriented progress or count question."
            )
        ]
        unsafeExternalSignals = [
            "send now",
            "post now",
            "send it",
            "send to",
            "今すぐ送信",
            "送信して",
            "送って",
            "投稿して",
            "勝手に送",
            "without review"
        ]
        unsafeDestructiveSignals = [
            "delete",
            "remove all",
            "wipe",
            "destroy",
            "削除",
            "消して",
            "全削除",
            "push to main",
            "deploy production",
            "本番反映"
        ]
        unsafeExecutionSignals = [
            "run without approval",
            "execute without approval",
            "run without review",
            "execute without review",
            "without approval",
            "without review",
            "承認なし",
            "未承認",
            "レビューなし",
            "確認なし",
            "勝手に実行"
        ]
    }

    public func route(transcript: String) -> VoiceCommandRoutingResult {
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return clarify(
                originalTranscript: transcript,
                normalizedTranscript: normalized,
                confidence: 0,
                reason: "Transcript is empty.",
                matchedSignals: []
            )
        }

        let folded = normalized
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if let unsafeSignal = firstMatchedSignal(in: folded, from: unsafeDestructiveSignals) {
            return clarify(
                originalTranscript: transcript,
                normalizedTranscript: normalized,
                confidence: 0.2,
                reason: "Destructive commands require explicit clarification before planning.",
                matchedSignals: [unsafeSignal]
            )
        }

        if let unsafeSignal = firstMatchedSignal(in: folded, from: unsafeExecutionSignals) {
            return clarify(
                originalTranscript: transcript,
                normalizedTranscript: normalized,
                confidence: 0.25,
                reason: "Execution without review or approval is not allowed in the personal MVP.",
                matchedSignals: [unsafeSignal]
            )
        }

        if containsExternalDestination(folded),
           let unsafeSignal = firstMatchedSignal(in: folded, from: unsafeExternalSignals) {
            return clarify(
                originalTranscript: transcript,
                normalizedTranscript: normalized,
                confidence: 0.28,
                reason: "Direct external sending must become a reviewed draft before any external action.",
                matchedSignals: [unsafeSignal]
            )
        }

        let scores = candidates
            .map { score(candidate: $0, foldedTranscript: folded) }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.intent.rawValue < rhs.intent.rawValue
                }
                return lhs.score > rhs.score
            }

        guard let best = scores.first, best.score >= 2.0 else {
            return clarify(
                originalTranscript: transcript,
                normalizedTranscript: normalized,
                confidence: 0.42,
                reason: "The transcript does not contain enough task, schedule, document, development, notification, or status signal.",
                matchedSignals: scores.first?.matchedSignals ?? []
            )
        }

        let runnerUpScore = scores.dropFirst().first?.score ?? 0
        let gap = best.score - runnerUpScore
        guard gap >= 0.65 || best.score >= 4.0 else {
            return clarify(
                originalTranscript: transcript,
                normalizedTranscript: normalized,
                confidence: 0.5,
                reason: "The transcript has overlapping intent signals and needs a clearer target.",
                matchedSignals: best.matchedSignals
            )
        }

        return VoiceCommandRoutingResult(
            originalTranscript: transcript,
            normalizedTranscript: normalized,
            intent: best.intent,
            interpretationSummary: best.summary,
            confidence: min(0.96, 0.58 + min(best.score, 4.0) * 0.08 + min(gap, 2.0) * 0.05),
            decision: .reviewOnly,
            reviewOnly: true,
            matchedSignals: best.matchedSignals
        )
    }

    private func score(candidate: RouteCandidate, foldedTranscript: String) -> RouteScore {
        let matches = candidate.signals.filter { signal in
            matchesSignal(signal.phrase, in: foldedTranscript)
        }
        let score = matches.reduce(0) { partialResult, signal in
            partialResult + signal.weight
        }
        return RouteScore(
            intent: candidate.intent,
            score: score,
            matchedSignals: matches.map(\.phrase),
            summary: candidate.summary
        )
    }

    private func firstMatchedSignal(in foldedTranscript: String, from signals: [String]) -> String? {
        signals.first { matchesSignal($0, in: foldedTranscript) }
    }

    private func containsExternalDestination(_ foldedTranscript: String) -> Bool {
        ["slack", "line", "discord", "mail", "email", "メール", "通知", "連絡"].contains {
            matchesSignal($0, in: foldedTranscript)
        }
    }

    private func matchesSignal(_ signal: String, in foldedTranscript: String) -> Bool {
        guard usesOnlyASCIILettersOrDigits(signal) else {
            return foldedTranscript.contains(signal)
        }

        var searchStart = foldedTranscript.startIndex
        while let range = foldedTranscript.range(of: signal, range: searchStart..<foldedTranscript.endIndex) {
            if isLatinWordBoundary(before: range.lowerBound, after: range.upperBound, in: foldedTranscript) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private func usesOnlyASCIILettersOrDigits(_ signal: String) -> Bool {
        signal.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (97...122).contains(value) || (48...57).contains(value)
        }
    }

    private func isLatinWordBoundary(
        before lowerBound: String.Index,
        after upperBound: String.Index,
        in text: String
    ) -> Bool {
        let hasLatinWordBefore = lowerBound > text.startIndex && isLatinWordCharacter(text[text.index(before: lowerBound)])
        let hasLatinWordAfter = upperBound < text.endIndex && isLatinWordCharacter(text[upperBound])
        return !hasLatinWordBefore && !hasLatinWordAfter
    }

    private func isLatinWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (65...90).contains(value)
                || (97...122).contains(value)
                || (48...57).contains(value)
                || value == 95
        }
    }

    private func clarify(
        originalTranscript: String,
        normalizedTranscript: String,
        confidence: Double,
        reason: String,
        matchedSignals: [String]
    ) -> VoiceCommandRoutingResult {
        // The local router deliberately fails closed. Voice commands are often
        // noisy, so unclear or unsafe transcripts must stop before provider or
        // external-action planning and become an explicit clarification target.
        VoiceCommandRoutingResult(
            originalTranscript: originalTranscript,
            normalizedTranscript: normalizedTranscript,
            intent: .clarify,
            interpretationSummary: "Route as clarify before creating an action plan.",
            confidence: confidence,
            decision: .clarifyRequired,
            clarificationReason: reason,
            reviewOnly: true,
            matchedSignals: matchedSignals
        )
    }
}
