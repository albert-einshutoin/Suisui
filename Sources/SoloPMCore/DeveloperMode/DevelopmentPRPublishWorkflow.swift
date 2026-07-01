import Foundation

public struct GitHubCLICommandInvocation: Equatable, Sendable {
    public var arguments: [String]
    public var workingDirectory: URL

    public init(arguments: [String], workingDirectory: URL) {
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public struct GitHubCLICommandOutput: Equatable, Sendable {
    public var standardOutput: String
    public var standardError: String
    public var exitCode: Int32

    public init(standardOutput: String, standardError: String, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }
}

public protocol GitHubCLICommandRunner: Sendable {
    func runGitHub(arguments: [String], workingDirectory: URL) throws -> GitHubCLICommandOutput
}

public struct ProcessGitHubCLICommandRunner: GitHubCLICommandRunner {
    public init() {}

    public func runGitHub(arguments: [String], workingDirectory: URL) throws -> GitHubCLICommandOutput {
        #if os(iOS) || targetEnvironment(macCatalyst)
        throw DevelopmentPRPublishWorkflowError.commandFailed(
            tool: .developmentCreatePullRequest,
            command: ["gh"] + arguments,
            exitCode: 127,
            standardError: "GitHub CLI execution is available only on macOS."
        )
        #else
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        ]

        try process.run()
        process.waitUntilExit()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

        return GitHubCLICommandOutput(
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
        #endif
    }
}

public enum DevelopmentPRPublishWorkflowError: Error, Equatable, Sendable {
    case unexpectedBranch(expected: String, actual: String?)
    case dirtyWorkspace(changedPathCount: Int)
    case invalidPullRequestTitle
    case invalidPullRequestBody
    case invalidPublishHeadBranch
    case sameBaseAndHeadBranch
    case secretLikePullRequestContent
    case localPathInPullRequestContent
    case invalidPullRequestURL
    case invalidGitHubOriginRemote
    case pullRequestRepositoryMismatch(expected: String, actual: String)
    case invalidPullRequestStatusJSON
    case invalidPullRequestReviewThreadsJSON
    case missingPullRequestURL
    case commandNotAllowed(tool: ActionTool, command: [String])
    case commandFailed(tool: ActionTool, command: [String], exitCode: Int32, standardError: String)

    var userMessage: String {
        switch self {
        case .unexpectedBranch(let expected, let actual):
            return "Expected current branch \(expected), but found \(actual ?? "(unknown)")."
        case .dirtyWorkspace(let changedPathCount):
            return "Workspace has \(changedPathCount) changed path(s); push and PR creation require a clean reviewed commit."
        case .invalidPullRequestTitle:
            return "Pull request title must be non-blank, single-line text under 200 characters."
        case .invalidPullRequestBody:
            return "Pull request body must be non-blank UTF-8 text under 20000 bytes."
        case .invalidPublishHeadBranch:
            return "Publish head branch must use a reviewed feature branch."
        case .sameBaseAndHeadBranch:
            return "Pull request base and head branches must be different."
        case .secretLikePullRequestContent:
            return "Pull request title or body looks like it contains credentials or secrets."
        case .localPathInPullRequestContent:
            return "Pull request title or body includes a local filesystem path."
        case .invalidPullRequestURL:
            return "Pull request URL must be a GitHub HTTPS pull request URL."
        case .invalidGitHubOriginRemote:
            return "Origin remote must resolve to a GitHub repository."
        case .pullRequestRepositoryMismatch(let expected, let actual):
            return "Pull request repository \(actual) does not match origin repository \(expected)."
        case .invalidPullRequestStatusJSON:
            return "GitHub CLI returned an unreadable pull request status response."
        case .invalidPullRequestReviewThreadsJSON:
            return "GitHub CLI returned an unreadable pull request review thread response."
        case .missingPullRequestURL:
            return "GitHub CLI did not return a pull request URL."
        case .commandNotAllowed:
            return "Command is not allowed for development publish workflow."
        case .commandFailed(let tool, let command, let exitCode, let standardError):
            let suffix = standardError.isEmpty ? "" : " stderr: \(standardError)"
            if command == ["remote", "get-url", "origin"] {
                return "Git origin remote lookup failed with exit code \(exitCode).\(suffix)"
            }
            if tool == .developmentCreatePullRequest {
                return "GitHub CLI pull request creation failed with exit code \(exitCode).\(suffix)"
            }
            if tool == .developmentReviewPullRequestGate {
                return "GitHub CLI pull request status check failed with exit code \(exitCode).\(suffix)"
            }
            if tool == .developmentMergePullRequest {
                return "GitHub CLI pull request merge failed with exit code \(exitCode).\(suffix)"
            }
            return "\((["git"] + command).joined(separator: " ")) failed with exit code \(exitCode).\(suffix)"
        }
    }
}

public enum DevelopmentPublishGitCommandPolicy {
    public static func isAllowed(arguments: [String]) -> Bool {
        if arguments == ["status", "--short", "--branch"]
            || arguments == ["remote", "get-url", "origin"] {
            return true
        }

        guard arguments.count == 4,
              arguments[0] == "push",
              arguments[1] == "-u",
              arguments[2] == "origin" else {
            return false
        }
        return (try? validatedPublishHeadBranch(arguments[3])) != nil
    }

    public static func validatedPublishHeadBranch(_ rawBranch: String) throws -> String {
        let branch = try DevelopmentBranchNamePolicy.validated(rawBranch)
        let lowercased = branch.lowercased()
        guard branch.hasPrefix("feature/"),
              !["main", "master", "develop"].contains(lowercased) else {
            throw DevelopmentPRPublishWorkflowError.invalidPublishHeadBranch
        }
        return branch
    }
}

struct DevelopmentGitHubRepositoryIdentity: Equatable, Sendable {
    var owner: String
    var name: String

    var displayNameWithOwner: String {
        "\(owner)/\(name)"
    }

    func matches(_ other: DevelopmentGitHubRepositoryIdentity) -> Bool {
        owner.lowercased() == other.owner.lowercased()
            && name.lowercased() == other.name.lowercased()
    }
}

struct DevelopmentGitHubPullRequestIdentity: Equatable, Sendable {
    var repository: DevelopmentGitHubRepositoryIdentity
    var number: Int
}

public enum DevelopmentGitHubPRCommandPolicy {
    public static let statusJSONFields = "reviewDecision,statusCheckRollup,mergeable,mergeStateStatus,url,headRefName,headRefOid,baseRefName,headRepository,headRepositoryOwner,isCrossRepository"
    public static let reviewThreadsQuery = """
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            totalCount
            nodes {
              isResolved
            }
            pageInfo {
              hasNextPage
            }
          }
        }
      }
    }
    """

    public static func isAllowed(arguments: [String]) -> Bool {
        if isAllowedStatusView(arguments: arguments)
            || isAllowedReviewThreadsQuery(arguments: arguments)
            || isAllowedMerge(arguments: arguments) {
            return true
        }

        guard arguments.count == 10,
              arguments[0] == "pr",
              arguments[1] == "create",
              arguments[2] == "--base",
              arguments[4] == "--head",
              arguments[6] == "--title",
              arguments[8] == "--body-file" else {
            return false
        }

        guard (try? DevelopmentBranchNamePolicy.validated(arguments[3])) != nil,
              (try? DevelopmentPublishGitCommandPolicy.validatedPublishHeadBranch(arguments[5])) != nil,
              arguments[3] != arguments[5],
              isValidPullRequestTitle(arguments[7]) else {
            return false
        }

        let bodyFilePath = arguments[9]
        return bodyFilePath.hasPrefix("/")
            && !bodyFilePath.contains("\u{0}")
            && !URL(fileURLWithPath: bodyFilePath).lastPathComponent.hasPrefix("-")
    }

    public static func validatedPullRequestURL(
        _ rawURL: String,
        redactor: DeveloperSecretRedactor
    ) throws -> String {
        let pullRequestURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard redactor.redact(pullRequestURL).report.replacementCount == 0,
              !pullRequestURL.contains("\u{0}"),
              !pullRequestURL.contains(where: { $0.isWhitespace }),
              !containsLocalPath(pullRequestURL) else {
            throw DevelopmentPRPublishWorkflowError.invalidPullRequestURL
        }
        // Keep gh subcommands tied to a concrete repository and PR number;
        // arbitrary GitHub URLs are not safe enough for a merge-capable workflow.
        _ = try repositoryIdentity(fromPullRequestURL: pullRequestURL)
        return pullRequestURL
    }

    public static func reviewThreadsArguments(
        owner: String,
        repository: String,
        number: Int
    ) -> [String] {
        [
            "api", "graphql",
            "-f", "query=\(reviewThreadsQuery)",
            "-F", "owner=\(owner)",
            "-F", "repo=\(repository)",
            "-F", "number=\(number)"
        ]
    }

    public static func validatedHeadCommitOID(_ rawOID: String) throws -> String {
        let oid = rawOID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard [40, 64].contains(oid.count),
              !oid.contains("\u{0}"),
              oid.unicodeScalars.allSatisfy({ scalar in
                (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
              }) else {
            throw DevelopmentPRPublishWorkflowError.invalidPullRequestStatusJSON
        }
        return oid
    }

    static func repositoryIdentity(fromPullRequestURL pullRequestURL: String) throws -> DevelopmentGitHubRepositoryIdentity {
        try pullRequestIdentity(fromPullRequestURL: pullRequestURL).repository
    }

    static func pullRequestIdentity(fromPullRequestURL pullRequestURL: String) throws -> DevelopmentGitHubPullRequestIdentity {
        guard let components = URLComponents(string: pullRequestURL),
              components.scheme == "https",
              components.host?.lowercased() == "github.com",
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw DevelopmentPRPublishWorkflowError.invalidPullRequestURL
        }

        let parts = strictPathParts(components.percentEncodedPath)
        guard parts.count == 4,
              parts[2] == "pull",
              isValidGitHubOwner(parts[0]),
              isValidGitHubRepositoryName(parts[1]),
              !parts[3].isEmpty,
              parts[3].allSatisfy(\.isNumber),
              let number = Int(parts[3]) else {
            throw DevelopmentPRPublishWorkflowError.invalidPullRequestURL
        }

        return DevelopmentGitHubPullRequestIdentity(
            repository: DevelopmentGitHubRepositoryIdentity(owner: parts[0], name: parts[1]),
            number: number
        )
    }

    static func repositoryIdentity(fromRemoteURL rawRemoteURL: String) throws -> DevelopmentGitHubRepositoryIdentity {
        let remoteURL = rawRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remoteURL.isEmpty,
              !remoteURL.contains("\u{0}"),
              !remoteURL.contains(where: { $0.isWhitespace }),
              !containsLocalPath(remoteURL) else {
            throw DevelopmentPRPublishWorkflowError.invalidGitHubOriginRemote
        }

        if remoteURL.hasPrefix("git@github.com:") {
            let path = String(remoteURL.dropFirst("git@github.com:".count))
            return try repositoryIdentity(fromRemotePath: path)
        }

        guard let components = URLComponents(string: remoteURL),
              components.host?.lowercased() == "github.com",
              components.port == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw DevelopmentPRPublishWorkflowError.invalidGitHubOriginRemote
        }

        if components.scheme == "https" {
            guard components.user == nil else {
                throw DevelopmentPRPublishWorkflowError.invalidGitHubOriginRemote
            }
            return try repositoryIdentity(fromRemotePath: components.path)
        }

        if components.scheme == "ssh" {
            guard components.user == "git" else {
                throw DevelopmentPRPublishWorkflowError.invalidGitHubOriginRemote
            }
            return try repositoryIdentity(fromRemotePath: components.path)
        }

        throw DevelopmentPRPublishWorkflowError.invalidGitHubOriginRemote
    }

    public static func validatedPullRequestTitle(
        _ rawTitle: String,
        redactor: DeveloperSecretRedactor
    ) throws -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPullRequestTitle(title) else {
            throw DevelopmentPRPublishWorkflowError.invalidPullRequestTitle
        }
        guard redactor.redact(title).report.replacementCount == 0 else {
            throw DevelopmentPRPublishWorkflowError.secretLikePullRequestContent
        }
        guard !containsLocalPath(title) else {
            throw DevelopmentPRPublishWorkflowError.localPathInPullRequestContent
        }
        return title
    }

