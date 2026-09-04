import XCTest
@testable import SuisuiCore

final class LocalTriageTests: XCTestCase {
    private let router = LocalTriageRouter()

    func testExactTaskStatusChangeUsesDeterministicReviewRoute() {
        let decision = router.evaluate(request(
            "このTaskをDoneへ移動",
            scope: .task,
            selectedTaskID: 42,
            capabilities: [.taskRead, .taskWrite]
        ))

        XCTAssertEqual(decision.route, .deterministic)
        XCTAssertEqual(decision.capability, .taskWrite)
        XCTAssertEqual(decision.requiredApproval, .explicitApproval)
        XCTAssertTrue(decision.reasons.contains(.exactDeterministicOperation))
        XCTAssertTrue(decision.reasons.contains(.externalWriteRequiresApproval) == false)
    }

    func testExplicitTaskAndProjectReferencesUseDeterministicProjectMoveRoute() {
        let decision = router.evaluate(request(
            "#42をLaunchプロジェクトへ移動",
            scope: .project,
            selectedProjectID: 7,
            capabilities: [.taskWrite, .projectWrite]
        ))

        XCTAssertEqual(decision.route, .deterministic)
        XCTAssertEqual(decision.capability, .projectWrite)
        XCTAssertEqual(decision.requiredApproval, .explicitApproval)
    }

    func testAmbiguousTaskReferenceRequiresClarificationWithoutMutation() {
        let decision = router.evaluate(request(
            "このTaskをDoneへ移動",
            scope: .task,
            capabilities: [.taskRead, .taskWrite]
        ))

        XCTAssertEqual(decision.route, .clarification)
        XCTAssertTrue(decision.missingFields.contains(.taskReference))
        XCTAssertTrue(decision.reasons.contains(.ambiguousReference))
        XCTAssertEqual(decision.requiredApproval, .userConfirmation)
    }

    func testLocalOnlyPolicyExcludesCloudProvidersForFrontierCandidate() {
        let request = request(
            "競合を調べて戦略資料を作って",
            scope: .workspace,
            dataZone: .localOnly,
            capabilities: [.documentResearch, .documentDraft],
            providers: [
                ProviderReadinessReference(
                    providerID: ProviderID("cloud.frontier"),
                    isReady: true,
                    isLocal: false,
                    allowsLocalData: false,
                    requiresNetwork: true,
                    capabilities: [.documentResearch, .documentDraft]
                ),
                ProviderReadinessReference(
                    providerID: ProviderID("local.model"),
                    isReady: true,
                    isLocal: true,
                    allowsLocalData: true,
                    requiresNetwork: false,
                    capabilities: [.documentResearch, .documentDraft]
                )
            ]
        )

        let decision = router.evaluate(request)

        XCTAssertNotEqual(decision.route, .frontierFast)
        XCTAssertNotEqual(decision.route, .frontierDeep)
        XCTAssertTrue(decision.eligibleProviderIDs.contains(ProviderID("local.model")))
        XCTAssertFalse(decision.eligibleProviderIDs.contains(ProviderID("cloud.frontier")))
        XCTAssertEqual(decision.prohibitedProviderIDs, [ProviderID("cloud.frontier")])
        XCTAssertTrue(decision.reasons.contains(.dataPolicyConflict))
    }

    func testOfflineRequestDoesNotEligibleCloudProvider() {
        let decision = router.evaluate(request(
            "競合を調べて戦略資料を作って",
            scope: .workspace,
            networkAvailable: false,
            capabilities: [.documentResearch, .documentDraft],
            providers: [
                ProviderReadinessReference(
                    providerID: ProviderID("cloud.frontier"),
                    isReady: true,
                    isLocal: false,
                    allowsLocalData: true,
                    requiresNetwork: true,
                    capabilities: [.documentResearch, .documentDraft]
                )
            ]
        ))

        XCTAssertEqual(decision.route, .clarification)
        XCTAssertTrue(decision.eligibleProviderIDs.isEmpty)
        XCTAssertTrue(decision.reasons.contains(.networkUnavailable))
    }

