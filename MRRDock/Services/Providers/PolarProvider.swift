import Foundation

/// Polar, via its metrics endpoint.
///
/// Polar computes MRR itself; the app asks for a single monthly interval ending
/// today and reads the last period, which is what Polar's own dashboard shows.
struct PolarProvider: RevenueProvider {
    let kind: ProviderKind = .polar

    func fetch(source: Source, secret: String, http: HTTPClient) async throws -> ProviderSnapshot {
        let base = source.flag("sandbox") ? "https://sandbox-api.polar.sh" : "https://api.polar.sh"
        let currency = source.option("currency") ?? "USD"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        let today = Date()
        var query = [
            URLQueryItem(name: "start_date", value: formatter.string(from: today.addingTimeInterval(-31 * 86400))),
            URLQueryItem(name: "end_date", value: formatter.string(from: today)),
            URLQueryItem(name: "interval", value: "day"),
        ]
        if let org = source.option("organizationId") {
            query.append(URLQueryItem(name: "organization_id", value: org))
        }

        let json = try await http.getObject("\(base)/v1/metrics",
                                            headers: ["Authorization": "Bearer \(secret)", "Accept": "application/json"],
                                            query: query)
        guard let periods = json.arr("periods"), let last = periods.last else {
            throw ProviderError.decoding("no metric periods returned")
        }
        guard let rawMRR = last.firstNum(["monthly_recurring_revenue", "mrr"]) else {
            throw ProviderError.decoding("no MRR field in the metrics response")
        }

        // Polar returns money in minor units. Guarding on the currency exponent
        // rather than hard-coding /100 keeps zero-decimal currencies honest.
        var snapshot = ProviderSnapshot()
        snapshot.mrr = MoneyBag(Money.minorUnits(rawMRR, currency))
        let revenue = periods.suffix(28).compactMap { $0.firstNum(["revenue"]) }.reduce(0, +)
        if revenue > 0 { snapshot.revenue28d = MoneyBag(Money.minorUnits(revenue, currency)) }
        snapshot.activeSubscriptions = last.firstNum(["active_subscriptions"]).map { Int($0) }
        return snapshot
    }
}