    public static func validatedPullRequestBody(
        _ rawBody: String,
        redactor: DeveloperSecretRedactor
    ) throws -> String {
        guard !rawBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Data(rawBody.utf8).count <= 20_000,
              !rawBody.contains("\u{0}") else {
            throw DevelopmentPRPublishWorkflowError.invalidPullRequestBody
        }
        guard redactor.redact(rawBody).report.replacementCount == 0 else {
            throw DevelopmentPRPublishWorkflowError.secretLikePullRequestContent
        }
        guard !containsLocalPath(rawBody) else {
            throw DevelopmentPRPublishWorkflowError.localPathInPullRequestContent
        }
        return rawBody
    }

    public static func validateBaseAndHead(baseBranch: String, headBranch: String) throws {
        guard baseBranch != headBranch else {
            throw DevelopmentPRPublishWorkflowError.sameBaseAndHeadBranch
        }
    }

    private static func isValidPullRequestTitle(_ title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.count <= 200
            && !title.contains("\u{0}")
            && !title.contains("\n")
            && !title.contains("\r")
    }

    private static func containsLocalPath(_ value: String) -> Bool {
        LocalPathRedactor.redact(value) != value
    }

    private static func repositoryIdentity(fromRemotePath rawPath: String) throws -> DevelopmentGitHubRepositoryIdentity {
        var parts = strictPathParts(rawPath)
        guard parts.count == 2 else {
            throw DevelopmentPRPublishWorkflowError.invalidGitHubOriginRemote
        }
        if parts[1].hasSuffix(".git") {
            parts[1].removeLast(4)
        }
        guard isValidGitHubOwner(parts[0]),
              isValidGitHubRepositoryName(parts[1]) else {
            throw DevelopmentPRPublishWorkflowError.invalidGitHubOriginRemote
        }
        return DevelopmentGitHubRepositoryIdentity(owner: parts[0], name: parts[1])
    }

