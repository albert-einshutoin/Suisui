import Foundation

public enum DeveloperModeCapability: String, CaseIterable, Equatable, Hashable, Sendable {
    case gitReadOnly
    case githubIssues
    case codebaseMemory
    case developmentPRWorkflow
    case developmentRepositoryFiles
    case developmentVerificationCommands
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
    case projectStoresRequired
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
        case .developmentPRWorkflow:
            return DeveloperModePermissionDisclosure(
                capability: self,
                title: "Development PR workflow",
                summary: "Creates local branches only inside an approved project directory and keeps push or PR creation behind a separate approval."
            )
        case .developmentRepositoryFiles:
            return DeveloperModePermissionDisclosure(
                capability: self,
                title: "Development repository files",
                summary: "Reads, creates, and updates supported text files only inside the approved project directory; create and update require explicit approval."
            )
        case .developmentVerificationCommands:
            return DeveloperModePermissionDisclosure(
                capability: self,
                title: "Development verification commands",
                summary: "Runs approved local test, lint, and security commands only inside the approved project directory after explicit approval."
            )
        }
    }
}

public extension ToolRegistryFactory {
    static func developerMode(
        settings: DeveloperModeSettings,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        developmentCommandRunner: any DevelopmentCommandRunner = ProcessDevelopmentCommandRunner(),
        projectStore: SQLiteProjectStore? = nil,
        taskStore: SQLiteTaskStore? = nil
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

        if settings.enabledCapabilities.contains(.developmentPRWorkflow) {
            guard let projectStore, let taskStore else {
                throw DeveloperModeError.projectStoresRequired
            }
            tools.append(DevelopmentPRWorkflowTool(
                projectStore: projectStore,
                taskStore: taskStore,
                gitRunner: gitRunner
            ))
        }

        if settings.enabledCapabilities.contains(.developmentRepositoryFiles) {
            guard let projectStore else {
                throw DeveloperModeError.projectStoresRequired
            }
            tools.append(contentsOf: [
                DevelopmentRepositoryFileTool(name: .developmentRepositoryReadFile, projectStore: projectStore),
                DevelopmentRepositoryFileTool(name: .developmentRepositoryCreateFile, projectStore: projectStore),
                DevelopmentRepositoryFileTool(name: .developmentRepositoryUpdateFile, projectStore: projectStore)
            ])
        }

        if settings.enabledCapabilities.contains(.developmentVerificationCommands) {
            guard let projectStore else {
                throw DeveloperModeError.projectStoresRequired
            }
            tools.append(DevelopmentVerificationCommandTool(
                projectStore: projectStore,
                commandRunner: developmentCommandRunner
            ))
        }

        return try ToolRegistry(tools: tools)
    }
}
