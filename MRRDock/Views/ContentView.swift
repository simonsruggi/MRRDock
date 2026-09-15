import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case overview, sources, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .sources: return "Sources"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "chart.line.uptrend.xyaxis"
        case .sources: return "creditcard"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var metrics = MetricsService.shared
    @State private var tab: Tab = .overview

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            header
            Divider().overlay(DS.hairline)
            Group {
                switch tab {
                case .overview: OverviewView()
                case .sources: SourcesView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 380, height: 520)
        .background(DS.ground)
        .preferredColorScheme(colorScheme)
        .onAppear { if storage.sources.isEmpty { tab = .sources } }
    }

    private var colorScheme: ColorScheme? {
        switch storage.appearanceRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// Marketing version prefixed with "v", e.g. "v1.1.0".
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(v)"
    }

    /// `build-app.sh` stamps its bundles; `release.sh` builds its own and never
    /// does. `swift run` has no Info.plist at all. Either way, not the released app.
    private var isDevBuild: Bool {
        guard let info = Bundle.main.infoDictionary, info["CFBundleShortVersionString"] != nil else { return true }
        return info["MRRDockDevBuild"] as? Bool == true
    }

    private var titleBar: some View {
        HStack(spacing: 6) {
            Text("MRRDock").font(DS.title).foregroundStyle(DS.ink)
            Text(appVersion).font(DS.caption.weight(.medium)).foregroundStyle(DS.inkTertiary)
            if isDevBuild {
                Text("DEV")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(DS.warn))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 10)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Label(item.title, systemImage: item.icon)
                        .font(DS.caption.weight(.medium))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(tab == item ? DS.brand.opacity(0.12) : .clear))
                        .foregroundStyle(tab == item ? DS.brand : DS.inkSecondary)
                        // Without this the unselected tab is a transparent
                        // capsule: SwiftUI hit-tests the glyphs only, so a click
                        // landing between the icon and the label does nothing.
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                metrics.refresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(metrics.isRefreshing ? 360 : 0))
                    .animation(metrics.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: metrics.isRefreshing)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.inkSecondary)
            .help("Refresh now")

            Menu {
                Button("Refresh now") { metrics.refresh(force: true) }
                Divider()
                Button("MRRDock on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/simonsruggi/MRRDock")!) }
                Button("Report a bug") { NSWorkspace.shared.open(URL(string: "https://github.com/simonsruggi/MRRDock/issues")!) }
                Divider()
                Button("Quit MRRDock") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
            .foregroundStyle(DS.inkSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}
