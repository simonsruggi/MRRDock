import XCTest
@testable import MRRDock

final class MenuBarTitleTests: XCTestCase {
    private func aggregate(mrr: Double = 1234, subs: Int = 42, revenue: Double = 2000) -> Aggregate {
        var a = Aggregate()
        a.sourcesReporting = 1
        a.currency = "EUR"
        a.mrr = mrr
        a.activeSubscriptions = subs
        a.revenue28d = revenue
        return a
    }

    func testMRRMode() {
        let title = MenuBarTitle.text(.init(mode: .mrr, aggregate: aggregate(), growth30d: nil,
                                            privacy: false, decimals: 0))
        XCTAssertTrue(title.contains("1"))
        XCTAssertTrue(title.contains("234"))
    }

    func testChangeModeFallsBackWhenThereIsNoHistory() {
        let withGrowth = MenuBarTitle.text(.init(mode: .mrrWithChange, aggregate: aggregate(), growth30d: 12.4,
                                                 privacy: false, decimals: 0))
        XCTAssertTrue(withGrowth.hasSuffix("+12%"))
        let without = MenuBarTitle.text(.init(mode: .mrrWithChange, aggregate: aggregate(), growth30d: nil,
                                              privacy: false, decimals: 0))
        XCTAssertFalse(without.contains("%"))
    }

    func testPrivacyModeHidesEveryNumber() {
        for mode in MenuBarMode.allCases {
            let title = MenuBarTitle.text(.init(mode: mode, aggregate: aggregate(), growth30d: 5,
                                                privacy: true, decimals: 0))
            XCTAssertEqual(title, "•••", "mode \(mode.rawValue) leaked a number")
        }
    }

    func testSubscriptionsAndARRModes() {
        XCTAssertEqual(MenuBarTitle.text(.init(mode: .activeSubscriptions, aggregate: aggregate(), growth30d: nil,
                                               privacy: false, decimals: 0)), "42 subs")
        XCTAssertTrue(MenuBarTitle.text(.init(mode: .arr, aggregate: aggregate(), growth30d: nil,
                                              privacy: false, decimals: 0)).hasSuffix("ARR"))
    }

    func testIconOnlyIsEmptyAndNoSourcesShowsAPlaceholder() {
        XCTAssertEqual(MenuBarTitle.text(.init(mode: .iconOnly, aggregate: aggregate(), growth30d: nil,
                                               privacy: false, decimals: 0)), "")
        XCTAssertEqual(MenuBarTitle.text(.init(mode: .mrr, aggregate: aggregate(), growth30d: nil,
                                               privacy: false, decimals: 0, hasSources: false)), "MRR —")
    }

    func testNoAnswerYetShowsADashNotZero() {
        var pending = Aggregate()
        pending.currency = "EUR"
        let title = MenuBarTitle.text(.init(mode: .mrr, aggregate: pending, growth30d: nil,
                                            privacy: false, decimals: 0))
        XCTAssertEqual(title, "—")
    }

    func testPerSourceCyclesAndTruncatesLongNames() {
        let stripe = Source(kind: .stripe, name: "Stripe")
        let rc = Source(kind: .revenuecat, name: "RevenueCat Apps Portfolio")
        var a = aggregate()
        a.perSource = [stripe.id: 800, rc.id: 434]

        let first = MenuBarTitle.text(.init(mode: .perSource, aggregate: a, growth30d: nil, privacy: false,
                                            decimals: 0, sourceIndex: 0, sources: [stripe, rc]))
        let second = MenuBarTitle.text(.init(mode: .perSource, aggregate: a, growth30d: nil, privacy: false,
                                             decimals: 0, sourceIndex: 1, sources: [stripe, rc]))
        XCTAssertTrue(first.hasPrefix("Stripe"))
        XCTAssertTrue(second.hasPrefix("RevenueCat"))
        XCTAssertFalse(second.contains("Portfolio"))
        // Wrapping round the end must not crash or blank the bar.
        let wrapped = MenuBarTitle.text(.init(mode: .perSource, aggregate: a, growth30d: nil, privacy: false,
                                              decimals: 0, sourceIndex: 7, sources: [stripe, rc]))
        XCTAssertFalse(wrapped.isEmpty)
    }
}
