import Foundation

/// What the status item shows, as a pure function of the numbers and the
/// settings. Kept out of `AppDelegate` so the string in the menu bar — the one
/// thing users look at all day — is covered by tests.
enum MenuBarTitle {
    struct Input {
        var mode: MenuBarMode
        var aggregate: Aggregate
        var growth30d: Double?
        var privacy: Bool
        var decimals: Int
        /// Index into the enabled sources, for the cycling mode.
        var sourceIndex: Int = 0
        var sources: [Source] = []
        var hasSources: Bool = true
    }

    static func text(_ input: Input) -> String {
        guard input.hasSources else { return "MRR —" }
        // Nothing has answered yet (first launch, no network, a pending Keychain
        // prompt): show a dash rather than a confident zero.
        if input.aggregate.sourcesReporting == 0 && input.aggregate.sourcesFailing == 0 { return "—" }
        if input.privacy { return "•••" }
        let aggregate = input.aggregate
        let currency = aggregate.currency

        switch input.mode {
        case .iconOnly:
            return ""
        case .mrr:
            return Format.money(aggregate.mrr, currency: currency, decimals: input.decimals, compact: true)
        case .mrrWithChange:
            let base = Format.money(aggregate.mrr, currency: currency, decimals: input.decimals, compact: true)
            guard let growth = input.growth30d else { return base }
            return "\(base) \(Format.percent(growth, decimals: 0))"
        case .arr:
            return Format.money(aggregate.arr, currency: currency, decimals: 0, compact: true) + " ARR"
        case .revenue28d:
            return Format.money(aggregate.revenue28d, currency: currency, decimals: 0, compact: true)
        case .activeSubscriptions:
            return "\(aggregate.activeSubscriptions) subs"
        case .perSource:
            let enabled = input.sources.filter(\.enabled)
            guard !enabled.isEmpty else {
                return Format.money(aggregate.mrr, currency: currency, decimals: input.decimals, compact: true)
            }
            let source = enabled[input.sourceIndex % enabled.count]
            let value = aggregate.perSource[source.id] ?? 0
            let label = source.name.count > 10 ? String(source.name.prefix(10)) : source.name
            return "\(label) \(Format.money(value, currency: currency, decimals: 0, compact: true))"
        }
    }
}
