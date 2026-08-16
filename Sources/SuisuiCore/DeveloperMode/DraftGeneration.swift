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

struct SecretRedactionPatternDefinition: Equatable, Sendable {
    var name: String
    var expression: String

    init(name: String, expression: String) {
        self.name = name
        self.expression = expression
    }
}

public struct DeveloperSecretRedactor: Sendable {
    private struct CompiledPattern: @unchecked Sendable {
        var name: String
        var regex: NSRegularExpression
    }

    private static let initializationFailurePatternName = "redactor_initialization_failed"

    private static let defaultPatternDefinitions: [SecretRedactionPatternDefinition] = [
        SecretRedactionPatternDefinition(name: "github_pat", expression: #"github_pat_[A-Za-z0-9_]{8,}"#),
        // Keep the historical report name while covering GitHub's complete
        // token-prefix family; classic ghp values retain their compatibility threshold.
        SecretRedactionPatternDefinition(name: "ghp", expression: #"gh(?:p_[A-Za-z0-9_]{6,}|[ousr]_[A-Za-z0-9_]{8,})"#),
        SecretRedactionPatternDefinition(name: "slack", expression: #"(?<![A-Za-z0-9_-])(?:xox[baprs]|xapp)-[A-Za-z0-9-]{10,}(?![A-Za-z0-9_-])"#),
        SecretRedactionPatternDefinition(name: "openai", expression: #"sk-(?:proj-)?[A-Za-z0-9_-]{8,}"#),
        SecretRedactionPatternDefinition(name: "stripe", expression: #"(?<![A-Za-z0-9_-])(?:sk|rk)_(?:live|test)_[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])"#),
        SecretRedactionPatternDefinition(name: "aws_access_key", expression: #"(?:AKIA|ASIA)[0-9A-Z]{16}"#),
        // Consume the entire key block, not only its header, so draft/log output
        // cannot retain secret body lines. An unterminated block fails closed.
        SecretRedactionPatternDefinition(name: "private_key_block", expression: #"(?is)-----BEGIN ([A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?)-----.*?(?:-----END \1-----|\z)"#),
        // Repository indexes must reject Docker credential JSON before it can be
        // persisted; matching field names catches encoded values too.
        SecretRedactionPatternDefinition(name: "docker_auth_json", expression: #"(?i)\"(?:auths|auth|identitytoken)\"\s*:\s*(?:\{|\"(?:\\.|[^\"\\])*\")"#),
        SecretRedactionPatternDefinition(name: "credential_json", expression: #"(?i)\"(?:api[_-]?key|token|[A-Za-z0-9_-]*(?:password|passwd|passphrase)|db[_-]?pass|secret|client_secret|private_key)\"\s*:\s*\"(?:\\.|[^\"\\])*\""#),
        SecretRedactionPatternDefinition(name: "credential_uri", expression: #"(?i)\b[a-z][a-z0-9+.-]*://[^/\s:@]*:[^@\s/]+@"#),
        SecretRedactionPatternDefinition(name: "authorization_header", expression: #"(?i)\bauthorization\b\s*[\"']?\s*[:=]\s*(?:\"(?:\\.|[^\"\\\r\n])*\"|'(?:\\.|[^'\\\r\n])*'|[^\s,;\r\n][^\r\n]*)"#),
        SecretRedactionPatternDefinition(name: "jwt", expression: #"(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*(?![A-Za-z0-9_-])"#),
        SecretRedactionPatternDefinition(name: "assignment", expression: #"(?i)\b(?:api[_-]?key|token|[A-Za-z0-9_-]*(?:password|passwd|passphrase)|db[_-]?pass|secret)\s*[:=]\s*(?!\[REDACTED_SECRET\])[^\s,;]+"#)
    ]

    private let patterns: [CompiledPattern]
    private let compilationFailure: String?

    public init() {
        self.init(compilation: Result { try Self.compileDefaultPatterns() })
    }

    init(patternDefinitions: [SecretRedactionPatternDefinition]) {
        self.init(compilation: Result { try Self.compilePatterns(patternDefinitions) })
    }

    private init(compilation: Result<[CompiledPattern], any Error>) {
        switch compilation {
        case .success(let patterns):
            self.patterns = patterns
            self.compilationFailure = nil
        case .failure(let error):
            self.patterns = []
            self.compilationFailure = String(describing: error)
        }
    }

    public func redact(_ text: String) -> SecretRedactionResult {
        if compilationFailure != nil {
            return SecretRedactionResult(
                text: text.isEmpty ? "" : "[REDACTED_SECRET]",
                report: SecretRedactionReport(
                    replacementCount: text.isEmpty ? 0 : 1,
                    matchedPatternNames: [Self.initializationFailurePatternName]
                )
            )
        }

        // JSON and TOML permit escaped key names (for example `to\u006ben`).
        // Decode those keys before regex redaction so the spelling cannot hide
        // a credential field from logs or repository-index checks.
        if Self.containsEscapedCredentialKey(text) {
            return SecretRedactionResult(
                text: text.isEmpty ? "" : "[REDACTED_SECRET]",
                report: SecretRedactionReport(
                    replacementCount: text.isEmpty ? 0 : 1,
                    matchedPatternNames: ["credential_json"]
                )
            )
        }

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

    private static func compileDefaultPatterns() throws -> [CompiledPattern] {
        try compilePatterns(defaultPatternDefinitions)
    }

    private static func compilePatterns(_ patternDefinitions: [SecretRedactionPatternDefinition]) throws -> [CompiledPattern] {
        try patternDefinitions.map { pattern in
            try compiledPattern(name: pattern.name, expression: pattern.expression)
        }
    }

    private static func compiledPattern(name: String, expression: String) throws -> CompiledPattern {
        try CompiledPattern(
            name: name,
            regex: NSRegularExpression(pattern: expression)
        )
    }

    private static func containsEscapedCredentialKey(_ text: String) -> Bool {
        var index = text.startIndex
        // Overlapping quote candidates recover from arbitrary log prefixes.
        // Bound their total look-ahead so adversarial escaped quotes cannot
        // turn redaction into quadratic work; exhaustion fails closed.
        var scanBudget = text.count > Int.max / 2 ? Int.max : text.count * 2
        while index < text.endIndex {
            guard text[index] == "\"" else {
                index = text.index(after: index)
                continue
            }
            let start = index
            var cursor = text.index(after: index)
            var escaped = false
            var sawEscape = false
            while cursor < text.endIndex {
                guard scanBudget > 0 else {
                    return true
                }
                scanBudget -= 1
                let character = text[cursor]
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                    sawEscape = true
                } else if character == "\"" {
                    break
                }
                cursor = text.index(after: cursor)
            }
            guard cursor < text.endIndex else {
                index = text.index(after: start)
                continue
            }
            let end = text.index(after: cursor)
            var delimiter = end
            while delimiter < text.endIndex, text[delimiter].isWhitespace {
                delimiter = text.index(after: delimiter)
            }
            if sawEscape, delimiter < text.endIndex,
               text[delimiter] == ":" || text[delimiter] == "=" {
                let literal = String(text[start..<end])
                guard let data = literal.data(using: .utf8),
                      let key = try? JSONDecoder().decode(String.self, from: data) else {
                    return true
                }
                if isCredentialJSONKey(key) {
                    return true
                }
            }
            // Arbitrary log text can contain an unmatched quote before an
            // embedded JSON object. Try the next quote as a candidate start;
            // adjacent quote intervals are each examined at most twice.
            index = text.index(after: start)
        }
        return false
    }

    static func isCredentialJSONKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
        // Serialized config models often append `Value` to a credential field.
        // Strip that neutral wrapper once so `previewValue` stays harmless.
        let credentialCandidate = normalized.hasSuffix("value")
            ? String(normalized.dropLast("value".count))
            : normalized
        return ["auth", "auths", "authorization", "identitytoken", "dbpass"].contains(credentialCandidate)
            // Config ecosystems commonly abbreviate password independently of
            // separator and case, so all repository egress paths share these suffixes.
            || [
                "apikey", "accesskey", "privatekey", "clientkeydata", "token",
                "password", "passwd", "passphrase", "secret", "credential", "credentials",
            ]
                .contains(where: credentialCandidate.hasSuffix)
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