    private static func strictPathParts(_ rawPath: String) -> [String] {
        guard rawPath.hasPrefix("/") else {
            return rawPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        }
        let pathWithoutLeadingSlash = rawPath.dropFirst()
        return pathWithoutLeadingSlash.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    private static func isValidGitHubOwner(_ value: String) -> Bool {
        guard (1...39).contains(value.count),
              let first = value.first,
              let last = value.last,
              first.isLetter || first.isNumber,
              last.isLetter || last.isNumber else {
            return false
        }
        return value.allSatisfy { isASCIIAlphaNumeric($0) || $0 == "-" }
    }

    private static func isValidGitHubRepositoryName(_ value: String) -> Bool {
        guard (1...100).contains(value.count),
              value != ".",
              value != ".." else {
            return false
        }
        return value.allSatisfy { character in
            isASCIIAlphaNumeric(character) || character == "-" || character == "_" || character == "."
        }
    }

    private static func isASCIIAlphaNumeric(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        return (48...57).contains(scalar.value)
            || (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
    }

    private static func isAllowedStatusView(arguments: [String]) -> Bool {
        guard arguments.count == 5,
              arguments[0] == "pr",
              arguments[1] == "view",
              arguments[3] == "--json",
              arguments[4] == statusJSONFields else {
            return false
        }
        return (try? validatedPullRequestURL(arguments[2], redactor: DeveloperSecretRedactor())) != nil
    }

    private static func isAllowedReviewThreadsQuery(arguments: [String]) -> Bool {
        guard arguments.count == 10,
              arguments[0] == "api",
              arguments[1] == "graphql",
              arguments[2] == "-f",
              arguments[3] == "query=\(reviewThreadsQuery)",
              arguments[4] == "-F",
              arguments[5].hasPrefix("owner="),
              arguments[6] == "-F",
              arguments[7].hasPrefix("repo="),
              arguments[8] == "-F",
              arguments[9].hasPrefix("number=") else {
            return false
        }
        let owner = String(arguments[5].dropFirst("owner=".count))
        let repository = String(arguments[7].dropFirst("repo=".count))
        let numberRaw = String(arguments[9].dropFirst("number=".count))
        guard isValidGitHubOwner(owner),
              isValidGitHubRepositoryName(repository),
              let number = Int(numberRaw),
              number > 0 else {
            return false
        }
        return true
    }

    private static func isAllowedMerge(arguments: [String]) -> Bool {
        guard arguments.count == 7,
              arguments[0] == "pr",
              arguments[1] == "merge",
              arguments[3] == "--merge",
              arguments[4] == "--delete-branch",
              arguments[5] == "--match-head-commit",
              (try? validatedHeadCommitOID(arguments[6])) != nil else {
            return false
        }
        return (try? validatedPullRequestURL(arguments[2], redactor: DeveloperSecretRedactor())) != nil
    }
}

private struct DevelopmentPullRequestCheckStatus: Decodable, Equatable, Sendable {
    var name: String
    var status: String?
    var conclusion: String?

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case name
        case context
        case status
        case conclusion
        case state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawName = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .context)
            ?? container.decodeIfPresent(String.self, forKey: .typename)
            ?? "unnamed status check"
        name = rawName
        status = try container.decodeIfPresent(String.self, forKey: .status)
        conclusion = try container.decodeIfPresent(String.self, forKey: .conclusion)

        if status == nil, let state = try container.decodeIfPresent(String.self, forKey: .state) {
            switch state.uppercased() {
            case "SUCCESS", "FAILURE", "ERROR":
                status = "COMPLETED"
                conclusion = conclusion ?? state
            default:
                status = state
            }
        }
    }
}

private struct DevelopmentPullRequestRepositoryStatus: Decodable, Equatable, Sendable {
    var name: String?
    var nameWithOwner: String?
}

private struct DevelopmentPullRequestRepositoryOwnerStatus: Decodable, Equatable, Sendable {
    var login: String?
}

private struct DevelopmentPullRequestGateStatus: Decodable, Equatable, Sendable {
    var url: String
    var headRefName: String
    var headRefOid: String?
    var baseRefName: String
    var headRepository: DevelopmentPullRequestRepositoryStatus?
    var headRepositoryOwner: DevelopmentPullRequestRepositoryOwnerStatus?
    var isCrossRepository: Bool?
    var reviewDecision: String?
    var mergeable: String?
    var mergeStateStatus: String?
    var statusCheckRollup: [DevelopmentPullRequestCheckStatus]

    var normalizedReviewDecision: String {
        normalized(reviewDecision)
    }

    var normalizedMergeable: String {
        normalized(mergeable)
    }

    var normalizedMergeStateStatus: String {
        normalized(mergeStateStatus)
    }

    var validatedHeadRefOID: String? {
        guard let headRefOid else {
            return nil
        }
        return try? DevelopmentGitHubPRCommandPolicy.validatedHeadCommitOID(headRefOid)
    }

    func blockingReasons(
        expectedURL: String,
        expectedHeadBranch: String,
        expectedBaseBranch: String,
        expectedRepository: DevelopmentGitHubRepositoryIdentity
    ) -> [String] {
        var reasons: [String] = []

        if url != expectedURL {
            reasons.append("pull request URL mismatch")
        }
        if headRefName != expectedHeadBranch {
            reasons.append("head branch is \(headRefName), expected \(expectedHeadBranch)")
        }
        if validatedHeadRefOID == nil {
            reasons.append("head commit is missing")
        }
        if baseRefName != expectedBaseBranch {
            reasons.append("base branch is \(baseRefName), expected \(expectedBaseBranch)")
        }
        // Fork PRs can be valid collaboration, but this automation only owns
        // same-repository merges for the approved project workspace.
        switch isCrossRepository {
        case .some(false):
            break
        case .some(true):
            reasons.append("head repository is cross-repository")
        case .none:
            reasons.append("cross-repository status is UNKNOWN")
        }
        if let headRepositoryIdentity {
            if !headRepositoryIdentity.matches(expectedRepository) {
                reasons.append("head repository is \(headRepositoryIdentity.displayNameWithOwner), expected \(expectedRepository.displayNameWithOwner)")
            }
        } else {
            reasons.append("head repository metadata is missing")
        }
        if normalizedReviewDecision != "APPROVED" {
            reasons.append("review decision is \(normalizedReviewDecision)")
        }
        if normalizedMergeable != "MERGEABLE" {
            reasons.append("mergeable is \(normalizedMergeable)")
        }
        if normalizedMergeStateStatus != "CLEAN" {
            reasons.append("merge state is \(normalizedMergeStateStatus)")
        }
        if statusCheckRollup.isEmpty {
            reasons.append("status checks are missing")
        }
        for check in statusCheckRollup {
            let name = displayName(check.name)
            let status = normalized(check.status)
            let conclusion = normalized(check.conclusion)
            if status != "COMPLETED" {
                reasons.append("\(name) is \(status)")
                continue
            }
            if conclusion != "SUCCESS" {
                reasons.append("\(name) concluded \(conclusion)")
            }
        }

        return reasons
    }

