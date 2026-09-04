import Foundation

/// Paddle Billing (the v2 API — Paddle Classic is not supported).
struct PaddleProvider: RevenueProvider {
    let kind: ProviderKind = .paddle

    func fetch(source: Source, secret: String, http: HTTPClient) async throws -> ProviderSnapshot {
        let base = source.flag("sandbox") ? "https://sandbox-api.paddle.com" : "https://api.paddle.com"
        let headers = ["Authorization": "Bearer \(secret)", "Accept": "application/json"]

        var snapshot = ProviderSnapshot()
        var bag = MoneyBag()
        var count = 0
        var unpriced = 0
        var trials = 0
        var after: String?

        for _ in 0..<http.maxPages {
            var query = [
                URLQueryItem(name: "status", value: "active,trialing"),
                URLQueryItem(name: "per_page", value: "100"),
            ]
            if let cursor = after { query.append(URLQueryItem(name: "after", value: cursor)) }
            let page = try await http.getObject("\(base)/subscriptions", headers: headers, query: query)
            let subs = page.arr("data") ?? []

            for sub in subs {
                if sub.str("status") == "trialing" {
                    // A trial bills nothing yet, so it is counted but contributes
                    // no MRR — otherwise every free trial inflates the number the
                    // menu bar shows.
                    trials += 1
                    continue
                }
                count += 1
                let currency = sub.str("currency_code") ?? "USD"
                var priced = false
                for item in sub.arr("items") ?? [] where item.str("status") != "trialing" {
                    guard let price = item.obj("price"),
                          let unitPrice = price.obj("unit_price"),
                          let amount = unitPrice.num("amount") else { continue }
                    let cycle = price.obj("billing_cycle") ?? sub.obj("billing_cycle")
                    guard let intervalRaw = cycle?.str("interval"),
                          let interval = BillingInterval(provider: intervalRaw) else { continue }
                    let money = Money.minorUnits(amount, unitPrice.str("currency_code") ?? currency)
                    let monthly = MRRMath.monthly(unitAmount: money.amount,
                                                  interval: interval,
                                                  intervalCount: cycle?.int("frequency") ?? 1,
                                                  quantity: item.int("quantity") ?? 1)
                    bag.add(Money(monthly, money.currency))
                    priced = true
                }
                if !priced { unpriced += 1 }
            }

            guard let next = page.obj("meta")?.obj("pagination"), next["has_more"] as? Bool == true,
                  let last = subs.last?.str("id") else { break }
            after = last
        }

        snapshot.mrr = bag
        snapshot.activeSubscriptions = count
        snapshot.activeTrials = trials
        snapshot.unpricedSubscriptions = unpriced
        return snapshot
    }
}
