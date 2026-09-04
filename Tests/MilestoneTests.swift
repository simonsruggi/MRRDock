import XCTest
@testable import MRRDock

final class MilestoneTests: XCTestCase {
    func testFiresOnceOnTheWayUp() {
        XCTAssertEqual(MilestoneEvaluator.crossed(mrr: 1050, step: 1000, lastMilestone: 0), 1000)
        XCTAssertNil(MilestoneEvaluator.crossed(mrr: 1200, step: 1000, lastMilestone: 1000))
        XCTAssertEqual(MilestoneEvaluator.crossed(mrr: 2010, step: 1000, lastMilestone: 1000), 2000)
    }

    func testDoesNotFireBelowTheFirstStepOrGoingDown() {
        XCTAssertNil(MilestoneEvaluator.crossed(mrr: 900, step: 1000, lastMilestone: 0))
        XCTAssertNil(MilestoneEvaluator.crossed(mrr: 1500, step: 1000, lastMilestone: 5000))
        XCTAssertNil(MilestoneEvaluator.crossed(mrr: 0, step: 1000, lastMilestone: 0))
        XCTAssertNil(MilestoneEvaluator.crossed(mrr: 1500, step: 0, lastMilestone: 0))
    }

    func testDailySummaryIsDueOncePerDayAfterTheHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 22, minute: 30))!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 9))!

        XCTAssertFalse(MilestoneEvaluator.summaryDue(now: morning, lastSummaryDay: "", calendar: calendar))
        XCTAssertTrue(MilestoneEvaluator.summaryDue(now: evening, lastSummaryDay: "", calendar: calendar))
        XCTAssertFalse(MilestoneEvaluator.summaryDue(now: evening, lastSummaryDay: "2026-09-04", calendar: calendar))
        XCTAssertTrue(MilestoneEvaluator.summaryDue(now: evening, lastSummaryDay: "2026-09-03", calendar: calendar))
    }
}
