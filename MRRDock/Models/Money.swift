import Foundation

/// Billing period of a recurring price, normalized across providers.
///
/// Every provider spells intervals differently (Stripe `month`, Paddle `month`,
/// Dodo `Month`, Lemon Squeezy `month`), so parsing is case- and plural-tolerant
/// and lives in one place: an interval we fail to recognize would silently make
/// a subscription worth zero MRR.
enum BillingInterval: String, Codable, CaseIterable {
    case day, week, month, year

    init?(provider raw: String) {
        var s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("s") { s.removeLast() }
        switch s {
        case "day", "daily": self = .day
        case "week", "weekly": self = .week
        case "month", "monthly": self = .month
        case "year", "yearly", "annual", "annually": self = .year
        default: return nil
        }
    }

    /// How many of this interval fit in an average month.
    ///
    /// Uses the average Gregorian month (365.25 / 12 = 30.4375 days) rather than
    /// 30: with 30, a yearly plan and twelve monthly plans don't reconcile, and
    /// the drift shows up as a permanently wrong MRR on weekly-heavy accounts.
    var perMonth: Double {
        switch self {
        case .day: return 30.4375
        case .week: return 30.4375 / 7
        case .month: return 1
        case .year: return 1.0 / 12
        }
    }
}

/// An amount plus its ISO currency code. Amounts are always in *major* units
/// (12.34 EUR), never cents — providers disagree on this and the conversion
/// happens at the edge, in each provider, so nothing downstream has to ask.
struct Money: Equatable, Codable {
    var amount: Double
    var currency: String

    init(_ amount: Double, _ currency: String) {
        self.amount = amount
        self.currency = currency.uppercased()
    }

    /// Builds from a minor-unit integer (cents) using the currency's exponent.
    static func minorUnits(_ value: Double, _ currency: String) -> Money {
        Money(value / pow(10, Double(Self.exponent(for: currency))), currency)
    }

    /// Decimal digits in a currency's minor unit. The zero-decimal list is
    /// Stripe's (JPY 100 means ¥100, not ¥1.00) and applies to every provider
    /// that quotes in minor units.
    static func exponent(for currency: String) -> Int {
        let c = currency.uppercased()
        if zeroDecimal.contains(c) { return 0 }
        if threeDecimal.contains(c) { return 3 }
        return 2
    }

    private static let zeroDecimal: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG",
        "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF",
    ]
    private static let threeDecimal: Set<String> = ["BHD", "JOD", "KWD", "OMR", "TND"]
}

/// Sums of money that keep each currency separate until an exchange rate is
/// available. A source can legitimately bill in several currencies at once, and
/// adding those numbers together before converting is the classic way to report
/// a wrong MRR.
struct MoneyBag: Equatable, Codable {
    private(set) var byCurrency: [String: Double] = [:]

    init() {}
    init(_ money: Money) { add(money) }
    init(byCurrency: [String: Double]) {
        self.byCurrency = byCurrency.reduce(into: [:]) { $0[$1.key.uppercased()] = $1.value }
    }

    var isEmpty: Bool { byCurrency.allSatisfy { $0.value == 0 } }

    mutating func add(_ money: Money) {
        guard money.amount != 0 else { return }
        byCurrency[money.currency, default: 0] += money.amount
    }

    mutating func add(_ other: MoneyBag) {
        for (currency, amount) in other.byCurrency {
            byCurrency[currency, default: 0] += amount
        }
    }

    func adding(_ other: MoneyBag) -> MoneyBag {
        var copy = self
        copy.add(other)
        return copy
    }

    /// Converts every currency into `target`. `rate(from:to:)` returns nil when a
    /// rate is unavailable; those amounts are reported in `missing` instead of
    /// being dropped silently, so the UI can say "partial" rather than lie.
    func converted(to target: String, rate: (String, String) -> Double?) -> (total: Double, missing: [String: Double]) {
        var total: Double = 0
        var missing: [String: Double] = [:]
        for (currency, amount) in byCurrency {
            if currency == target.uppercased() {
                total += amount
            } else if let r = rate(currency, target.uppercased()) {
                total += amount * r
            } else {
                missing[currency] = amount
            }
        }
        return (total, missing)
    }
}

enum MRRMath {
    /// Monthly value of one recurring line item.
    ///
    /// - Parameters:
    ///   - unitAmount: price per unit, in major units.
    ///   - interval: how often it is billed.
    ///   - intervalCount: e.g. every 3 months → `.month`, 3.
    ///   - quantity: seats/licences.
    ///   - discountPercent: 0–100, applied last (a 50% off coupon halves MRR).
    static func monthly(unitAmount: Double,
                        interval: BillingInterval,
                        intervalCount: Int = 1,
                        quantity: Int = 1,
                        discountPercent: Double = 0) -> Double {
        guard intervalCount > 0, quantity > 0 else { return 0 }
        let perPeriod = unitAmount * Double(quantity)
        let periodsPerMonth = interval.perMonth / Double(intervalCount)
        let gross = perPeriod * periodsPerMonth
        return gross * (1 - min(max(discountPercent, 0), 100) / 100)
    }

    /// Annual run rate.
    static func arr(mrr: Double) -> Double { mrr * 12 }

    /// Growth between two MRR readings, as a percentage. Nil when there is no
    /// baseline to grow from (0 → anything is not "infinite growth", it's a
    /// number the UI should not print).
    static func growthPercent(from previous: Double, to current: Double) -> Double? {
        guard previous > 0 else { return nil }
        return (current - previous) / previous * 100
    }
}
