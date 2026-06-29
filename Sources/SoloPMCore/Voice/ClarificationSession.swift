import Foundation

public enum ClarificationSlot: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case project
    case dueDate
    case destination
    case documentScope
    case executionApproval
}

public enum ClarificationValue: Codable, Equatable, Sendable {
    case text(String)
    case approval(Bool)
}

public struct ClarificationQuestion: Codable, Equatable, Sendable {
    public var slot: ClarificationSlot
    public var prompt: String

    public init(slot: ClarificationSlot, prompt: String) {
        self.slot = slot
        self.prompt = prompt
    }
}

public struct ClarificationResult: Codable, Equatable, Sendable {
    public var originalUtterance: String
    public var answers: [ClarificationSlot: ClarificationValue]

    public init(originalUtterance: String, answers: [ClarificationSlot: ClarificationValue]) {
        self.originalUtterance = originalUtterance
        self.answers = answers
    }
}

public enum ClarificationSessionState: Codable, Equatable, Sendable {
    case needsClarification(question: ClarificationQuestion, remainingSlots: [ClarificationSlot])
    case resolved(result: ClarificationResult)
}

public struct ClarificationSession: Codable, Equatable, Sendable {
    public let originalUtterance: String
    public let requiredSlots: [ClarificationSlot]
    public private(set) var answers: [ClarificationSlot: ClarificationValue]

    public init(
        originalUtterance: String,
        requiredSlots: [ClarificationSlot] = [.project, .dueDate, .executionApproval]
    ) {
        self.originalUtterance = originalUtterance
        self.requiredSlots = Self.unique(requiredSlots)
        self.answers = [:]
    }

    private var remainingSlots: [ClarificationSlot] {
        requiredSlots.filter { answers[$0] == nil }
    }

    public var state: ClarificationSessionState {
        guard let currentSlot = remainingSlots.first else {
            return .resolved(result: ClarificationResult(originalUtterance: originalUtterance, answers: answers))
        }
        return .needsClarification(
            question: question(for: currentSlot),
            remainingSlots: remainingSlots
        )
    }

    public mutating func answer(_ response: String) -> ClarificationSessionState {
        guard let currentSlot = remainingSlots.first else {
            return state
        }

        guard let parsedValue = parse(currentSlot, from: response) else {
            // Keep the same question when input is empty or ambiguous.
            // This avoids unsafe fallback by pretending a missing required value is present.
            return .needsClarification(
                question: question(for: currentSlot),
                remainingSlots: remainingSlots
            )
        }

        answers[currentSlot] = parsedValue
        return state
    }

    private func question(for slot: ClarificationSlot) -> ClarificationQuestion {
        switch slot {
        case .project:
            return ClarificationQuestion(
                slot: .project,
                prompt: "Which project should this request belong to?"
            )
        case .dueDate:
            return ClarificationQuestion(
                slot: .dueDate,
                prompt: "When is the due date for this request?"
            )
        case .destination:
            return ClarificationQuestion(
                slot: .destination,
                prompt: "Which destination should this request use?"
            )
        case .documentScope:
            return ClarificationQuestion(
                slot: .documentScope,
                prompt: "Which document scope should be used?"
            )
        case .executionApproval:
            return ClarificationQuestion(
                slot: .executionApproval,
                prompt: "Do you approve running this execution?"
            )
        }
    }

    private func parse(_ slot: ClarificationSlot, from response: String) -> ClarificationValue? {
        let normalized = response.voiceClarificationNormalized
        let trimmed = response.trimmedForClarification
        switch slot {
        case .project, .destination, .documentScope:
            return parseTextSlotValue(from: trimmed)
        case .dueDate:
            return parseDueDate(from: normalized, raw: trimmed)
        case .executionApproval:
            return parseExecutionApproval(from: normalized)
        }
    }

    private func parseTextSlotValue(from response: String) -> ClarificationValue? {
        let trimmed = response.trimmedForClarification
        guard !trimmed.isEmpty, !trimmed.isClarificationFallback else {
            return nil
        }

        return .text(trimmed)
    }

    private func parseDueDate(from response: String, raw: String) -> ClarificationValue? {
        let dateSignals = [
            "today", "tomorrow", "next week", "this week", "friday", "monday", "tuesday", "wednesday",
            "thursday", "saturday", "sunday", "明日", "今日", "来週", "今週", "金曜", "月曜", "火曜", "水曜", "木曜", "土曜", "日曜", "明後日"
        ]

        if raw.isClarificationFallback || raw.isEmpty {
            return nil
        }
        if response.matches(dateSignals: dateSignals) || response.looksLikeDateLiteral {
            return .text(raw)
        }
        return nil
    }

    private func parseExecutionApproval(from response: String) -> ClarificationValue? {
        let normalized = response.trimmedForClarification
        guard !normalized.isClarificationFallback else {
            return nil
        }

        let yesSignals = [
            "yes", "yeah", "y", "ok", "okay", "approve", "approved", "sure", "go ahead", "please do",
            "はい", "承認", "承認する", "できます"
        ]
        let noSignals = [
            "no", "nah", "nope", "not now", "not yet", "not approved", "do not approve",
            "don't approve", "do not run", "don't run", "reject", "rejected", "やめ", "やめて",
            "不要", "いりません", "だめ", "承認しない", "承認しません", "実行しない"
        ]

        // Negative approval phrases can contain positive words such as
        // "approved" or "承認", so rejection must be checked first.
        if normalized.matches(anyOf: noSignals) {
            return .approval(false)
        }
        if normalized.matches(anyOf: yesSignals) {
            return .approval(true)
        }

        return nil
    }

    private static func unique(_ slots: [ClarificationSlot]) -> [ClarificationSlot] {
        var seen = Set<ClarificationSlot>()
        return slots.filter {
            if seen.insert($0).inserted {
                return true
            }
            return false
        }
    }
}

private extension String {
    var voiceClarificationNormalized: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var trimmedForClarification: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isClarificationFallback: Bool {
        let normalized = voiceClarificationNormalized
        let unknownSignals = [
            "", "?", "？", "わからない", "分からない", "不明", "不明です", "なんとなく", "maybe", "not sure", "idk"
        ]
        return unknownSignals.contains(normalized)
    }

    func matches(anyOf candidates: [String]) -> Bool {
        candidates.contains(where: { contains($0) })
    }

    func matches(dateSignals: [String]) -> Bool {
        dateSignals.contains(where: { contains($0) })
    }

    var looksLikeDateLiteral: Bool {
        let regexes = [
            #"\d{4}[-/]\d{1,2}[-/]\d{1,2}"#,
            #"\d{1,2}/\d{1,2}"#,
            #"\d{1,2}月\d{1,2}日"#
        ]

        return regexes.contains { pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            return expression.firstMatch(
                in: self,
                options: [],
                range: NSRange(location: 0, length: utf16.count)
            ) != nil
        }
    }
}
