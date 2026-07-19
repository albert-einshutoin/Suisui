import Foundation

/// Collects local workspace context for a free-form question so an
/// `AnswerGeneratingLLMProvider` can answer without inventing work items.
/// Deadline pressure (overdue, due today) always leads, followed by keyword
/// matches on open tasks and projects, then knowledge frame FTS hits.
public final class WorkspaceQuestionRetriever: @unchecked Sendable {
    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore
    private let knowledgeFrameStore: SQLiteKnowledgeFrameStore
    private let dateProvider: any DateProvider
    private let settings: AppSettings

    public init(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore,
        knowledgeFrameStore: SQLiteKnowledgeFrameStore,
        dateProvider: any DateProvider = SystemDateProvider(),
        settings: AppSettings = .default
    ) {
        self.projectStore = projectStore
        self.taskStore = taskStore
        self.knowledgeFrameStore = knowledgeFrameStore
        self.dateProvider = dateProvider
        self.settings = settings
    }

    public func retrieve(question: String, limit: Int = 8) throws -> [WorkspaceContextSnippet] {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty, limit > 0 else {
            return []
        }

        var snippets: [WorkspaceContextSnippet] = []
        var seenKeys = Set<String>()

        func append(kind: String, title: String, detail: String?) {
            guard snippets.count < limit else {
                return
            }
            guard seenKeys.insert("\(kind)|\(title)").inserted else {
                return
            }
            snippets.append(WorkspaceContextSnippet(kind: kind, title: title, detail: detail))
        }

        let deadlineService = DeadlineQueryService(
            projectStore: projectStore,
            taskStore: taskStore,
            dateProvider: dateProvider,
            settings: settings
        )
        let summary = try deadlineService.summary()
        for item in summary.overdue {
            append(
                kind: item.kind.rawValue,
                title: item.title,
                detail: "overdue, due \(Self.dayLabel(for: item.dueAt, timeZoneIdentifier: settings.timeZoneIdentifier))"
            )
        }
        for item in summary.today {
            append(kind: item.kind.rawValue, title: item.title, detail: "due today")
        }

        let tokens = Self.matchTokens(for: trimmedQuestion)
        if !tokens.isEmpty {
            for task in try taskStore.listAll() where task.status != "completed" {
                if Self.matches(tokens: tokens, in: [task.title, task.detail ?? ""]) {
                    append(kind: "task", title: task.title, detail: task.detail.map(Self.bodyPreview))
                }
            }
            for project in try projectStore.list() where Self.matches(tokens: tokens, in: [project.title]) {
                append(kind: "project", title: project.title, detail: project.deadline.map { "deadline \($0)" })
            }
        }

        // FTS syntax problems must degrade to "no knowledge context", never
        // fail the whole question, so frame search errors are swallowed.
        var frames = (try? knowledgeFrameStore.search(query: trimmedQuestion)) ?? []
        if frames.isEmpty {
            // The full question rarely matches as one FTS phrase, so fall back
            // to individual word tokens (CJK 2-grams are skipped because the
            // default FTS tokenizer cannot match CJK substrings).
            var frameIDs = Set<Int64>()
            for token in Self.wordTokens(for: trimmedQuestion) {
                for frame in (try? knowledgeFrameStore.search(query: token)) ?? []
                    where frameIDs.insert(frame.id).inserted {
                    frames.append(frame)
                }
            }
        }
        for frame in frames {
            append(kind: "knowledge", title: frame.name, detail: Self.bodyPreview(frame.body))
        }

        return snippets
    }

    // MARK: - Matching

    static func matchTokens(for question: String) -> [String] {
        var tokens = wordTokens(for: question)

        // Japanese questions are not space-separated, so CJK runs contribute
        // sliding 2-grams that "contains" matching can find inside titles.
        let lowered = question.lowercased()
        for run in cjkRuns(in: lowered) {
            let characters = Array(run)
            guard characters.count >= 2 else {
                continue
            }
            for index in 0..<(characters.count - 1) {
                tokens.append(String(characters[index...(index + 1)]))
            }
        }

        var uniqueTokens: [String] = []
        var seen = Set<String>()
        for token in tokens where seen.insert(token).inserted {
            uniqueTokens.append(token)
        }
        return uniqueTokens
    }

    private static func wordTokens(for question: String) -> [String] {
        question
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private static func matches(tokens: [String], in fields: [String]) -> Bool {
        let haystack = fields.joined(separator: "\n").lowercased()
        guard !haystack.isEmpty else {
            return false
        }
        return tokens.contains { haystack.contains($0) }
    }

    private static func cjkRuns(in text: String) -> [String] {
        var runs: [String] = []
        var currentRun = ""
        for character in text {
            if !character.unicodeScalars.isEmpty, character.unicodeScalars.allSatisfy(isCJK) {
                currentRun.append(character)
            } else if !currentRun.isEmpty {
                runs.append(currentRun)
                currentRun = ""
            }
        }
        if !currentRun.isEmpty {
            runs.append(currentRun)
        }
        return runs
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, // Hiragana and Katakana
             0x3400...0x4DBF, // CJK Unified Ideographs Extension A
             0x4E00...0x9FFF, // CJK Unified Ideographs
             0xF900...0xFAFF, // CJK Compatibility Ideographs
             0xFF66...0xFF9D: // Half-width Katakana
            return true
        default:
            return false
        }
    }

    // MARK: - Formatting

    private static let bodyPreviewLimit = 160

    private static func bodyPreview(_ body: String) -> String {
        let flattened = body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > bodyPreviewLimit else {
            return flattened
        }
        return "\(flattened.prefix(bodyPreviewLimit))..."
    }

    private static func dayLabel(for date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
