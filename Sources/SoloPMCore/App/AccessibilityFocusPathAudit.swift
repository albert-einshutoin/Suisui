import Foundation

public enum AccessibilityNodeRole: String, Codable, Equatable, Sendable {
    case button
    case textField
    case textArea
    case group
    case outline
    case staticText
}

public struct AccessibilityNodeSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var role: AccessibilityNodeRole
    public var label: String
    public var help: String
    public var isEnabled: Bool
    public var isDestructive: Bool
    public var confirmsDestructiveAction: Bool

    public init(
        id: String,
        role: AccessibilityNodeRole,
        label: String,
        help: String = "",
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        confirmsDestructiveAction: Bool = false
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.help = help
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.confirmsDestructiveAction = confirmsDestructiveAction
    }
}

public struct AccessibilityFocusPathRequirement: Equatable, Sendable {
    public var requiredNodeIDs: [String]

    public init(requiredNodeIDs: [String]) {
        self.requiredNodeIDs = requiredNodeIDs
    }

    public static let taskLifecycleAndExecution = AccessibilityFocusPathRequirement(requiredNodeIDs: [
        "project-board-sidebar",
        "project-board-detail",
        "project-header-add-task",
        "inline-task-title",
        "inline-task-detail",
        "inline-task-create",
        "project-board-task-auto-execution-review",
        "task-card-open-details",
        "task-inspector-title",
        "task-inspector-detail",
        "task-inspector-save",
        "task-status-move-controls",
        "task-auto-execution-review",
        "task-auto-execution-run-plan",
        "approved-execution-receipt",
        "task-inspector-delete",
        "task-inspector-delete-confirmation-confirm"
    ])
}

public enum AccessibilityFocusPathFindingKind: String, Codable, Equatable, Sendable {
    case missingRequiredNode
    case disabledRequiredNode
    case outOfOrderRequiredNode
    case unlabeledInteractiveNode
    case genericButtonWithoutHelp
    case missingDestructiveConfirmation
}

public struct AccessibilityFocusPathFinding: Codable, Equatable, Sendable {
    public var kind: AccessibilityFocusPathFindingKind
    public var nodeID: String
    public var message: String

    public init(kind: AccessibilityFocusPathFindingKind, nodeID: String, message: String) {
        self.kind = kind
        self.nodeID = nodeID
        self.message = message
    }
}

public struct AccessibilityFocusPathAuditResult: Equatable, Sendable {
    public var findings: [AccessibilityFocusPathFinding]
    public var coveredRequiredNodeIDs: [String]

    public init(findings: [AccessibilityFocusPathFinding], coveredRequiredNodeIDs: [String]) {
        self.findings = findings
        self.coveredRequiredNodeIDs = coveredRequiredNodeIDs
    }
}

public struct AccessibilityFocusPathAudit: Sendable {
    public init() {}

    public func audit(
        nodes: [AccessibilityNodeSnapshot],
        requirements: AccessibilityFocusPathRequirement
    ) -> AccessibilityFocusPathAuditResult {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let firstNodeIndexesByID = nodes.enumerated().reduce(into: [String: Int]()) { indexes, pair in
            indexes[pair.element.id] = indexes[pair.element.id] ?? pair.offset
        }
        var findings: [AccessibilityFocusPathFinding] = []
        var coveredNodeIDs: [String] = []
        var lastRequiredNodeIndex = -1

        for requiredNodeID in requirements.requiredNodeIDs {
            guard let node = nodesByID[requiredNodeID] else {
                findings.append(AccessibilityFocusPathFinding(
                    kind: .missingRequiredNode,
                    nodeID: requiredNodeID,
                    message: "Missing required accessibility node \(requiredNodeID)."
                ))
                continue
            }
            coveredNodeIDs.append(node.id)
            if let currentIndex = firstNodeIndexesByID[requiredNodeID] {
                if currentIndex < lastRequiredNodeIndex {
                    // VoiceOver follows the AX traversal order, so a required
                    // node that appears before an earlier lifecycle step cannot
                    // prove the create/edit/execute/delete path is reachable.
                    findings.append(AccessibilityFocusPathFinding(
                        kind: .outOfOrderRequiredNode,
                        nodeID: requiredNodeID,
                        message: "Required accessibility node \(requiredNodeID) appears before an earlier lifecycle step."
                    ))
                }
                lastRequiredNodeIndex = max(lastRequiredNodeIndex, currentIndex)
            }
            if !node.isEnabled {
                // A disabled required node can still be visible to AX, but it
                // cannot complete the keyboard/VoiceOver CRUD path the release
                // checklist is trying to prove.
                findings.append(AccessibilityFocusPathFinding(
                    kind: .disabledRequiredNode,
                    nodeID: requiredNodeID,
                    message: "Required accessibility node \(requiredNodeID) must be enabled for the lifecycle path."
                ))
            }
            findings.append(contentsOf: nodeFindings(for: node, allNodes: nodes))
        }

        return AccessibilityFocusPathAuditResult(findings: findings, coveredRequiredNodeIDs: coveredNodeIDs)
    }

    private func nodeFindings(
        for node: AccessibilityNodeSnapshot,
        allNodes: [AccessibilityNodeSnapshot]
    ) -> [AccessibilityFocusPathFinding] {
        var findings: [AccessibilityFocusPathFinding] = []
        let normalizedLabel = node.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHelp = node.help.trimmingCharacters(in: .whitespacesAndNewlines)

        if node.role == .button || node.role == .textField || node.role == .textArea {
            if normalizedLabel.isEmpty {
                findings.append(AccessibilityFocusPathFinding(
                    kind: .unlabeledInteractiveNode,
                    nodeID: node.id,
                    message: "Interactive accessibility node \(node.id) needs a label."
                ))
            }
        }

        if node.role == .button,
           ["button", "ボタン"].contains(normalizedLabel.lowercased()),
           normalizedHelp.isEmpty {
            findings.append(AccessibilityFocusPathFinding(
                kind: .genericButtonWithoutHelp,
                nodeID: node.id,
                message: "Button \(node.id) needs a descriptive label or help text."
            ))
        }

        if node.isDestructive,
           !allNodes.contains(where: { $0.confirmsDestructiveAction && $0.id.hasPrefix(node.id) }) {
            findings.append(AccessibilityFocusPathFinding(
                kind: .missingDestructiveConfirmation,
                nodeID: node.id,
                message: "Destructive control \(node.id) must expose a confirmation step."
            ))
        }

        return findings
    }
}
