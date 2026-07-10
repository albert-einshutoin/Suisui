import XCTest
@testable import SoloPMCore

final class DailyPlanningReviewPreviewCacheTests: XCTestCase {
    func testSamePlanningDayAndRevisionBuildsPreviewOnlyOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let key = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: PlanningDayKey(
                referenceDate: Date(timeIntervalSince1970: 1_783_000_000),
                calendar: calendar
            ),
            sourceRevision: 7
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
            for: DailyPlanningReviewPreviewCacheKey(planningDayKey: tokyoKey, sourceRevision: 1)
        ) {
            buildCount += 1
            return makeReview(sourceTranscript: "tokyo")
        }
        _ = cache.review(
            for: DailyPlanningReviewPreviewCacheKey(planningDayKey: tokyoKey, sourceRevision: 2)
        ) {
            buildCount += 1
            return makeReview(sourceTranscript: "revision")
        }
        _ = cache.review(
            for: DailyPlanningReviewPreviewCacheKey(planningDayKey: newYorkKey, sourceRevision: 2)
        ) {
            buildCount += 1
            return makeReview(sourceTranscript: "timezone")
        }

        XCTAssertEqual(buildCount, 3)
        XCTAssertNotEqual(tokyoKey, newYorkKey)
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
}
