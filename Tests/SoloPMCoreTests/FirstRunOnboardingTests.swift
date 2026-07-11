import XCTest
@testable import SoloPMCore

final class FirstRunOnboardingTests: XCTestCase {
    func testFlowAdvancesThroughAllStepsInOrderAndStopsAtEnds() {
        var flow = FirstRunOnboardingFlow()

        XCTAssertEqual(flow.step, .welcome)
        XCTAssertTrue(flow.isFirstStep)
        XCTAssertFalse(flow.isLastStep)
        XCTAssertEqual(flow.stepIndex, 0)
        XCTAssertEqual(flow.stepCount, 4)

        flow.goBack()
        XCTAssertEqual(flow.step, .welcome)

        flow.advance()
        XCTAssertEqual(flow.step, .aiProvider)
        flow.advance()
        XCTAssertEqual(flow.step, .permissions)
        flow.advance()
        XCTAssertEqual(flow.step, .finish)
        XCTAssertTrue(flow.isLastStep)

        flow.advance()
        XCTAssertEqual(flow.step, .finish)

        flow.goBack()
        XCTAssertEqual(flow.step, .permissions)
    }

    func testGatePresentsOnlyForFreshInteractiveLaunches() {
        XCTAssertTrue(
            FirstRunOnboardingGate.shouldPresent(hasCompletedOnboarding: false, environment: [:])
        )
        XCTAssertFalse(
            FirstRunOnboardingGate.shouldPresent(hasCompletedOnboarding: true, environment: [:])
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
            ["SOLOPM_DATABASE_PATH": "/tmp/isolated.sqlite"],
            ["SOLOPM_LAUNCH_RECOVERY_MODE": "1"],
            ["SOLOPM_FORCE_PROJECT_BOARD_FALLBACK": "1"],
            ["SOLOPM_OPEN_SETTINGS_ON_LAUNCH": "1"],
            ["SOLOPM_OPEN_VOICE_COMMAND_ON_LAUNCH": "1"]
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
