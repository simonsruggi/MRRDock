import Foundation

/// Lemon Squeezy.
///
/// The subscription object carries no price, only a `price_id`, so prices are
/// fetched once each and cached per refresh: an account with 500 subscribers on
/// three plans makes three price calls, not 500.
struct LemonSqueezyProvider: RevenueProvider {
    let kind: ProviderKind = .lemonsqueezy
    private let base = "https://api.lemonsqueezy.com/v1"

    func fetch(source: Source, secret: String, http: HTTPClient) async throws -> ProviderSnapshot {
        let headers = [
            "Authorization": "Bearer \(secret)",
            "Accept": "application/vnd.api+json",
            "Content-Type": "application/vnd.api+json",
        ]
        var bag = MoneyBag()
        var count = 0
        var trials = 0
        var unpriced = 0
        var priceCache: [String: (amount: Double, interval: BillingInterval, count: Int)] = [:]
        var storeCurrency: [String: String] = [:]
        var page = 1

        for _ in 0..<http.maxPages {
            var query = [
                URLQueryItem(name: "page[size]", value: "100"),
                URLQueryItem(name: "page[number]", value: String(page)),
            ]
            if let storeID = source.option("storeId") {
                query.append(URLQueryItem(name: "filter[store_id]", value: storeID))
            }
            let json = try await http.getObject("\(base)/subscriptions", headers: headers, query: query)
            let rows = json.arr("data") ?? []

            for row in rows {
                guard let attrs = row.obj("attributes") else { continue }
                let status = attrs.str("status") ?? ""
                guard ["active", "on_trial", "past_due"].contains(status) else { continue }
                if status == "on_trial" { trials += 1; continue }
                count += 1

                guard let item = attrs.obj("first_subscription_item"), let priceID = item.num("price_id").map({ String(Int($0)) }) else {
                    unpriced += 1
                    continue
                }
                if priceCache[priceID] == nil {
                    priceCache[priceID] = try await self.price(id: priceID, headers: headers, http: http)
                }
                guard let price = priceCache[priceID] else { unpriced += 1; continue }

                let storeID = attrs.num("store_id").map { String(Int($0)) } ?? ""
                if storeCurrency[storeID] == nil {
                    storeCurrency[storeID] = (try? await self.storeCurrency(id: storeID, headers: headers, http: http)) ?? "USD"
                }
                let currency = storeCurrency[storeID] ?? "USD"
                let money = Money.minorUnits(price.amount, currency)
                let monthly = MRRMath.monthly(unitAmount: money.amount,
                                              interval: price.interval,
                                              intervalCount: price.count,
                                              quantity: item.int("quantity") ?? 1)
                bag.add(Money(monthly, currency))
            }

            let lastPage = json.obj("meta")?.obj("page")?.int("lastPage") ?? page
            guard page < lastPage else { break }
            page += 1
        }

        var snapshot = ProviderSnapshot()
        snapshot.mrr = bag
        snapshot.activeSubscriptions = count
        snapshot.activeTrials = trials
        snapshot.unpricedSubscriptions = unpriced
        return snapshot
    }

    private func price(id: String, headers: [String: String], http: HTTPClient)
        async throws -> (amount: Double, interval: BillingInterval, count: Int)? {
        let json = try await http.getObject("\(base)/prices/\(id)", headers: headers)
        guard let attrs = json.obj("data")?.obj("attributes"),
              let amount = attrs.firstNum(["unit_price", "unit_price_decimal"]),
              let unit = attrs.str("renewal_interval_unit"),
              let interval = BillingInterval(provider: unit) else { return nil }
        return (amount, interval, attrs.int("renewal_interval_quantity") ?? 1)
    }

    private func storeCurrency(id: String, headers: [String: String], http: HTTPClient) async throws -> String {
        let json = try await http.getObject("\(base)/stores/\(id)", headers: headers)
        return json.obj("data")?.obj("attributes")?.str("currency") ?? "USD"
    }
}
