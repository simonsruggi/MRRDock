import XCTest
@testable import MRRDock

/// Provider responses are parsed from `[String: Any]`, so these tests pin the
/// shapes each API actually returns — the pricing logic is worthless if the
/// fields are read from the wrong place.
final class ProviderParsingTests: XCTestCase {

    func testRevenueCatFlatOverviewShape() {
        let json: [String: Any] = [
            "active_trials": 12,
            "active_subscriptions": 340,
            "mrr": 2480.5,
            "revenue_last_28_days": 3100.0,
        ]
        let metrics = RevenueCatProvider.metrics(from: json)
        XCTAssertEqual(metrics["mrr"], 2480.5)
        XCTAssertEqual(metrics["active_subscriptions"], 340)
        XCTAssertEqual(metrics["active_trials"], 12)
        XCTAssertEqual(metrics["revenue"], 3100)
    }

    /// The shape the live v2 endpoint returns (checked against a real project).
    func testRevenueCatMetricsArrayShape() {
        let json: [String: Any] = [
            "currency": "USD",
            "metrics": [
                ["id": "mrr", "name": "MRR", "value": 1500.0, "unit": "USD"],
                ["id": "active_subscriptions", "value": 210],
                ["id": "active_trials", "value": 9],
            ],
        ]
        let metrics = RevenueCatProvider.metrics(from: json)
        XCTAssertEqual(metrics["mrr"], 1500)
        XCTAssertEqual(metrics["active_subscriptions"], 210)
        XCTAssertEqual(metrics["active_trials"], 9)
    }

    func testCustomEndpointAcceptsTheDocumentedShape() throws {
        let json: [String: Any] = ["mrr": 1234.5, "currency": "eur", "active_subscriptions": 42, "trials": 5]
        let snapshot = try CustomProvider.parse(json, currencyFallback: "USD")
        XCTAssertEqual(snapshot.mrr.byCurrency["EUR"], 1234.5)
        XCTAssertEqual(snapshot.activeSubscriptions, 42)
        XCTAssertEqual(snapshot.activeTrials, 5)
    }

    func testCustomEndpointUnwrapsDataAndUsesTheFallbackCurrency() throws {
        let json: [String: Any] = ["data": ["monthly_recurring_revenue": 99.0]]
        let snapshot = try CustomProvider.parse(json, currencyFallback: "GBP")
        XCTAssertEqual(snapshot.mrr.byCurrency["GBP"], 99)
    }

    func testCustomEndpointHonorsAnExplicitKey() throws {
        let json: [String: Any] = ["totals": 5, "my_mrr": 77.0]
        let snapshot = try CustomProvider.parse(json, currencyFallback: "USD", mrrKey: "my_mrr")
        XCTAssertEqual(snapshot.mrr.byCurrency["USD"], 77)
    }

    func testCustomEndpointWithoutAnMRRFieldFails() {
        XCTAssertThrowsError(try CustomProvider.parse(["hello": "world"], currencyFallback: "USD"))
    }

    /// A Stripe subscription item, priced the way `StripeProvider` prices it.
    func testStripeYearlySeatPricingMatchesTheMonthlyEquivalent() {
        // $120/year × 3 seats, 20% off → $24/month.
        let monthly = MRRMath.monthly(unitAmount: Money.minorUnits(12000, "usd").amount,
                                      interval: .year, intervalCount: 1, quantity: 3, discountPercent: 20)
        XCTAssertEqual(monthly, 24, accuracy: 0.0001)
    }

    /// Dodo quotes `recurring_pre_tax_amount` in minor units with a capitalized
    /// interval — the combination that would silently produce a 100× MRR.
    func testDodoStyleAmountAndInterval() throws {
        let interval = try XCTUnwrap(BillingInterval(provider: "Month"))
        let money = Money.minorUnits(1999, "USD")
        XCTAssertEqual(MRRMath.monthly(unitAmount: money.amount, interval: interval), 19.99, accuracy: 0.0001)
    }
}
