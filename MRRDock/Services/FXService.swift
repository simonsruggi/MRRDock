import Foundation

/// Exchange rates from Yahoo Finance's public quote endpoint — no key, no
/// account, same source StockDock uses. Rates are cached for 12 hours: MRR
/// moves slowly and a menu-bar refresh every 15 minutes must not hammer a free
/// endpoint (nor let a rate outage blank the total).
@MainActor
final class FXService: ObservableObject {
    static let shared = FXService()

    private struct Entry { var rate: Double; var fetchedAt: Date }
    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 12 * 3600
    private let cacheURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MRRDock/fx.json")
    }()

    private init() { loadCache() }

    func cachedRate(from: String, to: String) -> Double? {
        let f = from.uppercased(), t = to.uppercased()
        if f == t { return 1 }
        return cache["\(f)\(t)"]?.rate
    }

    /// Makes sure every currency in `currencies` can be converted into `target`,
    /// fetching what is missing or stale. Failures are swallowed: a missing rate
    /// leaves that currency unconverted and the UI marks the total partial.
    func ensureRates(for currencies: Set<String>, target: String) async {
        let target = target.uppercased()
        for currency in currencies.map({ $0.uppercased() }) where currency != target {
            let key = "\(currency)\(target)"
            if let entry = cache[key], Date().timeIntervalSince(entry.fetchedAt) < ttl { continue }
            if let rate = await fetchRate(from: currency, to: target) {
                cache[key] = Entry(rate: rate, fetchedAt: Date())
            }
        }
        saveCache()
    }

    private func fetchRate(from: String, to: String) async -> Double? {
        let symbol = "\(from)\(to)=X"
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=1d"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = (json?["chart"] as? [String: Any])?["result"] as? [[String: Any]]
            let meta = result?.first?["meta"] as? [String: Any]
            return (meta?["regularMarketPrice"] as? NSNumber)?.doubleValue
        } catch {
            NSLog("[MRRDock] FX %@→%@ failed: %@", from, to, error.localizedDescription)
            return nil
        }
    }

    private struct StoredEntry: Codable { var rate: Double; var fetchedAt: Date }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let stored = try? JSONDecoder().decode([String: StoredEntry].self, from: data) else { return }
        cache = stored.mapValues { Entry(rate: $0.rate, fetchedAt: $0.fetchedAt) }
    }

    private func saveCache() {
        let stored = cache.mapValues { StoredEntry(rate: $0.rate, fetchedAt: $0.fetchedAt) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}
