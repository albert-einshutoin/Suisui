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
}
