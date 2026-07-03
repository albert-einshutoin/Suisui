import XCTest
@testable import SoloPMCore

final class ExecutionUsageMeterTests: XCTestCase {
    func testWorkspaceTotalsAggregateMeasuredAndEstimatedReceiptUsage() throws {
        let snapshot = ExecutionUsageMeterReadModel.snapshot(from: [
            receipt(
                id: "estimated",
                finishedAt: "2026-06-18T09:00:00Z",
                usage: ExecutionReceiptUsage(
                    inputTokens: 1_000,
                    outputTokens: 250,
                    estimatedCostCents: 0.50,
                    currencyCode: "USD",
                    state: .estimated
                )
            ),
            receipt(
                id: "measured",
                finishedAt: "2026-06-18T10:00:00Z",
                usage: ExecutionReceiptUsage(
                    inputTokens: 400,
                    outputTokens: 100,
                    estimatedCostCents: 0.20,
                    currencyCode: "USD",
                    state: .measured
                )
            ),
            receipt(id: "unavailable", finishedAt: "2026-06-18T11:00:00Z", usage: .unavailable),
            receipt(id: "unknown", finishedAt: "2026-06-18T12:00:00Z", usage: .unknown)
        ])

        XCTAssertEqual(snapshot.summary.trackedReceiptCount, 2)
        XCTAssertEqual(snapshot.summary.estimatedReceiptCount, 1)
        XCTAssertEqual(snapshot.summary.measuredReceiptCount, 1)
        XCTAssertEqual(snapshot.summary.inputTokens, 1_400)
        XCTAssertEqual(snapshot.summary.outputTokens, 350)
        XCTAssertEqual(snapshot.summary.totalTokens, 1_750)
        XCTAssertEqual(snapshot.summary.costTotals.first?.currencyCode, "USD")
        XCTAssertEqual(snapshot.summary.costTotals.first?.estimatedCostCents ?? -1, 0.50, accuracy: 0.0001)
        XCTAssertEqual(snapshot.summary.costTotals.first?.measuredCostCents ?? -1, 0.20, accuracy: 0.0001)
        XCTAssertEqual(snapshot.dailyRows.map(\.bucketKey), ["2026-06-18"])
        XCTAssertEqual(snapshot.monthlyRows.map(\.bucketKey), ["2026-06"])
    }

    func testProjectTotalsOnlyCountProjectReferencedReceiptsAndRedactLabels() throws {
        let snapshot = ExecutionUsageMeterReadModel.snapshot(from: [
            receipt(
                id: "project",
                finishedAt: "2026-06-18T09:00:00Z",
                usage: ExecutionReceiptUsage(inputTokens: 10, outputTokens: 5, estimatedCostCents: 0.1, currencyCode: "USD"),
                references: [
                    ExecutionReceiptReference(kind: .project, id: "7", label: "Launch token=usage-secret"),
                    ExecutionReceiptReference(kind: .project, id: "7", label: "Duplicate Launch token=usage-secret"),
                    ExecutionReceiptReference(kind: .project, id: "8", label: "Secondary project token=other-secret"),
                    ExecutionReceiptReference(kind: .task, id: "42", label: "Task token=task-secret")
                ]
            ),
            receipt(
                id: "global",
                finishedAt: "2026-06-18T10:00:00Z",
                usage: ExecutionReceiptUsage(inputTokens: 90, outputTokens: 10, estimatedCostCents: 0.2, currencyCode: "USD")
            )
        ])

        XCTAssertEqual(snapshot.summary.totalTokens, 115)
        XCTAssertEqual(snapshot.projectRows.count, 1)
        let projectRow = try XCTUnwrap(snapshot.projectRows.first)
        XCTAssertEqual(projectRow.bucketKey, "project:7")
        XCTAssertFalse(snapshot.projectRows.map(\.bucketKey).contains("project:8"))
        XCTAssertEqual(projectRow.summary.totalTokens, 15)
        XCTAssertTrue(projectRow.title.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(projectRow.accessibilityValue.contains("usage-secret"))
        XCTAssertFalse(projectRow.accessibilityValue.contains("task-secret"))
    }

    func testManagedAIBillingUsageThresholdRowsCompareConfiguredCapsWithReceiptUsageBuckets() throws {
        let snapshot = ExecutionUsageMeterReadModel.snapshot(from: [
            receipt(
                id: "first-day",
                finishedAt: "2026-06-18T09:00:00Z",
                usage: ExecutionReceiptUsage(inputTokens: 100, outputTokens: 50, estimatedCostCents: 30, currencyCode: "USD")
            ),
            receipt(
                id: "latest-day",
                finishedAt: "2026-06-19T09:00:00Z",
                usage: ExecutionReceiptUsage(inputTokens: 200, outputTokens: 50, estimatedCostCents: 80, currencyCode: "USD")
            )
        ])
        let billing = ManagedAIBillingSettings(
            isEnabled: true,
            perRunCapCents: 25,
            dailyCapCents: 75,
            monthlyCapCents: 200,
            workspaceCapCents: 100
        )

        let rows = billing.usageThresholdRows(for: snapshot)

        XCTAssertEqual(rows.map(\.scope), [.daily, .monthly, .workspace])
        XCTAssertEqual(rows.map(\.title), ["Latest Daily Usage", "Latest Monthly Usage", "Workspace Receipt Usage"])
        XCTAssertEqual(rows.map(\.status), [.exceeded, .withinLimit, .exceeded])
        XCTAssertEqual(rows[0].usedCents, 80)
        XCTAssertEqual(rows[1].usedCents, 110)
        XCTAssertEqual(rows[2].usedCents, 110)
        XCTAssertTrue(rows[0].statusLabel.contains("exceeded"))
        XCTAssertTrue(rows[1].statusLabel.contains("remaining"))
        XCTAssertTrue(rows[2].accessibilityValue.contains("USD 1.10 used"))
    }

    private func receipt(
        id: String,
        finishedAt: String,
        usage: ExecutionReceiptUsage,
        references: [ExecutionReceiptReference] = []
    ) -> ExecutionReceipt {
        ExecutionReceipt(
            id: "receipt-\(id)",
            runID: "run-\(id)",
            createdAt: date(finishedAt),
            finishedAt: date(finishedAt),
            status: .succeeded,
            inputPreview: "Raw prompt token=secret",
            outputSummary: "Done",
            primaryToolName: ActionTool.taskCreate.rawValue,
            usage: usage,
            references: references,
            visibleSurfaces: [.auditLog]
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