    private var headRepositoryIdentity: DevelopmentGitHubRepositoryIdentity? {
        guard let owner = headRepositoryOwner?.login,
              let name = headRepository?.name,
              !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let nameWithOwner = headRepository?.nameWithOwner,
               let identity = identity(fromNameWithOwner: nameWithOwner) {
                return identity
            }
            return nil
        }
        return DevelopmentGitHubRepositoryIdentity(owner: owner, name: name)
    }

    private func identity(fromNameWithOwner nameWithOwner: String) -> DevelopmentGitHubRepositoryIdentity? {
        let parts = nameWithOwner.split(separator: "/").map(String.init)
        guard parts.count == 2,
              !parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !parts[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return DevelopmentGitHubRepositoryIdentity(owner: parts[0], name: parts[1])
    }

    private func normalized(_ value: String?, fallback: String = "UNKNOWN") -> String {
        guard let value else {
            return fallback
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed.uppercased()
    }

    private func displayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unnamed status check" : trimmed
    }
}

private struct DevelopmentPullRequestReviewThreadStatus: Decodable, Equatable, Sendable {
    struct ResponseData: Decodable, Equatable, Sendable {
        var repository: Repository?
    }

    struct Repository: Decodable, Equatable, Sendable {
        var pullRequest: PullRequest?
    }

    struct PullRequest: Decodable, Equatable, Sendable {
        var reviewThreads: ReviewThreads
    }

    struct ReviewThreads: Decodable, Equatable, Sendable {
        var totalCount: Int
        var nodes: [ReviewThread]
        var pageInfo: PageInfo
    }

    struct ReviewThread: Decodable, Equatable, Sendable {
        var isResolved: Bool?
    }

    struct PageInfo: Decodable, Equatable, Sendable {
        var hasNextPage: Bool
    }

    var data: ResponseData
}

private struct DevelopmentPullRequestReviewThreadSummary: Equatable, Sendable {
    var totalCount: Int
    var unresolvedCount: Int
    var hasNextPage: Bool

    static let notChecked = DevelopmentPullRequestReviewThreadSummary(
        totalCount: 0,
        unresolvedCount: 0,
        hasNextPage: false
    )

    var blockingReasons: [String] {
        var reasons: [String] = []
        if hasNextPage {
            reasons.append("review thread count exceeds verification limit")
        }
        if unresolvedCount == 1 {
            reasons.append("1 review thread is unresolved")
        } else if unresolvedCount > 1 {
            reasons.append("\(unresolvedCount) review threads are unresolved")
        }
        return reasons
    }
}

private struct DevelopmentPullRequestGateDecision: Equatable, Sendable {
    var status: DevelopmentPullRequestGateStatus
    var reviewThreads: DevelopmentPullRequestReviewThreadSummary
    var blockingReasons: [String]

    var isReadyToMerge: Bool {
        blockingReasons.isEmpty
    }

    var summary: String {
        if isReadyToMerge {
            return "Pull request review, CI, and mergeability gates passed."
        }
        return "Pull request merge blocked: \(blockingReasons.joined(separator: "; "))."
    }

    func output(projectID: Int64, pullRequestURL: String, branchName: String, baseBranch: String) -> [String: JSONValue] {
        var output: [String: JSONValue] = [
            "projectId": .number(Double(projectID)),
            "pullRequestURL": .string(pullRequestURL),
            "branchName": .string(branchName),
            "baseBranch": .string(baseBranch),
            "readyToMerge": .bool(isReadyToMerge),
            "reviewDecision": .string(status.normalizedReviewDecision),
            "mergeable": .string(status.normalizedMergeable),
            "mergeStateStatus": .string(status.normalizedMergeStateStatus),
            "statusCheckCount": .number(Double(status.statusCheckRollup.count)),
            "reviewThreadCount": .number(Double(reviewThreads.totalCount)),
            "unresolvedReviewThreadCount": .number(Double(reviewThreads.unresolvedCount)),
            "reviewThreadPageTruncated": .bool(reviewThreads.hasNextPage),
            "blockingReasons": .array(blockingReasons.map(JSONValue.string))
        ]
        if let headRefOID = status.validatedHeadRefOID {
            output["headRefOid"] = .string(headRefOID)
        }
        return output
    }
}

private struct DevelopmentPullRequestGateEvaluator {
    var projectStore: SQLiteProjectStore
    var gitRunner: any GitCommandRunner
    var githubRunner: any GitHubCLICommandRunner
    var redactor: DeveloperSecretRedactor
    var bookmarkResolver: any ProjectWorkspaceBookmarkResolving

    func evaluate(arguments: [String: JSONValue], tool: ActionTool) throws -> DevelopmentPullRequestGateContext {
        try validateRequiredArguments(arguments, tool: tool)
        let args = ToolArguments(arguments, tool: tool)
        let projectID = try args.requiredInt64("projectId")
        let pullRequestURL = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestURL(
            args.requiredTrimmedString("pullRequestURL"),
            redactor: redactor
        )
        let branchName = try DevelopmentPublishGitCommandPolicy.validatedPublishHeadBranch(
            args.requiredTrimmedString("branchName")
        )
        let baseBranch = try DevelopmentBranchNamePolicy.validated(args.requiredTrimmedString("baseBranch"))
        try DevelopmentGitHubPRCommandPolicy.validateBaseAndHead(baseBranch: baseBranch, headBranch: branchName)
        let project = try projectStore.get(id: projectID)
        let scope = try ProjectWorkspaceScope(project: project, bookmarkResolver: bookmarkResolver)
        return try withExtendedLifetime(scope) {
            // Resolve origin before calling GitHub so a pasted PR URL for another
            // repository cannot read or merge outside the approved workspace.
            let originRepository = try fetchOriginRepository(
                workingDirectory: scope.rootURL,
                tool: tool
            )
            let pullRequestRepository = try DevelopmentGitHubPRCommandPolicy.repositoryIdentity(
                fromPullRequestURL: pullRequestURL
            )
            guard pullRequestRepository.matches(originRepository) else {
                throw DevelopmentPRPublishWorkflowError.pullRequestRepositoryMismatch(
                    expected: originRepository.displayNameWithOwner,
                    actual: pullRequestRepository.displayNameWithOwner
                )
            }
            let status = try fetchStatus(
                pullRequestURL: pullRequestURL,
                workingDirectory: scope.rootURL,
                tool: tool
            )
            let preliminaryBlockingReasons = status.blockingReasons(
                expectedURL: pullRequestURL,
                expectedHeadBranch: branchName,
                expectedBaseBranch: baseBranch,
                expectedRepository: originRepository
            ).map(redacted)
            let reviewThreads = preliminaryBlockingReasons.isEmpty
                ? try fetchReviewThreads(
                    pullRequestURL: pullRequestURL,
                    workingDirectory: scope.rootURL,
                    tool: tool
                )
                : .notChecked
            let blockingReasons = preliminaryBlockingReasons + reviewThreads.blockingReasons.map(redacted)

            return DevelopmentPullRequestGateContext(
                projectID: project.id,
                pullRequestURL: pullRequestURL,
                branchName: branchName,
                baseBranch: baseBranch,
                scope: scope,
                decision: DevelopmentPullRequestGateDecision(
                    status: status,
                    reviewThreads: reviewThreads,
                    blockingReasons: blockingReasons
                )
            )
        }
    }

