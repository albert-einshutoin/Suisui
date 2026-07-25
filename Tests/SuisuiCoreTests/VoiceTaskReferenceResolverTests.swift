import XCTest
@testable import SuisuiCore

final class VoiceTaskReferenceResolverTests: XCTestCase {
    private let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let sourceTurnID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testGivenExplicitTaskIDWhenResolveThenUsesExplicitTarget() {
        let target = ConversationResolvedTarget.task(id: 41, projectID: 7)
        let result = resolver.resolve(
            request(
                utterance: "task 41",
                explicitTarget: target,
                candidates: [candidate(taskID: 41, projectID: 7, title: "Ship release")]
            )
        )

        XCTAssertEqual(result, .resolved(target, reason: .explicitIdentifier))
    }

    func testGivenSelectedTaskAndPronounWhenResolveThenUsesSelection() {
        let selected = ConversationResolvedTarget.task(id: 42, projectID: 7)
        let result = resolver.resolve(
            request(
                utterance: "それを完了にして",
                selectedTask: selected,
                candidates: [candidate(taskID: 42, projectID: 7, title: "Write notes")]
            )
        )

        XCTAssertEqual(result, .resolved(selected, reason: .selectedTask))
    }

    func testGivenPreviousActionLinkWhenSoreReferenceThenResolvesCreatedTask() throws {
        let link = try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            taskID: 43,
            reviewedFingerprint: "reviewed",
            createdAt: now.addingTimeInterval(-5)
        )
        let target = ConversationResolvedTarget.task(id: 43, projectID: 8)

        let result = resolver.resolve(
            request(
                utterance: "さっき追加したものを開いて",
                previousActionLink: link,
                candidates: [candidate(taskID: 43, projectID: 8, title: "Prepare demo")]
            )
        )