    func testManualOnlyOperationCannotUseDeterministicRoute() {
        let decision = router.evaluate(request(
            "このTaskをDoneへ移動",
            scope: .task,
            selectedTaskID: 42,
            manualOnly: true,
            capabilities: [.taskWrite]
        ))

        XCTAssertEqual(decision.route, .clarification)
        XCTAssertTrue(decision.reasons.contains(.manualOnly))
        XCTAssertEqual(decision.requiredApproval, .userConfirmation)
    }

    func testDestructiveRequestIsProhibitedBeforeFrontierCandidate() {
        let decision = router.evaluate(request(
            "本番へdeployして全部削除して",
            scope: .external,
            capabilities: [.taskWrite]
        ))

        XCTAssertEqual(decision.route, .prohibited)
        XCTAssertTrue(decision.reasons.contains(.destructiveOperation))
        XCTAssertEqual(decision.requiredApproval, .blocked)
    }

    func testSameInputAndConfigurationHasStableDigestRegardlessOfOrdering() {
        let first = router.evaluate(request(
            "今日の期限切れだけ表示",
            scope: .today,
            capabilities: [.taskRead, .projectRead],
            providers: [
                ProviderReadinessReference(
                    providerID: ProviderID("b"),
                    isReady: true,
                    isLocal: true,
                    allowsLocalData: true,
                    requiresNetwork: false,
                    capabilities: [.taskRead]
                ),
                ProviderReadinessReference(
                    providerID: ProviderID("a"),
                    isReady: true,
                    isLocal: true,
                    allowsLocalData: true,
                    requiresNetwork: false,
                    capabilities: [.taskRead]
                )
            ]
        ))
        let second = router.evaluate(request(
            "今日の期限切れだけ表示",
            scope: .today,
            capabilities: [.projectRead, .taskRead],
            providers: [
                ProviderReadinessReference(
                    providerID: ProviderID("a"),
                    isReady: true,
                    isLocal: true,
                    allowsLocalData: true,
                    requiresNetwork: false,
                    capabilities: [.taskRead]
                ),
                ProviderReadinessReference(
                    providerID: ProviderID("b"),
                    isReady: true,
                    isLocal: true,
                    allowsLocalData: true,
                    requiresNetwork: false,
                    capabilities: [.taskRead]
                )
            ]
        ))

        XCTAssertEqual(first.decisionDigest, second.decisionDigest)
    }

    func testOversizedInputIsRejectedBeforeAnyProviderRoute() {
        let decision = router.evaluate(request(
            String(repeating: "a", count: 5_000),
            scope: .workspace,
            providers: [
                ProviderReadinessReference(
                    providerID: ProviderID("cloud.frontier"),
                    isReady: true,
                    isLocal: false,
                    allowsLocalData: true,
                    requiresNetwork: true,
                    capabilities: [.documentResearch]
                )
            ]
        ))

        XCTAssertEqual(decision.route, .prohibited)
        XCTAssertTrue(decision.reasons.contains(.inputTooLarge))
        XCTAssertTrue(decision.eligibleProviderIDs.isEmpty)
    }

    func testShadowEventContainsDigestOnlyAndPreservesRejectedOverride() {
        let request = request(
            "佐藤さんの /Users/private/secret.txt を削除して",
            scope: .external,
            capabilities: [.notificationWrite]
        )
        let decision = router.evaluate(request, userOverride: .frontierDeep)
        let event = router.shadowEvent(
            for: request,
            decision: decision,
            latencyMilliseconds: 12,
            finalExecutionPath: .review,
            outcomeLink: "receipt:opaque"
        )

        XCTAssertEqual(decision.route, .prohibited)
        XCTAssertEqual(event.userOverrideRoute, .frontierDeep)
        XCTAssertTrue(event.userOverrideRejected)
        XCTAssertFalse(event.serializedSummary.contains("佐藤"))
        XCTAssertFalse(event.serializedSummary.contains("secret.txt"))
        XCTAssertFalse(event.serializedSummary.contains("/Users"))
        XCTAssertTrue(event.frontierCallAvoided)
    }

