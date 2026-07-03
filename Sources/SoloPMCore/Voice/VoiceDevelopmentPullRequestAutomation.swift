import Foundation

public enum VoiceDevelopmentPullRequestAutomationRequestError: Error, Equatable, Sendable {
    case unsupportedIntent
    case clarificationRequired
    case projectWorkspaceBookmarkRequired(Int64)
    case projectWorkspaceInvalid(String)
    case missingPullRequestURL
    case missingBranchName
    case missingBaseBranch
    case invalidPullRequestURL
    case invalidHeadBranch(String)
    case invalidBaseBranch(String)
    case branchMatchesBase

    public var userMessage: String {
        switch self {
        case .unsupportedIntent:
            return "Voice command is not a development PR workflow request."
        case .clarificationRequired:
            return "Development PR workflow needs clarification before queueing a review gate."
        case .projectWorkspaceBookmarkRequired:
            return "Select and approve the project directory before queueing a development PR automation request."
        case .projectWorkspaceInvalid(let message):
            return message
        case .missingPullRequestURL:
            return "Development PR workflow needs a GitHub pull request URL."
        case .missingBranchName:
            return "Development PR workflow needs an explicit head branch."
        case .missingBaseBranch:
            return "Development PR workflow needs an explicit base branch."
        case .invalidPullRequestURL:
            return "Development PR workflow needs a valid GitHub pull request URL."
        case .invalidHeadBranch:
            return "Development PR workflow needs a feature/* head branch."
        case .invalidBaseBranch:
            return "Development PR workflow needs a safe base branch name."
        case .branchMatchesBase:
            return "Development PR workflow needs different head and base branches."
        }
    }
}

public struct VoiceDevelopmentPullRequestAutomationRequestBuilder: Sendable {
    private let bookmarkResolver: any ProjectWorkspaceBookmarkResolving
    private let requestIDProvider: @Sendable () -> String
    private let redactor: DeveloperSecretRedactor

    public init(
        bookmarkResolver: any ProjectWorkspaceBookmarkResolving = SecurityScopedProjectWorkspaceBookmarkResolver(),
        requestIDProvider: @escaping @Sendable () -> String = { "voice-development-pr:\(UUID().uuidString)" },
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.bookmarkResolver = bookmarkResolver
        self.requestIDProvider = requestIDProvider
        self.redactor = redactor
    }

    public static func containsPullRequestURL(in transcript: String) -> Bool {
        firstPullRequestURL(in: transcript) != nil
    }

    public func makeRequest(
        route: VoiceCommandRoutingResult,
        project: ProjectRecord,
        sourceClientID: String = "voice"
    ) throws -> SyncAutomationRequestPayload {
        try makeRequest(
            route: route,
            project: project,
            operation: Self.requestedOperation(in: route.normalizedTranscript),
            sourceClientID: sourceClientID
        )
    }

    public func makeReviewGateRequest(
        route: VoiceCommandRoutingResult,
        project: ProjectRecord,
        sourceClientID: String = "voice"
    ) throws -> SyncAutomationRequestPayload {
        try makeRequest(route: route, project: project, operation: .reviewGate, sourceClientID: sourceClientID)
    }

