import XCTest
@testable import SoloPMCore

final class DailyPlanningReviewPreviewCacheTests: XCTestCase {
    @MainActor
    func testProjectBoardViewModelCountsOnlyDailyPlanningPreviewCacheMisses() {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        let referenceDate = Date(timeIntervalSince1970: 1_783_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        viewModel.refreshDerivedReadModels(on: referenceDate, calendar: calendar)
        XCTAssertEqual(viewModel.dailyPlanningReviewPreviewBuildCount, 1)

        viewModel.refreshDerivedReadModels(on: referenceDate, calendar: calendar)
        XCTAssertEqual(viewModel.dailyPlanningReviewPreviewBuildCount, 1)

        viewModel.invalidateTodayWorkflowSnapshot(.taskMutation)
        viewModel.refreshDerivedReadModels(on: referenceDate, calendar: calendar)
        XCTAssertEqual(viewModel.dailyPlanningReviewPreviewBuildCount, 2)
    }

    func testSamePlanningDayAndRevisionBuildsPreviewOnlyOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let referenceDate = Date(timeIntervalSince1970: 1_783_000_000)
        let key = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: PlanningDayKey(
                referenceDate: referenceDate,
                calendar: calendar
            ),
            sourceRevision: 7,
            referenceDate: referenceDate,
            calendar: calendar
        )
        var cache = DailyPlanningReviewPreviewCache()
        var buildCount = 0

        let first = cache.review(for: key) {
            buildCount += 1
            return makeReview(sourceTranscript: "preview")
        }
        let second = cache.review(for: key) {
            buildCount += 1
            return makeReview(sourceTranscript: "unexpected rebuild")
        }

        XCTAssertEqual(first, second)
        XCTAssertEqual(buildCount, 1)
    }

    func testRevisionAndTimezoneChangesRebuildThePreview() {
        let referenceDate = Date(timeIntervalSince1970: 1_783_000_000)
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let tokyoKey = PlanningDayKey(referenceDate: referenceDate, calendar: tokyo)
        let newYorkKey = PlanningDayKey(referenceDate: referenceDate, calendar: newYork)
        var cache = DailyPlanningReviewPreviewCache()
        var buildCount = 0

        _ = cache.review(
            for: DailyPlanningReviewPreviewCacheKey(
                planningDayKey: tokyoKey,
                sourceRevision: 1,
                referenceDate: referenceDate,
                calendar: tokyo
            )
        ) {
            buildCount += 1
            return makeReview(sourceTranscript: "tokyo")
        }
        _ = cache.review(
            for: DailyPlanningReviewPreviewCacheKey(
                planningDayKey: tokyoKey,
                sourceRevision: 2,
                referenceDate: referenceDate,
                calendar: tokyo
            )
        ) {
            buildCount += 1
            return makeReview(sourceTranscript: "revision")
        }
        _ = cache.review(
            for: DailyPlanningReviewPreviewCacheKey(
                planningDayKey: newYorkKey,
                sourceRevision: 2,
                referenceDate: referenceDate,
                calendar: newYork
            )
        ) {
            buildCount += 1
            return makeReview(sourceTranscript: "timezone")
        }

        XCTAssertEqual(buildCount, 3)
        XCTAssertNotEqual(tokyoKey, newYorkKey)
    }

    func testPhaseAndHalfHourBoundarySeparateSameDayPreviewKeys() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let beforeNoon = try isoDate("2026-07-10T11:59:00Z")
        let afterNoon = try isoDate("2026-07-10T12:01:00Z")
        let planningDayKey = PlanningDayKey(referenceDate: beforeNoon, calendar: calendar)

        let beforeKey = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: planningDayKey,
            sourceRevision: 1,
            referenceDate: beforeNoon,
            calendar: calendar
        )
        let afterKey = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: planningDayKey,
            sourceRevision: 1,
            referenceDate: afterNoon,
            calendar: calendar
        )

        XCTAssertNotEqual(beforeKey, afterKey)
        XCTAssertEqual(beforeKey.phase, .morning)
        XCTAssertEqual(afterKey.phase, .midday)

        let beforeHalfHour = try isoDate("2026-07-10T12:29:00Z")
        let afterHalfHour = try isoDate("2026-07-10T12:30:00Z")
        let beforeHalfHourKey = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: planningDayKey,
            sourceRevision: 1,
            referenceDate: beforeHalfHour,
            calendar: calendar
        )
        let afterHalfHourKey = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: planningDayKey,
            sourceRevision: 1,
            referenceDate: afterHalfHour,
            calendar: calendar
        )

        XCTAssertNotEqual(beforeHalfHourKey, afterHalfHourKey)
    }

    func testDSTFoldAndSpringSkipRemainDistinctPreviewKeys() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        let firstFold = try isoDate("2026-11-01T05:30:00Z")
        let secondFold = try isoDate("2026-11-01T06:30:00Z")
        let foldDayKey = PlanningDayKey(referenceDate: firstFold, calendar: calendar)
        let firstFoldKey = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: foldDayKey,
            sourceRevision: 1,
            referenceDate: firstFold,
            calendar: calendar
        )
        let secondFoldKey = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: foldDayKey,
            sourceRevision: 1,
            referenceDate: secondFold,
            calendar: calendar
        )

        let beforeSpringSkip = try isoDate("2026-03-08T06:59:00Z")
        let afterSpringSkip = try isoDate("2026-03-08T07:00:00Z")
        let springDayKey = PlanningDayKey(referenceDate: beforeSpringSkip, calendar: calendar)
        let beforeSpringKey = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: springDayKey,
            sourceRevision: 1,
            referenceDate: beforeSpringSkip,
            calendar: calendar
        )
        let afterSpringKey = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: springDayKey,
            sourceRevision: 1,
            referenceDate: afterSpringSkip,
            calendar: calendar
        )

        XCTAssertNotEqual(firstFoldKey, secondFoldKey)
        XCTAssertNotEqual(beforeSpringKey, afterSpringKey)
    }

    private func makeReview(sourceTranscript: String) -> DailyPlanningReview {
        DailyPlanningReview(
            sourceTranscript: sourceTranscript,
            phase: .morning,
            requestedMinutes: nil,
            headline: "Preview",
            spokenSummary: "Preview",
            overdueCount: 0,
            dueTodayCount: 0,
            inboxUntriagedCount: 0,
            recommendedTaskID: nil,
            focusItems: [],
            scheduleBlocks: []
        )
    }

    private func isoDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