    func testReadAuthorizationUsesRequestedScopeCapability() {
        let cases: [(TriageScope, PersonalCapability)] = [
            (.project, .projectRead),
            (.schedule, .scheduleRead),
            (.external, .calendarRead)
        ]

        for (scope, expectedCapability) in cases {
            let decision = router.evaluate(request(
                "show status",
                scope: scope,
                capabilities: [expectedCapability]
            ))

            XCTAssertEqual(decision.route, .deterministic, "scope: \(scope)")
            XCTAssertEqual(decision.capability, expectedCapability, "scope: \(scope)")
        }

        let denied = router.evaluate(request(
            "show project status",
            scope: .project,
            capabilities: [.taskRead]
        ))
        XCTAssertEqual(denied.route, .clarification)
        XCTAssertEqual(denied.capability, .projectRead)
        XCTAssertTrue(denied.reasons.contains(.capabilityUnavailable))
    }

    func testEligibleFrontierOverrideBecomesSelectedRoute() {
        let decision = router.evaluate(
            request(
                "research competitor strategy",
                scope: .workspace,
                capabilities: [.documentResearch],
                providers: [
                    ProviderReadinessReference(
                        providerID: ProviderID("cloud.frontier"),
                        isReady: true,
                        isLocal: false,
                        allowsLocalData: true,
                        requiresNetwork: true,
                        capabilities: [.documentResearch]
                    )
                ]
            ),
            userOverride: .frontierFast
        )

        XCTAssertEqual(decision.route, .frontierFast)
        XCTAssertFalse(decision.userOverrideRejected)
    }

    func testEnglishTaskCreateWithoutTitleRequiresClarification() {
        for input in ["add task", "create task", "new task", "add a task", "create the task"] {
            let decision = router.evaluate(request(
                input,
                scope: .task,
                capabilities: [.taskWrite]
            ))

            XCTAssertEqual(decision.route, .clarification, "input: \(input)")
            XCTAssertTrue(decision.missingFields.contains(.taskTitle), "input: \(input)")
        }
    }

    func testShadowEventUsesFinalExecutionPathForFrontierAvoidance() {
        let request = request(
            "show overdue tasks",
            scope: .task,
            capabilities: [.taskRead]
        )
        let decision = router.evaluate(request)
        let event = router.shadowEvent(
            for: request,
            decision: decision,
            finalExecutionPath: .frontier
        )

        XCTAssertFalse(event.frontierCallAvoided)
    }

    func testProviderIDTextCannotMakeRemoteProviderLocal() {
        let decision = router.evaluate(request(
            "research competitor strategy",
            scope: .workspace,
            capabilities: [.documentResearch],
            providers: [
                ProviderReadinessReference(
                    providerID: ProviderID("cloud-localization"),
                    isReady: true,
                    isLocal: false,
                    allowsLocalData: true,
                    requiresNetwork: true,
                    capabilities: [.documentResearch]
                )
            ]
        ))

        XCTAssertEqual(decision.route, .frontierDeep)
        XCTAssertFalse(decision.reasons.contains(.localCandidate))
    }

    func testLocalOnlyPolicyRejectsRemoteProviderThatAcceptsLocalData() {
        let decision = router.evaluate(request(
            "research competitor strategy",
            scope: .workspace,
            dataZone: .localOnly,
            capabilities: [.documentResearch],
            providers: [
                ProviderReadinessReference(
                    providerID: ProviderID("cloud.frontier"),
                    isReady: true,
                    isLocal: false,
                    allowsLocalData: true,
                    requiresNetwork: true,
                    capabilities: [.documentResearch]
                )
            ]
        ))

        XCTAssertEqual(decision.route, .clarification)
        XCTAssertTrue(decision.eligibleProviderIDs.isEmpty)
        XCTAssertTrue(decision.reasons.contains(.dataPolicyConflict))
    }

