import XCTest
@testable import SuisuiCore

final class ApprovalBindingTests: XCTestCase {
    func testCanonicalJSONIgnoresDictionaryInsertionOrderAndPreservesNumberNullAndUnicode() throws {
        let first: JSONValue = .object([
            "unicode": .string("すいすい🌊"),
            "number": .number(1.5),
            "nullable": .null
        ])
        let second: JSONValue = .object([
            "nullable": .null,
            "number": .number(1.5),
            "unicode": .string("すいすい🌊")
        ])

        let firstData = try CanonicalJSONEncoder.encode(first)
        let secondData = try CanonicalJSONEncoder.encode(second)

        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(
            String(decoding: firstData, as: UTF8.self),
            #"{"nullable":null,"number":1.5,"unicode":"すいすい🌊"}"#
        )
    }

    func testCanonicalJSONNormalizesNegativeZeroAndRejectsNonFiniteNumbers() throws {
        XCTAssertEqual(
            String(decoding: try CanonicalJSONEncoder.encode(.number(-0.0)), as: UTF8.self),
            "0"
        )
        XCTAssertThrowsError(try CanonicalJSONEncoder.encode(.number(.infinity))) { error in
            XCTAssertEqual(error as? CanonicalJSONError, .nonFiniteNumber)
        }
    }

    func testTypedActionOutputReferenceHasStableCanonicalRepresentation() throws {
        let reference = ActionOutputReference(actionID: "create-project", key: "projectId")

        XCTAssertEqual(
            String(decoding: try CanonicalJSONEncoder.encode(.actionOutput(reference)), as: UTF8.self),
            #"{"$type":"actionOutput","actionID":"create-project","key":"projectId"}"#
        )
    }

    func testPlanDigestCoversOrderRiskEnabledArgumentsDependencyAndExecutionPolicy() throws {
        let reference = JSONValue.actionOutput(
            ActionOutputReference(actionID: "create-project", key: "projectId")
        )
        let items = [
            ApprovalPlanItem(
                action: PlanAction(
                    id: "create-project",
                    tool: .projectCreate,
                    arguments: ["title": .string("Alpha")]
                ),
                isEnabled: true
            ),
            ApprovalPlanItem(
                action: PlanAction(
                    id: "create-task",
                    tool: .taskCreate,
                    arguments: ["title": .string("Draft"), "projectId": reference]
                ),
                isEnabled: true
            )
        ]
        let baseline = ApprovalPlanBinding(
            planID: "plan-1",
            items: items,
            executionPolicy: .stopOnFailure
        )

        let baselineDigest = try baseline.digest()
        XCTAssertNotEqual(
            baselineDigest,
            try ApprovalPlanBinding(
                planID: "plan-1",
                items: Array(items.reversed()),
                executionPolicy: .stopOnFailure
            ).digest()
        )

        var changedRisk = items
        changedRisk[1].action.riskLevel = .danger
        XCTAssertNotEqual(
            baselineDigest,
            try ApprovalPlanBinding(
                planID: "plan-1",
                items: changedRisk,
                executionPolicy: .stopOnFailure
            ).digest()
        )

        var changedEnabled = items
        changedEnabled[1].isEnabled = false
        XCTAssertNotEqual(
            baselineDigest,
            try ApprovalPlanBinding(
                planID: "plan-1",
                items: changedEnabled,
                executionPolicy: .stopOnFailure
            ).digest()
        )

        var changedArguments = items
        changedArguments[1].action.arguments["title"] = .string("Edited")
        XCTAssertNotEqual(
            baselineDigest,
            try ApprovalPlanBinding(
                planID: "plan-1",
                items: changedArguments,
                executionPolicy: .stopOnFailure
            ).digest()
        )

        var changedReference = items
        changedReference[1].action.arguments["projectId"] = .actionOutput(
            ActionOutputReference(actionID: "other-project", key: "projectId")
        )
        XCTAssertNotEqual(
            baselineDigest,
            try ApprovalPlanBinding(
                planID: "plan-1",
                items: changedReference,
                executionPolicy: .stopOnFailure
            ).digest()
        )

        XCTAssertNotEqual(
            baselineDigest,
            try ApprovalPlanBinding(
                planID: "plan-1",
                items: items,
                executionPolicy: .continueOnFailure
            ).digest()
        )
    }

    func testApprovedExecutionRejectsCrossSessionPlanMutationExpiryAndEnabledSetMismatch() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let binding = ApprovalPlanBinding(
            planID: "plan-1",
            items: [
                ApprovalPlanItem(
                    action: PlanAction(
                        id: "task",
                        tool: .taskCreate,
                        arguments: ["title": .string("Draft")]
                    ),
                    isEnabled: true
                )
            ],
            executionPolicy: .stopOnFailure
        )
        let approved = ApprovedExecution(
            approvalID: UUID(),
            sessionID: "session-1",
            planID: binding.planID,
            canonicalPlanDigest: try binding.digest(),
            enabledActionIDs: binding.enabledActionIDs,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(300),
            nonce: UUID()
        )

        XCTAssertNoThrow(try approved.validate(for: binding, sessionID: "session-1", now: now))
        XCTAssertThrowsError(try approved.validate(for: binding, sessionID: "session-2", now: now)) { error in
            XCTAssertEqual(error as? ApprovedExecutionValidationError, .sessionMismatch)
        }

        var otherPlan = binding
        otherPlan.planID = "plan-2"
        XCTAssertThrowsError(try approved.validate(for: otherPlan, sessionID: "session-1", now: now)) { error in
            XCTAssertEqual(error as? ApprovedExecutionValidationError, .planMismatch)
        }

        var mutated = binding
        mutated.items[0].action.arguments["title"] = .string("Mutated")
        XCTAssertThrowsError(try approved.validate(for: mutated, sessionID: "session-1", now: now)) { error in
            XCTAssertEqual(error as? ApprovedExecutionValidationError, .digestMismatch)
        }

        var disabled = binding
        disabled.items[0].isEnabled = false
        let wrongEnabledEnvelope = ApprovedExecution(
            approvalID: approved.approvalID,
            sessionID: approved.sessionID,
            planID: disabled.planID,
            canonicalPlanDigest: try disabled.digest(),
            enabledActionIDs: approved.enabledActionIDs,
            issuedAt: approved.issuedAt,
            expiresAt: approved.expiresAt,
            nonce: approved.nonce
        )
        XCTAssertThrowsError(
            try wrongEnabledEnvelope.validate(for: disabled, sessionID: "session-1", now: now)
        ) { error in
            XCTAssertEqual(error as? ApprovedExecutionValidationError, .enabledActionsMismatch)
        }

        XCTAssertThrowsError(
            try approved.validate(for: binding, sessionID: "session-1", now: approved.expiresAt)
        ) { error in
            XCTAssertEqual(error as? ApprovedExecutionValidationError, .expired)
        }
    }
}
