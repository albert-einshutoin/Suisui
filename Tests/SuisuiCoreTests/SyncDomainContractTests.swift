import XCTest
@testable import SuisuiCore

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

    func testAutomationRequestDecodesLegacyTaskMutationPayloadWithoutDevelopmentPullRequest() throws {
        let json = """
        {
          "id": "legacy-task-mutation",
          "source": "cloudRelay",
          "approvalState": "pendingApproval",
          "sourceClientID": "web",
          "toolName": "task_due_date_update",
          "redactedArgumentSummary": "taskID=42",
          "taskMutation": {
            "taskID": 42,
            "operation": "updateDueDate",
            "dueAt": "2026-07-03T09:00:00Z",
            "source": "cloudRelay",
            "approvalState": "pendingApproval"
          }
        }
        """.data(using: .utf8)!

        let request = try JSONDecoder().decode(SyncAutomationRequestPayload.self, from: json)

        XCTAssertEqual(request.id, "legacy-task-mutation")
        XCTAssertEqual(request.taskMutation?.operation, .updateDueDate)
        XCTAssertNil(request.developmentPullRequest)
    }

    func testDevelopmentPullRequestAutomationPayloadRoundTripsThroughJSON() throws {
        let request = SyncAutomationRequestPayload(
            id: "pr-review",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
            redactedArgumentSummary: "Review PR",
            developmentPullRequest: SyncDevelopmentPullRequestPayload(
                projectID: 7,
                operation: .reviewGate,
                pullRequestURL: "https://github.com/albert-einshutoin/suisui/pull/116",
                branchName: "feature/suisui-7-merge-gate",
                baseBranch: "feature/phase14-product-completion"
            )
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SyncAutomationRequestPayload.self, from: data)

        XCTAssertEqual(decoded, request)
        XCTAssertNil(decoded.taskMutation)
        XCTAssertEqual(decoded.developmentPullRequest?.operation, .reviewGate)
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
