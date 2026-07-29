import XCTest
@testable import SuisuiCore

final class AssistantQueueRowActionPresentationTests: XCTestCase {
    func testWaitingReviewMaximumCapabilitiesPresentsApproveThenStableSecondaryOrder() {
        let presentation = AssistantQueueRowActionPresentation.make(
            for: makeRow(
                state: .waitingReview,
                capabilities: [.approve, .edit, .defer, .reject]
            )
        )

        XCTAssertEqual(presentation.primaryAction, .approve)
        XCTAssertEqual(presentation.secondaryActions, [.edit, .defer, .reject])
    }

    func testApprovedMaximumCapabilitiesPresentsRunThenStableSecondaryOrder() {
        let presentation = AssistantQueueRowActionPresentation.make(
            for: makeRow(
                state: .approved,
                capabilities: [.run, .edit, .defer, .reject]
            )
        )

        XCTAssertEqual(presentation.primaryAction, .run)
        XCTAssertEqual(presentation.secondaryActions, [.edit, .defer, .reject])
    }

    func testFailedRetryCapabilityPresentsReopenAsTheOnlyAction() {
        let presentation = AssistantQueueRowActionPresentation.make(
            for: makeRow(state: .failed, capabilities: [.reopen])
        )

        XCTAssertEqual(presentation.primaryAction, .reopen)
        XCTAssertEqual(presentation.secondaryActions, [])
    }

    func testRunningRejectCapabilityHidesAllActionsBecauseRejectDoesNotCancelInflightExecution() {
        let presentation = AssistantQueueRowActionPresentation.make(
            for: makeRow(state: .running, capabilities: [.reject])
        )

        XCTAssertNil(presentation.primaryAction)
        XCTAssertEqual(presentation.secondaryActions, [])
    }

    func testEveryStateAndSingleCapabilityUsesExplicitFailClosedExpectation() throws {
        let hidden = Expected(primary: nil, secondary: [])
        let approve = Expected(primary: .approve, secondary: [])
        let run = Expected(primary: .run, secondary: [])
        let reopen = Expected(primary: .reopen, secondary: [])
        let edit = Expected(primary: nil, secondary: [.edit])
        let deferAction = Expected(primary: nil, secondary: [.defer])
        let reject = Expected(primary: nil, secondary: [.reject])

        // Every state names all six capability outcomes so a newly permissive
        // combination cannot silently inherit an expectation from production code.
        let expectations: [AssistantQueueState: [Capability: Expected]] = [
            .captured: [
                .approve: approve, .run: hidden, .reopen: hidden,
                .edit: edit, .defer: deferAction, .reject: reject,
            ],
            .interpreted: [
                .approve: approve, .run: hidden, .reopen: hidden,
                .edit: edit, .defer: deferAction, .reject: reject,
            ],
            .drafted: [
                .approve: approve, .run: hidden, .reopen: hidden,
                .edit: edit, .defer: deferAction, .reject: reject,
            ],
            .waitingReview: [
                .approve: approve, .run: hidden, .reopen: hidden,
                .edit: edit, .defer: deferAction, .reject: reject,
            ],
            .approved: [
                .approve: hidden, .run: run, .reopen: hidden,
                .edit: edit, .defer: deferAction, .reject: reject,
            ],
            .running: [
                .approve: hidden, .run: hidden, .reopen: hidden,
                .edit: hidden, .defer: hidden, .reject: hidden,
            ],
            .blocked: [
                .approve: hidden, .run: hidden, .reopen: hidden,
                .edit: hidden, .defer: hidden, .reject: reject,
            ],
            .done: [
                .approve: hidden, .run: hidden, .reopen: hidden,
                .edit: hidden, .defer: hidden, .reject: hidden,
            ],
            .failed: [
                .approve: hidden, .run: hidden, .reopen: reopen,
                .edit: hidden, .defer: hidden, .reject: hidden,
            ],
            .rejected: [
                .approve: hidden, .run: hidden, .reopen: hidden,
                .edit: hidden, .defer: hidden, .reject: hidden,
            ],
            .deferred: [
                .approve: approve, .run: hidden, .reopen: hidden,
                .edit: edit, .defer: hidden, .reject: reject,
            ],
        ]

        XCTAssertEqual(Set(expectations.keys), Set(AssistantQueueState.allCases))
        for state in AssistantQueueState.allCases {
            let stateExpectations = try XCTUnwrap(expectations[state])
            XCTAssertEqual(Set(stateExpectations.keys), Set(Capability.allCases))
            for capability in Capability.allCases {
                let expected = try XCTUnwrap(stateExpectations[capability])
                let presentation = AssistantQueueRowActionPresentation.make(
                    for: makeRow(state: state, capabilities: [capability])
                )

                XCTAssertEqual(
                    presentation.primaryAction,
                    expected.primary,
                    "\(state.rawValue) + \(capability.rawValue) primary"
                )
                XCTAssertEqual(
                    presentation.secondaryActions,
                    expected.secondary,
                    "\(state.rawValue) + \(capability.rawValue) secondary"
                )
            }
        }
    }

