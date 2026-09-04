import AppKit
import Combine
import Sparkle
import SwiftUI

/// Sparkle auto-updates.
///
/// The updater is only started when the bundle actually carries a feed URL, so
/// `swift run` and the dev build don't spawn an updater that would check a feed
/// they can't use.
@MainActor
final class UpdaterViewModel: ObservableObject {
    private let controller: SPUStandardUpdaterController?

    init() {
        controller = Bundle.main.infoDictionary?["SUFeedURL"] != nil
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var isAvailable: Bool { controller != nil }
    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    func checkForUpdates() { controller?.updater.checkForUpdates() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var refreshTimer: Timer?
    private var cycleTimer: Timer?
    private var sourceIndex = 0
    private var observers: Set<AnyCancellable> = []
    private var debugWindow: NSWindow?

    private let storage = StorageService.shared
    private let metrics = MetricsService.shared
    static let updater = UpdaterViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpPopover()

        // Any change to the numbers or the preferences redraws the title: the
        // menu bar must never disagree with the popover it just closed.
        metrics.objectWillChange
            .merge(with: storage.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateTitle() }
            .store(in: &observers)

        storage.$refreshMinutes
            .removeDuplicates()
            .sink { [weak self] minutes in self?.scheduleRefresh(minutes: minutes) }
            .store(in: &observers)

        cycleTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let delegate = self else { return }
            Task { @MainActor in
                guard delegate.storage.menuBarMode == .perSource else { return }
                delegate.sourceIndex += 1
                delegate.updateTitle()
            }
        }

        metrics.refresh(force: true)
        updateTitle()

        // Screenshot/debug affordance: the popover can't be opened from a script,
        // so MRRDOCK_SHOW_WINDOW puts the same view in a plain window.
        if ProcessInfo.processInfo.environment["MRRDOCK_SHOW_WINDOW"] == "1" {
            showDebugWindow()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let delegate = self else { return }
                Task { @MainActor in delegate.metrics.refresh(force: true) }
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        storage.save()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = menuBarIcon()
        statusItem?.button?.imagePosition = .imageLeading
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self
    }

    private func menuBarIcon() -> NSImage? {
        let image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "MRRDock")
        image?.isTemplate = true
        return image
    }

    private func setUpPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())
        self.popover = popover
    }

    private func scheduleRefresh(minutes: Int) {
        refreshTimer?.invalidate()
        let interval = TimeInterval(max(minutes, 1) * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let delegate = self else { return }
            Task { @MainActor in delegate.metrics.refresh() }
        }
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            metrics.refresh()
        }
    }

    private func showDebugWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MRRDock"
        window.contentViewController = NSHostingController(rootView: ContentView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        debugWindow = window
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let growth = MRRHistory.value(storage.history, daysAgo: 30)
            .flatMap { MRRMath.growthPercent(from: $0, to: metrics.aggregate.mrr) }
        let title = MenuBarTitle.text(.init(mode: storage.menuBarMode,
                                            aggregate: metrics.aggregate,
                                            growth30d: growth,
                                            privacy: storage.privacyMode,
                                            decimals: storage.decimals,
                                            sourceIndex: sourceIndex,
                                            sources: storage.sources,
                                            hasSources: !storage.sources.isEmpty))
        button.title = title.isEmpty ? "" : " \(title)"
        // The icon is dropped in text modes when the user turns it off, but a
        // title-less mode always keeps it — a blank status item is unclickable.
        button.image = (storage.showMenuBarIcon || title.isEmpty) ? menuBarIcon() : nil
    }
}
