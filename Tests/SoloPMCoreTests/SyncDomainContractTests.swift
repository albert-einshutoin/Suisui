import XCTest
@testable import SoloPMCore

final class SyncDomainContractTests: XCTestCase {
    func testSyncDataClassesExposePhase13ContractClasses() {
        XCTAssertEqual(
            SyncDataClass.allCases,
            [
                .projects,
                .tasks,
                .settings,
                .conversations,
                .documents,
                .actionPlans,
                .automationRequests,
                .harnessRuns
            ]
        )
        XCTAssertEqual(SyncDataClass.conversations.displayName, "Conversations")
        XCTAssertEqual(SyncDataClass.documents.displayName, "Documents")
        XCTAssertEqual(SyncDataClass.actionPlans.displayName, "Action Plans")
        XCTAssertEqual(SyncDataClass.automationRequests.displayName, "Automation Requests")
        XCTAssertEqual(SyncDataClass.harnessRuns.displayName, "Harness Runs")
    }

    func testProjectAndTaskRecordsMapToPlatformNeutralSyncPayloads() throws {
        let project = ProjectRecord(
            id: 42,
            title: "Launch Readiness",
            status: "active",
            priority: "high",
            deadline: "2026-07-01",
            workspacePath: "/Users/example/Workspace",
            tags: ["release", "alpha"],
            sourceCommand: "Prepare launch"
        )
        let task = TaskRecord(
            id: 99,
            projectID: 42,
            title: "Write release notes",
            status: "in_progress",
            dueAt: "2026-06-24",
            priority: "high",
            sourceCommand: "Create release task",
            detail: "Summarize user-facing changes."
        )

        let payload = SyncDomainPayloadAdapter.payload(projects: [project], tasks: [task])

        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.projects, [
            SyncProjectPayload(
                id: 42,
                title: "Launch Readiness",
                status: "active",
                priority: "high",
                deadline: "2026-07-01",
                tags: ["release", "alpha"],
                sourceCommand: "Prepare launch"
            )
        ])
        XCTAssertEqual(payload.tasks, [
            SyncTaskPayload(
                id: 99,
                projectID: 42,
                title: "Write release notes",
                detail: "Summarize user-facing changes.",
                status: "in_progress",
                dueAt: "2026-06-24",
                priority: "high",
                sourceCommand: "Create release task",
                auditMetadata: SyncTaskAuditMetadata(source: .localDatabase, sourceCommand: "Create release task")
            )
        ])
    }

    func testSyncPayloadExcludesLocalOnlyPathsAndSecrets() throws {
        let project = ProjectRecord(
            id: 7,
            title: "Private Project",
            status: "active",
            priority: nil,
            deadline: nil,
            workspacePath: "/Users/example/Secrets",
            tags: [],
            sourceCommand: "token=secret-value"
        )

        let data = try JSONEncoder().encode(SyncDomainPayloadAdapter.payload(projects: [project], tasks: []))
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(encoded.contains("/Users/example/Secrets"))
        XCTAssertFalse(encoded.contains("secret-value"))
        XCTAssertTrue(encoded.contains("[REDACTED_SECRET]"))
    }

    func testTaskMutationPayloadRepresentsStatusProjectDueAndCompletionChanges() throws {
        let statusMove = SyncTaskMutationPayload(
            taskID: 99,
            operation: .update,
            status: "blocked",
            projectID: 11,
            dueAt: "2026-06-30",
            priority: "medium",
            source: .conversation,
            approvalState: .pendingApproval
        )
        let completion = SyncTaskMutationPayload(
            taskID: 99,
            operation: .complete,
            status: "completed",
            projectID: nil,
            dueAt: nil,
            priority: nil,
            source: .hostedMCP,
            approvalState: .approved
        )

        XCTAssertEqual(statusMove.operation, .update)
        XCTAssertEqual(statusMove.status, "blocked")
        XCTAssertEqual(statusMove.projectID, 11)
        XCTAssertEqual(statusMove.dueAt, "2026-06-30")
        XCTAssertEqual(statusMove.approvalState, .pendingApproval)
        XCTAssertEqual(completion.operation, .complete)
        XCTAssertEqual(completion.status, "completed")
        XCTAssertEqual(completion.source, .hostedMCP)
    }

    func testSyncDomainPayloadRoundTripsAsStableJSON() throws {
        let payload = SyncDomainPayload(
            schemaVersion: 1,
            projects: [
                SyncProjectPayload(
                    id: 1,
                    title: "Project",
                    status: "active",
                    priority: nil,
                    deadline: nil,
                    tags: [],
                    sourceCommand: nil
                )
            ],
            tasks: [
                SyncTaskPayload(
                    id: 2,
                    projectID: 1,
                    title: "Task",
                    detail: "",
                    status: "planned",
                    dueAt: nil,
                    priority: "medium",
                    sourceCommand: nil,
                    auditMetadata: SyncTaskAuditMetadata(source: .localDatabase, sourceCommand: nil)
                )
            ]
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(SyncDomainPayload.self, from: data)

        XCTAssertEqual(decoded, payload)
    }
}
