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
    public var dynamicRequiredNodeIDPrefixes: Set<String>

    public init(
        requiredNodeIDs: [String],
        dynamicRequiredNodeIDPrefixes: Set<String> = []
    ) {
        self.requiredNodeIDs = requiredNodeIDs
        self.dynamicRequiredNodeIDPrefixes = dynamicRequiredNodeIDPrefixes
    }

    public static let taskLifecycleAndExecution = AccessibilityFocusPathRequirement(
        requiredNodeIDs: [
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
            "task-status-move-in_progress",
            "task-auto-execution-review",
            "task-auto-execution-run-plan",
            "approved-execution-receipt",
            "task-inspector-delete",
            "task-inspector-delete-confirmation-cancel",
            "task-inspector-delete-confirmation-confirm"
        ],
        dynamicRequiredNodeIDPrefixes: [
            "task-status-move-in_progress"
        ]
    )
}

public enum AccessibilityFocusPathFindingKind: String, Codable, Equatable, Sendable {
    case missingRequiredNode
    case disabledRequiredNode
    case outOfOrderRequiredNode
    case duplicateNodeID
    case blankNodeID
    case unlabeledRequiredNode
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
        var nodesByID: [String: AccessibilityNodeSnapshot] = [:]
        var firstNodeIndexesByID: [String: Int] = [:]
        var duplicateNodeIDs: [String] = []
        var seenDuplicateNodeIDs = Set<String>()
        var blankNodeIDs: [String] = []

        for (index, node) in nodes.enumerated() {
            if node.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blankNodeIDs.append(node.id)
                continue
            }
            if nodesByID[node.id] == nil {
                nodesByID[node.id] = node
                firstNodeIndexesByID[node.id] = index
            } else if seenDuplicateNodeIDs.insert(node.id).inserted {
                duplicateNodeIDs.append(node.id)
            }
        }
        var findings = blankNodeIDs.map { nodeID in
            // Blank AX identifiers are impossible to target reliably from
            // MCP/E2E automation, so they cannot be treated as harmless
            // decoration in a release focus-path snapshot.
            AccessibilityFocusPathFinding(
                kind: .blankNodeID,
                nodeID: nodeID,
                message: "Accessibility node id must not be blank in the focus path snapshot."
            )
        }
        findings.append(contentsOf: duplicateNodeIDs.map { nodeID in
            // Duplicate AX identifiers make UI automation and VoiceOver
            // evidence ambiguous. Keep auditing with the first node so one
            // duplicate does not hide later release-gate findings.
            AccessibilityFocusPathFinding(
                kind: .duplicateNodeID,
                nodeID: nodeID,
                message: "Accessibility node id \(nodeID) must be unique in the focus path snapshot."
            )
        })
        var coveredNodeIDs: [String] = []
        var lastRequiredNodeIndex = -1

        for requiredNodeID in requirements.requiredNodeIDs {
            guard let matchedNode = matchedRequiredNode(
                requiredNodeID,
                requirements: requirements,
                nodesByID: nodesByID,
                firstNodeIndexesByID: firstNodeIndexesByID
            ) else {
                findings.append(AccessibilityFocusPathFinding(
                    kind: .missingRequiredNode,
                    nodeID: requiredNodeID,
                    message: "Missing required accessibility node \(requiredNodeID)."
                ))
                continue
            }
            let node = matchedNode.node
            coveredNodeIDs.append(requiredNodeID)
            if node.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Required group/outline nodes such as the project detail region
                // and approved execution receipt are not "interactive", but a
                // blank label still leaves VoiceOver users without a meaningful
                // landmark for the audited lifecycle step.
                findings.append(AccessibilityFocusPathFinding(
                    kind: .unlabeledRequiredNode,
                    nodeID: requiredNodeID,
                    message: "Required accessibility node \(requiredNodeID) needs a label."
                ))
            }
            if matchedNode.index < lastRequiredNodeIndex {
                // VoiceOver follows the AX traversal order, so a required
                // node that appears before an earlier lifecycle step cannot
                // prove the create/edit/execute/delete path is reachable.
                findings.append(AccessibilityFocusPathFinding(
                    kind: .outOfOrderRequiredNode,
                    nodeID: requiredNodeID,
                    message: "Required accessibility node \(requiredNodeID) appears before an earlier lifecycle step."
                ))
            }
            lastRequiredNodeIndex = max(lastRequiredNodeIndex, matchedNode.index)
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
            findings.append(contentsOf: nodeFindings(for: node, allNodes: nodes, reportingNodeID: requiredNodeID))
        }

        return AccessibilityFocusPathAuditResult(findings: findings, coveredRequiredNodeIDs: coveredNodeIDs)
    }

    private func matchedRequiredNode(
        _ requiredNodeID: String,
        requirements: AccessibilityFocusPathRequirement,
        nodesByID: [String: AccessibilityNodeSnapshot],
        firstNodeIndexesByID: [String: Int]
    ) -> (node: AccessibilityNodeSnapshot, index: Int)? {
        if let node = nodesByID[requiredNodeID],
           let index = firstNodeIndexesByID[requiredNodeID] {
            return (node, index)
        }

        guard requirements.dynamicRequiredNodeIDPrefixes.contains(requiredNodeID) else {
            return nil
        }

        // Runtime SwiftUI AX identifiers include the task id for repeated peer
        // controls. The release contract still names the stable prefix so one
        // dynamic card cannot weaken exact matching for unrelated required ids.
        return firstNodeIndexesByID
            .filter { nodeID, _ in nodeID.hasPrefix("\(requiredNodeID)-") }
            .min { lhs, rhs in lhs.value < rhs.value }
            .flatMap { nodeID, index in
                nodesByID[nodeID].map { ($0, index) }
            }
    }

    private func nodeFindings(
        for node: AccessibilityNodeSnapshot,
        allNodes: [AccessibilityNodeSnapshot],
        reportingNodeID: String
    ) -> [AccessibilityFocusPathFinding] {
        var findings: [AccessibilityFocusPathFinding] = []
        let normalizedLabel = node.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHelp = node.help.trimmingCharacters(in: .whitespacesAndNewlines)

        if node.role == .button || node.role == .textField || node.role == .textArea {
            if normalizedLabel.isEmpty {
                findings.append(AccessibilityFocusPathFinding(
                    kind: .unlabeledInteractiveNode,
                    nodeID: reportingNodeID,
                    message: "Interactive accessibility node \(node.id) needs a label."
                ))
            }
        }

        if node.role == .button,
           ["button", "ボタン"].contains(normalizedLabel.lowercased()),
           normalizedHelp.isEmpty {
            findings.append(AccessibilityFocusPathFinding(
                kind: .genericButtonWithoutHelp,
                nodeID: reportingNodeID,
                message: "Button \(node.id) needs a descriptive label or help text."
            ))
        }

        if node.isDestructive,
           !allNodes.contains(where: { $0.confirmsDestructiveAction && $0.id.hasPrefix(node.id) }) {
            findings.append(AccessibilityFocusPathFinding(
                kind: .missingDestructiveConfirmation,
                nodeID: reportingNodeID,
                message: "Destructive control \(node.id) must expose a confirmation step."
            ))
        }

        return findings
    }
}
