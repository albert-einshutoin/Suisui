import SuisuiCore
import SwiftUI

struct SettingsStatusOverviewView: View {
    let groups: [SettingsReadinessRowGroup]
    let performAction: (SettingsReadinessAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups, id: \SettingsReadinessRowGroup.group) { (group: SettingsReadinessRowGroup) in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(group.rows, id: \SettingsReadinessRow.id) { (row: SettingsReadinessRow) in
                            SettingsReadinessRowView(row: row, performAction: performAction)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label {
                        Text(localizedSettingsDisplay(group.group.title))
                    } icon: {
                        Image(systemName: group.group.systemImage)
                    }
                    .font(SuisuiTypography.sectionTitle)
                }
                .accessibilityLabel(localizedSettingsDisplay(group.group.title))
                .accessibilityIdentifier("settings-readiness-group-\(group.group.identifierSuffix)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-status-overview")
    }
}

private struct SettingsReadinessRowView: View {
    let row: SettingsReadinessRow
    let performAction: (SettingsReadinessAction) -> Void

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
                .stroke(row.state.borderColor)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-readiness-row-\(row.id)")
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
        case .needsAction: SuisuiTone.neutral.color
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
