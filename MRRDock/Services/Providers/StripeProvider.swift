import Foundation

/// Stripe Billing.
///
/// MRR is computed from the live subscription list rather than from any Stripe
/// dashboard number: the dashboard's MRR is only available in Sigma/Revenue
/// Recognition, and reconstructing it here keeps the app working with a plain
/// read-only restricted key.
struct StripeProvider: RevenueProvider {
    let kind: ProviderKind = .stripe
    private let base = "https://api.stripe.com/v1"

    func fetch(source: Source, secret: String, http: HTTPClient) async throws -> ProviderSnapshot {
        var headers = ["Authorization": "Bearer \(secret)"]
        // Platform accounts read a connected account's data with this header;
        // without it a platform key reports the platform's own (usually empty) MRR.
        if let account = source.option("stripeAccount") { headers["Stripe-Account"] = account }

        var snapshot = ProviderSnapshot()
        let active = try await subscriptions(status: "active", headers: headers, http: http)
        snapshot.mrr = active.mrr
        snapshot.activeSubscriptions = active.count
        snapshot.unpricedSubscriptions = active.unpriced

        // Trials are counted but priced at zero: a free trial is not revenue yet.
        if source.options["countTrials"] != "false" {
            let trialing = try await subscriptions(status: "trialing", headers: headers, http: http)
            snapshot.activeTrials = trialing.count
        }
        if source.flag("includeRevenue") {
            snapshot.revenue28d = try await revenue(days: 28, headers: headers, http: http)
        }
        return snapshot
    }

    private func subscriptions(status: String, headers: [String: String], http: HTTPClient)
        async throws -> (mrr: MoneyBag, count: Int, unpriced: Int) {
        var bag = MoneyBag()
        var count = 0
        var unpriced = 0
        var startingAfter: String?

        for _ in 0..<http.maxPages {
            var query = [
                URLQueryItem(name: "status", value: status),
                URLQueryItem(name: "limit", value: "100"),
            ]
            if let cursor = startingAfter { query.append(URLQueryItem(name: "starting_after", value: cursor)) }
            let page = try await http.getObject("\(base)/subscriptions", headers: headers, query: query)
            let items = page.arr("data") ?? []
            count += items.count

            for sub in items {
                let discount = discountPercent(sub)
                var priced = false
                for item in sub.obj("items")?.arr("data") ?? [] {
                    guard let price = item.obj("price"),
                          let recurring = price.obj("recurring"),
                          let intervalRaw = recurring.str("interval"),
                          let interval = BillingInterval(provider: intervalRaw) else { continue }
                    // Tiered / metered prices have no unit_amount: their revenue
                    // depends on usage Stripe hasn't billed yet, so they are
                    // counted as unpriced instead of guessed at.
                    guard let unitAmount = price.num("unit_amount") else { continue }
                    let currency = price.str("currency") ?? "usd"
                    let money = Money.minorUnits(unitAmount, currency)
                    let monthly = MRRMath.monthly(unitAmount: money.amount,
                                                  interval: interval,
                                                  intervalCount: recurring.int("interval_count") ?? 1,
                                                  quantity: item.int("quantity") ?? 1,
                                                  discountPercent: discount)
                    bag.add(Money(monthly, currency))
                    priced = true
                }
                if !priced { unpriced += 1 }
            }

            guard page["has_more"] as? Bool == true, let last = items.last?.str("id") else { break }
            startingAfter = last
        }
        return (bag, count, unpriced)
    }

    /// Percentage discounts are applied; fixed-amount coupons are not, because a
    /// €5-off coupon on a €5 plan would need per-line proration Stripe does not
    /// expose on the subscription object.
    ///
    /// Discounts are read from whatever the account's API version already
    /// returns — the legacy `discount` object, or `discounts` when it comes back
    /// expanded. They are deliberately *not* requested with `expand[]`: an
    /// expand path the account's API version doesn't know is a 400, and losing
    /// the whole MRR over a coupon nobody has is a bad trade.
    private func discountPercent(_ sub: [String: Any]) -> Double {
        var discounts = sub.arr("discounts") ?? []
        if let single = sub.obj("discount") { discounts.append(single) }
        for discount in discounts {
            if let percent = discount.obj("coupon")?.num("percent_off") { return percent }
        }
        return 0
    }

    private func revenue(days: Int, headers: [String: String], http: HTTPClient) async throws -> MoneyBag {
        var bag = MoneyBag()
        let since = Int(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
        var startingAfter: String?

        for _ in 0..<http.maxPages {
            var query = [
                URLQueryItem(name: "created[gte]", value: String(since)),
                URLQueryItem(name: "limit", value: "100"),
            ]
            if let cursor = startingAfter { query.append(URLQueryItem(name: "starting_after", value: cursor)) }
            let page = try await http.getObject("\(base)/charges", headers: headers, query: query)
            let items = page.arr("data") ?? []
            for charge in items where (charge["paid"] as? Bool) == true {
                let currency = charge.str("currency") ?? "usd"
                let net = (charge.num("amount") ?? 0) - (charge.num("amount_refunded") ?? 0)
                bag.add(Money.minorUnits(net, currency))
            }
            guard page["has_more"] as? Bool == true, let last = items.last?.str("id") else { break }
            startingAfter = last
        }
        return bag
    }
}
