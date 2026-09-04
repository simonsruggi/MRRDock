import Foundation

/// Dodo Payments (merchant of record).
struct DodoProvider: RevenueProvider {
    let kind: ProviderKind = .dodo

    func fetch(source: Source, secret: String, http: HTTPClient) async throws -> ProviderSnapshot {
        let base = source.flag("sandbox") ? "https://test.dodopayments.com" : "https://live.dodopayments.com"
        let headers = ["Authorization": "Bearer \(secret)", "Accept": "application/json"]

        var bag = MoneyBag()
        var count = 0
        var unpriced = 0
        var pageNumber = 0

        for _ in 0..<http.maxPages {
            var query = [
                URLQueryItem(name: "status", value: "active"),
                URLQueryItem(name: "page_size", value: "100"),
                URLQueryItem(name: "page_number", value: String(pageNumber)),
            ]
            if let brand = source.option("brandId") { query.append(URLQueryItem(name: "brand_id", value: brand)) }
            let json = try await http.getObject("\(base)/subscriptions", headers: headers, query: query)
            let items = json.arr("items") ?? json.arr("data") ?? []
            count += items.count

            for sub in items {
                let currency = sub.str("currency") ?? "USD"
                guard let amount = sub.firstNum(["recurring_pre_tax_amount"]),
                      let intervalRaw = sub.str("payment_frequency_interval") ?? sub.str("subscription_period_interval"),
                      let interval = BillingInterval(provider: intervalRaw) else {
                    unpriced += 1
                    continue
                }
                let money = Money.minorUnits(amount, currency)
                let monthly = MRRMath.monthly(unitAmount: money.amount,
                                              interval: interval,
                                              intervalCount: sub.int("payment_frequency_count") ?? 1)
                bag.add(Money(monthly, currency))
            }

            guard items.count == 100 else { break }
            pageNumber += 1
        }

        var snapshot = ProviderSnapshot()
        snapshot.mrr = bag
        snapshot.activeSubscriptions = count
        snapshot.unpricedSubscriptions = unpriced
        return snapshot
    }
}
