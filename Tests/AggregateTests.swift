import XCTest
@testable import MRRDock

final class AggregateTests: XCTestCase {
    private func source(_ kind: ProviderKind = .stripe, enabled: Bool = true) -> Source {
        Source(kind: kind, name: kind.displayName, enabled: enabled)
    }

    private func snapshot(mrr: [String: Double], subs: Int? = nil, trials: Int? = nil,
                          revenue: [String: Double] = [:], unpriced: Int = 0) -> ProviderSnapshot {
        var s = ProviderSnapshot()
        s.mrr = MoneyBag(byCurrency: mrr)
        s.revenue28d = MoneyBag(byCurrency: revenue)
        s.activeSubscriptions = subs
        s.activeTrials = trials
        s.unpricedSubscriptions = unpriced
        return s
    }

    func testSumsAcrossSourcesAndCurrencies() {
        let stripe = source(.stripe)
        let rc = source(.revenuecat)
        let aggregate = Aggregate.build(states: [
            (stripe, SourceState(snapshot: snapshot(mrr: ["EUR": 1000], subs: 40, trials: 3))),
            (rc, SourceState(snapshot: snapshot(mrr: ["USD": 500], subs: 60, trials: 7))),
        ], currency: "EUR", rate: { from, _ in from == "USD" ? 0.9 : nil })

        XCTAssertEqual(aggregate.mrr, 1450, accuracy: 0.0001)
        XCTAssertEqual(aggregate.arr, 17400, accuracy: 0.0001)
        XCTAssertEqual(aggregate.activeSubscriptions, 100)
        XCTAssertEqual(aggregate.activeTrials, 10)
        XCTAssertEqual(aggregate.perSource[rc.id] ?? 0, 450, accuracy: 0.0001)
        XCTAssertEqual(aggregate.sourcesReporting, 2)
        XCTAssertFalse(aggregate.isPartial)
    }

    func testDisabledSourcesAreIgnored() {
        let off = source(.paddle, enabled: false)
        let aggregate = Aggregate.build(states: [(off, SourceState(snapshot: snapshot(mrr: ["EUR": 999])))],
                                        currency: "EUR", rate: { _, _ in 1 })
        XCTAssertEqual(aggregate.mrr, 0)
        XCTAssertEqual(aggregate.sourcesReporting, 0)
    }

    func testAFailingSourceKeepsItsLastSnapshotAndMarksThTotalPartial() {
        let stripe = source(.stripe)
        let state = SourceState(snapshot: snapshot(mrr: ["EUR": 300]), error: "HTTP 502")
        let aggregate = Aggregate.build(states: [(stripe, state)], currency: "EUR", rate: { _, _ in 1 })
        XCTAssertEqual(aggregate.mrr, 300, accuracy: 0.0001)
        XCTAssertEqual(aggregate.sourcesFailing, 1)
        XCTAssertTrue(aggregate.isPartial)
    }

    func testMissingRateMakesTheTotalPartial() {
        let stripe = source(.stripe)
        let aggregate = Aggregate.build(states: [(stripe, SourceState(snapshot: snapshot(mrr: ["EUR": 100, "SEK": 900])))],
                                        currency: "EUR", rate: { from, _ in from == "SEK" ? nil : 1 })
        XCTAssertEqual(aggregate.mrr, 100, accuracy: 0.0001)
        XCTAssertEqual(aggregate.unconverted["SEK"], 900)
        XCTAssertTrue(aggregate.isPartial)
    }
}

final class DuplicateSourceTests: XCTestCase {
    private func rc(_ project: String, enabled: Bool = true) -> Source {
        Source(kind: .revenuecat, name: "RC", enabled: enabled, options: ["projectId": project])
    }

    func testTheSameRevenueCatProjectWithAndWithoutPrefixIsCountedOnce() {
        let first = rc("proj1c0213f5")
        let second = rc(" 1C0213F5 ")
        var s = ProviderSnapshot()
        s.mrr = MoneyBag(byCurrency: ["USD": 18])
        s.activeSubscriptions = 1
        let aggregate = Aggregate.build(states: [
            (first, SourceState(snapshot: s)),
            (second, SourceState(snapshot: s)),
        ], currency: "USD", rate: { _, _ in 1 })

        XCTAssertEqual(aggregate.mrr, 18, accuracy: 0.0001)
        XCTAssertEqual(aggregate.activeSubscriptions, 1)
        XCTAssertEqual(aggregate.sourcesReporting, 1)
        XCTAssertEqual(Source.duplicateIDs(in: [first, second]), [second.id])
    }

    func testADisabledCopyDoesNotHideTheEnabledOne() {
        let off = rc("proj1c0213f5", enabled: false)
        let on = rc("1c0213f5")
        XCTAssertEqual(Source.duplicateIDs(in: [off, on]), [])
    }

    func testDifferentProjectsAreNotDuplicates() {
        XCTAssertEqual(Source.duplicateIDs(in: [rc("proj0539cdcb"), rc("proj0786bbce")]), [])
    }

    func testSourcesWithoutAnAccountOptionAreNeverDuplicates() {
        let a = Source(kind: .stripe, name: "Stripe")
        let b = Source(kind: .stripe, name: "Stripe")
        XCTAssertEqual(Source.duplicateIDs(in: [a, b]), [])
    }

    func testRevenueCatProjectIDIsNormalizedForTheAPI() {
        XCTAssertEqual(RevenueCatProvider.normalizedProjectID(" 1c0213f5 "), "proj1c0213f5")
        XCTAssertEqual(RevenueCatProvider.normalizedProjectID("proj1c0213f5"), "proj1c0213f5")
    }
}