    private func makeRequest(
        route: VoiceCommandRoutingResult,
        project: ProjectRecord,
        operation: SyncDevelopmentPullRequestOperation,
        sourceClientID: String
    ) throws -> SyncAutomationRequestPayload {
        guard route.intent == .developmentPRWorkflow else {
            throw VoiceDevelopmentPullRequestAutomationRequestError.unsupportedIntent
        }
        guard !route.needsClarification else {
            throw VoiceDevelopmentPullRequestAutomationRequestError.clarificationRequired
        }

        try validateApprovedWorkspace(project: project)

        let transcript = route.normalizedTranscript
        guard let rawPullRequestURL = Self.firstPullRequestURL(in: transcript) else {
            throw VoiceDevelopmentPullRequestAutomationRequestError.missingPullRequestURL
        }
        let pullRequestURL: String
        do {
            pullRequestURL = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestURL(
                rawPullRequestURL,
                redactor: redactor
            )
        } catch {
            throw VoiceDevelopmentPullRequestAutomationRequestError.invalidPullRequestURL
        }

        guard let rawBranchName = Self.labeledBranchValue(
            in: transcript,
            labels: ["head branch", "head", "branch", "ブランチ"]
        ) else {
            throw VoiceDevelopmentPullRequestAutomationRequestError.missingBranchName
        }
        let branchName: String
        do {
            branchName = try DevelopmentPublishGitCommandPolicy.validatedPublishHeadBranch(rawBranchName)
        } catch {
            throw VoiceDevelopmentPullRequestAutomationRequestError.invalidHeadBranch(rawBranchName)
        }

        guard let rawBaseBranch = Self.labeledBranchValue(
            in: transcript,
            labels: ["base branch", "base", "target", "ベース"]
        ) else {
            throw VoiceDevelopmentPullRequestAutomationRequestError.missingBaseBranch
        }
        let baseBranch: String
        do {
            baseBranch = try DevelopmentBranchNamePolicy.validated(rawBaseBranch)
        } catch {
            throw VoiceDevelopmentPullRequestAutomationRequestError.invalidBaseBranch(rawBaseBranch)
        }

        guard branchName != baseBranch else {
            throw VoiceDevelopmentPullRequestAutomationRequestError.branchMatchesBase
        }

        return SyncAutomationRequestPayload(
            id: sanitizedRequestID(requestIDProvider()),
            source: .conversation,
            approvalState: .pendingApproval,
            sourceClientID: sanitizedMetadata(sourceClientID, maxLength: 160),
            toolName: toolName(for: operation),
            redactedArgumentSummary: reviewSummary(
                operation: operation,
                pullRequestURL: pullRequestURL,
                branchName: branchName,
                baseBranch: baseBranch,
                transcript: transcript
            ),
            developmentPullRequest: SyncDevelopmentPullRequestPayload(
                projectID: project.id,
                operation: operation,
                pullRequestURL: pullRequestURL,
                branchName: branchName,
                baseBranch: baseBranch
            )
        )
    }

    private func validateApprovedWorkspace(project: ProjectRecord) throws {
        guard let bookmarkData = project.workspaceBookmarkData,
              !bookmarkData.isEmpty else {
            throw VoiceDevelopmentPullRequestAutomationRequestError.projectWorkspaceBookmarkRequired(project.id)
        }

        do {
            _ = try ProjectWorkspaceScope(project: project, bookmarkResolver: bookmarkResolver)
        } catch let error as DevelopmentPRWorkflowError {
            throw VoiceDevelopmentPullRequestAutomationRequestError.projectWorkspaceInvalid(error.userMessage)
        } catch {
            throw VoiceDevelopmentPullRequestAutomationRequestError.projectWorkspaceInvalid(
                UserFacingErrorMessageSanitizer.message(from: error)
            )
        }
    }

    private func reviewSummary(
        operation: SyncDevelopmentPullRequestOperation,
        pullRequestURL: String,
        branchName: String,
        baseBranch: String,
        transcript: String
    ) -> String {
        let operationLabel: String
        switch operation {
        case .reviewGate:
            operationLabel = "review"
        case .merge:
            operationLabel = "merge"
        }
        return sanitizedMetadata(
            "Voice development PR \(operationLabel): \(pullRequestURL) head \(branchName) into \(baseBranch). Source: \(transcript)",
            maxLength: 1_200
        )
    }

    private func toolName(for operation: SyncDevelopmentPullRequestOperation) -> String {
        switch operation {
        case .reviewGate:
            return ActionTool.developmentReviewPullRequestGate.rawValue
        case .merge:
            return ActionTool.developmentMergePullRequest.rawValue
        }
    }

