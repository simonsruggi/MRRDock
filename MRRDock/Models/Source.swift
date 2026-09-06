import Foundation

/// A revenue platform MRRDock can read from.
///
/// Adding a provider means adding a case here, an implementation of
/// `RevenueProvider`, and a row in `ProviderRegistry` — nothing else in the app
/// knows the difference between Stripe and RevenueCat.
enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case stripe
    case revenuecat
    case paddle
    case lemonsqueezy
    case polar
    case dodo
    case gumroad
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stripe: return "Stripe"
        case .revenuecat: return "RevenueCat"
        case .paddle: return "Paddle"
        case .lemonsqueezy: return "Lemon Squeezy"
        case .polar: return "Polar"
        case .dodo: return "Dodo Payments"
        case .gumroad: return "Gumroad"
        case .custom: return "Custom endpoint"
        }
    }

    /// What the user has to paste in the "secret" field, in their words.
    var secretLabel: String {
        switch self {
        case .stripe: return "Restricted API key (rk_live_…)"
        case .revenuecat: return "Secret API key (sk_… or atk_…)"
        case .paddle: return "API key (pdl_live_apikey_…)"
        case .lemonsqueezy: return "API key"
        case .polar: return "Organization access token (polar_oat_…)"
        case .dodo: return "API key"
        case .gumroad: return "Access token"
        case .custom: return "Bearer token (optional)"
        }
    }

    /// Whether the provider reports a real MRR. Sources that don't still count
    /// towards revenue, and the UI says so instead of showing a silent zero.
    var reportsMRR: Bool { self != .gumroad }

    var docsURL: String {
        switch self {
        case .stripe: return "https://dashboard.stripe.com/apikeys"
        case .revenuecat: return "https://app.revenuecat.com/settings/api-keys"
        case .paddle: return "https://vendors.paddle.com/authentication-v2"
        case .lemonsqueezy: return "https://app.lemonsqueezy.com/settings/api"
        case .polar: return "https://polar.sh/dashboard"
        case .dodo: return "https://app.dodopayments.com/developer/api-keys"
        case .gumroad: return "https://app.gumroad.com/settings/advanced"
        case .custom: return "https://github.com/simonsruggi/MRRDock#custom-endpoint"
        }
    }
}

/// One configured account. The secret never lives here — it is stored in the
/// macOS Keychain under `keychainAccount` and only read when a request is about
/// to be made, so `sources.json` stays safe to sync, back up or paste in a bug
/// report.
struct Source: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: ProviderKind
    var name: String
    var enabled: Bool = true
    /// Provider-specific settings (project id, sandbox flag, custom URL…).
    /// A dictionary rather than one struct per provider: these are all short
    /// strings typed by the user, and a new provider must not force a migration
    /// of everyone else's saved file.
    var options: [String: String] = [:]

    var keychainAccount: String { "source.\(id.uuidString)" }

    func option(_ key: String) -> String? {
        guard let v = options[key], !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return v
    }

    func flag(_ key: String) -> Bool { options[key] == "true" }
}

/// What a provider gives back for one account.
struct ProviderSnapshot: Equatable, Codable {
    var mrr = MoneyBag()
    var revenue28d = MoneyBag()
    var activeSubscriptions: Int?
    var activeTrials: Int?
    /// Subscriptions the provider returned but that could not be priced (usage
    /// based, tiered, metered). Surfaced in the UI so an under-reported MRR is
    /// visible instead of mysterious.
    var unpricedSubscriptions: Int = 0
    var fetchedAt: Date = Date()
}

/// Live state of one source in the app.
struct SourceState: Equatable {
    var snapshot: ProviderSnapshot?
    var error: String?
    var isLoading: Bool = false
}

/// An MRR reading, in the user's display currency. Readings from the last two
/// days are kept as they come (one per refresh) so the 24-hour chart has a
/// shape; older ones collapse to one per day — this is a trend line, not an
/// audit log.
struct MRRPoint: Codable, Equatable, Identifiable {
    var date: Date
    var mrr: Double
    var currency: String

    var id: Date { date }
}

/// The window the overview chart draws. `custom` reads its bounds from the
/// two dates the user picked, so it carries none of its own.
enum ChartRange: String, CaseIterable, Identifiable, Codable {
    case day, week, year, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "24H"
        case .week: return "7D"
        case .year: return "1Y"
        case .custom: return "Custom"
        }
    }

    /// How far back the window reaches. Nil for `custom`, which is bounded by
    /// explicit dates instead.
    var duration: TimeInterval? {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .year: return 365 * 86_400
        case .custom: return nil
        }
    }
}

enum MRRHistory {
    /// Records a reading and compacts the series.
    static func upsert(_ points: [MRRPoint], value: Double, currency: String, now: Date = Date(),
                       calendar: Calendar = .current, keepDays: Int = 730,
                       intradayHours: Int = 48) -> [MRRPoint] {
        var out = points
        out.append(MRRPoint(date: now, mrr: value, currency: currency))
        return compact(out, now: now, calendar: calendar, keepDays: keepDays, intradayHours: intradayHours)
    }