    func testProviderWithoutDeclaredCapabilityIsNotEligible() {
        let decision = router.evaluate(request(
            "research competitor strategy",
            scope: .workspace,
            capabilities: [.documentResearch],
            providers: [
                ProviderReadinessReference(
                    providerID: ProviderID("cloud.frontier"),
                    isReady: true,
                    isLocal: false,
                    allowsLocalData: true,
                    requiresNetwork: true,
                    capabilities: []
                )
            ]
        ))

        XCTAssertEqual(decision.route, .clarification)
        XCTAssertTrue(decision.eligibleProviderIDs.isEmpty)
        XCTAssertTrue(decision.reasons.contains(.providerUnavailable))
    }

    func testFrontierRouteRequiresRequestCapability() {
        let decision = router.evaluate(request(
            "research competitor strategy",
            scope: .workspace,
            capabilities: [],
            providers: [
                ProviderReadinessReference(
                    providerID: ProviderID("cloud.frontier"),
                    isReady: true,
                    isLocal: false,
                    allowsLocalData: true,
                    requiresNetwork: true,
                    capabilities: [.documentResearch]
                )
            ]
        ))

        XCTAssertEqual(decision.route, .clarification)
        XCTAssertEqual(decision.capability, .documentResearch)
        XCTAssertTrue(decision.eligibleProviderIDs.isEmpty)
        XCTAssertTrue(decision.reasons.contains(.capabilityUnavailable))
    }

    func testExternalWriteIntentCannotBeDowngradedToRead() {
        let decision = router.evaluate(request(
            "show status and send it",
            scope: .external,
            capabilities: [.calendarRead, .notificationWrite]
        ))

        XCTAssertEqual(decision.route, .deterministic)
        XCTAssertEqual(decision.capability, .notificationWrite)
        XCTAssertEqual(decision.requiredApproval, .explicitApproval)
        XCTAssertTrue(decision.reasons.contains(.externalWriteRequiresApproval))
    }

    func testDuplicateProviderIDIsRejectedWithoutLocalityMixing() {
        let providerID = ProviderID("provider")
        let decision = router.evaluate(request(
            "research competitor strategy",
            scope: .workspace,
            capabilities: [.documentResearch],
            providers: [
                ProviderReadinessReference(
                    providerID: providerID,
                    isReady: true,
                    isLocal: false,
                    allowsLocalData: true,
                    requiresNetwork: true,
                    capabilities: [.documentResearch]
                ),
                ProviderReadinessReference(
                    providerID: providerID,
                    isReady: false,
                    isLocal: true,
                    allowsLocalData: true,
                    requiresNetwork: false,
                    capabilities: [.documentResearch]
                )
            ]
        ))

        XCTAssertEqual(decision.route, .clarification)
        XCTAssertTrue(decision.eligibleProviderIDs.isEmpty)
        XCTAssertEqual(decision.prohibitedProviderIDs, [providerID])
        XCTAssertTrue(decision.reasons.contains(.providerUnavailable))
    }

    func testInputLimitUsesBytesBeforeNormalization() {
        let decision = router.evaluate(request(
            String(repeating: " ", count: 5_000) + "show status",
            scope: .task,
            capabilities: [.taskRead]
        ))

        XCTAssertEqual(decision.route, .prohibited)
        XCTAssertTrue(decision.reasons.contains(.inputTooLarge))
    }

    private func request(
        _ input: String,
        scope: TriageScope,
        dataZone: LocalTriageDataZone = .standard,
        selectedTaskID: Int64? = nil,
        selectedProjectID: Int64? = nil,
        networkAvailable: Bool = true,
        manualOnly: Bool = false,
        capabilities: Set<PersonalCapability> = [.taskRead, .taskWrite],
        providers: [ProviderReadinessReference] = []
    ) -> LocalTriageRequest {
        LocalTriageRequest(
            source: .text,
            normalizedInput: input,
            scope: scope,
            availableCapabilities: capabilities,
            providerReadiness: providers,
            dataPolicyVersion: 1,
            operatingPolicyVersion: 1,
            frozenAt: Date(timeIntervalSince1970: 1_720_000_000),
            timeZoneID: "Asia/Tokyo",
            dataZone: dataZone,
            selectedTaskID: selectedTaskID,
            selectedProjectID: selectedProjectID,
            networkAvailable: networkAvailable,
            manualOnly: manualOnly
        )
    }
}
