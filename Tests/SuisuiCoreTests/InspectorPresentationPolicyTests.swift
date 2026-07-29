import XCTest
@testable import SuisuiCore

final class InspectorPresentationPolicyTests: XCTestCase {
    func testProjectDevelopmentContextExistsOnlyForCurrentInspectorSession() {
        var context = ProjectInspectorDevelopmentContext()

        context.handle(.openProject(taskID: 41))
        XCTAssertEqual(context.taskID, 41)

        context.handle(.dismissInspector)
        XCTAssertNil(context.taskID)

        context.handle(.openProject(taskID: 42))
        context.handle(.destinationChanged)
        XCTAssertNil(context.taskID)

        context.handle(.openProject(taskID: 43))
        context.handle(.openTaskInspector)
        XCTAssertNil(context.taskID)

        context.handle(.openProject(taskID: nil))
        XCTAssertNil(context.taskID)
    }

    func testLegacyDestinationChangedEventStillClearsDevelopmentContext() {
        var context = ProjectInspectorDevelopmentContext()

        context.handle(.openProject(taskID: 41))
        context.handle(.destinationChanged)

        XCTAssertNil(context.taskID)
    }

    func testCompactWindowsStartClosedAndRequireExplicitPresentation() {
        for width in [960.0, 1_024.0] {
            XCTAssertFalse(
                InspectorPresentationPolicy.shouldPresent(
                    windowWidth: width,
                    route: .project(42),
                    selection: .project,
                    userRequested: false,
                    allowsCompactPresentation: false
                )
            )
            XCTAssertFalse(
                InspectorPresentationPolicy.shouldPresent(
                    windowWidth: width,
                    route: .project(42),
                    selection: .task,
                    userRequested: true,
                    allowsCompactPresentation: false
                )
            )
            XCTAssertTrue(
                InspectorPresentationPolicy.shouldPresent(
                    windowWidth: width,
                    route: .project(42),
                    selection: .task,
                    userRequested: true,
                    allowsCompactPresentation: true
                )
            )
        }
    }

    func testWideWindowRestoresSceneLocalIntentOnlyForSupportedSelection() {
        XCTAssertTrue(
            InspectorPresentationPolicy.shouldPresent(
                windowWidth: 1_180,
                route: .project(42),
                selection: .project,
                userRequested: true,
                allowsCompactPresentation: false
            )
        )
        XCTAssertFalse(
            InspectorPresentationPolicy.shouldPresent(
                windowWidth: 1_180,
                route: .project(42),
                selection: .none,
                userRequested: true,
                allowsCompactPresentation: false
            )
        )
        XCTAssertFalse(
            InspectorPresentationPolicy.shouldPresent(
                windowWidth: 1_180,
                route: .primary(.projects),
                selection: .project,
                userRequested: true,
                allowsCompactPresentation: false
            )
        )
    }

    func testTodayAndInboxRailsOnlyYieldToAnExplicitEditRequest() {
        for route in [BoardRoute.primary(.today), .primary(.inbox)] {
            XCTAssertFalse(
                InspectorPresentationPolicy.shouldPresent(
                    windowWidth: 1_180,
                    route: route,
                    selection: .task,
                    userRequested: true,
                    allowsCompactPresentation: false
                )
            )
            XCTAssertTrue(
                InspectorPresentationPolicy.shouldPresent(
                    windowWidth: 1_024,
                    route: route,
                    selection: .task,
                    userRequested: true,
                    allowsCompactPresentation: true
                )
            )
        }
    }

    func testWideToCompactResizePreservesFreshExplicitCompactRequest() {
        let explicitIntent = InspectorPresentationIntent(
            userRequested: true,
            allowsCompactPresentation: true
        )
        let intent = InspectorPresentationPolicy.intentAfterResize(
            previousWindowWidth: 1_180,
            currentWindowWidth: 1_024,
            intent: explicitIntent
        )

        XCTAssertEqual(intent, explicitIntent)
    }

    func testWideToCompactResizeClearsPassiveWideIntent() {
        XCTAssertEqual(
            InspectorPresentationPolicy.intentAfterResize(
                previousWindowWidth: 1_180,
                currentWindowWidth: 1_024,
                intent: InspectorPresentationIntent(
                    userRequested: true,
                    allowsCompactPresentation: false
                )
            ),
            .closed
        )
    }

    func testClearedOrDeletedSelectionClosesWithoutChangingUserIntentInput() {
        XCTAssertFalse(
            InspectorPresentationPolicy.shouldPresent(
                windowWidth: 1_180,
                route: .project(42),
                selection: .none,
                userRequested: true,
                allowsCompactPresentation: true
            )
        )
    }
}
