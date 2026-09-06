import Foundation

/// RevenueCat, via the v2 project overview metrics.
///
/// RevenueCat already computes MRR the way its dashboard shows it, so the app
/// reads that number instead of re-deriving one from the subscriber list: the
/// two would disagree on trials, grace periods and proceeds, and the dashboard
/// is what the user compares against.
struct RevenueCatProvider: RevenueProvider {
    let kind: ProviderKind = .revenuecat

    func fetch(source: Source, secret: String, http: HTTPClient) async throws -> ProviderSnapshot {
        guard let projectID = source.option("projectId") else { throw ProviderError.missingOption("Project ID") }
        let json = try await http.getObject(
            "https://api.revenuecat.com/v2/projects/\(projectID)/metrics/overview",
            headers: ["Authorization": "Bearer \(secret)", "Accept": "application/json"])

        // The overview response carries the project's own currency; the setting
        // is only a fallback for accounts whose response predates that field.
        let currency = json.str("currency") ?? source.option("currency") ?? "USD"
        let values = Self.metrics(from: json)
        var snapshot = ProviderSnapshot()
        if let mrr = values["mrr"] { snapshot.mrr = MoneyBag(Money(mrr, currency)) }
        if let revenue = values["revenue"] { snapshot.revenue28d = MoneyBag(Money(revenue, currency)) }
        snapshot.activeSubscriptions = values["active_subscriptions"].map { Int($0) }
        snapshot.activeTrials = values["active_trials"].map { Int($0) }
        guard !snapshot.mrr.isEmpty || snapshot.activeSubscriptions != nil else {
            throw ProviderError.decoding("no metrics in the overview response")
        }
        return snapshot
    }

    /// Daily MRR from the project's own MRR chart — the same series the
    /// RevenueCat dashboard draws, so the app inherits the whole history
    /// instead of starting from the day the source was added.
    func history(source: Source, secret: String, http: HTTPClient, days: Int) async throws -> [DailyMRR] {
        guard let projectID = source.option("projectId") else { throw ProviderError.missingOption("Project ID") }
        let json = try await http.getObject(
            "https://api.revenuecat.com/v2/projects/\(projectID)/charts/mrr",
            headers: ["Authorization": "Bearer \(secret)", "Accept": "application/json"],
            query: [URLQueryItem(name: "resolution", value: "day"),
                    URLQueryItem(name: "start_date", value: Self.day(daysAgo: days)),
                    URLQueryItem(name: "end_date", value: Self.day(daysAgo: 0))])

        let currency = json.str("yaxis_currency") ?? "USD"
        return (json.arr("values") ?? []).compactMap { point in
            // The last cohort is flagged incomplete: it is today's partial
            // figure, and plotting it as a day would draw a daily crash.
            guard (point["incomplete"] as? Bool) != true,
                  let cohort = point.num("cohort"), let value = point.num("value") else { return nil }
            return DailyMRR(date: Date(timeIntervalSince1970: cohort), money: Money(value, currency))
        }
    }

    private static func day(daysAgo: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date().addingTimeInterval(-Double(daysAgo) * 86_400))
    }

    /// Reads both response shapes RevenueCat has shipped: a flat object of
    /// metric names, and the `{"metrics": [{"id": …, "value": …}]}` envelope.
    /// Supporting both costs ten lines and means a response format change does
    /// not take the app down until a release ships.
    static func metrics(from json: [String: Any]) -> [String: Double] {
        var out: [String: Double] = [:]
        func store(_ id: String, _ value: Double) {
            switch id.lowercased() {
            case "mrr", "monthly_recurring_revenue": out["mrr"] = value
            case "revenue", "revenue_last_28_days", "revenue_28d": out["revenue"] = value
            case "active_subscriptions", "active_subscriptions_count": out["active_subscriptions"] = value
            case "active_trials", "active_trials_count": out["active_trials"] = value
            default: break
            }
        }
        for metric in json.arr("metrics") ?? [] {
            guard let id = metric.str("id") ?? metric.str("name"), let value = metric.num("value") else { continue }
            store(id, value)
        }
        for (key, value) in json {
            if let number = value as? NSNumber { store(key, number.doubleValue) }
        }
        return out
    }
}
