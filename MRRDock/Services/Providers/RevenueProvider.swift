import Foundation

enum ProviderError: LocalizedError {
    case missingSecret
    case missingOption(String)
    case badURL
    case http(Int, String)
    case decoding(String)
    case insecureURL

    var errorDescription: String? {
        switch self {
        case .missingSecret: return "No API key saved for this source"
        case .missingOption(let name): return "Missing \(name)"
        case .badURL: return "Invalid URL"
        case .insecureURL: return "Only https:// endpoints are allowed"
        case .http(let code, let body):
            let detail = body.prefix(180).trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(detail)"
        case .decoding(let what): return "Unexpected response (\(what))"
        }
    }
}

/// Reads one account and returns its metrics. Implementations own every quirk of
/// their platform (pagination, minor units, interval spelling) and hand back
/// numbers already normalized to major units and `BillingInterval`.
protocol RevenueProvider: Sendable {
    var kind: ProviderKind { get }
    func fetch(source: Source, secret: String, http: HTTPClient) async throws -> ProviderSnapshot
}

enum ProviderRegistry {
    static func provider(for kind: ProviderKind) -> RevenueProvider {
        switch kind {
        case .stripe: return StripeProvider()
        case .revenuecat: return RevenueCatProvider()
        case .paddle: return PaddleProvider()
        case .lemonsqueezy: return LemonSqueezyProvider()
        case .polar: return PolarProvider()
        case .dodo: return DodoProvider()
        case .gumroad: return GumroadProvider()
        case .custom: return CustomProvider()
        }
    }
}

/// Thin JSON client shared by every provider.
///
/// https only, on purpose: these requests carry live API keys, and a provider
/// with a typo'd base URL must fail loudly rather than send a Stripe key over
/// plaintext.
struct HTTPClient: Sendable {
    var session: URLSession = .shared
    /// Pages fetched at most per listing call. Stops an account with 40k
    /// subscriptions from turning a menu-bar refresh into a five-minute crawl.
    var maxPages: Int = 25

    func getJSON(_ urlString: String,
                 headers: [String: String] = [:],
                 query: [URLQueryItem] = []) async throws -> Any {
        guard var comps = URLComponents(string: urlString) else { throw ProviderError.badURL }
        guard comps.scheme?.lowercased() == "https" else { throw ProviderError.insecureURL }
        if !query.isEmpty {
            comps.queryItems = (comps.queryItems ?? []) + query
        }
        guard let url = comps.url else { throw ProviderError.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("MRRDock/\(AppInfo.version) (+https://github.com/simonsruggi/MRRDock)",
                         forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ProviderError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    func getObject(_ urlString: String,
                   headers: [String: String] = [:],
                   query: [URLQueryItem] = []) async throws -> [String: Any] {
        guard let obj = try await getJSON(urlString, headers: headers, query: query) as? [String: Any] else {
            throw ProviderError.decoding("expected a JSON object")
        }
        return obj
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

/// JSON digging helpers. Provider responses are read as `[String: Any]` rather
/// than Codable structs: every one of these APIs adds fields continuously, and a
/// strict decoder turns an unrelated new field into a broken menu bar.
extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String? { self[key] as? String }
    func num(_ key: String) -> Double? {
        if let d = self[key] as? Double { return d }
        if let i = self[key] as? Int { return Double(i) }
        if let n = self[key] as? NSNumber { return n.doubleValue }
        if let s = self[key] as? String { return Double(s) }
        return nil
    }
    func int(_ key: String) -> Int? { num(key).map { Int($0) } }
    func obj(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func arr(_ key: String) -> [[String: Any]]? { self[key] as? [[String: Any]] }

    /// First non-nil number among several candidate keys — providers rename
    /// fields (`mrr`, `monthly_recurring_revenue`, `value`) and the docs lag.
    func firstNum(_ keys: [String]) -> Double? {
        for key in keys { if let v = num(key) { return v } }
        return nil
    }
}
