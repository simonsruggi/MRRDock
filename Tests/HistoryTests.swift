import XCTest
@testable import MRRDock

final class HistoryTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    func testOnePointPerDayTheLastOneWins() {
        let now = Date()
        var points = MRRHistory.upsert([], value: 100, currency: "EUR", now: now, calendar: calendar)
        points = MRRHistory.upsert(points, value: 120, currency: "EUR", now: now.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.mrr, 120)
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
}