    /// Keeps every reading from the last `intradayHours` and one per day before
    /// that. Refreshing every 15 minutes for two years would otherwise pile up
    /// 70.000 points to draw a line 730 pixels wide.
    static func compact(_ points: [MRRPoint], now: Date = Date(), calendar: Calendar = .current,
                        keepDays: Int = 730, intradayHours: Int = 48) -> [MRRPoint] {
        let intradayCutoff = now.addingTimeInterval(-Double(intradayHours) * 3600)
        var lastOfDay: [Date: MRRPoint] = [:]
        var recent: [MRRPoint] = []
        for point in points.sorted(by: { $0.date < $1.date }) {
            if point.date >= intradayCutoff {
                recent.append(point)
            } else {
                lastOfDay[calendar.startOfDay(for: point.date)] = point
            }
        }
        var out = Array(lastOfDay.values) + recent
        out.sort { $0.date < $1.date }
        if let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: now) {
            out = out.filter { $0.date >= cutoff }
        }
        return out
    }

    /// The readings the chart should draw for a range. A custom range with no
    /// dates yet, or one picked backwards, returns nothing rather than
    /// silently drawing the whole history.
    static func points(_ points: [MRRPoint], in range: ChartRange, from: Date? = nil, to: Date? = nil,
                       now: Date = Date(), calendar: Calendar = .current) -> [MRRPoint] {
        if range == .custom {
            guard let from, let to else { return [] }
            let start = calendar.startOfDay(for: min(from, to))
            let end = calendar.startOfDay(for: max(from, to)).addingTimeInterval(86_400)
            return points.filter { $0.date >= start && $0.date < end }
        }
        guard let duration = range.duration else { return points }
        let start = now.addingTimeInterval(-duration)
        return points.filter { $0.date >= start }
    }

    /// Sums per-source daily history into one series in the display currency.
    ///
    /// A day is only reported when **every** source has a value for it: sources
    /// start at different dates, and summing whoever happens to be present
    /// would draw a business that grew in steps it never took.
    static func dailyTotals(_ perSource: [UUID: [DailyMRR]], currency: String,
                            calendar: Calendar = .current,
                            rate: (String, String) -> Double?) -> [Date: Double] {
        guard !perSource.isEmpty else { return [:] }
        var byDay: [Date: [UUID: Double]] = [:]
        for (id, points) in perSource {
            for point in points {
                guard let converted = convert(point.money, to: currency, rate: rate) else { continue }
                let day = calendar.startOfDay(for: point.date)
                // The provider may report a day more than once (resolution
                // changes, time zones): the last value for that day wins.
                byDay[day, default: [:]][id] = converted
            }
        }
        return byDay.compactMapValues { values in
            values.count == perSource.count ? values.values.reduce(0, +) : nil
        }
    }

    private static func convert(_ money: Money, to currency: String, rate: (String, String) -> Double?) -> Double? {
        if money.currency == currency { return money.amount }
        guard let factor = rate(money.currency, currency) else { return nil }
        return money.amount * factor
    }

    /// Puts the provider-reported days in place of the app's own past readings,
    /// keeping today's — that one was measured at a known instant, and the
    /// provider's figure for today is still moving.
    static func backfilled(_ points: [MRRPoint], with totals: [Date: Double], currency: String,
                           now: Date = Date(), calendar: Calendar = .current) -> [MRRPoint] {
        let today = calendar.startOfDay(for: now)
        let ownRecent = points.filter { $0.date >= today }
        var historical = totals
            .filter { $0.key < today }
            .map { MRRPoint(date: $0.key, mrr: $0.value, currency: currency) }
            .sorted { $0.date < $1.date }
        // Providers answer for the whole window asked, so a project that
        // launched in April comes back with months of zeros in front of it.
        // Those are not a flat business, they are an absent one.
        if let start = historical.firstIndex(where: { $0.mrr > 0 }) {
            historical.removeSubrange(historical.startIndex..<start)
        } else {
            historical = []
        }
        return (historical + ownRecent).sorted { $0.date < $1.date }
    }

    /// Backfilling is worth one round of API calls a day.
    static func backfillDue(lastRun: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let lastRun else { return true }
        return !calendar.isDate(lastRun, inSameDayAs: now)
    }

    /// The reading closest to `days` ago, used for the "vs 30 days" delta.    /// The reading closest to `days` ago, used for the "vs 30 days" delta.
    /// Returns nil when history doesn't reach back that far — showing a delta
    /// against the oldest point available would invent growth on day two.
    static func value(_ points: [MRRPoint], daysAgo days: Int, now: Date = Date(),
                      calendar: Calendar = .current, tolerance: Int = 3) -> Double? {
        guard let target = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }
        let toleranceInterval = Double(tolerance) * 86400
        let candidates = points.filter { abs($0.date.timeIntervalSince(target)) <= toleranceInterval }
        return candidates.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }?.mrr
    }
}
