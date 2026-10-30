import Foundation

/// Tools MRRDock exposes over MCP. They read the sources configured in the app and ask the
/// providers for fresh numbers, but never save: history, milestones and webhooks stay the
/// menu bar app's job, so running both at once can't record a point twice or notify twice.
enum MRRDockTools {
    static func server() -> MCPServer {
        MCPServer(
            name: "mrrdock",
            instructions: "MRR, ARR, revenue and subscriptions from the revenue platforms connected in MRRDock (Stripe, RevenueCat, Paddle, Lemon Squeezy, Polar, Dodo Payments, Gumroad). Amounts are in the app's display currency. Read-only.",
            tools: [mrr, history]
        )
    }

    private static let mrr = MCPTool(
        name: "get_mrr",
        description: "Current MRR, ARR, revenue of the last 28 days, active subscriptions and trials, in total and per connected platform, fetched live from the providers. Includes the change against 30 days ago when the history reaches that far.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        handler: { _ in try MCPServer.wait { try await liveMRR() } }
    )

    private static let history = MCPTool(
        name: "get_mrr_history",
        description: "Daily total MRR recorded by MRRDock, oldest first: one value per day, the last reading of that day.",
        inputSchema: [
            "type": "object",
            "properties": ["days": ["type": "integer", "minimum": 1, "maximum": 730, "default": 90]],
        ],
        handler: { args in
            let days = args.int("days", default: 90, range: 1...730)
            return try MCPServer.wait { dailyHistory(days: days) }
        }
    )

    @MainActor
    private static func liveMRR() async throws -> [String: Any] {
        let storage = StorageService.shared
        let duplicates = Source.duplicateIDs(in: storage.sources)
        let sources = storage.sources.filter { $0.enabled && !duplicates.contains($0.id) }
        guard !sources.isEmpty else {
            throw MCPToolError("No platform is connected yet: add one in MRRDock's Settings.")
        }

        let http = HTTPClient()
        var states: [UUID: SourceState] = [:]
        await withTaskGroup(of: (UUID, SourceState).self) { group in
            for source in sources {
                let secret = storage.secret(for: source) ?? ""
                group.addTask {
                    if secret.isEmpty, source.kind != .custom {
                        return (source.id, SourceState(error: "Missing API key"))
                    }
                    do {
                        let snapshot = try await ProviderRegistry.provider(for: source.kind)
                            .fetch(source: source, secret: secret, http: http)
                        return (source.id, SourceState(snapshot: snapshot))
                    } catch {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        return (source.id, SourceState(error: message))
                    }
                }
            }
            for await (id, state) in group { states[id] = state }
        }

        let currency = storage.displayCurrency
        let fx = FXService.shared
        let currencies = Set(states.values.flatMap { state -> [String] in
            guard let s = state.snapshot else { return [] }
            return Array(s.mrr.byCurrency.keys) + Array(s.revenue28d.byCurrency.keys)
        })
        await fx.ensureRates(for: currencies, target: currency)
        let rate: (String, String) -> Double? = { fx.cachedRate(from: $0, to: $1) }
        let total = Aggregate.build(states: sources.map { ($0, states[$0.id] ?? SourceState()) },
                                    currency: currency, rate: rate)

        var result: [String: Any] = [
            "currency": total.currency,
            "mrr": money(total.mrr),
            "arr": money(total.arr),
            "revenue_last_28_days": money(total.revenue28d),
            "active_subscriptions": total.activeSubscriptions,
            "active_trials": total.activeTrials,
            "fetched_at": ISO8601DateFormatter().string(from: Date()),
            "sources": sources.map { source -> [String: Any] in
                let state = states[source.id] ?? SourceState()
                var row: [String: Any] = ["name": source.name, "platform": source.kind.displayName]
                if let s = state.snapshot {
                    row["mrr"] = source.kind.reportsMRR ? money(s.mrr.converted(to: currency, rate: rate).total) : NSNull()
                    row["revenue_last_28_days"] = money(s.revenue28d.converted(to: currency, rate: rate).total)
                    if let n = s.activeSubscriptions { row["active_subscriptions"] = n }
                    if let n = s.activeTrials { row["active_trials"] = n }
                    if s.unpricedSubscriptions > 0 { row["unpriced_subscriptions"] = s.unpricedSubscriptions }
                }
                if let error = state.error { row["error"] = error }
                return row
            },
        ]
        if let previous = MRRHistory.value(storage.history, daysAgo: 30) {
            result["mrr_30_days_ago"] = money(previous)
            if let growth = MRRMath.growthPercent(from: previous, to: total.mrr) {
                result["growth_30_days_percent"] = money(growth)
            }
        }
        if !total.unconverted.isEmpty {
            result["left_out_no_exchange_rate"] = total.unconverted.mapValues(money)
        }
        if total.unpricedSubscriptions > 0 {
            result["note"] = "\(total.unpricedSubscriptions) subscriptions could not be priced (usage-based or tiered) and are not in the MRR."
        }
        return result
    }

    @MainActor
    private static func dailyHistory(days: Int) -> [String: Any] {
        let storage = StorageService.shared
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var lastPerDay: [String: MRRPoint] = [:]
        for point in storage.history where point.date >= from {
            let day = formatter.string(from: point.date)
            if let current = lastPerDay[day], current.date > point.date { continue }
            lastPerDay[day] = point
        }
        return [
            "currency": storage.displayCurrency,
            "points": lastPerDay.keys.sorted().map { day -> [String: Any] in
                let p = lastPerDay[day]!
                return ["date": day, "mrr": money(p.mrr), "currency": p.currency]
            },
        ]
    }

    /// Two decimals, as Decimal so JSON doesn't print 1234.5600000000001.
    private static func money(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", value)) ?? 0
    }
}
