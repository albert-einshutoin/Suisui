import Foundation

public enum DeveloperModeCapability: String, CaseIterable, Equatable, Hashable, Sendable {
    case gitReadOnly
    case githubIssues
    case codebaseMemory
}

public struct DeveloperModePermissionDisclosure: Equatable, Sendable {
    public var capability: DeveloperModeCapability
    public var title: String
    public var summary: String

    public init(capability: DeveloperModeCapability, title: String, summary: String) {
        self.capability = capability
        self.title = title
        self.summary = summary
    }
}

public struct DeveloperModeSettings: Equatable, Sendable {
    public var isEnabled: Bool
    public var workspaceRoot: URL?
    public var enabledCapabilities: Set<DeveloperModeCapability>

    public init(
        isEnabled: Bool,
        workspaceRoot: URL?,
        enabledCapabilities: Set<DeveloperModeCapability> = []
    ) {
        self.isEnabled = isEnabled
        self.workspaceRoot = workspaceRoot
        self.enabledCapabilities = enabledCapabilities
    }

    public var permissionDisclosureItems: [DeveloperModeCapability] {
        guard isEnabled else {
            return []
        }

        return DeveloperModeCapability.allCases.filter { enabledCapabilities.contains($0) }
    }

    public var permissionDisclosures: [DeveloperModePermissionDisclosure] {
        permissionDisclosureItems.map(\.disclosure)
    }
}

public enum DeveloperModeError: Error, Equatable, Sendable {
    case workspaceRequired
}

public extension DeveloperModeCapability {
    var disclosure: DeveloperModePermissionDisclosure {
        switch self {
        case .gitReadOnly:
            return DeveloperModePermissionDisclosure(
                capability: self,
                title: "Git read-only scan",
                summary: "Reads status, branch, bounded log, and diff stat inside the selected workspace only."
            )
        case .githubIssues:
            return DeveloperModePermissionDisclosure(
                capability: self,
                title: "GitHub issue creation",
                summary: "Creates reviewable drafts first and performs GitHub writes only after explicit approval."
            )
        case .codebaseMemory:
            return DeveloperModePermissionDisclosure(
                capability: self,
                title: "codebase-memory optional context",
                summary: "Previews selected local context before sending it to an approved external connector."
            )
        }
    }
}

public extension ToolRegistryFactory {
    static func developerMode(
        settings: DeveloperModeSettings,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner()
    ) throws -> ToolRegistry {
        guard settings.isEnabled else {
            return ToolRegistry()
        }

        guard let workspaceRoot = settings.workspaceRoot else {
            throw DeveloperModeError.workspaceRequired
        }

        var tools: [any Tool] = []

        if settings.enabledCapabilities.contains(.gitReadOnly) {
            let gitClient = GitReadOnlyClient(workspaceRoot: workspaceRoot, runner: gitRunner)
            tools.append(contentsOf: [
                GitReadOnlyTool(name: .gitStatus, client: gitClient),
                GitReadOnlyTool(name: .gitBranch, client: gitClient),
                GitReadOnlyTool(name: .gitLogSummary, client: gitClient),
                GitReadOnlyTool(name: .gitDiffSummary, client: gitClient)
            ])
        }

        return try ToolRegistry(tools: tools)
    }
}
