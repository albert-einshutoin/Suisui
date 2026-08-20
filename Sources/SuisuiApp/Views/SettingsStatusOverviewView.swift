import SuisuiCore
import SwiftUI

struct SettingsStatusOverviewView: View {
    let groups: [SettingsReadinessRowGroup]
    let performAction: (SettingsReadinessAction) -> Void
    var selectedRowID: String? = nil
    var onSelectRow: ((SettingsReadinessRow) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups, id: \SettingsReadinessRowGroup.group) { (group: SettingsReadinessRowGroup) in
                SettingsReadinessGroupView(
                    group: group,
                    selectedRowID: selectedRowID,
                    performAction: performAction,
                    onSelectRow: onSelectRow
                )
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-status-overview")
    }
}

/// One readiness group.
///
/// Every group used to be collapsed behind a label that was only its own status
/// name, so the first thing Settings showed was two rows reading "Ready" and
/// "Set Up When Used" — no subject, no count, nothing to act on. The label now
/// carries how many items it covers, and anything needing attention starts
/// open, because that is the only group the user has to do something about.
private struct SettingsReadinessGroupView: View {
    let group: SettingsReadinessRowGroup
    let selectedRowID: String?
    let performAction: (SettingsReadinessAction) -> Void
    let onSelectRow: ((SettingsReadinessRow) -> Void)?

    @State private var isExpanded: Bool

    init(
        group: SettingsReadinessRowGroup,
        selectedRowID: String?,
        performAction: @escaping (SettingsReadinessAction) -> Void,
        onSelectRow: ((SettingsReadinessRow) -> Void)?
    ) {
        self.group = group
        self.selectedRowID = selectedRowID
        self.performAction = performAction
        self.onSelectRow = onSelectRow
        _isExpanded = State(initialValue: group.group == .needsAttention)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.rows, id: \SettingsReadinessRow.id) { (row: SettingsReadinessRow) in
                    SettingsReadinessRowView(
                        row: row,
                        isSelected: selectedRowID == row.id,
                        performAction: performAction,
                        onSelect: onSelectRow.map { callback in
                            { callback(row) }
                        }
                    )
                }
            }
            .padding(.top, 8)
        } label: {
            Label {
                HStack(spacing: SuisuiSpacing.sm) {
                    Text(localizedSettingsDisplay(group.group.title))
                    SuisuiStatusChip(
                        text: "\(group.rows.count)",
                        tone: group.group == .needsAttention ? .caution : .neutral
                    )
                    Spacer(minLength: 0)
                    // Naming the subjects makes a collapsed group answer "ready
                    // for what?" without a click.
                    Text(subjectSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } icon: {
                Image(systemName: group.group.systemImage)
                    .foregroundStyle(group.group == .needsAttention ? SuisuiTone.caution.color : .secondary)
            }
            .font(SuisuiTypography.sectionTitle)
        }
        .accessibilityLabel(localizedSettingsDisplay(group.group.title))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("settings-readiness-group-\(group.group.identifierSuffix)")
    }

    private var subjectSummary: String {
        group.rows
            .prefix(3)
            .map { localizedSettingsDisplay($0.title) }
            .joined(separator: localizedSettingsDisplay(", "))
    }

    private var accessibilityValue: String {
        let countText = localizedCount(group.rows.count, one: "%d item", other: "%d items")
        guard !group.rows.isEmpty else {
            return countText
        }
        return "\(countText): \(subjectSummary)"
    }
}

private struct SettingsReadinessRowView: View {
    let row: SettingsReadinessRow
    let isSelected: Bool
    let performAction: (SettingsReadinessAction) -> Void
    let onSelect: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.state.systemImage)
                .foregroundStyle(row.state.color)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedSettingsDisplay(row.title))
                    .font(.subheadline.weight(.semibold))
                Text(localizedSettingsDisplay(row.detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if row.action == nil {
                    Text("No action needed now.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let action = row.action {
                Button(localizedSettingsDisplay(action.title)) {
                    performAction(action)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("settings-readiness-action-\(row.id)")
                .accessibilityHint("Opens the relevant setting or retries this readiness check.")
            }
        }
        .padding(10)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: SuisuiRadius.card)
                .stroke(isSelected ? Color.accentColor : row.state.borderColor, lineWidth: isSelected ? 1.5 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-readiness-row-\(row.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension SettingsReadinessGroup {
    var title: String {
        switch self {
        case .readyNow: "Ready"
        case .setUpWhenUsed: "Set Up When Used"
        case .needsAttention: "Needs Attention"
        case .advanced: "Advanced"
        }
    }

    var identifierSuffix: String {
        switch self {
        case .readyNow: "ready"
        case .setUpWhenUsed: "setup-when-used"
        case .needsAttention: "needs-attention"
        case .advanced: "advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .readyNow: "checkmark.circle.fill"
        case .setUpWhenUsed: "circle.dashed"
        case .needsAttention: "exclamationmark.triangle.fill"
        case .advanced: "slider.horizontal.3"
        }
    }
}

private extension SettingsReadinessState {
    var color: Color {
        switch self {
        case .ready: SuisuiTone.positive.color
        case .setupWhenNeeded, .checking: .secondary
        // A warning triangle rendered in neutral gray reads as "informational"
        // and gets skipped. This is ordinary settings recovery, so it uses the
        // general caution tone instead of assistant-only Signal Amber.
        case .needsAction: SuisuiTone.caution.color
        case .blocked: SuisuiTone.danger.color
        case .unsupported: SuisuiTone.neutral.color
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .setupWhenNeeded: "circle.dashed"
        case .checking: "clock.arrow.circlepath"
        case .needsAction: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        case .unsupported: "nosign"
        }
    }

    var borderColor: Color {
        switch self {
        case .blocked:
            SuisuiBorder.danger
        case .ready, .setupWhenNeeded, .checking, .needsAction, .unsupported:
            SuisuiBorder.subtle
        }
    }
}

private extension SettingsReadinessAction {
    var title: String {
        switch self {
        case .openAI: "Open AI"
        case .openPrivacy: "Open Privacy"
        case .showAdvanced: "Show Advanced"
        case .openMCP: "Open MCP"
        case .openSync: "Open Sync"
        case .retry: "Retry"
        }
    }
}
