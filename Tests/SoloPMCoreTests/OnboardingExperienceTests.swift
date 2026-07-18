import XCTest
@testable import SoloPMCore

final class OnboardingExperienceTests: XCTestCase {
    func testWelcomeDefaultsToLocalExperienceWithoutProviderOrPermissions() {
        let experience = OnboardingExperience.initial

        XCTAssertEqual(experience.primaryAction, .trySoloPM)
        XCTAssertEqual(experience.secondaryAction, .setUpAI)
        XCTAssertEqual(experience.requestedPermissions, [])
    }

    func testLearnProjectRoutesToToday() {
        XCTAssertEqual(OnboardingExperience.learnProjectTargetRoute, .primary(.today))
    }

    func testPermissionsAppearOnlyAfterSelectingTheirCapability() {
        XCTAssertEqual(OnboardingExperience.permissions(for: .ai), [])
        XCTAssertEqual(OnboardingExperience.permissions(for: .voice), [.microphone])
        XCTAssertEqual(OnboardingExperience.permissions(for: .calendar), [.calendar])
        XCTAssertEqual(OnboardingExperience.permissions(for: .reminders), [.reminders])
        XCTAssertEqual(OnboardingExperience.permissions(for: .notifications), [.notifications])
    }

    func testFirstLessonFocusReappliesAfterRouteClearAndCompletesOnlyWhenStable() {
        var intent = OnboardingLessonFocusIntent(taskID: 42)

        XCTAssertNil(intent.nextAction(visibleTaskIDs: [7, 9], selectedTaskID: nil))
        XCTAssertEqual(intent.pendingTaskID, 42)
        XCTAssertEqual(intent.nextAction(visibleTaskIDs: [9, 42], selectedTaskID: nil), .select(42))
        XCTAssertNil(intent.nextAction(visibleTaskIDs: [9, 42], selectedTaskID: 42))
        XCTAssertEqual(
            intent.nextAction(visibleTaskIDs: [9, 42], selectedTaskID: nil),
            .select(42),
            "a route clear must reapply the still-pending lesson focus"
        )
        XCTAssertNil(intent.nextAction(visibleTaskIDs: [9, 42], selectedTaskID: 42))
        XCTAssertEqual(intent.nextAction(visibleTaskIDs: [9, 42], selectedTaskID: 42), .completed)
        XCTAssertNil(intent.pendingTaskID)
        XCTAssertNil(intent.nextAction(visibleTaskIDs: [42], selectedTaskID: 42))
    }

    func testTargetedRoutePolicyRetriesEarlyRejectedRequestInsteadOfDroppingIt() {
        let policy = OnboardingTargetedRouteRetryPolicy(maximumAttempts: 3)

        XCTAssertEqual(
            policy.decision(afterAttempt: 1, requestWasAccepted: false),
            .retry,
            "an early click can precede scene registration, so a nil request remains retryable"
        )
        XCTAssertEqual(
            policy.decision(afterAttempt: 2, requestWasAccepted: true),
            .awaitApplication
        )
    }

    func testTargetedRoutePolicyStopsAtItsBound() {
        let policy = OnboardingTargetedRouteRetryPolicy(maximumAttempts: 3)

        XCTAssertEqual(policy.decision(afterAttempt: 2, requestWasAccepted: false), .retry)
        XCTAssertEqual(policy.decision(afterAttempt: 3, requestWasAccepted: false), .exhausted)
    }
}
