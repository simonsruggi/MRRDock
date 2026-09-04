import Foundation
import Combine

/// Everything the app remembers, in one JSON file under Application Support.
/// Secrets are the deliberate exception: they live in the Keychain (`Keychain`).
@MainActor
final class StorageService: ObservableObject {
    static let shared = StorageService()

    @Published var sources: [Source] = [] { didSet { scheduleSave() } }
    @Published var history: [MRRPoint] = [] { didSet { scheduleSave() } }

    /// Currency every source is converted into for the totals and the menu bar.
    @Published var displayCurrency: String = "EUR" { didSet { scheduleSave() } }
    /// What the menu bar shows. See `MenuBarMode`.
    @Published var menuBarModeRaw: String = MenuBarMode.mrr.rawValue { didSet { scheduleSave() } }
    @Published var showMenuBarIcon: Bool = true { didSet { scheduleSave() } }
    /// Hide the figure behind a click — for screen sharing and cafés.
    @Published var privacyMode: Bool = false { didSet { scheduleSave() } }
    @Published var refreshMinutes: Int = 15 { didSet { scheduleSave() } }
    @Published var appearanceRaw: String = "system" { didSet { scheduleSave() } }
    @Published var decimals: Int = 0 { didSet { scheduleSave() } }

    // MARK: Notifications
    @Published var webhookURL: String = "" { didSet { scheduleSave() } }
    @Published var notifyMilestones: Bool = false { didSet { scheduleSave() } }
    /// MRR step that counts as a milestone (every 1.000 by default).
    @Published var milestoneStep: Double = 1000 { didSet { scheduleSave() } }
    @Published var lastMilestone: Double = 0 { didSet { scheduleSave() } }
    @Published var notifyDailySummary: Bool = false { didSet { scheduleSave() } }
    @Published var lastSummaryDay: String = "" { didSet { scheduleSave() } }

    var menuBarMode: MenuBarMode {
        get { MenuBarMode(rawValue: menuBarModeRaw) ?? .mrr }
        set { menuBarModeRaw = newValue.rawValue }
    }

    private var saveTimer: Timer?
    private var isLoading = false

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MRRDock", isDirectory: true)
    }()
    private static let fileURL = directory.appendingPathComponent("data.json")

    private init() { load() }

    // MARK: - Sources

    func addSource(_ source: Source, secret: String) {
        sources.append(source)
        if !secret.isEmpty { Keychain.set(secret, account: source.keychainAccount) }
    }

    func updateSource(_ source: Source, secret: String?) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
        if let secret, !secret.isEmpty { Keychain.set(secret, account: source.keychainAccount) }
    }

    func removeSource(_ source: Source) {
        sources.removeAll { $0.id == source.id }
        Keychain.delete(account: source.keychainAccount)
    }

    func secret(for source: Source) -> String? { Keychain.get(account: source.keychainAccount) }

    // MARK: - Persistence

    private struct Payload: Codable {
        var sources: [Source]
        var history: [MRRPoint]
        var displayCurrency: String
        var menuBarMode: String
        var showMenuBarIcon: Bool
        var privacyMode: Bool
        var refreshMinutes: Int
        var appearance: String
        var decimals: Int
        var webhookURL: String
        var notifyMilestones: Bool
        var milestoneStep: Double
        var lastMilestone: Double
        var notifyDailySummary: Bool
        var lastSummaryDay: String
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: Self.fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        sources = payload.sources
        history = payload.history
        displayCurrency = payload.displayCurrency
        menuBarModeRaw = payload.menuBarMode
        showMenuBarIcon = payload.showMenuBarIcon
        privacyMode = payload.privacyMode
        refreshMinutes = payload.refreshMinutes
        appearanceRaw = payload.appearance
        decimals = payload.decimals
        webhookURL = payload.webhookURL
        notifyMilestones = payload.notifyMilestones
        milestoneStep = payload.milestoneStep
        lastMilestone = payload.lastMilestone
        notifyDailySummary = payload.notifyDailySummary
        lastSummaryDay = payload.lastSummaryDay
    }

    /// Disk writes are debounced: every keystroke in Settings mutates a
    /// `@Published`, and writing the file on each one would block the main
    /// thread while typing.
    private func scheduleSave() {
        guard !isLoading else { return }
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let storage = self else { return }
            Task { @MainActor in storage.save() }
        }
    }

    func save() {
        let payload = Payload(sources: sources, history: history, displayCurrency: displayCurrency,
                              menuBarMode: menuBarModeRaw, showMenuBarIcon: showMenuBarIcon,
                              privacyMode: privacyMode, refreshMinutes: refreshMinutes,
                              appearance: appearanceRaw, decimals: decimals, webhookURL: webhookURL,
                              notifyMilestones: notifyMilestones, milestoneStep: milestoneStep,
                              lastMilestone: lastMilestone, notifyDailySummary: notifyDailySummary,
                              lastSummaryDay: lastSummaryDay)
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("[MRRDock] save failed: %@", error.localizedDescription)
        }
    }
}

enum MenuBarMode: String, CaseIterable, Identifiable {
    case mrr
    case mrrWithChange
    case arr
    case revenue28d
    case activeSubscriptions
    case perSource
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mrr: return "MRR"
        case .mrrWithChange: return "MRR + 30-day change"
        case .arr: return "ARR"
        case .revenue28d: return "Revenue (28 days)"
        case .activeSubscriptions: return "Active subscriptions"
        case .perSource: return "Cycle through sources"
        case .iconOnly: return "Icon only"
        }
    }
}

/// Currency and number formatting used by both the menu bar and the UI.
enum Format {
    static func money(_ value: Double, currency: String, decimals: Int = 0, compact: Bool = false) -> String {
        if compact, abs(value) >= 10_000 {
            let thousands = value / 1000
            return symbol(for: currency) + String(format: "%.1fk", thousands)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = decimals
        formatter.minimumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Plain grouped number, for labels that are counts rather than money.
    static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    static func percent(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%@%.\(decimals)f%%", value >= 0 ? "+" : "", value)
    }

    static func symbol(for currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.currencySymbol ?? currency
    }

    static let currencies = ["EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD", "SEK", "NOK", "DKK", "PLN", "BRL", "INR"]
}