    private func sanitizedRequestID(_ rawID: String) -> String {
        let sanitized = rawID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { character in
                character.isASCII && (character.isLetter || character.isNumber || "-_:.".contains(character))
            }
        return sanitized.isEmpty ? "voice-development-pr:\(UUID().uuidString)" : String(sanitized.prefix(160))
    }

    private func sanitizedMetadata(_ value: String, maxLength: Int) -> String {
        let secretRedacted = redactor.redact(value.trimmingCharacters(in: .whitespacesAndNewlines)).text
        let pathRedacted = LocalPathRedactor.redact(secretRedacted)
        guard pathRedacted.count > maxLength else {
            return pathRedacted
        }
        return "\(pathRedacted.prefix(maxLength))..."
    }

    private static func firstPullRequestURL(in transcript: String) -> String? {
        let pattern = #"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        guard let match = expression.firstMatch(in: transcript, range: range),
              let matchRange = Range(match.range, in: transcript) else {
            return nil
        }
        return String(transcript[matchRange])
    }

    private static func requestedOperation(in transcript: String) -> SyncDevelopmentPullRequestOperation {
        // Review phrasing wins because users often say "review before merge";
        // treating that as a merge command would turn a safety check into a write.
        if containsReviewGateSignal(in: transcript) {
            return .reviewGate
        }
        if containsMergeSignal(in: transcript) {
            return .merge
        }
        return .reviewGate
    }

    private static func containsReviewGateSignal(in transcript: String) -> Bool {
        let normalized = transcript.lowercased()
        return normalized.contains("review pr")
            || normalized.contains("review pull request")
            || normalized.contains("check pr")
            || normalized.contains("review gate")
            || transcript.contains("レビュー")
            || transcript.contains("確認")
    }

    private static func containsMergeSignal(in transcript: String) -> Bool {
        guard !containsMergeNegation(in: transcript) else {
            return false
        }
        let englishPattern = #"(?i)(?:^|[\s,;])(merge)\s+(?:the\s+)?(?:pr|pull request|https://github\.com)"#
        if matches(englishPattern, in: transcript) {
            return true
        }
        return transcript.contains("マージ")
    }

    private static func containsMergeNegation(in transcript: String) -> Bool {
        let normalized = transcript.lowercased()
        if normalized.contains("do not merge")
            || normalized.contains("don't merge")
            || normalized.contains("dont merge")
            || normalized.contains("not merge") {
            return true
        }
        return transcript.contains("マージしない")
            || transcript.contains("マージはしない")
            || transcript.contains("マージしないで")
    }

    private static func matches(_ pattern: String, in transcript: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        return expression.firstMatch(in: transcript, range: range) != nil
    }

    private static func labeledBranchValue(in transcript: String, labels: [String]) -> String? {
        labels.lazy.compactMap { label -> String? in
            labeledBranchValue(in: transcript, label: label)
        }.first
    }

    private static func labeledBranchValue(in transcript: String, label: String) -> String? {
        let escapedLabel = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"(?i)(?:^|[\s,;])"# + escapedLabel + #"\s*[:=]?\s*([A-Za-z0-9][A-Za-z0-9._/-]*[A-Za-z0-9])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        let matches = expression.matches(in: transcript, range: range)
        for match in matches {
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: transcript) else {
                continue
            }
            if label == "branch",
               let labelRange = Range(match.range(at: 0), in: transcript) {
                let prefix = transcript[..<labelRange.lowerBound].lowercased()
                if prefix.hasSuffix("base ") {
                    continue
                }
            }
            return String(transcript[valueRange])
        }
        return nil
    }
}

public enum VoiceDevelopmentProjectSelection {
    public static func uniqueApprovedActiveProject(from projects: [ProjectRecord]) -> ProjectRecord? {
        let approvedProjects = projects.filter { project in
            project.status == "active"
                && project.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                && project.workspaceBookmarkData?.isEmpty == false
        }
        // Voice commands without an explicit project picker must not guess
        // between repositories. If more than one active approved workspace
        // exists, the user needs to pick the project before developer work.
        return approvedProjects.count == 1 ? approvedProjects[0] : nil
    }
}
