import SwiftUI

struct SourcesView: View {
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var metrics = MetricsService.shared
    @State private var editing: Source?
    @State private var isAdding = false
    @State private var pendingDelete: Source?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(storage.sources) { source in
                        row(source)
                    }
                    if storage.sources.isEmpty {
                        Text("Add the platforms you get paid on. Keys are stored in your macOS Keychain and only ever sent to that platform.")
                            .font(DS.body).foregroundStyle(DS.inkSecondary)
                            .multilineTextAlignment(.center).padding(.vertical, 30).padding(.horizontal, 10)
                    }
                }
                .padding(14)
            }
            Divider().overlay(DS.hairline)
            HStack {
                Button {
                    isAdding = true
                } label: {
                    Label("Add source", systemImage: "plus")
                        .font(DS.body.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(DS.brand))
                        .foregroundStyle(.white)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(12)
        }
        .sheet(isPresented: $isAdding) {
            SourceEditView(source: Source(kind: .stripe, name: "Stripe"), isNew: true)
        }
        .sheet(item: $editing) { source in
            SourceEditView(source: source, isNew: false)
        }
        .alert(item: $pendingDelete) { source in
            Alert(title: Text("Remove \(source.name)?"),
                  message: Text("Its API key is deleted from the Keychain. Your MRR history is kept."),
                  primaryButton: .destructive(Text("Remove")) {
                      storage.removeSource(source)
                      metrics.refresh(force: true)
                  },
                  secondaryButton: .cancel())
        }
    }

    private func row(_ source: Source) -> some View {
        let state = metrics.state(for: source)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { newValue in
                    var copy = source
                    copy.enabled = newValue
                    storage.updateSource(copy, secret: nil)
                    metrics.refresh(force: true)
                }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(DS.body.weight(.medium)).foregroundStyle(DS.ink)
                HStack(spacing: 4) {
                    // The platform name is dropped when the user kept it as the
                    // source name: "Stripe / Stripe" is a line that says nothing.
                    if source.name != source.kind.displayName {
                        Text(source.kind.displayName).font(DS.caption).foregroundStyle(DS.inkTertiary)
                    }
                    if source.flag("sandbox") {
                        Text("TEST").font(DS.label).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(DS.warn.opacity(0.15))).foregroundStyle(DS.warn)
                    }
                }
            }
            Spacer()
            if let error = state.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.warn)
                    .font(.system(size: 11)).help(error)
            } else if state.snapshot != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.up).font(.system(size: 11))
            }
            // Icon buttons get a real 22pt target: an 11pt glyph is a coin toss
            // with a trackpad.
            Button { editing = source } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11))
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(DS.inkSecondary)
            Button { pendingDelete = source } label: {
                Image(systemName: "trash").font(.system(size: 11))
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(DS.inkTertiary)
        }
        .card(padding: 11)
    }
}

struct SourceEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var metrics = MetricsService.shared

    @State var source: Source
    let isNew: Bool
    @State private var secret: String = ""
    @State private var testResult: String?
    @State private var testOK = false
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add source" : "Edit source").font(DS.title).foregroundStyle(DS.ink)

            Picker("Platform", selection: $source.kind) {
                ForEach(ProviderKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .onChange(of: source.kind) { _, newValue in
                if isNew { source.name = newValue.displayName }
                testResult = nil
            }

            TextField("Name", text: $source.name)

            VStack(alignment: .leading, spacing: 4) {
                SecureField(source.kind.secretLabel, text: $secret)
                if !isNew, secret.isEmpty, storage.secret(for: source) != nil {
                    Text("A key is already saved. Leave empty to keep it.")
                        .font(DS.caption).foregroundStyle(DS.inkTertiary)
                }
                Button("Where do I find this?") {
                    if let url = URL(string: source.kind.docsURL) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link).font(DS.caption)
            }

            options

            if let testResult {
                Text(testResult)
                    .font(DS.caption)
                    .foregroundStyle(testOK ? DS.up : DS.down)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Button("Test") { test() }
                    .disabled(isTesting)
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isNew ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(source.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380, height: 400)
        .background(DS.ground)
    }

    @ViewBuilder
    private var options: some View {
        switch source.kind {
        case .revenuecat:
            optionField("Project ID", key: "projectId", help: "app.revenuecat.com → Project settings")
            currencyPicker(help: "RevenueCat reports in your dashboard currency")
        case .stripe:
            optionField("Connected account ID (optional)", key: "stripeAccount")
            optionToggle("Include revenue over the last 28 days", key: "includeRevenue")
        case .paddle, .polar:
            optionToggle("Sandbox", key: "sandbox")
            if source.kind == .polar {
                optionField("Organization ID (optional)", key: "organizationId")
                currencyPicker(help: "Polar reports in your organization currency")
            }
        case .dodo:
            optionToggle("Test mode", key: "sandbox")
            optionField("Brand ID (optional)", key: "brandId")
        case .lemonsqueezy:
            optionField("Store ID (optional)", key: "storeId")
        case .custom:
            optionField("HTTPS endpoint", key: "url", help: "Must return JSON with an \"mrr\" field")
            optionField("JSON key holding the MRR (optional)", key: "mrrKey")
            currencyPicker(help: "Used when the response has no \"currency\"")
        case .gumroad:
            Text("Gumroad has no subscription pricing API, so this source contributes revenue over the last 28 days — not MRR.")
                .font(DS.caption).foregroundStyle(DS.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func optionField(_ title: String, key: String, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField(title, text: Binding(
                get: { source.options[key] ?? "" },
                set: { source.options[key] = $0 }))
            if let help {
                Text(help).font(DS.caption).foregroundStyle(DS.inkTertiary)
            }
        }
    }

    private func optionToggle(_ title: String, key: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { source.flag(key) },
            set: { source.options[key] = $0 ? "true" : "false" }))
            .font(DS.body)
    }

    private func currencyPicker(help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Picker("Currency", selection: Binding(
                get: { source.options["currency"] ?? "USD" },
                set: { source.options["currency"] = $0 })) {
                    ForEach(Format.currencies, id: \.self) { Text($0).tag($0) }
                }
            Text(help).font(DS.caption).foregroundStyle(DS.inkTertiary)
        }
    }

    private func effectiveSecret() -> String {
        secret.isEmpty ? (storage.secret(for: source) ?? "") : secret
    }

    private func test() {
        isTesting = true
        testResult = nil
        let source = source
        let secret = effectiveSecret()
        Task {
            let result = await metrics.test(source: source, secret: secret)
            isTesting = false
            switch result {
            case .success(let snapshot):
                testOK = true
                let mrr = snapshot.mrr.byCurrency
                    .sorted { $0.key < $1.key }
                    .map { Format.money($0.value, currency: $0.key, decimals: 2) }
                    .joined(separator: " + ")
                testResult = "Connected. MRR \(mrr.isEmpty ? "—" : mrr)"
                    + (snapshot.activeSubscriptions.map { " · \($0) active" } ?? "")
            case .failure(let error):
                testOK = false
                testResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func save() {
        if isNew {
            storage.addSource(source, secret: secret)
        } else {
            storage.updateSource(source, secret: secret.isEmpty ? nil : secret)
        }
        metrics.refresh(force: true)
        dismiss()
    }
}