        XCTAssertEqual(result, .resolved(target, reason: .previousActionLink))
    }

    func testGivenStableThirdCandidateWhenResolveThenReturnsThirdTask() throws {
        let candidates = [
            candidate(taskID: 51, projectID: 9, title: "First"),
            candidate(taskID: 52, projectID: 9, title: "Second"),
            candidate(taskID: 53, projectID: 9, title: "Third"),
        ]
        let reference = try ordinalReference(
            target: .task(53),
            ordinal: 2,
            fingerprint: "ordered-v1"
        )

        let result = resolver.resolve(
            request(
                utterance: "3つ目を開いて",
                ordinalReference: reference,
                candidateOrderingFingerprint: "ordered-v1",
                candidates: candidates
            )
        )

        XCTAssertEqual(
            result,
            .resolved(.task(id: 53, projectID: 9), reason: .stableOrdinal)
        )
    }

    func testGivenReorderedCandidatesWhenResolveThirdThenRequiresClarification() throws {
        let candidates = [
            candidate(taskID: 53, projectID: 9, title: "Third"),
            candidate(taskID: 51, projectID: 9, title: "First"),
            candidate(taskID: 52, projectID: 9, title: "Second"),
        ]
        let reference = try ordinalReference(
            target: .task(53),
            ordinal: 2,
            fingerprint: "ordered-v1"
        )

        let result = resolver.resolve(
            request(
                utterance: "the third one",
                ordinalReference: reference,
                candidateOrderingFingerprint: "ordered-v2",
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .needsClarification(candidates))
    }

    func testGivenDeletedTaskWhenResolveThenReturnsUnavailable() {
        let target = ConversationResolvedTarget.task(id: 61, projectID: 10)
        let result = resolver.resolve(
            request(
                utterance: "that",
                selectedTask: target,
                candidates: [
                    candidate(
                        taskID: 61,
                        projectID: 10,
                        title: "Deleted",
                        availability: .deleted
                    ),
                ]
            )
        )

        XCTAssertEqual(result, .unavailable(.deletedTarget(target)))
    }

    func testGivenSameTitleAcrossProjectsWhenResolveThenRequiresClarification() {
        let candidates = [
            candidate(taskID: 71, projectID: 11, title: "Ship release"),
            candidate(taskID: 72, projectID: 12, title: "Ship release"),
        ]

        let result = resolver.resolve(
            request(utterance: "Ship release", candidates: candidates)
        )

        XCTAssertEqual(result, .needsClarification(candidates))
    }

    func testGivenExpiredReferenceWhenResolveThenDoesNotUseIt() throws {
        let candidate = candidate(taskID: 81, projectID: 13, title: "Expired")
        let reference = try ConversationReference(
            sessionID: sessionID,
            target: .task(81),
            sourceTurnID: sourceTurnID,
            ordinal: 0,
            orderingFingerprint: "ordered-v1",
            expiresAt: now,
            createdAt: now.addingTimeInterval(-60)
        )

        let result = resolver.resolve(
            request(
                utterance: "the first one",
                ordinalReference: reference,
                candidateOrderingFingerprint: "ordered-v1",
                candidates: [candidate]
            )
        )

        XCTAssertEqual(result, .unavailable(.expiredReference))
    }

    func testJapaneseEnglishAndMixedRecentActionPhrasesResolveDeterministically() throws {
        let link = try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            taskID: 91,
            reviewedFingerprint: "reviewed",
            createdAt: now.addingTimeInterval(-5)
        )
        let target = ConversationResolvedTarget.task(id: 91, projectID: 14)
        let candidate = candidate(taskID: 91, projectID: 14, title: "Review PR")

        for utterance in [
            "さっき追加したもの",
            "the task we just added",
            "さっき added した task",
        ] {
            XCTAssertEqual(
                resolver.resolve(
                    request(
                        utterance: utterance,
                        previousActionLink: link,
                        candidates: [candidate]
                    )
                ),
                .resolved(target, reason: .previousActionLink),
                utterance
            )
        }
    }

    func testGivenConfirmedFactScopeWhenResolveThenUsesOnlyConfirmedScope() throws {
        let fact = try TaskContextFact(
            sessionID: sessionID,
            kind: .task,
            scope: .task(101),
            state: .confirmed,
            value: "Current task",
            sourceTurnID: sourceTurnID,
            confidence: 1,
            author: .userExplicit,
            createdAt: now.addingTimeInterval(-30)
        )
        let target = ConversationResolvedTarget.task(id: 101, projectID: 15)

        let result = resolver.resolve(
            request(
                utterance: "that task",
                candidates: [candidate(taskID: 101, projectID: 15, title: "Current task")],
                confirmedFacts: [fact]
            )
        )

        XCTAssertEqual(result, .resolved(target, reason: .confirmedFact))
    }

    func testGivenSameInputWhenResolveRepeatedlyThenCandidateOrderAndResultStayStable() {
        let candidates = [
            candidate(taskID: 111, projectID: 16, title: "Alpha", stableSortKey: "b"),
            candidate(taskID: 112, projectID: 17, title: "Alpha", stableSortKey: "a"),
        ]
        let request = request(utterance: "Alpha", candidates: candidates)

        let first = resolver.resolve(request)
        let second = resolver.resolve(request)

        XCTAssertEqual(first, .needsClarification(candidates))
        XCTAssertEqual(second, first)
    }

    private var resolver: VoiceTaskReferenceResolver {
        VoiceTaskReferenceResolver(now: { [now] in now })
    }

    private func request(
        utterance: String,
        explicitTarget: ConversationResolvedTarget? = nil,
        selectedTask: ConversationResolvedTarget? = nil,
        selectedProject: ConversationResolvedTarget? = nil,
        previousActionLink: ConversationActionLink? = nil,
        ordinalReference: ConversationReference? = nil,
        candidateOrderingFingerprint: String? = nil,
        candidates: [ConversationReferenceCandidate] = [],
        confirmedFacts: [TaskContextFact] = []
    ) -> VoiceTaskReferenceRequest {
        VoiceTaskReferenceRequest(
            sessionID: sessionID,
            utterance: utterance,
            explicitTarget: explicitTarget,
            selectedTask: selectedTask,
            selectedProject: selectedProject,
            previousActionLink: previousActionLink,
            ordinalReference: ordinalReference,
            candidateOrderingFingerprint: candidateOrderingFingerprint,
            candidates: candidates,
            confirmedFacts: confirmedFacts
        )
    }

    private func candidate(
        taskID: Int64,
        projectID: Int64,
        title: String,
        stableSortKey: String? = nil,
        availability: ConversationReferenceCandidateAvailability = .available
    ) -> ConversationReferenceCandidate {
        ConversationReferenceCandidate(
            target: .task(id: taskID, projectID: projectID),
            title: title,
            stableSortKey: stableSortKey ?? String(format: "%020lld", taskID),
            availability: availability
        )
    }

    private func ordinalReference(
        target: ConversationStableTargetID,
        ordinal: Int,
        fingerprint: String
    ) throws -> ConversationReference {
        try ConversationReference(
            sessionID: sessionID,
            target: target,
            sourceTurnID: sourceTurnID,
            ordinal: ordinal,
            orderingFingerprint: fingerprint,
            expiresAt: now.addingTimeInterval(60),
            createdAt: now.addingTimeInterval(-60)
        )
    }
}
