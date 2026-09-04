import Foundation

/// Gumroad.
///
/// Gumroad exposes sales, not a subscription ledger you can price, so this
/// source contributes **revenue over the last 28 days** and no MRR. Reporting a
/// made-up MRR from one-off sales is precisely the number this app exists to
/// get right.
struct GumroadProvider: RevenueProvider {
    let kind: ProviderKind = .gumroad

    func fetch(source: Source, secret: String, http: HTTPClient) async throws -> ProviderSnapshot {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let after = formatter.string(from: Date().addingTimeInterval(-28 * 86400))

        var bag = MoneyBag()
        var url: String? = "https://api.gumroad.com/v2/sales"
        var query: [URLQueryItem]? = [
            URLQueryItem(name: "access_token", value: secret),
            URLQueryItem(name: "after", value: after),
        ]

        for _ in 0..<http.maxPages {
            guard let current = url else { break }
            let json = try await http.getObject(current, query: query ?? [])
            for sale in json.arr("sales") ?? [] {
                let currency = sale.str("currency")?.uppercased() ?? "USD"
                // `price` is in the seller's currency, minor units; refunded and
                // disputed sales stay in the list and must not be counted.
                if sale["refunded"] as? Bool == true || sale["disputed"] as? Bool == true { continue }
                guard let price = sale.firstNum(["price"]) else { continue }
                bag.add(Money.minorUnits(price, currency))
            }
            guard let next = json.str("next_page_url") else { break }
            url = next.hasPrefix("http") ? next : "https://api.gumroad.com\(next)"
            query = [URLQueryItem(name: "access_token", value: secret)]
        }

        var snapshot = ProviderSnapshot()
        snapshot.revenue28d = bag
        return snapshot
    }
}
