import Foundation

/// One retrieved piece of local workspace context that may inform a
/// workspace answer. `kind` is "task", "project", or "knowledge".
public struct WorkspaceContextSnippet: Equatable, Sendable {
    public var kind: String
    public var title: String
    public var detail: String?

    public init(kind: String, title: String, detail: String? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct WorkspaceAnswerRequest: Equatable, Sendable {
    public var question: String
    public var contextSnippets: [WorkspaceContextSnippet]
    public var currentDate: Date
    public var timeZoneIdentifier: String
    public var languageCode: String

    public init(
        question: String,
        contextSnippets: [WorkspaceContextSnippet] = [],
        currentDate: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier,
        languageCode: String = "en"
    ) {
        self.question = question
        self.contextSnippets = contextSnippets
        self.currentDate = currentDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.languageCode = languageCode
    }
}

/// Providers that can answer a free-form question about local work using
/// only the retrieved workspace context, returning short speakable text.
public protocol AnswerGeneratingLLMProvider: LLMProvider {
    func generateAnswer(for request: WorkspaceAnswerRequest) async throws -> String
}

public enum WorkspaceAnswerPromptBuilder {
    public static func buildPrompt(for request: WorkspaceAnswerRequest) -> PlanningPrompt {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let system = """
        You are Suisui's local work assistant. \
        Answer ONLY from the provided workspace context; if it is insufficient, say so briefly. \
        Answer in at most 280 characters of plain speakable text, no markdown or lists, \
        in language '\(request.languageCode)'. \
        Never invent tasks, projects, or dates.
        """

        let context = request.contextSnippets.isEmpty
            ? "No workspace context was found."
            : request.contextSnippets.enumerated()
                .map { index, snippet in formatSnippet(snippet, number: index + 1) }
                .joined(separator: "\n")

        let user = """
        Current date: \(dateFormatter.string(from: request.currentDate))
        Time zone: \(request.timeZoneIdentifier)

        Workspace context:
        \(context)

        Question: \(request.question)
        """

        return PlanningPrompt(system: system, user: user)
    }

    private static func formatSnippet(_ snippet: WorkspaceContextSnippet, number: Int) -> String {
        let title = redacted(snippet.title)
        guard let detail = snippet.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty else {
            return "[\(number)] (\(snippet.kind)) \(title)"
        }
        return "[\(number)] (\(snippet.kind)) \(title) — \(redacted(detail))"
    }

    /// Same composition order as `DailyPlanningReviewReadoutBuilder`: secret
    /// patterns first, then local filesystem paths.
    private static func redacted(_ text: String) -> String {
        LocalPathRedactor.redact(DeveloperSecretRedactor().redact(text).text)
    }
}