    private func fetchOriginRepository(
        workingDirectory: URL,
        tool: ActionTool
    ) throws -> DevelopmentGitHubRepositoryIdentity {
        let arguments = ["remote", "get-url", "origin"]
        guard DevelopmentPublishGitCommandPolicy.isAllowed(arguments: arguments) else {
            throw DevelopmentPRPublishWorkflowError.commandNotAllowed(tool: tool, command: arguments)
        }
        let output = try gitRunner.runGit(arguments: arguments, workingDirectory: workingDirectory)
        guard output.exitCode == 0 else {
            throw DevelopmentPRPublishWorkflowError.commandFailed(
                tool: tool,
                command: arguments,
                exitCode: output.exitCode,
                standardError: redacted(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
            )
        }
        return try DevelopmentGitHubPRCommandPolicy.repositoryIdentity(fromRemoteURL: output.standardOutput)
    }

    private func fetchStatus(
        pullRequestURL: String,
        workingDirectory: URL,
        tool: ActionTool
    ) throws -> DevelopmentPullRequestGateStatus {
        let arguments = [
            "pr", "view", pullRequestURL,
            "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
        ]
        guard DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: arguments) else {
            throw DevelopmentPRPublishWorkflowError.commandNotAllowed(tool: tool, command: arguments)
        }
        let output = try githubRunner.runGitHub(arguments: arguments, workingDirectory: workingDirectory)
        guard output.exitCode == 0 else {
            throw DevelopmentPRPublishWorkflowError.commandFailed(
                tool: tool,
                command: arguments,
                exitCode: output.exitCode,
                standardError: redacted(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
            )
        }
        guard let data = output.standardOutput.data(using: .utf8),
              let status = try? JSONDecoder().decode(DevelopmentPullRequestGateStatus.self, from: data) else {
            throw DevelopmentPRPublishWorkflowError.invalidPullRequestStatusJSON
        }
        return status
    }

    private func fetchReviewThreads(
        pullRequestURL: String,
        workingDirectory: URL,
        tool: ActionTool
    ) throws -> DevelopmentPullRequestReviewThreadSummary {
        let identity = try DevelopmentGitHubPRCommandPolicy.pullRequestIdentity(
            fromPullRequestURL: pullRequestURL
        )
        let arguments = DevelopmentGitHubPRCommandPolicy.reviewThreadsArguments(
            owner: identity.repository.owner,
            repository: identity.repository.name,
            number: identity.number
        )
        guard DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: arguments) else {
            throw DevelopmentPRPublishWorkflowError.commandNotAllowed(tool: tool, command: arguments)
        }
        let output = try githubRunner.runGitHub(arguments: arguments, workingDirectory: workingDirectory)
        guard output.exitCode == 0 else {
            throw DevelopmentPRPublishWorkflowError.commandFailed(
                tool: tool,
                command: arguments,
                exitCode: output.exitCode,
                standardError: redacted(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
            )
        }
        guard let data = output.standardOutput.data(using: .utf8),
              let response = try? JSONDecoder().decode(DevelopmentPullRequestReviewThreadStatus.self, from: data),
              let threads = response.data.repository?.pullRequest?.reviewThreads else {
            throw DevelopmentPRPublishWorkflowError.invalidPullRequestReviewThreadsJSON
        }
        let unresolvedCount = threads.nodes.filter { $0.isResolved != true }.count
        // We intentionally fail closed when more than the first page exists:
        // a merge-capable local agent must not assume comments beyond the
        // fetched page are resolved.
        return DevelopmentPullRequestReviewThreadSummary(
            totalCount: threads.totalCount,
            unresolvedCount: unresolvedCount,
            hasNextPage: threads.pageInfo.hasNextPage
        )
    }

    private func validateRequiredArguments(_ arguments: [String: JSONValue], tool: ActionTool) throws {
        let required = ["projectId", "pullRequestURL", "branchName", "baseBranch"]
        for key in required where arguments[key] == nil {
            throw ToolExecutionError.validationFailed(tool, "Missing required argument '\(key)'.")
        }
    }

    private func redacted(_ value: String) -> String {
        LocalPathRedactor.redact(redactor.redact(value).text)
    }
}

private struct DevelopmentPullRequestGateContext: Equatable, Sendable {
    var projectID: Int64
    var pullRequestURL: String
    var branchName: String
    var baseBranch: String
    var scope: ProjectWorkspaceScope
    var decision: DevelopmentPullRequestGateDecision

    var workingDirectory: URL {
        scope.rootURL
    }

    var headRefOID: String? {
        decision.status.validatedHeadRefOID
    }

    var mergeArguments: [String] {
        [
            "pr", "merge", pullRequestURL,
            "--merge", "--delete-branch",
            "--match-head-commit", headRefOID ?? ""
        ]
    }
}

public struct DevelopmentPullRequestReviewGateTool: Tool {
    public let name: ActionTool = .developmentReviewPullRequestGate
    public let description: String = "Check GitHub pull request review, CI, and mergeability status before merge approval."
    public let inputSchema = ToolInputSchema(
        required: ["projectId", "pullRequestURL", "branchName", "baseBranch"],
        properties: [
            "projectId": "integer",
            "pullRequestURL": "string",
            "branchName": "string",
            "baseBranch": "string"
        ],
        nonBlank: ["pullRequestURL", "branchName", "baseBranch"]
    )
    public let permissionLevel: ToolPermissionLevel = .writeWithApproval

    private let evaluator: DevelopmentPullRequestGateEvaluator
    private let redactor: DeveloperSecretRedactor

