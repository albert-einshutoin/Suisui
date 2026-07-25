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

    func testGivenSelectedTaskAndThisTaskReferenceThenUsesSelection() {
        let selected = ConversationResolvedTarget.task(id: 421, projectID: 7)
        let result = resolver.resolve(
            request(
                utterance: "complete this task",
                selectedTask: selected,
                candidates: [candidate(taskID: 421, projectID: 7, title: "Write notes")]
            )
        )

        XCTAssertEqual(result, .resolved(selected, reason: .selectedTask))
    }

    func testGivenNamedCandidateWithoutOrdinalFingerprintThenResolvesName() {
        let target = ConversationResolvedTarget.task(id: 422, projectID: 7)
        let candidates = [
            candidate(taskID: 422, projectID: 7, title: "Ship release"),
        ]
        let request = VoiceTaskReferenceRequest(
            sessionID: sessionID,
            utterance: "open Ship release",
            candidates: candidates
        )

        XCTAssertEqual(
            resolver.resolve(request),
            .resolved(target, reason: .uniqueCandidate)
        )
    }

    func testGivenSelectedProjectWhenResolveThenUsesProjectSelection() {
        let selected = ConversationResolvedTarget.project(id: 17)
        let candidate = ConversationReferenceCandidate(
            target: selected,
            title: "Launch",
            stableSortKey: "project-17"
        )
        let result = resolver.resolve(
            request(
                utterance: "このプロジェクト",
                selectedProject: selected,
                candidates: [candidate]
            )
        )

        XCTAssertEqual(result, .resolved(selected, reason: .selectedProject))
    }

    func testGivenTaskAndProjectSelectionsWhenProjectQualifiedPronounThenUsesProject() {
        let selectedTask = ConversationResolvedTarget.task(id: 45, projectID: 17)
        let selectedProject = ConversationResolvedTarget.project(id: 17)
        let candidates = [
            candidate(taskID: 45, projectID: 17, title: "Selected task"),
            ConversationReferenceCandidate(
                target: selectedProject,
                title: "Launch",
                stableSortKey: "project-17"
            ),
        ]

        let result = resolver.resolve(
            request(
                utterance: "that project",
                selectedTask: selectedTask,
                selectedProject: selectedProject,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .resolved(selectedProject, reason: .selectedProject))
    }

    func testGivenSelectedTaskInsideCurrentProjectWhenResolveThenKeepsTaskTarget() {
        let selectedTask = ConversationResolvedTarget.task(id: 452, projectID: 17)
        let selectedProject = ConversationResolvedTarget.project(id: 17)
        let candidates = [
            candidate(taskID: 452, projectID: 17, title: "Selected task"),
            ConversationReferenceCandidate(
                target: selectedProject,
                title: "Launch",
                stableSortKey: "project-17"
            ),
        ]

        let result = resolver.resolve(
            request(
                utterance: "complete this task in the current project",
                selectedTask: selectedTask,
                selectedProject: selectedProject,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .resolved(selectedTask, reason: .selectedTask))
    }

    func testGivenMalformedProjectSelectionWhenResolveThenFailsClosed() {
        let task = ConversationResolvedTarget.task(id: 451, projectID: 17)
        let candidates = [
            candidate(taskID: 451, projectID: 17, title: "Selected task"),
        ]

        let result = resolver.resolve(
            request(
                utterance: "that project",
                selectedProject: task,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .unavailable(.unsupportedReferenceTarget))
    }

    func testGivenOnlyTaskSelectionWhenProjectQualifiedPronounThenClarifiesProject() {
        let selectedTask = ConversationResolvedTarget.task(id: 46, projectID: 18)
        let projectCandidate = ConversationReferenceCandidate(
            target: .project(id: 18),
            title: "Launch",
            stableSortKey: "project-18"
        )
        let candidates = [
            candidate(taskID: 46, projectID: 18, title: "Selected task"),
            projectCandidate,
        ]

        let result = resolver.resolve(
            request(
                utterance: "that project",
                selectedTask: selectedTask,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .needsClarification([projectCandidate]))
    }

    func testGivenModifiedProjectAnaphorWithTaskSelectionThenClarifiesProject() {
        let selectedTask = ConversationResolvedTarget.task(id: 461, projectID: 18)
        let projectCandidate = ConversationReferenceCandidate(
            target: .project(id: 18),
            title: "Launch",
            stableSortKey: "project-18"
        )
        let candidates = [
            candidate(taskID: 461, projectID: 18, title: "Selected task"),
            projectCandidate,
        ]

        let result = resolver.resolve(
            request(
                utterance: "delete this old project",
                selectedTask: selectedTask,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .needsClarification([projectCandidate]))
    }

    func testGivenPreviousTaskActionWhenProjectQualifiedPronounThenDoesNotUseTask() throws {
        let link = try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            taskID: 47,
            reviewedFingerprint: "reviewed",
            createdAt: now.addingTimeInterval(-5)
        )
        let projectCandidate = ConversationReferenceCandidate(
            target: .project(id: 19),
            title: "Launch",
            stableSortKey: "project-19"
        )
        let candidates = [
            candidate(taskID: 47, projectID: 19, title: "Previous task"),
            projectCandidate,
        ]

        let result = resolver.resolve(
            request(
                utterance: "that project",
                previousActionLink: link,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .needsClarification([projectCandidate]))
    }

    func testGivenPreviousActionLinkWhenSoreReferenceThenResolvesCreatedTask() throws {
        let link = try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            taskID: 43,
            operation: .taskCreated,
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

    func testGivenRelativeClauseCreatedTaskWhenResolveThenUsesActionLinkOverSelection() throws {
        let selected = ConversationResolvedTarget.task(id: 432, projectID: 8)
        let created = ConversationResolvedTarget.task(id: 433, projectID: 8)
        let link = try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            taskID: 433,
            operation: .taskCreated,
            reviewedFingerprint: "reviewed",
            createdAt: now.addingTimeInterval(-5)
        )
        let candidates = [
            candidate(taskID: 432, projectID: 8, title: "Selected task"),
            candidate(taskID: 433, projectID: 8, title: "Created task"),
        ]

        let result = resolver.resolve(
            request(
                utterance: "delete the task that we just created",
                selectedTask: selected,
                previousActionLink: link,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .resolved(created, reason: .previousActionLink))
    }

    func testGivenUpdatedTaskLinkWhenReferenceClaimsCreationThenClarifies() throws {
        let link = try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            taskID: 434,
            operation: .taskUpdated,
            reviewedFingerprint: "reviewed",
            createdAt: now.addingTimeInterval(-5)
        )
        let candidates = [
            candidate(taskID: 434, projectID: 8, title: "Updated task"),
        ]

        let result = resolver.resolve(
            request(
                utterance: "the task we just created",
                previousActionLink: link,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .needsClarification(candidates))
    }

    func testGivenProjectCreationReferenceWithTaskLinkThenClarifiesProject() throws {
        let link = try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            taskID: 435,
            operation: .taskCreated,
            reviewedFingerprint: "reviewed",
            createdAt: now.addingTimeInterval(-5)
        )
        let projectCandidate = ConversationReferenceCandidate(
            target: .project(id: 8),
            title: "Launch",
            stableSortKey: "project-8"
        )
        let candidates = [
            candidate(taskID: 435, projectID: 8, title: "Created task"),
            projectCandidate,
        ]

        let result = resolver.resolve(
            request(
                utterance: "さっき作ったプロジェクトを開いて",
                previousActionLink: link,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .needsClarification([projectCandidate]))
    }

    func testGivenRecentlyViewedJapaneseReferenceThenDoesNotUseCreatedTaskLink() throws {
        let link = try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            taskID: 431,
            reviewedFingerprint: "reviewed",
            createdAt: now.addingTimeInterval(-5)
        )
        let candidates = [
            candidate(taskID: 431, projectID: 8, title: "Created task"),
        ]

        let result = resolver.resolve(
            request(
                utterance: "さっき見たものを削除して",
                previousActionLink: link,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .needsClarification(candidates))
    }

    func testGivenStableThirdCandidateWhenResolveThenReturnsThirdTask() throws {
        let candidates = [
            candidate(taskID: 51, projectID: 9, title: "First"),
            candidate(taskID: 52, projectID: 9, title: "Second"),
            candidate(taskID: 53, projectID: 9, title: "Third"),
        ]
        let fingerprint = VoiceTaskReferenceResolver.orderingFingerprint(for: candidates)
        let reference = try ordinalReference(
            target: .task(53),
            ordinal: 2,
            fingerprint: fingerprint
        )

        let result = resolver.resolve(
            request(
                utterance: "3つ目を開いて",
                ordinalReference: reference,
                candidateOrderingFingerprint: fingerprint,
                candidates: candidates
            )
        )

        XCTAssertEqual(
            result,
            .resolved(.task(id: 53, projectID: 9), reason: .stableOrdinal)
        )
    }

    func testGivenStableThirdProjectWhenResolveThenOrdinalBeatsCurrentSelection() throws {
        let candidates = [
            ConversationReferenceCandidate(
                target: .project(id: 21),
                title: "First",
                stableSortKey: "project-21"
            ),
            ConversationReferenceCandidate(
                target: .project(id: 22),
                title: "Second",
                stableSortKey: "project-22"
            ),
            ConversationReferenceCandidate(
                target: .project(id: 23),
                title: "Third",
                stableSortKey: "project-23"
            ),
        ]
        let fingerprint = VoiceTaskReferenceResolver.orderingFingerprint(for: candidates)
        let reference = try ordinalReference(
            target: .project(23),
            ordinal: 2,
            fingerprint: fingerprint
        )

        let result = resolver.resolve(
            request(
                utterance: "the third project",
                selectedProject: .project(id: 21),
                ordinalReference: reference,
                candidateOrderingFingerprint: fingerprint,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .resolved(.project(id: 23), reason: .stableOrdinal))
    }

    func testGivenProjectQualifiedOrdinalPointingAtTaskThenClarifiesProjects() throws {
        let projectCandidates = [
            ConversationReferenceCandidate(
                target: .project(id: 24),
                title: "First project",
                stableSortKey: "project-24"
            ),
            ConversationReferenceCandidate(
                target: .project(id: 25),
                title: "Second project",
                stableSortKey: "project-25"
            ),
        ]
        let candidates = projectCandidates + [
            candidate(taskID: 26, projectID: 25, title: "Third task"),
        ]
        let fingerprint = VoiceTaskReferenceResolver.orderingFingerprint(for: candidates)
        let staleReference = try ordinalReference(
            target: .task(26),
            ordinal: 2,
            fingerprint: fingerprint
        )

        let result = resolver.resolve(
            request(
                utterance: "the third project",
                ordinalReference: staleReference,
                candidateOrderingFingerprint: fingerprint,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .needsClarification(projectCandidates))
    }

    func testGivenOrdinalTaskInsideNamedProjectWhenResolveThenUsesTaskKind() throws {
        let candidates = [
            candidate(taskID: 27, projectID: 24, title: "First task"),
            candidate(taskID: 28, projectID: 24, title: "Second task"),
            ConversationReferenceCandidate(
                target: .project(id: 24),
                title: "Alpha",
                stableSortKey: "project-24"
            ),
        ]
        let fingerprint = VoiceTaskReferenceResolver.orderingFingerprint(for: candidates)
        let reference = try ordinalReference(
            target: .task(28),
            ordinal: 1,
            fingerprint: fingerprint
        )

        let result = resolver.resolve(
            request(
                utterance: "open the second task in project Alpha",
                ordinalReference: reference,
                candidateOrderingFingerprint: fingerprint,
                candidates: candidates
            )
        )

        XCTAssertEqual(
            result,
            .resolved(.task(id: 28, projectID: 24), reason: .stableOrdinal)
        )
    }

    func testGivenReorderedCandidatesWhenResolveThirdThenRequiresClarification() throws {
        let originalCandidates = [
            candidate(taskID: 51, projectID: 9, title: "First"),
            candidate(taskID: 52, projectID: 9, title: "Second"),
            candidate(taskID: 53, projectID: 9, title: "Third"),
        ]
        let reorderedCandidates = [
            candidate(taskID: 53, projectID: 9, title: "Third"),
            candidate(taskID: 51, projectID: 9, title: "First"),
            candidate(taskID: 52, projectID: 9, title: "Second"),
        ]
        let reference = try ordinalReference(
            target: .task(53),
            ordinal: 2,
            fingerprint: VoiceTaskReferenceResolver.orderingFingerprint(for: originalCandidates)
        )

        let result = resolver.resolve(
            request(
                utterance: "the third one",
                ordinalReference: reference,
                candidateOrderingFingerprint: VoiceTaskReferenceResolver.orderingFingerprint(
                    for: reorderedCandidates
                ),
                candidates: reorderedCandidates
            )
        )

        XCTAssertEqual(result, .needsClarification(reorderedCandidates))
    }

    func testGivenTaskTitleStartingWithOrdinalWordWhenResolveThenUsesNamedTask() throws {
        let candidates = [
            candidate(taskID: 54, projectID: 9, title: "Other"),
            candidate(taskID: 55, projectID: 9, title: "First aid"),
        ]
        let fingerprint = VoiceTaskReferenceResolver.orderingFingerprint(for: candidates)
        let priorOrdinal = try ordinalReference(
            target: .task(54),
            ordinal: 0,
            fingerprint: fingerprint
        )

        let result = resolver.resolve(
            request(
                utterance: "open First aid",
                ordinalReference: priorOrdinal,
                candidateOrderingFingerprint: fingerprint,
                candidates: candidates
            )
        )

        XCTAssertEqual(
            result,
            .resolved(.task(id: 55, projectID: 9), reason: .uniqueCandidate)
        )
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

    func testGivenTaskTitleContainingThatWhenResolveThenDoesNotUseSelection() {
        let selected = ConversationResolvedTarget.task(id: 73, projectID: 12)
        let named = ConversationResolvedTarget.task(id: 74, projectID: 12)
        let candidates = [
            candidate(taskID: 73, projectID: 12, title: "Selected"),
            candidate(taskID: 74, projectID: 12, title: "Thatched Roof"),
        ]

        let result = resolver.resolve(
            request(
                utterance: "open Thatched Roof",
                selectedTask: selected,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .resolved(named, reason: .uniqueCandidate))
    }

    func testGivenTaskTitleThatOneThingWhenResolveThenNamedTaskBeatsSelection() {
        let selected = ConversationResolvedTarget.task(id: 741, projectID: 12)
        let named = ConversationResolvedTarget.task(id: 742, projectID: 12)
        let candidates = [
            candidate(taskID: 741, projectID: 12, title: "Selected"),
            candidate(taskID: 742, projectID: 12, title: "That One Thing"),
        ]

        let result = resolver.resolve(
            request(
                utterance: "open That One Thing",
                selectedTask: selected,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .resolved(named, reason: .uniqueCandidate))
    }

    func testGivenShortCandidateTitleInsideAnotherWordThenDoesNotResolve() {
        let candidates = [
            candidate(taskID: 743, projectID: 12, title: "App"),
        ]

        let result = resolver.resolve(
            request(utterance: "apply the update", candidates: candidates)
        )

        XCTAssertEqual(result, .needsClarification(candidates))
    }

    func testGivenShortJapaneseTitleInsideAnotherWordThenDoesNotResolve() {
        let candidates = [
            candidate(taskID: 744, projectID: 12, title: "会"),
        ]

        let result = resolver.resolve(
            request(utterance: "会議を開いて", candidates: candidates)
        )

        XCTAssertEqual(result, .needsClarification(candidates))
    }

    func testGivenProjectQualifiedTaskTitleWhenResolveThenDoesNotResolveTask() {
        let candidates = [
            candidate(taskID: 745, projectID: 12, title: "Alpha"),
        ]

        let result = resolver.resolve(
            request(utterance: "open project Alpha", candidates: candidates)
        )

        XCTAssertEqual(result, .needsClarification(candidates))
    }

    func testGivenTaskTitleContainingProjectWhenResolveThenDoesNotUseProjectSelection() {
        let selectedProject = ConversationResolvedTarget.project(id: 12)
        let named = ConversationResolvedTarget.task(id: 75, projectID: 12)
        let candidates = [
            ConversationReferenceCandidate(
                target: selectedProject,
                title: "Launch",
                stableSortKey: "project-12"
            ),
            candidate(taskID: 75, projectID: 12, title: "Projector setup"),
        ]

        let result = resolver.resolve(
            request(
                utterance: "open Projector setup",
                selectedProject: selectedProject,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .resolved(named, reason: .uniqueCandidate))
    }

    func testGivenNamedTaskContainingRecentActionWordsThenDoesNotUsePreviousAction() throws {
        let link = try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            taskID: 76,
            reviewedFingerprint: "reviewed",
            createdAt: now.addingTimeInterval(-5)
        )
        let named = ConversationResolvedTarget.task(id: 77, projectID: 12)
        let candidates = [
            candidate(taskID: 76, projectID: 12, title: "Previous"),
            candidate(taskID: 77, projectID: 12, title: "Just Added Checklist"),
        ]

        let result = resolver.resolve(
            request(
                utterance: "open Just Added Checklist",
                previousActionLink: link,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .resolved(named, reason: .uniqueCandidate))
    }

    func testGivenJapaneseTitleStartingWithSoreThenDoesNotUseSelection() {
        let selected = ConversationResolvedTarget.task(id: 78, projectID: 12)
        let named = ConversationResolvedTarget.task(id: 79, projectID: 12)
        let candidates = [
            candidate(taskID: 78, projectID: 12, title: "Selected"),
            candidate(taskID: 79, projectID: 12, title: "それでもやる"),
        ]

        let result = resolver.resolve(
            request(
                utterance: "それでもやる",
                selectedTask: selected,
                candidates: candidates
            )
        )

        XCTAssertEqual(result, .resolved(named, reason: .uniqueCandidate))
    }

    func testGivenExpiredReferenceWhenResolveThenDoesNotUseIt() throws {
        let candidate = candidate(taskID: 81, projectID: 13, title: "Expired")
        let fingerprint = VoiceTaskReferenceResolver.orderingFingerprint(for: [candidate])
        let reference = try ConversationReference(
            sessionID: sessionID,
            target: .task(81),
            sourceTurnID: sourceTurnID,
            ordinal: 0,
            orderingFingerprint: fingerprint,
            expiresAt: now,
            createdAt: now.addingTimeInterval(-60)
        )

        let result = resolver.resolve(
            request(
                utterance: "the first one",
                ordinalReference: reference,
                candidateOrderingFingerprint: fingerprint,
                candidates: [candidate]
            )
        )

        XCTAssertEqual(result, .unavailable(.expiredReference))
    }

    func testGivenUnsupportedOrdinalTargetWhenResolveThenReturnsUnavailable() throws {
        let candidate = candidate(taskID: 82, projectID: 13, title: "Task")
        let fingerprint = VoiceTaskReferenceResolver.orderingFingerprint(for: [candidate])
        let reference = try ConversationReference(
            sessionID: sessionID,
            target: .actionPlan("plan-1"),
            sourceTurnID: sourceTurnID,
            ordinal: 0,
            orderingFingerprint: fingerprint,
            expiresAt: now.addingTimeInterval(60),
            createdAt: now.addingTimeInterval(-60)
        )

        let result = resolver.resolve(
            request(
                utterance: "the first one",
                ordinalReference: reference,
                candidateOrderingFingerprint: fingerprint,
                candidates: [candidate]
            )
        )

        XCTAssertEqual(result, .unavailable(.unsupportedReferenceTarget))
    }

    func testJapaneseEnglishAndMixedRecentActionPhrasesResolveDeterministically() throws {
        let link = try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            taskID: 91,
            operation: .taskCreated,
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

    func testGivenConfirmedFactSupersededByCorrectionThenUsesReplacementOnly() throws {
        let oldFact = try TaskContextFact(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            sessionID: sessionID,
            kind: .task,
            scope: .task(102),
            state: .confirmed,
            value: "Old task",
            sourceTurnID: sourceTurnID,
            confidence: 1,
            author: .userExplicit,
            createdAt: now.addingTimeInterval(-60)
        )
        let replacement = try TaskContextFact(
            sessionID: sessionID,
            kind: .task,
            scope: .task(103),
            state: .confirmed,
            value: "Corrected task",
            sourceTurnID: sourceTurnID,
            confidence: 1,
            author: .userExplicit,
            supersedesFactID: oldFact.id,
            createdAt: now.addingTimeInterval(-30)
        )
        let target = ConversationResolvedTarget.task(id: 103, projectID: 15)

        let result = resolver.resolve(
            request(
                utterance: "that task",
                candidates: [
                    candidate(taskID: 102, projectID: 15, title: "Old task"),
                    candidate(taskID: 103, projectID: 15, title: "Corrected task"),
                ],
                confirmedFacts: [oldFact, replacement]
            )
        )

        XCTAssertEqual(result, .resolved(target, reason: .confirmedFact))
    }

    func testGivenConfirmedFactSupersededByRetractionThenDoesNotReuseOldScope() throws {
        let oldFact = try TaskContextFact(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            sessionID: sessionID,
            kind: .task,
            scope: .task(104),
            state: .confirmed,
            value: "Retracted task",
            sourceTurnID: sourceTurnID,
            confidence: 1,
            author: .userExplicit,
            createdAt: now.addingTimeInterval(-60)
        )
        let retraction = try TaskContextFact(
            sessionID: sessionID,
            kind: .task,
            scope: .task(104),
            state: .retracted,
            value: "Retracted",
            sourceTurnID: sourceTurnID,
            confidence: 1,
            author: .userExplicit,
            supersedesFactID: oldFact.id,
            createdAt: now.addingTimeInterval(-30)
        )
        let candidates = [
            candidate(taskID: 104, projectID: 15, title: "Retracted task"),
        ]

        let result = resolver.resolve(
            request(
                utterance: "that task",
                candidates: candidates,
                confirmedFacts: [oldFact, retraction]
            )
        )

        XCTAssertEqual(result, .needsClarification(candidates))
    }

    func testGivenTaskQualifiedReferenceWithOnlyProjectFactThenDoesNotResolveProject() throws {
        let projectFact = try TaskContextFact(
            sessionID: sessionID,
            kind: .project,
            scope: .project(106),
            state: .confirmed,
            value: "Project scope",
            sourceTurnID: sourceTurnID,
            confidence: 1,
            author: .userExplicit,
            createdAt: now.addingTimeInterval(-30)
        )
        let candidates = [
            ConversationReferenceCandidate(
                target: .project(id: 106),
                title: "Project scope",
                stableSortKey: "project-106"
            ),
        ]

        let result = resolver.resolve(
            request(
                utterance: "that task",
                candidates: candidates,
                confirmedFacts: [projectFact]
            )
        )

        XCTAssertEqual(result, .needsClarification(candidates))
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

    func testGivenDuplicateStableOrderingKeysWhenResolveThenRejectsCandidateOrdering() {
        let candidates = [
            candidate(taskID: 121, projectID: 18, title: "First", stableSortKey: "duplicate"),
            candidate(taskID: 122, projectID: 18, title: "Second", stableSortKey: "duplicate"),
        ]

        let result = resolver.resolve(
            request(utterance: "that", candidates: candidates)
        )

        XCTAssertEqual(result, .unavailable(.invalidCandidateOrdering))
    }

    func testGivenDuplicateStableTargetWhenResolveThenRejectsCandidateOrdering() {
        let candidates = [
            candidate(taskID: 125, projectID: 18, title: "First", stableSortKey: "a"),
            candidate(taskID: 125, projectID: 19, title: "Second", stableSortKey: "b"),
        ]

        let result = resolver.resolve(
            request(utterance: "that", candidates: candidates)
        )

        XCTAssertEqual(result, .unavailable(.invalidCandidateOrdering))
    }

    func testGivenMissingSelectedTargetWhenResolveThenReturnsStaleUnavailable() {
        let selected = ConversationResolvedTarget.task(id: 131, projectID: 19)

        let result = resolver.resolve(
            request(utterance: "that", selectedTask: selected)
        )

        XCTAssertEqual(result, .unavailable(.staleTarget(selected)))
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
            candidateOrderingFingerprint: candidateOrderingFingerprint
                ?? VoiceTaskReferenceResolver.orderingFingerprint(for: candidates),
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
