import Foundation

/// Everything the UI and the menu bar read: totals in the display currency plus
/// what could not be converted.
struct Aggregate: Equatable {
    var mrr: Double = 0
    var revenue28d: Double = 0
    var activeSubscriptions: Int = 0
    var activeTrials: Int = 0
    var unpricedSubscriptions: Int = 0
    /// Amounts left out of the totals because no exchange rate was available.
    var unconverted: [String: Double] = [:]
    var currency: String = "EUR"
    var perSource: [UUID: Double] = [:]
    var sourcesReporting: Int = 0
    var sourcesFailing: Int = 0

    var arr: Double { MRRMath.arr(mrr: mrr) }
    var isPartial: Bool { !unconverted.isEmpty || sourcesFailing > 0 }

    /// Folds every source's snapshot into one total. Pure, so the arithmetic
    /// that produces the number in the menu bar is covered by tests rather than
    /// by squinting at the UI.
    static func build(states: [(source: Source, state: SourceState)],
                      currency: String,
                      rate: (String, String) -> Double?) -> Aggregate {
        var out = Aggregate(currency: currency.uppercased())
        for (source, state) in states {
            guard source.enabled else { continue }
            if state.error != nil { out.sourcesFailing += 1 }
            guard let snapshot = state.snapshot else { continue }
            out.sourcesReporting += 1

            let mrr = snapshot.mrr.converted(to: currency, rate: rate)
            out.mrr += mrr.total
            out.perSource[source.id] = mrr.total
            for (code, amount) in mrr.missing { out.unconverted[code, default: 0] += amount }

            let revenue = snapshot.revenue28d.converted(to: currency, rate: rate)
            out.revenue28d += revenue.total

            out.activeSubscriptions += snapshot.activeSubscriptions ?? 0
            out.activeTrials += snapshot.activeTrials ?? 0
            out.unpricedSubscriptions += snapshot.unpricedSubscriptions
        }
        return out
    }
}

/// Decides when an MRR reading deserves a notification. Pure and stateless: the
/// caller owns `lastMilestone`, so the same logic is testable and survives a
/// restart without re-firing yesterday's milestone.
enum MilestoneEvaluator {
    /// Returns the milestone just crossed upwards, or nil.
    ///
    /// Only upward crossings fire — a churned customer dropping MRR back under
    /// €5.000 is not a celebration, and re-crossing it next week would notify
    /// twice for the same milestone if the marker moved down on the way.
    static func crossed(mrr: Double, step: Double, lastMilestone: Double) -> Double? {
        guard step > 0, mrr > 0 else { return nil }
        let reached = (mrr / step).rounded(.down) * step
        guard reached >= step, reached > lastMilestone else { return nil }
        return reached
    }

    /// Whether the daily summary is due: after `hour` local time, once per day.
    static func summaryDue(now: Date, lastSummaryDay: String, hour: Int = 22,
                           calendar: Calendar = .current) -> Bool {
        guard calendar.component(.hour, from: now) >= hour else { return false }
        return dayKey(now, calendar: calendar) != lastSummaryDay
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
