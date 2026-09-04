import Foundation
import Combine

/// Fetches every source, converts, aggregates, and records the daily history
/// point. The single place the rest of the app reads numbers from.
@MainActor
final class MetricsService: ObservableObject {
    static let shared = MetricsService()

    @Published private(set) var states: [UUID: SourceState] = [:]
    @Published private(set) var aggregate = Aggregate()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private let storage = StorageService.shared
    private let fx = FXService.shared
    private let http = HTTPClient()
    private var refreshTask: Task<Void, Never>?

    private init() {}

    func state(for source: Source) -> SourceState { states[source.id] ?? SourceState() }

    /// Refreshes every enabled source concurrently. A slow or broken provider
    /// only fails its own row: one dead API key must not blank the total.
    func refresh(force: Bool = false) {
        guard !isRefreshing || force else { return }
        refreshTask?.cancel()
        refreshTask = Task { await performRefresh() }
    }

    func refreshAndWait() async { await performRefresh() }

    private func performRefresh() async {
        let sources = storage.sources.filter(\.enabled)
        guard !sources.isEmpty else {
            states = [:]
            aggregate = Aggregate(currency: storage.displayCurrency)
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        for source in sources {
            states[source.id, default: SourceState()].isLoading = true
        }

        let http = self.http
        var results: [UUID: Result<ProviderSnapshot, Error>] = [:]
        await withTaskGroup(of: (UUID, Result<ProviderSnapshot, Error>).self) { group in
            for source in sources {
                let secret = storage.secret(for: source) ?? ""
                group.addTask {
                    let provider = ProviderRegistry.provider(for: source.kind)
                    do {
                        if secret.isEmpty, source.kind != .custom {
                            throw ProviderError.missingSecret
                        }
                        return (source.id, .success(try await provider.fetch(source: source, secret: secret, http: http)))
                    } catch {
                        return (source.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group { results[id] = result }
        }

        for source in sources {
            switch results[source.id] {
            case .success(let snapshot):
                states[source.id] = SourceState(snapshot: snapshot, error: nil, isLoading: false)
            case .failure(let error):
                // The previous snapshot is kept on purpose: a transient 502 should
                // leave yesterday's MRR on screen with an error badge, not a zero.
                var state = state(for: source)
                state.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                state.isLoading = false
                states[source.id] = state
            case .none:
                states[source.id]?.isLoading = false
            }
        }
        // Drop states for sources deleted while the refresh was in flight.
        let liveIDs = Set(storage.sources.map(\.id))
        states = states.filter { liveIDs.contains($0.key) }

        await convertAndAggregate()
        lastRefresh = Date()
        recordHistory()
        await notifyIfNeeded()
    }

    private func convertAndAggregate() async {
        let currencies = Set(states.values.flatMap { state -> [String] in
            guard let snapshot = state.snapshot else { return [] }
            return Array(snapshot.mrr.byCurrency.keys) + Array(snapshot.revenue28d.byCurrency.keys)
        })
        await fx.ensureRates(for: currencies, target: storage.displayCurrency)
        let pairs = storage.sources.map { (source: $0, state: state(for: $0)) }
        aggregate = Aggregate.build(states: pairs, currency: storage.displayCurrency) { [fx] from, to in
            fx.cachedRate(from: from, to: to)
        }
    }

    /// Re-aggregates without hitting any API — used when the display currency
    /// changes, so switching EUR→USD is instant instead of a full refresh.
    func recompute() {
        Task { await convertAndAggregate() }
    }

    private func recordHistory() {
        guard aggregate.sourcesReporting > 0 else { return }
        storage.history = MRRHistory.upsert(storage.history,
                                            value: aggregate.mrr,
                                            currency: storage.displayCurrency)
    }

    private func notifyIfNeeded() async {
        let notifier = WebhookNotifier(urlString: storage.webhookURL)
        guard notifier != nil, aggregate.sourcesReporting > 0 else { return }

        if storage.notifyMilestones,
           let milestone = MilestoneEvaluator.crossed(mrr: aggregate.mrr,
                                                      step: storage.milestoneStep,
                                                      lastMilestone: storage.lastMilestone) {
            storage.lastMilestone = milestone
            await notifier?.send(title: "🎉 New MRR milestone",
                                 body: "MRR just crossed \(Format.money(milestone, currency: aggregate.currency)) — now at \(Format.money(aggregate.mrr, currency: aggregate.currency, decimals: storage.decimals)).",
                                 positive: true)
        }

        if storage.notifyDailySummary,
           MilestoneEvaluator.summaryDue(now: Date(), lastSummaryDay: storage.lastSummaryDay) {
            storage.lastSummaryDay = MilestoneEvaluator.dayKey(Date())
            var body = "MRR \(Format.money(aggregate.mrr, currency: aggregate.currency, decimals: storage.decimals)) · ARR \(Format.money(aggregate.arr, currency: aggregate.currency))"
            if let previous = MRRHistory.value(storage.history, daysAgo: 30),
               let growth = MRRMath.growthPercent(from: previous, to: aggregate.mrr) {
                body += " · \(Format.percent(growth)) vs 30 days ago"
            }
            body += "\n\(aggregate.activeSubscriptions) active subscriptions · \(aggregate.activeTrials) trials"
            await notifier?.send(title: "📊 Daily MRR summary", body: body, positive: aggregate.mrr > 0)
        }
    }

    /// One-off test of a source's credentials, without touching app state.
    func test(source: Source, secret: String) async -> Result<ProviderSnapshot, Error> {
        let provider = ProviderRegistry.provider(for: source.kind)
        do { return .success(try await provider.fetch(source: source, secret: secret, http: http)) }
        catch { return .failure(error) }
    }
}