    public init(
        projectStore: SQLiteProjectStore,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        githubRunner: any GitHubCLICommandRunner = ProcessGitHubCLICommandRunner(),
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor(),
        bookmarkResolver: any ProjectWorkspaceBookmarkResolving = SecurityScopedProjectWorkspaceBookmarkResolver()
    ) {
        self.evaluator = DevelopmentPullRequestGateEvaluator(
            projectStore: projectStore,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            redactor: redactor,
            bookmarkResolver: bookmarkResolver
        )
        self.redactor = redactor
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)

        do {
            let gate = try evaluator.evaluate(arguments: arguments, tool: name)
            return ToolResult(
                tool: name,
                status: gate.decision.isReadyToMerge ? .succeeded : .failed,
                summary: redacted(gate.decision.summary),
                output: gate.decision.output(
                    projectID: gate.projectID,
                    pullRequestURL: gate.pullRequestURL,
                    branchName: gate.branchName,
                    baseBranch: gate.baseBranch
                ),
                rollbackMetadata: ["pullRequestURL": .string(gate.pullRequestURL)],
                compensationHint: gate.decision.isReadyToMerge
                    ? "Request explicit merge approval before merging."
                    : "Resolve review, CI, or mergeability blockers before requesting merge approval."
            )
        } catch let error as ToolExecutionError {
            throw error
        } catch let error as DevelopmentPRWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as DevelopmentPRPublishWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as GitReadOnlyError {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        } catch {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        }
    }

    private func redacted(_ value: String) -> String {
        LocalPathRedactor.redact(redactor.redact(value).text)
    }
}

public struct DevelopmentPullRequestMergeTool: Tool {
    public let name: ActionTool = .developmentMergePullRequest
    public let description: String = "Merge a GitHub pull request only after review, CI, and mergeability gates pass and explicit approval is given."
    public let inputSchema = ToolInputSchema(
        required: ["projectId", "pullRequestURL", "branchName", "baseBranch"],
        properties: [
            "projectId": "integer",
            "pullRequestURL": "string",
            "branchName": "string",
            "baseBranch": "string"
        ],
        nonBlank: ["pullRequestURL", "branchName", "baseBranch"]
    )
    public let permissionLevel: ToolPermissionLevel = .writeWithApproval

    private let evaluator: DevelopmentPullRequestGateEvaluator
    private let githubRunner: any GitHubCLICommandRunner
    private let redactor: DeveloperSecretRedactor

    public init(
        projectStore: SQLiteProjectStore,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        githubRunner: any GitHubCLICommandRunner = ProcessGitHubCLICommandRunner(),
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor(),
        bookmarkResolver: any ProjectWorkspaceBookmarkResolving = SecurityScopedProjectWorkspaceBookmarkResolver()
    ) {
        self.githubRunner = githubRunner
        self.redactor = redactor
        self.evaluator = DevelopmentPullRequestGateEvaluator(
            projectStore: projectStore,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            redactor: redactor,
            bookmarkResolver: bookmarkResolver
        )
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)

        do {
            let gate = try evaluator.evaluate(arguments: arguments, tool: name)
            guard gate.decision.isReadyToMerge else {
                return ToolResult(
                    tool: name,
                    status: .failed,
                    summary: redacted(gate.decision.summary),
                    output: gate.decision.output(
                        projectID: gate.projectID,
                        pullRequestURL: gate.pullRequestURL,
                        branchName: gate.branchName,
                        baseBranch: gate.baseBranch
                    ),
                    rollbackMetadata: ["pullRequestURL": .string(gate.pullRequestURL)],
                    compensationHint: "Resolve review, CI, or mergeability blockers before requesting merge approval again."
                )
            }

            let mergeArguments = gate.mergeArguments
            guard DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: mergeArguments) else {
                throw DevelopmentPRPublishWorkflowError.commandNotAllowed(tool: name, command: mergeArguments)
            }
            let merge = try withExtendedLifetime(gate) {
                try githubRunner.runGitHub(arguments: mergeArguments, workingDirectory: gate.workingDirectory)
            }
            guard merge.exitCode == 0 else {
                return failedCommandResult(gate: gate, exitCode: merge.exitCode, standardError: merge.standardError)
            }

            var output = gate.decision.output(
                projectID: gate.projectID,
                pullRequestURL: gate.pullRequestURL,
                branchName: gate.branchName,
                baseBranch: gate.baseBranch
            )
            output["merged"] = .bool(true)
            output["mergeStrategy"] = .string("merge")
            output["deletedRemoteBranch"] = .bool(true)
            output["mergeSummary"] = .string(redacted(merge.standardOutput))

            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Merged pull request \(gate.pullRequestURL) after review and CI gates passed.",
                output: output,
                rollbackMetadata: [
                    "pullRequestURL": .string(gate.pullRequestURL),
                    "branchName": .string(gate.branchName),
                    "headRefOid": .string(gate.headRefOID ?? "")
                ],
                compensationHint: "Pull the base branch after merge and continue from the updated base."
            )
        } catch let error as ToolExecutionError {
            throw error
        } catch let error as DevelopmentPRWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as DevelopmentPRPublishWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as GitReadOnlyError {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        } catch {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        }
    }

    private func failedCommandResult(
        gate: DevelopmentPullRequestGateContext,
        exitCode: Int32,
        standardError: String
    ) -> ToolResult {
        let error = DevelopmentPRPublishWorkflowError.commandFailed(
            tool: name,
            command: gate.mergeArguments,
            exitCode: exitCode,
            standardError: redacted(standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        )
        var output = gate.decision.output(
            projectID: gate.projectID,
            pullRequestURL: gate.pullRequestURL,
            branchName: gate.branchName,
            baseBranch: gate.baseBranch
        )
        output["merged"] = .bool(false)
        output["publishError"] = .string(redacted(error.userMessage))
        return ToolResult(
            tool: name,
            status: .failed,
            summary: redacted(error.userMessage),
            output: output,
            rollbackMetadata: ["pullRequestURL": .string(gate.pullRequestURL)],
            compensationHint: "Inspect the GitHub merge result and retry after fixing the merge error."
        )
    }

    private func redacted(_ value: String) -> String {
        LocalPathRedactor.redact(redactor.redact(value).text)
    }
}

public struct DevelopmentPushWorkflowTool: Tool {
    public let name: ActionTool = .developmentPushBranch
    public let description: String = "Push a reviewed development branch to origin after explicit approval."
    public let inputSchema = ToolInputSchema(
        required: ["projectId", "branchName"],
        properties: [
            "projectId": "integer",
            "branchName": "string"
        ],
        nonBlank: ["branchName"]
    )
    public let permissionLevel: ToolPermissionLevel = .writeWithApproval

    private let projectStore: SQLiteProjectStore
    private let gitRunner: any GitCommandRunner
    private let redactor: DeveloperSecretRedactor

