import XCTest
@testable import SuisuiCore

final class FirstRunOnboardingTests: XCTestCase {
    func testFlowAdvancesThroughAllStepsInOrderAndStopsAtEnds() {
        var flow = FirstRunOnboardingFlow()

        XCTAssertEqual(flow.step, .welcome)
        XCTAssertTrue(flow.isFirstStep)
        XCTAssertFalse(flow.isLastStep)
        XCTAssertEqual(flow.stepIndex, 0)
        XCTAssertEqual(flow.stepCount, 3)

        flow.goBack()
        XCTAssertEqual(flow.step, .welcome)

        flow.advance()
        XCTAssertEqual(flow.step, .aiProvider)
        flow.advance()
        XCTAssertEqual(flow.step, .finish)
        XCTAssertTrue(flow.isLastStep)

        flow.advance()
        XCTAssertEqual(flow.step, .finish)

        flow.goBack()
        XCTAssertEqual(flow.step, .aiProvider)
    }

    func testGatePresentsOnlyForFreshInteractiveLaunches() {
        XCTAssertTrue(
            FirstRunOnboardingGate.shouldPresent(hasCompletedOnboarding: false, environment: [:])
        )
        XCTAssertFalse(
            FirstRunOnboardingGate.shouldPresent(hasCompletedOnboarding: true, environment: [:])
        )
    }

    func testOnlyThePrimaryProjectBoardWindowOwnsFirstRunPresentation() {
        XCTAssertTrue(
            FirstRunOnboardingGate.shouldPresent(
                hasDismissedOnboarding: false,
                isPrimaryWindow: true,
                environment: [:]
            )
        )
        XCTAssertFalse(
            FirstRunOnboardingGate.shouldPresent(
                hasDismissedOnboarding: false,
                isPrimaryWindow: false,
                environment: [:]
            )
        )
    }

    func testGateSkipsWhenExplicitlyDisabled() {
        XCTAssertFalse(
            FirstRunOnboardingGate.shouldPresent(
                hasCompletedOnboarding: false,
                environment: [FirstRunOnboardingGate.disableEnvironmentKey: "1"]
            )
        )
    }

    func testGateSkipsUnderEvidenceAndLaunchHarnessEnvironments() {
        let harnessEnvironments: [[String: String]] = [
            ["SUISUI_DATABASE_PATH": "/tmp/isolated.sqlite"],
            ["SUISUI_LAUNCH_RECOVERY_MODE": "1"],
            ["SUISUI_FORCE_PROJECT_BOARD_FALLBACK": "1"],
            ["SUISUI_OPEN_SETTINGS_ON_LAUNCH": "1"],
            ["SUISUI_OPEN_VOICE_COMMAND_ON_LAUNCH": "1"]
        ]

        for environment in harnessEnvironments {
            XCTAssertFalse(
                FirstRunOnboardingGate.shouldPresent(
                    hasCompletedOnboarding: false,
                    environment: environment
                ),
                "Expected onboarding to stay hidden for \(environment)."
            )
        }
    }

    func testOnboardingRuntimeSmokeUsesAnIsolatedDatabaseWithoutForcingDismissedUsers() {
        let environment = [
            "SUISUI_DATABASE_PATH": "/tmp/fresh-onboarding.sqlite",
            FirstRunOnboardingGate.runtimeSmokeEnvironmentKey: "1"
        ]

        XCTAssertTrue(
            FirstRunOnboardingGate.shouldPresent(
                hasDismissedOnboarding: false,
                environment: environment
            )
        )
        XCTAssertFalse(
            FirstRunOnboardingGate.shouldPresent(
                hasDismissedOnboarding: true,
                environment: environment
            )
        )
    }

    func testReadinessSnapshotKeepsPlanningRequiredAndPermissionsOptional() {
        let snapshot = OnboardingReadinessSnapshot.make(
            selectedProvider: .openaiResponses,
            providerReadiness: .needsAction(reason: "Save the provider API key in Keychain."),
            permissions: .empty
        )

        XCTAssertEqual(snapshot.planningState, .needsAction(reason: "Save the provider API key in Keychain."))
        XCTAssertTrue(snapshot.canStartUsing)
        XCTAssertEqual(snapshot.items.first?.requirement, .required)
        XCTAssertTrue(snapshot.items.dropFirst().allSatisfy { $0.requirement == .optional })
        XCTAssertTrue(snapshot.items.dropFirst().allSatisfy { $0.state != .ready })
    }

    func testReadinessSnapshotMapsGrantedPermissionsAndReadyProvider() {
        var permissions = PermissionSnapshot.empty
        for permission in [AppPermission.microphone, .calendar, .reminders, .notifications] {
            permissions.setStatus(.granted, for: permission)
        }

        let snapshot = OnboardingReadinessSnapshot.make(
            selectedProvider: .ollamaCompatible,
            providerReadiness: .ready,
            permissions: permissions
        )

        XCTAssertEqual(snapshot.planningState, .ready)
        XCTAssertTrue(snapshot.items.allSatisfy { $0.state == .ready })
    }

    func testLegacyCompletionMigratesToDismissedWithoutChangingReadinessSource() throws {
        let suiteName = "FirstRunOnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: FirstRunOnboardingGate.completionDefaultsKey)
        XCTAssertNil(defaults.object(forKey: FirstRunOnboardingGate.dismissedDefaultsKey))

        FirstRunOnboardingGate.migrateLegacyCompletionIfNeeded(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: FirstRunOnboardingGate.dismissedDefaultsKey))
        XCTAssertFalse(
            FirstRunOnboardingGate.shouldPresent(
                hasDismissedOnboarding: defaults.bool(forKey: FirstRunOnboardingGate.dismissedDefaultsKey),
                environment: [:]
            )
        )
    }
}
