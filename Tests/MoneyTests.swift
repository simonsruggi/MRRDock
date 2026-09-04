import XCTest
@testable import MRRDock

final class MoneyTests: XCTestCase {
    func testIntervalParsingIsToleranteAcrossProviders() {
        XCTAssertEqual(BillingInterval(provider: "month"), .month)
        XCTAssertEqual(BillingInterval(provider: "Month"), .month)      // Dodo
        XCTAssertEqual(BillingInterval(provider: "months"), .month)
        XCTAssertEqual(BillingInterval(provider: "yearly"), .year)
        XCTAssertEqual(BillingInterval(provider: "annual"), .year)
        XCTAssertEqual(BillingInterval(provider: " WEEK "), .week)
        XCTAssertNil(BillingInterval(provider: "quarter"))
    }

    func testMinorUnitsRespectCurrencyExponent() {
        XCTAssertEqual(Money.minorUnits(1999, "usd").amount, 19.99, accuracy: 0.0001)
        XCTAssertEqual(Money.minorUnits(1999, "JPY").amount, 1999, accuracy: 0.0001)
        XCTAssertEqual(Money.minorUnits(1999, "KWD").amount, 1.999, accuracy: 0.0001)
        XCTAssertEqual(Money.minorUnits(1999, "usd").currency, "USD")
    }

    func testMonthlyNormalization() {
        XCTAssertEqual(MRRMath.monthly(unitAmount: 10, interval: .month), 10, accuracy: 0.0001)
        XCTAssertEqual(MRRMath.monthly(unitAmount: 120, interval: .year), 10, accuracy: 0.0001)
        XCTAssertEqual(MRRMath.monthly(unitAmount: 30, interval: .month, intervalCount: 3), 10, accuracy: 0.0001)
        XCTAssertEqual(MRRMath.monthly(unitAmount: 10, interval: .month, quantity: 5), 50, accuracy: 0.0001)
        XCTAssertEqual(MRRMath.monthly(unitAmount: 1, interval: .week), 4.3482, accuracy: 0.001)
        XCTAssertEqual(MRRMath.monthly(unitAmount: 1, interval: .day), 30.4375, accuracy: 0.001)
    }

    func testTwelveMonthliesEqualOneYearly() {
        let yearly = MRRMath.monthly(unitAmount: 1200, interval: .year)
        let monthly = MRRMath.monthly(unitAmount: 100, interval: .month)
        XCTAssertEqual(yearly, monthly, accuracy: 0.0001)
    }

    func testPercentDiscountLowersMRR() {
        XCTAssertEqual(MRRMath.monthly(unitAmount: 100, interval: .month, discountPercent: 50), 50, accuracy: 0.0001)
        XCTAssertEqual(MRRMath.monthly(unitAmount: 100, interval: .month, discountPercent: 150), 0, accuracy: 0.0001)
        XCTAssertEqual(MRRMath.monthly(unitAmount: 100, interval: .month, discountPercent: -10), 100, accuracy: 0.0001)
    }

    func testZeroQuantityOrIntervalIsWorthNothing() {
        XCTAssertEqual(MRRMath.monthly(unitAmount: 100, interval: .month, intervalCount: 0), 0)
        XCTAssertEqual(MRRMath.monthly(unitAmount: 100, interval: .month, quantity: 0), 0)
    }

    func testMoneyBagKeepsCurrenciesApartUntilConverted() {
        var bag = MoneyBag()
        bag.add(Money(100, "EUR"))
        bag.add(Money(50, "EUR"))
        bag.add(Money(200, "USD"))
        XCTAssertEqual(bag.byCurrency["EUR"], 150)

        let converted = bag.converted(to: "EUR") { from, _ in from == "USD" ? 0.9 : nil }
        XCTAssertEqual(converted.total, 150 + 180, accuracy: 0.0001)
        XCTAssertTrue(converted.missing.isEmpty)
    }

    func testMissingRateIsReportedNotDropped() {
        var bag = MoneyBag()
        bag.add(Money(100, "EUR"))
        bag.add(Money(500, "JPY"))
        let converted = bag.converted(to: "EUR") { _, _ in nil }
        XCTAssertEqual(converted.total, 100, accuracy: 0.0001)
        XCTAssertEqual(converted.missing["JPY"], 500)
    }

    func testGrowthNeedsABaseline() {
        XCTAssertEqual(MRRMath.growthPercent(from: 100, to: 150), 50)
        XCTAssertEqual(MRRMath.growthPercent(from: 100, to: 80), -20)
        XCTAssertNil(MRRMath.growthPercent(from: 0, to: 500))
    }
}