    func testProductionMaximumCapabilityMatrixForEveryStateIsStable() {
        let cases: [ProductionCase] = [
            .init(
                state: .captured,
                capabilities: [.approve, .edit, .defer, .reject],
                expected: .init(primary: .approve, secondary: [.edit, .defer, .reject])
            ),
            .init(
                state: .interpreted,
                capabilities: [.approve, .edit, .defer, .reject],
                expected: .init(primary: .approve, secondary: [.edit, .defer, .reject])
            ),
            .init(
                state: .drafted,
                capabilities: [.approve, .edit, .defer, .reject],
                expected: .init(primary: .approve, secondary: [.edit, .defer, .reject])
            ),
            .init(
                state: .waitingReview,
                capabilities: [.approve, .edit, .defer, .reject],
                expected: .init(primary: .approve, secondary: [.edit, .defer, .reject])
            ),
            .init(
                state: .approved,
                capabilities: [.run, .edit, .defer, .reject],
                expected: .init(primary: .run, secondary: [.edit, .defer, .reject])
            ),
            .init(
                state: .running,
                capabilities: [.reject],
                expected: .init(primary: nil, secondary: [])
            ),
            .init(
                state: .blocked,
                capabilities: [.reject],
                expected: .init(primary: nil, secondary: [.reject])
            ),
            .init(
                state: .done,
                capabilities: [],
                expected: .init(primary: nil, secondary: [])
            ),
            .init(
                state: .failed,
                capabilities: [.reopen],
                expected: .init(primary: .reopen, secondary: [])
            ),
            .init(
                state: .rejected,
                capabilities: [],
                expected: .init(primary: nil, secondary: [])
            ),
            .init(
                state: .deferred,
                capabilities: [.approve, .edit, .reject],
                expected: .init(primary: .approve, secondary: [.edit, .reject])
            ),
        ]

        XCTAssertEqual(Set(cases.map(\.state)), Set(AssistantQueueState.allCases))
        for testCase in cases {
            let presentation = AssistantQueueRowActionPresentation.make(
                for: makeRow(state: testCase.state, capabilities: testCase.capabilities)
            )

            XCTAssertEqual(
                presentation.primaryAction,
                testCase.expected.primary,
                "\(testCase.state.rawValue) primary"
            )
            XCTAssertEqual(
                presentation.secondaryActions,
                testCase.expected.secondary,
                "\(testCase.state.rawValue) secondary"
            )
        }
    }

    func testAllFalseCapabilitiesHideActionsForEveryState() {
        for state in AssistantQueueState.allCases {
            let presentation = AssistantQueueRowActionPresentation.make(
                for: makeRow(state: state, capabilities: [])
            )

            XCTAssertNil(presentation.primaryAction, "\(state.rawValue) primary")
            XCTAssertEqual(presentation.secondaryActions, [], "\(state.rawValue) secondary")
        }
    }

    func testInconsistentMultiplePrimaryCapabilitiesFailClosed() {
        let presentation = AssistantQueueRowActionPresentation.make(
            for: makeRow(state: .approved, capabilities: [.approve, .run])
        )

        XCTAssertNil(presentation.primaryAction)
        XCTAssertEqual(presentation.secondaryActions, [])
    }

    private enum Capability: String, CaseIterable, Hashable {
        case approve
        case run
        case reopen
        case edit
        case `defer`
        case reject
    }

    private struct Expected {
        var primary: AssistantQueueRowActionPresentation.Action?
        var secondary: [AssistantQueueRowActionPresentation.Action]
    }

    private struct ProductionCase {
        var state: AssistantQueueState
        var capabilities: Set<Capability>
        var expected: Expected
    }

    private func makeRow(
        state: AssistantQueueState,
        capabilities: Set<Capability>
    ) -> AssistantQueueReadModelRow {
        AssistantQueueReadModelRow(
            id: "row-\(state.rawValue)",
            state: state,
            stateLabel: state.rawValue,
            riskLabel: "Write",
            title: "Queue row",
            redactedSummary: "Queue row summary",
            sourcePreview: "Queue row source",
            reviewReason: "Queue row action policy test.",
            capabilityLabels: ["Task Create"],
            costPreviewLabel: "Local only",
            blockingReason: state == .blocked ? "Blocked for policy test." : nil,
            latestReceipt: nil,
            canApprove: capabilities.contains(.approve),
            canRun: capabilities.contains(.run),
            canDefer: capabilities.contains(.defer),
            canEdit: capabilities.contains(.edit),
            canRetry: capabilities.contains(.reopen),
            canReject: capabilities.contains(.reject)
        )
    }
}
