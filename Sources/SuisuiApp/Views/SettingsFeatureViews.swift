import AppKit
import SuisuiCore
import SuisuiGoogleCalendarRuntime
import SwiftUI

enum SettingsFeatureLoadState<Value> {
    case loading
    case unavailable
    case loaded(Value)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

@MainActor
struct SettingsOverviewFeatureView: View {
    let dependencies: SettingsOverviewDependencies
    @State private var selectedRowID: String?
    @Environment(\.cockpitAuthoritativeContentWidth) private var authoritativeContentWidth

    private var selectedRow: SettingsReadinessRow? {
        let rows = dependencies.groups.flatMap(\.rows)
        if let selectedRowID {
            return rows.first { $0.id == selectedRowID } ?? rows.first
        }
        return rows.first
    }

    var body: some View {
        GeometryReader { proxy in
            let layoutWidth = CockpitSplitLayout.layoutWidth(measuredWidth: proxy.size.width, authoritativeContentWidth: authoritativeContentWidth)
            let isWide = CockpitSplitLayout.presentsSplitRail(
                measuredWidth: proxy.size.width,
                authoritativeContentWidth: authoritativeContentWidth
            )
            let railWidth = CockpitSplitLayout.railWidth(for: .settings, contentWidth: layoutWidth)
            Group {
                if isWide {
                    HStack(alignment: .top, spacing: CGFloat(CockpitLayoutPolicy.splitSpacing)) {
                        overviewForm
                            .cockpitSplitPrimaryColumn()
                        overviewDetailRail
                            .cockpitSplitSecondaryRail(width: railWidth)
                    }
                    .frame(width: layoutWidth, height: proxy.size.height, alignment: .topLeading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: CGFloat(CockpitLayoutPolicy.splitSpacing)) {
                            overviewForm
                            overviewDetailRail
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .onAppear {
            if selectedRowID == nil {
                selectedRowID = dependencies.groups.flatMap(\.rows).first?.id
            }
        }
        .onChange(of: dependencies.groups.map(\.group)) { _, _ in
            let rows = dependencies.groups.flatMap(\.rows)
            if let selectedRowID, rows.contains(where: { $0.id == selectedRowID }) {
                return
            }
            self.selectedRowID = rows.first?.id
        }
    }

    private var overviewForm: some View {
        Form {
            Section("Status Overview") {
                SettingsStatusOverviewView(
                    groups: dependencies.groups,
                    performAction: dependencies.performReadinessAction,
                    selectedRowID: selectedRowID,
                    onSelectRow: { selectedRowID = $0.id }
                )

                Button {
                    // The rerun request is owned by the app-level coordinator so
                    // it works even when no Project Board window is mounted and
                    // never opens more than one onboarding sheet.
                    dependencies.rerunOnboarding()
                } label: {
                    Label("Run Setup Again", systemImage: "arrow.clockwise.circle")
                }
                .accessibilityIdentifier("settings-run-onboarding")
                .accessibilityHint("Reopens onboarding to review current provider and permission readiness.")
            }

            if dependencies.showAdvanced {
                Section("Pro Value") {
                    ProValueOverviewRow(
                        syncStatusLabel: dependencies.syncStatusLabel,
                        syncValueLabel: dependencies.syncValueLabel,
                        syncBoundaryLabel: dependencies.syncBoundaryLabel,
                        syncTone: dependencies.syncTone,
                        mcpStatusLabel: dependencies.mcpStatusLabel,
                        mcpValueLabel: dependencies.mcpValueLabel,
                        mcpBoundaryLabel: dependencies.mcpBoundaryLabel,
                        mcpTone: dependencies.mcpTone
                    )
                }
            }

            Section("Advanced") {
                Toggle("Show advanced settings", isOn: dependencies.$showAdvanced)
                    .accessibilityIdentifier("settings-show-advanced-toggle")
                    .accessibilityHint("Reveals the MCP and Sync tabs and advanced AI options.")

                Text("Reveals MCP, Sync, and managed billing controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var overviewDetailRail: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            Label("Selected readiness", systemImage: "sidebar.right")
                .font(SuisuiTypography.sectionTitle)

            if let selectedRow {
                Text(localizedSettingsDisplay(selectedRow.title))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Text(localizedSettingsDisplay(selectedRow.detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let action = selectedRow.action {
                    Button(actionTitle(for: action)) {
                        dependencies.performReadinessAction(action)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("settings-overview-detail-action")
                } else {
                    Text("No action needed now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select a readiness row to review details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-overview-detail-rail")
    }

    private func actionTitle(for action: SettingsReadinessAction) -> String {
        switch action {
        case .openAI: localizedSettingsDisplay("Open AI")
        case .openPrivacy: localizedSettingsDisplay("Open Privacy")
        case .showAdvanced: localizedSettingsDisplay("Show Advanced")
        case .openMCP: localizedSettingsDisplay("Open MCP")
        case .openSync: localizedSettingsDisplay("Open Sync")
        case .retry: localizedSettingsDisplay("Retry")
        }
    }
}

@MainActor
struct SettingsAppearanceFeatureView: View {
    let context: SettingsAppearanceDependencies

    var body: some View {
        Form {
            SettingsAppearanceSection(appearancePreference: context.$appearancePreference, languagePreference: context.$languagePreference)
        }
        .formStyle(.grouped)
    }
}

@MainActor
struct SettingsOverviewDependencies {
    let groups: [SettingsReadinessRowGroup]
    @Binding var showAdvanced: Bool
    let syncStatusLabel: String
    let syncValueLabel: String
    let syncBoundaryLabel: String
    let syncTone: SettingsStatusTone
    let mcpStatusLabel: String
    let mcpValueLabel: String
    let mcpBoundaryLabel: String
    let mcpTone: SettingsStatusTone
    let performReadinessAction: (SettingsReadinessAction) -> Void
    let rerunOnboarding: () -> Void
}

@MainActor
struct SettingsAppearanceDependencies {
    @Binding var appearancePreference: SuisuiAppearancePreference
    @Binding var languagePreference: AppLanguagePreference
}

struct ProValueOverviewRow: View {
    let syncStatusLabel: String
    let syncValueLabel: String
    let syncBoundaryLabel: String
    let syncTone: SettingsStatusTone
    let mcpStatusLabel: String
    let mcpValueLabel: String
    let mcpBoundaryLabel: String
    let mcpTone: SettingsStatusTone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pro unlocks sync and advanced MCP execution", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))

            Text("Local Project and Task CRUD stays free. Paid paths fail closed before upload or tools/call when entitlement, backend, policy, or approval is missing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ProValueOverviewItem(
                        title: "Sync",
                        statusLabel: syncStatusLabel,
                        valueLabel: syncValueLabel,
                        boundaryLabel: syncBoundaryLabel,
                        tone: syncTone,
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    Divider()
                    ProValueOverviewItem(
                        title: "MCP Execution",
                        statusLabel: mcpStatusLabel,
                        valueLabel: mcpValueLabel,
                        boundaryLabel: mcpBoundaryLabel,
                        tone: mcpTone,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProValueOverviewItem(
                        title: "Sync",
                        statusLabel: syncStatusLabel,
                        valueLabel: syncValueLabel,
                        boundaryLabel: syncBoundaryLabel,
                        tone: syncTone,
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    Divider()
                    ProValueOverviewItem(
                        title: "MCP Execution",
                        statusLabel: mcpStatusLabel,
                        valueLabel: mcpValueLabel,
                        boundaryLabel: mcpBoundaryLabel,
                        tone: mcpTone,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings-pro-value-overview-row")
        .accessibilityLabel("Pro value overview")
        .accessibilityValue("\(syncStatusLabel). \(syncBoundaryLabel). \(mcpStatusLabel). \(mcpBoundaryLabel)")
    }
}

struct ProValueOverviewItem: View {
    let title: String
    let statusLabel: String
    let valueLabel: String
    let boundaryLabel: String
    let tone: SettingsStatusTone
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.color)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(localizedSettingsDisplay(statusLabel))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .lineLimit(1)

                Text(localizedSettingsDisplay(valueLabel))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label(localizedSettingsDisplay(boundaryLabel), systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(localizedSettingsDisplay(statusLabel)), \(localizedSettingsDisplay(boundaryLabel))")
    }
}

struct LocalizedValueLabeledContent: View {
    let title: LocalizedStringKey
    let value: String

    init(_ title: LocalizedStringKey, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        LabeledContent {
            Text(localizedSettingsDisplay(value))
        } label: {
            Text(title)
        }
    }
}

enum SettingsStatusTone {
    case ready
    case warning
    case danger
    case neutral

    var color: Color {
        switch self {
        case .ready:
            .green
        case .warning:
            .orange
        case .danger:
            .red
        case .neutral:
            .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .danger:
            "xmark.octagon.fill"
        case .neutral:
            "circle.dashed"
        }
    }
}
