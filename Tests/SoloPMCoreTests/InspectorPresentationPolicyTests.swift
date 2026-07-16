import XCTest
@testable import SoloPMCore

final class InspectorPresentationPolicyTests: XCTestCase {
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

    func testResizeHidesCompactPresentationWithoutErasingRestorableIntent() {
        XCTAssertFalse(
            InspectorPresentationPolicy.shouldPresent(
                windowWidth: 1_024,
                route: .project(42),
                selection: .task,
                userRequested: true,
                allowsCompactPresentation: false
            )
        )
        XCTAssertTrue(
            InspectorPresentationPolicy.shouldPresent(
                windowWidth: 1_180,
                route: .project(42),
                selection: .task,
                userRequested: true,
                allowsCompactPresentation: false
            )
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
