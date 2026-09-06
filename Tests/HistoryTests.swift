import XCTest
@testable import MRRDock

final class HistoryTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    func testRecentReadingsAreAllKeptSoTheDayChartHasAShape() {
        let now = Date()
        var points = MRRHistory.upsert([], value: 100, currency: "EUR", now: now.addingTimeInterval(-3600), calendar: calendar)
        points = MRRHistory.upsert(points, value: 120, currency: "EUR", now: now, calendar: calendar)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.last?.mrr, 120)
    }

    func testReadingsOlderThanTwoDaysCollapseToOnePerDay() {
        let now = Date()
        let old = day(-5, from: now)
        let series = [
            MRRPoint(date: old, mrr: 10, currency: "EUR"),
            MRRPoint(date: old.addingTimeInterval(3600), mrr: 20, currency: "EUR"),
            MRRPoint(date: old.addingTimeInterval(7200), mrr: 30, currency: "EUR"),
        ]
        let points = MRRHistory.compact(series, now: now, calendar: calendar)
        XCTAssertEqual(points.count, 1)
        // The last reading of the day is the one that survives.
        XCTAssertEqual(points.first?.mrr, 30)
    }

    func testOldPointsAreTrimmed() {
        let now = Date()
        let old = [MRRPoint(date: day(-800, from: now), mrr: 10, currency: "EUR")]
        let points = MRRHistory.upsert(old, value: 100, currency: "EUR", now: now, calendar: calendar, keepDays: 730)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.mrr, 100)
    }

    func testThirtyDayLookupNeedsAPointNearThatDate() {
        let now = Date()
        let points = [
            MRRPoint(date: day(-31, from: now), mrr: 800, currency: "EUR"),
            MRRPoint(date: day(-1, from: now), mrr: 1000, currency: "EUR"),
        ]
        XCTAssertEqual(MRRHistory.value(points, daysAgo: 30, now: now, calendar: calendar), 800)
        // Two weeks of history must not be passed off as a 30-day comparison.
        let young = [MRRPoint(date: day(-14, from: now), mrr: 900, currency: "EUR")]
        XCTAssertNil(MRRHistory.value(young, daysAgo: 30, now: now, calendar: calendar))
    }

    // MARK: Ranges

    private func series(from now: Date) -> [MRRPoint] {
        [
            MRRPoint(date: day(-400, from: now), mrr: 50, currency: "EUR"),
            MRRPoint(date: day(-20, from: now), mrr: 100, currency: "EUR"),
            MRRPoint(date: day(-3, from: now), mrr: 200, currency: "EUR"),
            MRRPoint(date: now.addingTimeInterval(-3600), mrr: 300, currency: "EUR"),
        ]
    }

    func testEachRangeKeepsOnlyItsOwnWindow() {
        let now = Date()
        let points = series(from: now)
        XCTAssertEqual(MRRHistory.points(points, in: .day, now: now, calendar: calendar).map(\.mrr), [300])
        XCTAssertEqual(MRRHistory.points(points, in: .week, now: now, calendar: calendar).map(\.mrr), [200, 300])
        XCTAssertEqual(MRRHistory.points(points, in: .year, now: now, calendar: calendar).map(\.mrr), [100, 200, 300])
    }

    func testCustomRangeIsInclusiveOfBothDaysAndSurvivesBackwardsDates() {
        let now = Date()
        let points = series(from: now)
        let inOrder = MRRHistory.points(points, in: .custom, from: day(-20, from: now), to: day(-3, from: now),
                                        now: now, calendar: calendar)
        XCTAssertEqual(inOrder.map(\.mrr), [100, 200])
        // Picking the end date first must not empty the chart.
        let reversed = MRRHistory.points(points, in: .custom, from: day(-3, from: now), to: day(-20, from: now),
                                         now: now, calendar: calendar)
        XCTAssertEqual(reversed.map(\.mrr), [100, 200])
    }

    func testCustomRangeWithoutDatesDrawsNothing() {
        let now = Date()
        XCTAssertTrue(MRRHistory.points(series(from: now), in: .custom, now: now, calendar: calendar).isEmpty)
    }

    // MARK: Backfill from the providers

    private let a = UUID(), b = UUID()
    private func daily(_ offsets: [Int], _ value: Double, currency: String = "USD", from now: Date) -> [DailyMRR] {
        offsets.map { DailyMRR(date: day($0, from: now), money: Money(value, currency)) }
    }

    func testADayCountsOnlyWhenEverySourceReportsIt() {
        let now = Date()
        let totals = MRRHistory.dailyTotals([a: daily([-2, -1], 10, from: now),
                                             b: daily([-1], 5, from: now)],
                                            currency: "USD", calendar: calendar) { _, _ in nil }
        // Two days back only one source existed: reporting 10 there would draw
        // a jump the business never made.
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[calendar.startOfDay(for: day(-1, from: now))], 15)
    }

    func testTotalsAreConvertedIntoTheDisplayCurrency() {
        let now = Date()
        let totals = MRRHistory.dailyTotals([a: daily([-1], 100, currency: "USD", from: now)],
                                            currency: "EUR", calendar: calendar) { from, to in
            from == "USD" && to == "EUR" ? 0.5 : nil
        }
        XCTAssertEqual(totals[calendar.startOfDay(for: day(-1, from: now))], 50)
    }

    func testUnconvertibleDaysAreDroppedNotCountedAsZero() {
        let now = Date()
        let totals = MRRHistory.dailyTotals([a: daily([-1], 100, currency: "USD", from: now)],
                                            currency: "EUR", calendar: calendar) { _, _ in nil }
        XCTAssertTrue(totals.isEmpty)
    }

    func testBackfillReplacesThePastAndKeepsTodaysOwnReading() {
        let now = Date()
        let own = [
            MRRPoint(date: day(-1, from: now), mrr: 999, currency: "EUR"),
            MRRPoint(date: now, mrr: 320, currency: "EUR"),
        ]
        let totals = [calendar.startOfDay(for: day(-2, from: now)): 100.0,
                      calendar.startOfDay(for: day(-1, from: now)): 200.0]
        let merged = MRRHistory.backfilled(own, with: totals, currency: "EUR", now: now, calendar: calendar)
        XCTAssertEqual(merged.map(\.mrr), [100, 200, 320])
    }

    func testBackfillRunsOncePerDay() {
        let now = Date()
        XCTAssertTrue(MRRHistory.backfillDue(lastRun: nil, now: now, calendar: calendar))
        XCTAssertFalse(MRRHistory.backfillDue(lastRun: now.addingTimeInterval(-60), now: now, calendar: calendar))
        XCTAssertTrue(MRRHistory.backfillDue(lastRun: day(-1, from: now), now: now, calendar: calendar))
    }

    func testBackfillDropsTheZerosBeforeTheBusinessStarted() {
        let now = Date()
        let totals = [calendar.startOfDay(for: day(-4, from: now)): 0.0,
                      calendar.startOfDay(for: day(-3, from: now)): 0.0,
                      calendar.startOfDay(for: day(-2, from: now)): 40.0,
                      calendar.startOfDay(for: day(-1, from: now)): 0.0]
        let merged = MRRHistory.backfilled([], with: totals, currency: "EUR", now: now, calendar: calendar)
        // A zero *after* the start is real (everybody churned) and stays.
        XCTAssertEqual(merged.map(\.mrr), [40, 0])
    }
}
