import XCTest
@testable import SoloPMCore

final class HostedMCPCloudRelayTests: XCTestCase {
    func testHostedMCPTaskSchemasExposeOnlyRemoteSafeTaskMutations() {
        let schemas = HostedMCPTaskToolSchema.all

        XCTAssertEqual(
            schemas.map(\.name),
            ["task_create", "task_update", "task_complete", "task_due_date_update", "task_project_move"]
        )
        XCTAssertEqual(schemas.first { $0.name == "task_create" }?.requiredArgumentKeys, ["title"])
        XCTAssertEqual(schemas.first { $0.name == "task_due_date_update" }?.requiredArgumentKeys, ["taskID", "dueAt"])
        XCTAssertFalse(schemas.contains { $0.name.contains("calendar") || $0.name.contains("filesystem") })
    }

    func testCloudRelayTaskCreateCanBecomeNotRequiredMutationAndAutomationPayload() throws {
        let request = CloudRelayTaskRequest(
            id: "relay-1",
            source: .cloudRelay,
            sourceClientID: "ios-shortcut",
            toolName: .taskCreate,
            arguments: [
                "title": .string("Capture launch task"),
                "detail": .string("Created while Mac was offline")
            ],
            receivedAt: "2026-06-21T06:10:00Z"
        )

        let mutation = try request.taskMutationPayload(policy: .defaultPersonal)
        let automation = try request.automationRequestPayload(policy: .defaultPersonal)

        XCTAssertEqual(mutation.operation, .create)
        XCTAssertEqual(mutation.title, "Capture launch task")
        XCTAssertEqual(mutation.detail, "Created while Mac was offline")
        XCTAssertEqual(mutation.source, .cloudRelay)
        XCTAssertEqual(mutation.approvalState, .notRequired)
        XCTAssertEqual(automation.id, "relay-1")
        XCTAssertEqual(automation.sourceClientID, "ios-shortcut")
        XCTAssertEqual(automation.toolName, "task_create")
        XCTAssertEqual(automation.taskMutation, mutation)
        XCTAssertEqual(automation.approvalState, .notRequired)
    }

    func testRemoteStatusDueDateAndProjectMoveRequestsStayPendingApproval() throws {
        let requests: [(CloudRelayTaskRequest, SyncTaskMutationOperation)] = [
            (
                CloudRelayTaskRequest(
                    id: "relay-update",
                    source: .hostedMCP,
                    sourceClientID: "external-llm",
                    toolName: .taskUpdate,
                    arguments: ["taskID": .number(42), "status": .string("in_progress")],
                    receivedAt: "2026-06-21T06:12:00Z"
                ),
                .update
            ),
            (
                CloudRelayTaskRequest(
                    id: "relay-due",
                    source: .hostedMCP,
                    sourceClientID: "external-llm",
                    toolName: .taskDueDateUpdate,
                    arguments: ["taskID": .number(42), "dueAt": .string("2026-06-22")],
                    receivedAt: "2026-06-21T06:13:00Z"
                ),
                .updateDueDate
            ),
            (
                CloudRelayTaskRequest(
                    id: "relay-move",
                    source: .hostedMCP,
                    sourceClientID: "external-llm",
                    toolName: .taskProjectMove,
                    arguments: ["taskID": .number(42), "projectID": .number(7)],
                    receivedAt: "2026-06-21T06:14:00Z"
                ),
                .moveProject
            )
        ]

        for (request, operation) in requests {
            let mutation = try request.taskMutationPayload(policy: .defaultPersonal)

            XCTAssertEqual(mutation.operation, operation)
            XCTAssertEqual(mutation.taskID, 42)
            XCTAssertEqual(mutation.source, .hostedMCP)
            XCTAssertEqual(mutation.approvalState, .pendingApproval)
        }
    }

    func testHostedMCPRelayRedactsArgumentsAndStoresAutomationRequestAsLedgerEntity() throws {
        let request = CloudRelayTaskRequest(
            id: "relay-secret",
            source: .hostedMCP,
            sourceClientID: "external-llm",
            toolName: .taskUpdate,
            arguments: [
                "taskID": .number(42),
                "detail": .string("Do not leak sk-relay-secret")
            ],
            receivedAt: "2026-06-21T06:15:00Z"
        )
        let encryptedPayload = EncryptedSyncPayload(
            algorithm: .xChaCha20Poly1305,
            keyID: "device-key-1",
            nonce: "nonce",
            ciphertext: "ciphertext",
            plaintextDigest: "sha256:digest"
        )

        let automation = try request.automationRequestPayload(policy: .defaultPersonal)
        let ledgerEntry = try request.ledgerEntry(
            deviceID: "cloud-relay",
            sequence: 9,
            encryptedPayload: encryptedPayload
        )

        XCTAssertTrue(automation.redactedArgumentSummary.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(automation.redactedArgumentSummary.contains("sk-relay-secret"))
        XCTAssertEqual(ledgerEntry.entity, SyncLedgerEntity(kind: .automationRequest, id: "relay-secret"))
        XCTAssertEqual(ledgerEntry.operation, .create)
        XCTAssertEqual(ledgerEntry.mergePolicy, .appendLedgerEntry)
        XCTAssertFalse(ledgerEntry.redactedAuditSummary?.contains("sk-relay-secret") ?? true)
    }
}
