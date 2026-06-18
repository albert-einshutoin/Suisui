import Foundation

public struct SecretRedactionReport: Equatable, Sendable {
    public var replacementCount: Int
    public var matchedPatternNames: [String]

    public init(replacementCount: Int, matchedPatternNames: [String]) {
        self.replacementCount = replacementCount
        self.matchedPatternNames = matchedPatternNames
    }
}

public struct SecretRedactionResult: Equatable, Sendable {
    public var text: String
    public var report: SecretRedactionReport

    public init(text: String, report: SecretRedactionReport) {
        self.text = text
        self.report = report
    }
}

public struct DeveloperSecretRedactor: Sendable {
    private struct CompiledPattern: @unchecked Sendable {
        var name: String
        var regex: NSRegularExpression
    }

    private static let defaultCompiledPatterns: [CompiledPattern] = [
        compiledPattern(name: "github_pat", expression: #"github_pat_[A-Za-z0-9_]{8,}"#),
        compiledPattern(name: "ghp", expression: #"ghp_[A-Za-z0-9_]{6,}"#),
        compiledPattern(name: "openai", expression: #"sk-(?:proj-)?[A-Za-z0-9_-]{8,}"#),
        compiledPattern(name: "aws_access_key", expression: #"AKIA[0-9A-Z]{16}"#),
        compiledPattern(name: "assignment", expression: #"(?i)\b(?:api[_-]?key|token|password|secret)\s*[:=]\s*\S+"#)
    ]

    private let patterns: [CompiledPattern]

    public init() {
        self.patterns = Self.defaultCompiledPatterns
    }

    public func redact(_ text: String) -> SecretRedactionResult {
        var redacted = text
        var replacementCount = 0
        var matchedPatternNames: [String] = []

        for pattern in patterns {
            let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
            let matches = pattern.regex.numberOfMatches(in: redacted, range: range)
            guard matches > 0 else {
                continue
            }

            matchedPatternNames.append(pattern.name)
            replacementCount += matches
            redacted = pattern.regex.stringByReplacingMatches(
                in: redacted,
                range: range,
                withTemplate: "[REDACTED_SECRET]"
            )
        }

        return SecretRedactionResult(
            text: redacted,
            report: SecretRedactionReport(
                replacementCount: replacementCount,
                matchedPatternNames: matchedPatternNames
            )
        )
    }

    private static func compiledPattern(name: String, expression: String) -> CompiledPattern {
        CompiledPattern(
            name: name,
            regex: try! NSRegularExpression(pattern: expression)
        )
    }
}

public struct DraftGenerationContext: Equatable, Sendable {
    public var repositoryName: String
    public var currentBranch: String
    public var gitStatusSummary: String
    public var commitSummaries: [String]
    public var taskSummaries: [String]
    public var generatedAt: Date

    public init(
        repositoryName: String,
        currentBranch: String,
        gitStatusSummary: String,
        commitSummaries: [String],
        taskSummaries: [String],
        generatedAt: Date = Date()
    ) {
        self.repositoryName = repositoryName
        self.currentBranch = currentBranch
        self.gitStatusSummary = gitStatusSummary
        self.commitSummaries = commitSummaries
        self.taskSummaries = taskSummaries
        self.generatedAt = generatedAt
    }
}

public enum DeveloperDraftKind: String, Equatable, Sendable {
    case readme
    case releaseNotes
}

public enum DeveloperDraftWritePolicy: Equatable, Sendable {
    case previewOnly(suggestedPath: String)
}

public enum DeveloperDraftSafetyNote: Equatable, Sendable {
    case previewOnly
    case doesNotOverwriteExistingReadme
    case secretsRedacted
}

public struct DeveloperDraftDocument: Equatable, Sendable {
    public var kind: DeveloperDraftKind
    public var title: String
    public var body: String
    public var writePolicy: DeveloperDraftWritePolicy
    public var safetyNotes: [DeveloperDraftSafetyNote]
    public var redactionReport: SecretRedactionReport

    public init(
        kind: DeveloperDraftKind,
        title: String,
        body: String,
        writePolicy: DeveloperDraftWritePolicy,
        safetyNotes: [DeveloperDraftSafetyNote],
        redactionReport: SecretRedactionReport
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.writePolicy = writePolicy
        self.safetyNotes = safetyNotes
        self.redactionReport = redactionReport
    }
}

public struct DeveloperDraftGenerator: Sendable {
    private let redactor: DeveloperSecretRedactor

    public init(redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()) {
        self.redactor = redactor
    }

    public func generateReadmeDraft(from context: DraftGenerationContext) -> DeveloperDraftDocument {
        let body = """
        # \(context.repositoryName)

        Generated draft: \(Self.iso8601String(for: context.generatedAt))

        ## Current State

        - Branch: \(context.currentBranch)
        - Git status: \(context.gitStatusSummary)

        ## Recent Changes

        \(bulletList(context.commitSummaries))

        ## Task Context

        \(bulletList(context.taskSummaries))
        """

        return makeDraft(
            kind: .readme,
            title: "\(context.repositoryName) README draft",
            body: body,
            suggestedPath: "README.draft.md",
            safetyNotes: [.previewOnly, .doesNotOverwriteExistingReadme]
        )
    }

    public func generateReleaseNoteDraft(from context: DraftGenerationContext) -> DeveloperDraftDocument {
        let body = """
        # Release Notes Draft

        Generated draft: \(Self.iso8601String(for: context.generatedAt))
        Repository: \(context.repositoryName)
        Branch: \(context.currentBranch)

        ## Changes

        \(bulletList(context.commitSummaries))

        ## Tasks

        \(bulletList(context.taskSummaries))

        ## Local Git Status

        \(context.gitStatusSummary)
        """

        return makeDraft(
            kind: .releaseNotes,
            title: "\(context.repositoryName) release notes draft",
            body: body,
            suggestedPath: "RELEASE_NOTES.draft.md",
            safetyNotes: [.previewOnly]
        )
    }

    private func makeDraft(
        kind: DeveloperDraftKind,
        title: String,
        body: String,
        suggestedPath: String,
        safetyNotes: [DeveloperDraftSafetyNote]
    ) -> DeveloperDraftDocument {
        let redaction = redactor.redact(body)
        var notes = safetyNotes
        if redaction.report.replacementCount > 0 {
            notes.append(.secretsRedacted)
        }

        return DeveloperDraftDocument(
            kind: kind,
            title: title,
            body: redaction.text,
            writePolicy: .previewOnly(suggestedPath: suggestedPath),
            safetyNotes: notes,
            redactionReport: redaction.report
        )
    }

    private func bulletList(_ values: [String]) -> String {
        if values.isEmpty {
            return "- (none)"
        }

        return values.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func iso8601String(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
