import Foundation

/// Any HTTPS endpoint that returns JSON with an MRR in it.
///
/// This is the escape hatch for platforms with no public revenue API —
/// Superwall, App Store Connect, an internal billing table — and for anyone who
/// would rather not hand their Stripe key to a desktop app: point MRRDock at a
/// small worker of your own that returns
/// `{"mrr": 1234.5, "currency": "EUR", "active_subscriptions": 42}`.
struct CustomProvider: RevenueProvider {
    let kind: ProviderKind = .custom

    func fetch(source: Source, secret: String, http: HTTPClient) async throws -> ProviderSnapshot {
        guard let urlString = source.option("url") else { throw ProviderError.missingOption("URL") }
        var headers = ["Accept": "application/json"]
        if !secret.isEmpty {
            let scheme = source.option("authScheme") ?? "Bearer"
            let header = source.option("authHeader") ?? "Authorization"
            headers[header] = scheme.isEmpty ? secret : "\(scheme) \(secret)"
        }
        let json = try await http.getObject(urlString, headers: headers)
        return try Self.parse(json, currencyFallback: source.option("currency") ?? "USD",
                              mrrKey: source.option("mrrKey"))
    }

    /// Pure so the accepted shapes are pinned by tests: a flat object, or one
    /// wrapped in `data`/`result`, with the usual spellings of "mrr".
    static func parse(_ json: [String: Any], currencyFallback: String, mrrKey: String? = nil) throws -> ProviderSnapshot {
        let root = json.obj("data") ?? json.obj("result") ?? json
        let currency = root.str("currency") ?? currencyFallback
        var keys = ["mrr", "monthly_recurring_revenue", "monthlyRecurringRevenue", "value"]
        if let mrrKey { keys.insert(mrrKey, at: 0) }
        guard let mrr = root.firstNum(keys) else {
            throw ProviderError.decoding("no \"mrr\" field in the response")
        }
        var snapshot = ProviderSnapshot()
        snapshot.mrr = MoneyBag(Money(mrr, currency))
        if let revenue = root.firstNum(["revenue_28d", "revenue", "revenue_last_28_days"]) {
            snapshot.revenue28d = MoneyBag(Money(revenue, currency))
        }
        snapshot.activeSubscriptions = root.firstNum(["active_subscriptions", "subscribers", "subscriptions"]).map { Int($0) }
        snapshot.activeTrials = root.firstNum(["active_trials", "trials"]).map { Int($0) }
        return snapshot
    }
}
