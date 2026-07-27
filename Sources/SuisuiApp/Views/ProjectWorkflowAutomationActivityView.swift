import Foundation
import SuisuiCore
import SwiftUI
import UniformTypeIdentifiers

/// Automation Activity is intentionally separate from completed work: a
/// successful execution receipt is audit evidence, not proof that a user's
/// task or project reached its completed state.
struct ProjectWorkflowAutomationActivityView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    let appSettings: AppSettings
    @State private var isExportingExecutionReceipts = false
    @State private var executionReceiptExportDocument = ExecutionReceiptHistoryFileDocument(data: Data())

    init(viewModel: ProjectBoardViewModel, appSettings: AppSettings = .default) {
        self.viewModel = viewModel
        self.appSettings = appSettings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Execution Record", systemImage: "doc.text.magnifyingglass")
                    .font(.title2.weight(.semibold))

                Text("Review receipt-derived AI usage and redacted execution history. This audit activity does not change completed task or project state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("automation-activity-boundary-note")

                VStack(alignment: .leading, spacing: 10) {
                    Label("AI Usage Meter", systemImage: "chart.bar.xaxis")
                        .font(.headline)
                    ExecutionUsageMeterSummaryView(
                        snapshot: viewModel.executionUsageMeterSnapshot,
                        managedAIBilling: appSettings.managedAIBilling
                    )
                }
                .accessibilityIdentifier("ai-usage-meter-summary")

                VStack(alignment: .leading, spacing: 10) {
                    Label("Recent AI Activity", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    HStack(spacing: 8) {
                        TextField(
                            "Search AI activity",
                            text: Binding(
                                get: { viewModel.executionReceiptHistorySearchText },
                                set: { viewModel.setExecutionReceiptHistorySearchText($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("execution-receipt-search-field")

                        Menu {
                            Button("All Statuses") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(nil)
                            }
                            Divider()
                            Button("Succeeded") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.succeeded)
                            }
                            Button("Failed") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.failed)
                            }
                            Button("Canceled") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.canceled)
                            }
                            Button("Running") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.running)
                            }
                        } label: {
                            Label(receiptStatusFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityIdentifier("execution-receipt-status-filter")

                        Menu {
                            Button("All References") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(nil)
                            }
                            Divider()
                            Button("Task") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.task)
                            }
                            Button("Project") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.project)
                            }
                            Button("Document") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.document)
                            }
                            Button("Reminder") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.reminder)
                            }
                            Button("Calendar Event") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.calendarEvent)
                            }
                            Button("Development Branch") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.developmentBranch)
                            }
                            Button("Pull Request") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.pullRequest)
                            }
                        } label: {
                            Label(receiptReferenceFilterLabel, systemImage: "tag")
                        }
                        .accessibilityIdentifier("execution-receipt-reference-filter")

                        Button {
                            viewModel.prepareExecutionReceiptHistoryExport()
                            guard let data = viewModel.executionReceiptHistoryExportData else {
                                return
                            }
                            executionReceiptExportDocument = ExecutionReceiptHistoryFileDocument(data: data)
                            isExportingExecutionReceipts = true
                        } label: {
                            Label("Export JSON", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.executionReceiptHistorySnapshot.rows.isEmpty)
                        .accessibilityIdentifier("execution-receipt-export-button")
                    }
                    .font(.caption)

                    if let exportMessage = viewModel.executionReceiptHistoryExportMessage {
                        Label(exportMessage, systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("execution-receipt-export-message")
                    }
                    if let unavailableMessage = viewModel.executionReceiptHistorySnapshot.unavailableMessage {
                        ContentUnavailableView(
                            "AI activity is unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(unavailableMessage)
                        )
                    } else if viewModel.executionReceiptHistorySnapshot.rows.isEmpty {
                        ContentUnavailableView(
                            "No AI activity yet",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("AI activity appears here after approved AI work runs.")
                        )
                    } else {
                        ForEach(viewModel.executionReceiptHistorySnapshot.rows) { row in
                            ExecutionReceiptHistoryRowView(row: row)
                        }
                    }
                }
                .accessibilityIdentifier("recent-ai-receipts")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("automation-activity-workflow")
        .onAppear {
            viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()
        }
        .fileExporter(
            isPresented: $isExportingExecutionReceipts,
            document: executionReceiptExportDocument,
            contentType: .json,
            defaultFilename: executionReceiptDefaultExportFilename
        ) { result in
            switch result {
            case .success:
                viewModel.recordExecutionReceiptHistoryExportCompleted()
                executionReceiptExportDocument = ExecutionReceiptHistoryFileDocument(data: Data())
            case .failure(let error):
                viewModel.recordExecutionReceiptHistoryFileFailure(error)
            }
        }
    }

    private var receiptStatusFilterLabel: LocalizedStringKey {
        guard let status = viewModel.executionReceiptHistoryStatusFilter else {
            return "All Statuses"
        }
        switch status {
        case .notStarted: return "Not Started"
        case .running: return "Running"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        case .canceled: return "Canceled"
        }
    }

    private var receiptReferenceFilterLabel: LocalizedStringKey {
        guard let referenceKind = viewModel.executionReceiptHistoryReferenceKindFilter else {
            return "All References"
        }
        switch referenceKind {
        case .unknown: return "Unknown"
        case .assistantQueue: return "Assistant Queue"
        case .actionPlan: return "Action Plan"
        case .reviewSession: return "Review Session"
        case .task: return "Task"
        case .project: return "Project"
        case .document: return "Document"
        case .calendarEvent: return "Calendar Event"
        case .notification: return "Notification"
        case .reminder: return "Reminder"
        case .developmentBranch: return "Development Branch"
        case .developmentBaseBranch: return "Development Base Branch"
        case .developmentCommit: return "Development Commit"
        case .file: return "File"
        case .pullRequest: return "Pull Request"
        case .externalMCP: return "External MCP"
        }
    }

    private var executionReceiptDefaultExportFilename: String {
        "suisui-receipts-\(Self.exportDateFormatter.string(from: Date())).json"
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