    public init(
        projectStore: SQLiteProjectStore,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.projectStore = projectStore
        self.gitRunner = gitRunner
        self.redactor = redactor
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        let projectID = try args.requiredInt64("projectId")

        do {
            let project = try projectStore.get(id: projectID)
            let scope = try ProjectWorkspaceScope(project: project)
            let branchName = try DevelopmentPublishGitCommandPolicy.validatedPublishHeadBranch(
                args.requiredTrimmedString("branchName")
            )

            return try withExtendedLifetime(scope) {
                let readiness = try workspacePublishReadiness(branchName: branchName, scope: scope)
                guard readiness.isReady else {
                    return failedReadinessResult(projectID: project.id, branchName: branchName, readiness: readiness)
                }

                let push = try runGit(arguments: ["push", "-u", "origin", branchName], workingDirectory: scope.rootURL)
                guard push.exitCode == 0 else {
                    return failedCommandResult(
                        projectID: project.id,
                        branchName: branchName,
                        error: .commandFailed(
                            tool: name,
                            command: ["push", "-u", "origin", branchName],
                            exitCode: push.exitCode,
                            standardError: redacted(push.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                        )
                    )
                }

                return ToolResult(
                    tool: name,
                    status: .succeeded,
                    summary: "Pushed development branch \(branchName). Pull request creation requires a separate approval gate.",
                    output: [
                        "projectId": .number(Double(project.id)),
                        "branchName": .string(branchName),
                        "remoteName": .string("origin"),
                        "workspaceClean": .bool(true),
                        "pushSummary": .string(redacted(push.standardOutput)),
                        "requiresPullRequestApproval": .bool(true)
                    ],
                    rollbackMetadata: ["branchName": .string(branchName)],
                    compensationHint: "Review the pushed branch before creating a pull request."
                )
            }
        } catch let error as ToolExecutionError {
            throw error
        } catch let error as DevelopmentPRWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as DevelopmentPRPublishWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as GitReadOnlyError {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        } catch {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        }
    }

    private func failedReadinessResult(
        projectID: Int64,
        branchName: String,
        readiness: DevelopmentPublishReadiness
    ) -> ToolResult {
        ToolResult(
            tool: name,
            status: .failed,
            summary: redacted(readiness.failureMessage ?? "Workspace is not ready for push."),
            output: readiness.output(projectID: projectID, branchName: branchName),
            rollbackMetadata: ["branchName": .string(branchName)],
            compensationHint: "Commit or resolve local changes, then request push approval again."
        )
    }

    private func failedCommandResult(
        projectID: Int64,
        branchName: String,
        error: DevelopmentPRPublishWorkflowError
    ) -> ToolResult {
        ToolResult(
            tool: name,
            status: .failed,
            summary: redacted(error.userMessage),
            output: [
                "projectId": .number(Double(projectID)),
                "branchName": .string(branchName),
                "remoteName": .string("origin"),
                "workspaceClean": .bool(true),
                "publishError": .string(redacted(error.userMessage))
            ],
            rollbackMetadata: ["branchName": .string(branchName)],
            compensationHint: "Inspect the branch and retry push after fixing the Git error."
        )
    }

    private func workspacePublishReadiness(branchName: String, scope: ProjectWorkspaceScope) throws -> DevelopmentPublishReadiness {
        let output = try runGit(arguments: ["status", "--short", "--branch"], workingDirectory: scope.rootURL)
        guard output.exitCode == 0 else {
            return DevelopmentPublishReadiness(
                currentBranch: nil,
                isClean: false,
                changedPathCount: nil,
                failureMessage: redacted(DevelopmentPRPublishWorkflowError.commandFailed(
                    tool: name,
                    command: ["status", "--short", "--branch"],
                    exitCode: output.exitCode,
                    standardError: redacted(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                ).userMessage)
            )
        }

        let status = GitStatusSummary.parse(output.standardOutput)
        if status.branch != branchName {
            return DevelopmentPublishReadiness(
                currentBranch: status.branch,
                isClean: status.isClean,
                changedPathCount: status.entries.count,
                failureMessage: DevelopmentPRPublishWorkflowError.unexpectedBranch(
                    expected: branchName,
                    actual: status.branch
                ).userMessage
            )
        }
        guard status.isClean else {
            return DevelopmentPublishReadiness(
                currentBranch: status.branch,
                isClean: false,
                changedPathCount: status.entries.count,
                failureMessage: DevelopmentPRPublishWorkflowError.dirtyWorkspace(
                    changedPathCount: status.entries.count
                ).userMessage
            )
        }
        return DevelopmentPublishReadiness(
            currentBranch: status.branch,
            isClean: true,
            changedPathCount: 0,
            failureMessage: nil
        )
    }

    private func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput {
        guard DevelopmentPublishGitCommandPolicy.isAllowed(arguments: arguments) else {
            throw DevelopmentPRPublishWorkflowError.commandNotAllowed(tool: name, command: arguments)
        }
        return try gitRunner.runGit(arguments: arguments, workingDirectory: workingDirectory)
    }

    private func redacted(_ value: String) -> String {
        LocalPathRedactor.redact(redactor.redact(value).text)
    }
}

public struct DevelopmentPullRequestCreationTool: Tool {
    public let name: ActionTool = .developmentCreatePullRequest
    public let description: String = "Create a GitHub pull request for a reviewed pushed branch after explicit approval."
    public let inputSchema = ToolInputSchema(
        required: ["projectId", "branchName", "baseBranch", "title", "body"],
        properties: [
            "projectId": "integer",
            "branchName": "string",
            "baseBranch": "string",
            "title": "string",
            "body": "string"
        ],
        nonBlank: ["branchName", "baseBranch", "title", "body"]
    )
    public let permissionLevel: ToolPermissionLevel = .writeWithApproval

    private let projectStore: SQLiteProjectStore
    private let gitRunner: any GitCommandRunner
    private let githubRunner: any GitHubCLICommandRunner
    private let redactor: DeveloperSecretRedactor

    public init(
        projectStore: SQLiteProjectStore,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        githubRunner: any GitHubCLICommandRunner = ProcessGitHubCLICommandRunner(),
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.projectStore = projectStore
        self.gitRunner = gitRunner
        self.githubRunner = githubRunner
        self.redactor = redactor
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        let projectID = try args.requiredInt64("projectId")

        do {
            let branchName = try DevelopmentPublishGitCommandPolicy.validatedPublishHeadBranch(
                args.requiredTrimmedString("branchName")
            )
            let baseBranch = try DevelopmentBranchNamePolicy.validated(args.requiredTrimmedString("baseBranch"))
            try DevelopmentGitHubPRCommandPolicy.validateBaseAndHead(
                baseBranch: baseBranch,
                headBranch: branchName
            )
            let title = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestTitle(
                args.requiredString("title"),
                redactor: redactor
            )
            let body = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestBody(
                args.requiredString("body"),
                redactor: redactor
            )
            let project = try projectStore.get(id: projectID)
            let scope = try ProjectWorkspaceScope(project: project)

            return try withExtendedLifetime(scope) {
                let readiness = try workspacePublishReadiness(branchName: branchName, scope: scope)
                guard readiness.isReady else {
                    return failedReadinessResult(
                        projectID: project.id,
                        branchName: branchName,
                        baseBranch: baseBranch,
                        readiness: readiness
                    )
                }

                let fileManager = FileManager.default
                let bodyFileURL = fileManager.temporaryDirectory
                    .appendingPathComponent("solopm-pr-body-\(UUID().uuidString).md")
                try body.write(to: bodyFileURL, atomically: true, encoding: .utf8)
                defer { try? fileManager.removeItem(at: bodyFileURL) }

                // Use --body-file so reviewed PR text never becomes shell-interpreted
                // or logged as an inline command argument by process tooling.
                let githubArguments = [
                    "pr", "create",
                    "--base", baseBranch,
                    "--head", branchName,
                    "--title", title,
                    "--body-file", bodyFileURL.path
                ]
                guard DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: githubArguments) else {
                    throw DevelopmentPRPublishWorkflowError.commandNotAllowed(tool: name, command: githubArguments)
                }

                let output = try githubRunner.runGitHub(arguments: githubArguments, workingDirectory: scope.rootURL)
                guard output.exitCode == 0 else {
                    return failedCommandResult(
                        projectID: project.id,
                        branchName: branchName,
                        baseBranch: baseBranch,
                        error: .commandFailed(
                            tool: name,
                            command: githubArguments,
                            exitCode: output.exitCode,
                            standardError: redacted(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                        )
                    )
                }

                guard let rawPullRequestURL = pullRequestURL(from: output.standardOutput) else {
                    return failedCommandResult(
                        projectID: project.id,
                        branchName: branchName,
                        baseBranch: baseBranch,
                        error: .missingPullRequestURL
                    )
                }
                let pullRequestURL = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestURL(
                    rawPullRequestURL,
                    redactor: redactor
                )

                return ToolResult(
                    tool: name,
                    status: .succeeded,
                    summary: "Created pull request \(pullRequestURL) from \(branchName) into \(baseBranch).",
                    output: [
                        "projectId": .number(Double(project.id)),
                        "branchName": .string(branchName),
                        "baseBranch": .string(baseBranch),
                        "title": .string(title),
                        "pullRequestURL": .string(pullRequestURL),
                        "workspaceClean": .bool(true)
                    ],
                    rollbackMetadata: [
                        "branchName": .string(branchName),
                        "pullRequestURL": .string(pullRequestURL)
                    ],
                    compensationHint: "Review CI and code review status before merging the pull request."
                )
            }
        } catch let error as ToolExecutionError {
            throw error
        } catch let error as DevelopmentPRWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as DevelopmentPRPublishWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as GitReadOnlyError {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        } catch {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        }
    }

    private func failedReadinessResult(
        projectID: Int64,
        branchName: String,
        baseBranch: String,
        readiness: DevelopmentPublishReadiness
    ) -> ToolResult {
        var output = readiness.output(projectID: projectID, branchName: branchName)
        output["baseBranch"] = .string(baseBranch)
        return ToolResult(
            tool: name,
            status: .failed,
            summary: redacted(readiness.failureMessage ?? "Workspace is not ready for pull request creation."),
            output: output,
            rollbackMetadata: ["branchName": .string(branchName)],
            compensationHint: "Confirm the pushed branch and clean workspace, then request PR creation approval again."
        )
    }

    private func failedCommandResult(
        projectID: Int64,
        branchName: String,
        baseBranch: String,
        error: DevelopmentPRPublishWorkflowError
    ) -> ToolResult {
        ToolResult(
            tool: name,
            status: .failed,
            summary: redacted(error.userMessage),
            output: [
                "projectId": .number(Double(projectID)),
                "branchName": .string(branchName),
                "baseBranch": .string(baseBranch),
                "workspaceClean": .bool(true),
                "publishError": .string(redacted(error.userMessage))
            ],
            rollbackMetadata: ["branchName": .string(branchName)],
            compensationHint: "Inspect the GitHub CLI result and retry PR creation after fixing the error."
        )
    }

    private func workspacePublishReadiness(branchName: String, scope: ProjectWorkspaceScope) throws -> DevelopmentPublishReadiness {
        let output = try runGit(arguments: ["status", "--short", "--branch"], workingDirectory: scope.rootURL)
        guard output.exitCode == 0 else {
            return DevelopmentPublishReadiness(
                currentBranch: nil,
                isClean: false,
                changedPathCount: nil,
                failureMessage: redacted(DevelopmentPRPublishWorkflowError.commandFailed(
                    tool: name,
                    command: ["status", "--short", "--branch"],
                    exitCode: output.exitCode,
                    standardError: redacted(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                ).userMessage)
            )
        }

        let status = GitStatusSummary.parse(output.standardOutput)
        if status.branch != branchName {
            return DevelopmentPublishReadiness(
                currentBranch: status.branch,
                isClean: status.isClean,
                changedPathCount: status.entries.count,
                failureMessage: DevelopmentPRPublishWorkflowError.unexpectedBranch(
                    expected: branchName,
                    actual: status.branch
                ).userMessage
            )
        }
        guard status.isClean else {
            return DevelopmentPublishReadiness(
                currentBranch: status.branch,
                isClean: false,
                changedPathCount: status.entries.count,
                failureMessage: DevelopmentPRPublishWorkflowError.dirtyWorkspace(
                    changedPathCount: status.entries.count
                ).userMessage
            )
        }
        return DevelopmentPublishReadiness(
            currentBranch: status.branch,
            isClean: true,
            changedPathCount: 0,
            failureMessage: nil
        )
    }

    private func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput {
        guard DevelopmentPublishGitCommandPolicy.isAllowed(arguments: arguments) else {
            throw DevelopmentPRPublishWorkflowError.commandNotAllowed(tool: name, command: arguments)
        }
        return try gitRunner.runGit(arguments: arguments, workingDirectory: workingDirectory)
    }

    private func pullRequestURL(from standardOutput: String) -> String? {
        standardOutput
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .first { token in
                token.hasPrefix("https://") && token.contains("/pull/")
            }
    }

    private func redacted(_ value: String) -> String {
        LocalPathRedactor.redact(redactor.redact(value).text)
    }
}

private struct DevelopmentPublishReadiness: Equatable, Sendable {
    var currentBranch: String?
    var isClean: Bool
    var changedPathCount: Int?
    var failureMessage: String?

    var isReady: Bool {
        failureMessage == nil && isClean
    }

    func output(projectID: Int64, branchName: String) -> [String: JSONValue] {
        var output: [String: JSONValue] = [
            "projectId": .number(Double(projectID)),
            "branchName": .string(branchName),
            "workspaceClean": .bool(isClean)
        ]
        if let currentBranch {
            output["currentBranch"] = .string(currentBranch)
        }
        if let changedPathCount {
            output["changedPathCount"] = .number(Double(changedPathCount))
        }
        if let failureMessage {
            output["publishError"] = .string(failureMessage)
        }
        return output
    }
}
