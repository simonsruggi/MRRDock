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

/// A daily MRR reading, in the user's display currency. One point per day
/// (the last of the day wins) — this is a trend line, not an audit log.
struct MRRPoint: Codable, Equatable, Identifiable {
    var date: Date
    var mrr: Double
    var currency: String

    var id: Date { date }
}

enum MRRHistory {
    /// Inserts today's reading, replacing an earlier one from the same day.
    static func upsert(_ points: [MRRPoint], value: Double, currency: String, now: Date = Date(),
                       calendar: Calendar = .current, keepDays: Int = 730) -> [MRRPoint] {
        var out = points.filter { !calendar.isDate($0.date, inSameDayAs: now) }
        out.append(MRRPoint(date: now, mrr: value, currency: currency))
        out.sort { $0.date < $1.date }
        if let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: now) {
            out = out.filter { $0.date >= cutoff }
        }
        return out
    }

    /// The reading closest to `days` ago, used for the "vs 30 days" delta.
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
