import AppKit
import SuisuiCore
import SuisuiGoogleCalendarRuntime
import SwiftUI

@MainActor
struct SettingsMCPFeatureView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    let context: SettingsMCPDependencies

    @ViewBuilder
    var body: some View {
        Group {
            if case .loaded(let loadedExternalMCPViewModel) = context.loadState {
                Form {
                    Section("External MCP") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Servers", systemImage: "externaldrive.connected.to.line.below")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    loadedExternalMCPViewModel.createRegistration()
                                } label: {
                                    Label("Add Server", systemImage: "plus")
                                }
                            }

                            ForEach(loadedExternalMCPViewModel.registrationRows) { row in
                                MCPServerSettingsRow(
                                    row: row,
                                    isCheckDisabled: loadedExternalMCPViewModel.isCheckingConnection,
                                    onSelect: {
                                        loadedExternalMCPViewModel.selectRegistration(id: row.id)
                                    },
                                    onCheck: {
                                        Task {
                                            await loadedExternalMCPViewModel.checkConnection(id: row.id)
                                        }
                                    }
                                )
                            }
                        }

                        MCPPaidExecutionBoundaryRow(
                            planLabel: context.planLabel,
                            statusLabel: context.mcpExecutionStatusLabel,
                            valueLabel: context.mcpExecutionValueLabel,
                            boundaryLabel: context.mcpExecutionSafetyBoundaryLabel,
                            tone: context.mcpExecutionTone
                        )

                        Toggle(
                            isOn: Binding(
                                get: { loadedExternalMCPViewModel.registration.isEnabled },
                                set: { loadedExternalMCPViewModel.updateEnabled($0) }
                            )
                        ) {
                            Label("Server Enabled", systemImage: "externaldrive.connected.to.line.below")
                        }
                        TextField("Display Name", text: Binding(
                            get: { loadedExternalMCPViewModel.registration.displayName },
                            set: { loadedExternalMCPViewModel.updateDisplayName($0) }
                        ))
                        TextField("Command", text: Binding(
                            get: { loadedExternalMCPViewModel.registration.command },
                            set: { loadedExternalMCPViewModel.updateCommand($0) }
                        ))
                        TextField("Arguments", text: Binding(
                            get: { loadedExternalMCPViewModel.argumentsText },
                            set: { loadedExternalMCPViewModel.updateArgumentsText($0) }
                        ))
                        LocalPathSelectionField(
                            title: "Working Directory",
                            text: Binding(
                                get: { loadedExternalMCPViewModel.registration.workingDirectory ?? "" },
                                set: { loadedExternalMCPViewModel.updateWorkingDirectory($0) }
                            ),
                            selectionKind: .directory,
                            accessibilityIdentifier: "settings-mcp-working-directory"
                        )
                        TextField("Environment References", text: Binding(
                            get: { loadedExternalMCPViewModel.environmentText },
                            set: { loadedExternalMCPViewModel.updateEnvironmentText($0) }
                        ), axis: .vertical)
                        .lineLimit(2...4)
                        .help("Use NAME=keychain:secret_key per line. Raw secret values are rejected.")

                        Group {
                            LocalizedValueLabeledContent("MCP Keychain Secret", value: settingsViewModel.keychainSecretStatusLabel)
                            TextField("Secret Key", text: Binding(
                                get: { settingsViewModel.keychainSecretKeyInput },
                                set: { settingsViewModel.updateKeychainSecretKeyInput($0) }
                            ))
                            .help("Use the same key name referenced by keychain:<secret_key>.")
                            SecureField("Secret Value", text: Binding(
                                get: { settingsViewModel.keychainSecretValueInput },
                                set: { settingsViewModel.updateKeychainSecretValueInput($0) }
                            ))
                            HStack {
                                Button {
                                    settingsViewModel.saveKeychainSecret()
                                } label: {
                                    Label("Save Secret", systemImage: "key")
                                }
                                .disabled(
                                    settingsViewModel.keychainSecretKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                    settingsViewModel.keychainSecretValueInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                )

                                Button(role: .destructive) {
                                    settingsViewModel.deleteKeychainSecret()
                                } label: {
                                    Label("Delete Secret", systemImage: "trash")
                                }
                                .disabled(settingsViewModel.keychainSecretKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }

                        LabeledContent("Transport", value: loadedExternalMCPViewModel.display.transportLabel)
                        LocalizedValueLabeledContent("Status", value: loadedExternalMCPViewModel.display.statusLabel)
                        LabeledContent("Protocol Version", value: loadedExternalMCPViewModel.protocolVersionLabel)
                        LocalizedValueLabeledContent("Check Result", value: loadedExternalMCPViewModel.connectionCheckResultLabel)
                        LocalizedValueLabeledContent("Resources", value: "Not supported in this release")
                        LocalizedValueLabeledContent("Prompts", value: "Not supported in this release")
                        ForEach(loadedExternalMCPViewModel.display.environmentRows, id: \.name) { row in
                            LabeledContent(row.name, value: row.sourceLabel)
                        }
                        if let errorMessage = loadedExternalMCPViewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        HStack {
                            Button {
                                loadedExternalMCPViewModel.save()
                            } label: {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }

                            Button(role: .destructive) {
                                context.isConfirmingMCPRegistrationDeletion = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                Task {
                                    await loadedExternalMCPViewModel.checkConnection()
                                }
                            } label: {
                                Label("Check Connection", systemImage: "network")
                            }
                            .disabled(loadedExternalMCPViewModel.isCheckingConnection)

                            if loadedExternalMCPViewModel.isCheckingConnection {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }

                    Section("MCP Tool Permissions") {
                        if loadedExternalMCPViewModel.toolRows.isEmpty {
                            Text("No tools discovered")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(loadedExternalMCPViewModel.toolRows, id: \.id) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(row.title, systemImage: toolPermissionIcon(row.permissionLevel))
                                    Spacer()
                                    Text(row.permissionLabel)
                                        .font(.caption)
                                        .foregroundStyle(toolPermissionColor(row.permissionLevel))
                                }
                                Text(row.inputSchemaSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }

                    Section("MCP Audit") {
                        if let auditErrorMessage = loadedExternalMCPViewModel.auditErrorMessage {
                            Label(auditErrorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if loadedExternalMCPViewModel.auditRows.isEmpty {
                            Text("No external calls recorded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(loadedExternalMCPViewModel.auditRows.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(row.toolName, systemImage: row.status == .failed ? "xmark.octagon" : "checkmark.circle")
                                    Spacer()
                                    Text(localizedSettingsDisplay(row.statusLabel))
                                        .font(.caption)
                                        .foregroundStyle(row.status == .failed ? .red : .secondary)
                                }
                                Text("\(row.serverName) / \(row.risk) / \(row.approval)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else if context.loadState.isLoading {
                Form {
                    Section("External MCP") {
                        HStack {
                            ProgressView()
                            Text("Loading MCP settings...")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("settings-mcp-loading")
                    }
                }
                .formStyle(.grouped)
            } else {
                Form {
                    Section("External MCP") {
                        Text("MCP settings not loaded yet.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-mcp-unavailable")
                        settingsLazyLoadUnavailableHint(message: "MCP settings load when this tab is opened.")
                    }
                }
                .formStyle(.grouped)
            }
        }
    }
}
@MainActor
struct SettingsMCPDependencies {
    let loadState: SettingsFeatureLoadState<ExternalMCPSettingsViewModel>
    let planLabel: String
    let mcpExecutionStatusLabel: String
    let mcpExecutionValueLabel: String
    let mcpExecutionSafetyBoundaryLabel: String
    let mcpExecutionTone: SettingsStatusTone
    @Binding var isConfirmingMCPRegistrationDeletion: Bool
}

private extension SettingsMCPFeatureView {
    func settingsLazyLoadUnavailableHint(message: String) -> some View {
        Label(message, systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .accessibilityIdentifier("settings-tab-lazy-load-hint")
    }

    func toolPermissionIcon(_ permission: ExternalMCPToolPermission) -> String {
        switch permission {
        case .read:
            "eye"
        case .draft:
            "doc.text"
        case .writeWithApproval:
            "checkmark.seal"
        case .dangerous:
            "exclamationmark.triangle"
        case .disabled:
            "nosign"
        }
    }

    func toolPermissionColor(_ permission: ExternalMCPToolPermission) -> Color {
        switch permission {
        case .read, .draft:
            .secondary
        case .writeWithApproval:
            .orange
        case .dangerous:
            .red
        case .disabled:
            .secondary
        }
    }
}

struct MCPServerSettingsRow: View {
    let row: MCPServerRegistrationRow
    let isCheckDisabled: Bool
    let onSelect: () -> Void
    let onCheck: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(row.isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(row.commandLine.isEmpty ? "Command not set" : row.commandLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                MCPServerStatusBadge(label: row.statusLabel)
                                MCPServerConnectionBadge(label: row.connectionCheckResultLabel)
                                Text("Protocol: \(row.protocolVersionLabel)")
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                MCPServerStatusBadge(label: row.statusLabel)
                                MCPServerConnectionBadge(label: row.connectionCheckResultLabel)
                                Text("Protocol: \(row.protocolVersionLabel)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Select \(row.displayName)")
            .accessibilityLabel(row.isSelected ? "Selected MCP server \(row.displayName)" : "Select MCP server \(row.displayName)")

            if row.isCheckingConnection {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: onCheck) {
                Label("Check", systemImage: "network")
            }
            .controlSize(.small)
            .disabled(isCheckDisabled)
            .help("Check \(row.displayName) connection")
            .accessibilityLabel("Check \(row.displayName) connection")
        }
        .padding(.vertical, 4)
    }
}

struct MCPServerStatusBadge: View {
    let label: String

    var body: some View {
        Label(localizedSettingsDisplay(label), systemImage: label == "Enabled" ? "checkmark.circle" : "pause.circle")
            .foregroundStyle(label == "Enabled" ? .green : .secondary)
            .lineLimit(1)
    }
}

struct MCPServerConnectionBadge: View {
    let label: String

    var body: some View {
        Label(localizedSettingsDisplay(label), systemImage: systemImage)
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
    }

    private var systemImage: String {
        if label == "Connected" {
            return "network"
        }
        if label == "Checking" {
            return "clock"
        }
        if label.hasPrefix("Failed") {
            return "exclamationmark.triangle"
        }
        return "questionmark.circle"
    }

    private var foregroundStyle: Color {
        if label == "Connected" {
            return .green
        }
        if label.hasPrefix("Failed") {
            return .red
        }
        return .secondary
    }
}

struct MCPPaidExecutionBoundaryRow: View {
    let planLabel: String
    let statusLabel: String
    let valueLabel: String
    let boundaryLabel: String
    let tone: SettingsStatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(tone.color)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedDisplay("%@ MCP Execution", planLabel))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(localizedSettingsDisplay(statusLabel))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .lineLimit(1)

                Text(localizedSettingsDisplay(valueLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label(localizedSettingsDisplay(boundaryLabel), systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mcp-paid-execution-boundary-row")
        .accessibilityLabel("MCP paid execution boundary")
        .accessibilityValue("\(planLabel), \(localizedSettingsDisplay(statusLabel)), \(localizedSettingsDisplay(boundaryLabel))")
    }
}
