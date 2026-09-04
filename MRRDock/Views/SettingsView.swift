import SwiftUI

struct SettingsView: View {
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var metrics = MetricsService.shared
    @State private var webhookTest: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                block("Display") {
                    Picker("Currency", selection: $storage.displayCurrency) {
                        ForEach(Format.currencies, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: storage.displayCurrency) { _, _ in metrics.recompute() }

                    Picker("Menu bar", selection: Binding(
                        get: { storage.menuBarMode },
                        set: { storage.menuBarMode = $0 })) {
                            ForEach(MenuBarMode.allCases) { Text($0.label).tag($0) }
                        }

                    Picker("Decimals", selection: $storage.decimals) {
                        Text("0").tag(0)
                        Text("2").tag(2)
                    }

                    Picker("Appearance", selection: $storage.appearanceRaw) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }

                    Toggle("Show icon in the menu bar", isOn: $storage.showMenuBarIcon)
                    Toggle("Privacy mode", isOn: $storage.privacyMode)
                }

                block("Refresh") {
                    Picker("Every", selection: $storage.refreshMinutes) {
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("6 hours").tag(360)
                    }
                    if let last = metrics.lastRefresh {
                        HStack(spacing: 4) {
                            Text("Last refresh").font(DS.caption).foregroundStyle(DS.inkTertiary)
                            Text(last, style: .relative).font(DS.caption).foregroundStyle(DS.inkTertiary)
                            Text("ago").font(DS.caption).foregroundStyle(DS.inkTertiary)
                        }
                    }
                }

                block("Notifications") {
                    TextField("Discord or Slack webhook URL", text: $storage.webhookURL)
                    Toggle("MRR milestones", isOn: $storage.notifyMilestones)
                    if storage.notifyMilestones {
                        Picker("Every", selection: $storage.milestoneStep) {
                            // Formatted, not hard-coded: "1.000" is right in
                            // Italian and wrong everywhere else.
                            ForEach([100.0, 500.0, 1000.0, 5000.0, 10000.0], id: \.self) { step in
                                Text(Format.money(step, currency: storage.displayCurrency)).tag(step)
                            }
                        }
                    }
                    Toggle("Daily summary (after 22:00)", isOn: $storage.notifyDailySummary)
                    HStack {
                        Button("Send test") { sendTestWebhook() }
                            .disabled(WebhookNotifier(urlString: storage.webhookURL) == nil)
                        if let webhookTest {
                            Text(webhookTest).font(DS.caption).foregroundStyle(DS.inkSecondary)
                        }
                    }
                }

                block("About") {
                    HStack {
                        Text("MRRDock \(AppInfo.version)").font(DS.caption).foregroundStyle(DS.inkSecondary)
                        Spacer()
                        Button("GitHub") {
                            NSWorkspace.shared.open(URL(string: "https://github.com/simonsruggi/MRRDock")!)
                        }
                        .buttonStyle(.link).font(DS.caption)
                    }
                    Text("Free and open source. Your keys stay in your Keychain; nothing is sent anywhere except to the platforms you connect.")
                        .font(DS.caption).foregroundStyle(DS.inkTertiary).fixedSize(horizontal: false, vertical: true)
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/simonsruggi")!)
                    } label: {
                        Label("Become a sponsor", systemImage: "heart.fill")
                            .font(DS.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(Color(red: 0.92, green: 0.29, blue: 0.67).opacity(0.14)))
                            .foregroundStyle(Color(red: 0.85, green: 0.24, blue: 0.60))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .font(DS.body)
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionLabel()
            VStack(alignment: .leading, spacing: 8) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }

    private func sendTestWebhook() {
        guard let notifier = WebhookNotifier(urlString: storage.webhookURL) else { return }
        webhookTest = "Sending…"
        Task {
            let ok = await notifier.send(title: "MRRDock test",
                                         body: "Webhook wired up. MRR \(Format.money(metrics.aggregate.mrr, currency: metrics.aggregate.currency)).",
                                         positive: true)
            webhookTest = ok ? "Sent ✓" : "Failed"
        }
    }
}
