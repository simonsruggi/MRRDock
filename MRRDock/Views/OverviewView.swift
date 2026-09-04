import SwiftUI

struct OverviewView: View {
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var metrics = MetricsService.shared
    @State private var revealed = false

    private var aggregate: Aggregate { metrics.aggregate }
    private var hidden: Bool { storage.privacyMode && !revealed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if storage.sources.isEmpty {
                    emptyState
                } else {
                    hero
                    stats
                    sourceBreakdown
                    if aggregate.isPartial || aggregate.unpricedSubscriptions > 0 { warnings }
                }
            }
            .padding(14)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Monthly recurring revenue").sectionLabel()
                Spacer()
                if storage.privacyMode {
                    Button { revealed.toggle() } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundStyle(DS.inkTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(hidden ? "••••" : Format.money(aggregate.mrr, currency: aggregate.currency, decimals: storage.decimals))
                    .font(DS.display).foregroundStyle(DS.ink)
                    .contentTransition(.numericText())
                if let growth = growth30d, !hidden { TrendPill(value: growth) }
            }
            HStack(spacing: 6) {
                Text("ARR \(hidden ? "••••" : Format.money(aggregate.arr, currency: aggregate.currency))")
                    .font(DS.caption).foregroundStyle(DS.inkSecondary)
                if let last = metrics.lastRefresh {
                    Text("·").foregroundStyle(DS.inkTertiary)
                    Text(last, style: .relative).font(DS.caption).foregroundStyle(DS.inkTertiary)
                    Text("ago").font(DS.caption).foregroundStyle(DS.inkTertiary)
                }
            }
            if chartPoints.count > 1 {
                Sparkline(points: chartPoints, color: DS.trend(growth30d ?? 0))
                    .frame(height: 54)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var chartPoints: [Double] {
        storage.history.suffix(90).map(\.mrr)
    }

    private var growth30d: Double? {
        guard let previous = MRRHistory.value(storage.history, daysAgo: 30) else { return nil }
        return MRRMath.growthPercent(from: previous, to: aggregate.mrr)
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: 10) {
            stat("Active", value: "\(aggregate.activeSubscriptions)", caption: "subscriptions")
            stat("Trials", value: "\(aggregate.activeTrials)", caption: "in progress")
            stat("28 days", value: hidden ? "••" : Format.money(aggregate.revenue28d, currency: aggregate.currency, compact: true),
                 caption: "revenue")
        }
    }

    private func stat(_ title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).sectionLabel()
            Text(value).font(DS.figureLG).foregroundStyle(DS.ink)
            Text(caption).font(DS.caption).foregroundStyle(DS.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 11)
    }

    // MARK: Per source

    private var sourceBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By source").sectionLabel()
            VStack(spacing: 0) {
                ForEach(storage.sources.filter(\.enabled)) { source in
                    SourceRow(source: source,
                              state: metrics.state(for: source),
                              mrr: aggregate.perSource[source.id] ?? 0,
                              share: share(of: source),
                              currency: aggregate.currency,
                              hidden: hidden)
                    if source.id != storage.sources.filter(\.enabled).last?.id {
                        Divider().overlay(DS.hairline)
                    }
                }
            }
            .card(padding: 0)
        }
    }

    private func share(of source: Source) -> Double {
        guard aggregate.mrr > 0 else { return 0 }
        return (aggregate.perSource[source.id] ?? 0) / aggregate.mrr
    }

    // MARK: Warnings

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 6) {
            if aggregate.sourcesFailing > 0 {
                warning("\(aggregate.sourcesFailing) source\(aggregate.sourcesFailing == 1 ? "" : "s") failed to refresh — see Sources.")
            }
            ForEach(aggregate.unconverted.sorted(by: { $0.key < $1.key }), id: \.key) { code, amount in
                warning("\(Format.money(amount, currency: code)) not included: no \(code)→\(aggregate.currency) rate.")
            }
            if aggregate.unpricedSubscriptions > 0 {
                warning("\(aggregate.unpricedSubscriptions) subscription\(aggregate.unpricedSubscriptions == 1 ? "" : "s") could not be priced (usage-based or tiered).")
            }
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(DS.warn)
            Text(text).font(DS.caption).foregroundStyle(DS.inkSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30, weight: .light)).foregroundStyle(DS.brand)
            Text("No sources yet").font(DS.title).foregroundStyle(DS.ink)
            Text("Connect Stripe, RevenueCat, Paddle, Lemon Squeezy, Polar or Dodo Payments to see your MRR in the menu bar.")
                .font(DS.body).foregroundStyle(DS.inkSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

struct SourceRow: View {
    let source: Source
    let state: SourceState
    let mrr: Double
    let share: Double
    let currency: String
    let hidden: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.cardAlt).frame(width: 26, height: 26)
                Text(String(source.kind.displayName.prefix(1)))
                    .font(DS.caption.weight(.bold)).foregroundStyle(DS.brand)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(source.name).font(DS.body.weight(.medium)).foregroundStyle(DS.ink).lineLimit(1)
                if let error = state.error {
                    Text(error).font(DS.caption).foregroundStyle(DS.down).lineLimit(1)
                } else if let count = state.snapshot?.activeSubscriptions {
                    Text("\(count) active").font(DS.caption).foregroundStyle(DS.inkTertiary)
                } else {
                    Text(source.kind.displayName).font(DS.caption).foregroundStyle(DS.inkTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if state.isLoading && state.snapshot == nil {
                    ProgressView().controlSize(.small)
                } else if source.kind.reportsMRR {
                    Text(hidden ? "••••" : Format.money(mrr, currency: currency, decimals: 0))
                        .font(DS.figure).foregroundStyle(DS.ink)
                    Text(share > 0 ? String(format: "%.0f%%", share * 100) : "—")
                        .font(DS.caption).foregroundStyle(DS.inkTertiary)
                } else {
                    Text("revenue only").font(DS.caption).foregroundStyle(DS.inkTertiary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}
