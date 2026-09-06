# MRRDock

macOS menu bar app showing aggregated MRR across payment platforms. No account, no server: the app talks straight to each provider's API with keys held in the user's Keychain.

## Tech stack

- **Language**: Swift 5.9 · **UI**: SwiftUI + AppKit status item
- **Platform**: macOS 14+ · **Build**: Swift Package Manager, **no dependencies**
- **Storage**: `~/Library/Application Support/MRRDock/data.json` (settings, sources, MRR history) + `fx.json` (rate cache); secrets in the login Keychain under service `com.simone.mrrdock`
- **Exchange rates**: Yahoo Finance public quote endpoint (no key), cached 12h
- **Chart history**: backfilled once a day from each provider's own series (RevenueCat: `GET /v2/projects/<id>/charts/mrr?resolution=day`), so the trend predates the install; the app's own readings cover today

## Folder structure

```
MRRDock/
├── Package.swift
├── build-app.sh                     # universal .app bundle, ad-hoc signed
├── scripts/make-icon.swift          # regenerates icon/*.png → AppIcon.icns
├── MRRDock/
│   ├── MRRDockApp.swift             # @main, AppDelegate adaptor
│   ├── AppDelegate.swift            # status item, popover, refresh + cycle timers
│   ├── Models/
│   │   ├── Money.swift              # BillingInterval, Money, MoneyBag, MRRMath (pure)
│   │   ├── Source.swift             # ProviderKind, Source, ProviderSnapshot, ChartRange, MRRHistory
│   │   ├── Aggregate.swift          # cross-source totals + MilestoneEvaluator (pure)
│   │   └── MenuBarTitle.swift       # the status item string (pure)
│   ├── Services/
│   │   ├── Keychain.swift           # generic passwords, one per source
│   │   ├── StorageService.swift     # persisted state, debounced saves, Format helpers
│   │   ├── FXService.swift          # currency conversion + disk cache
│   │   ├── MetricsService.swift     # concurrent refresh, aggregation, notifications
│   │   ├── WebhookNotifier.swift    # Discord/Slack, host-allowlisted
│   │   └── Providers/               # one file per platform + RevenueProvider protocol
│   └── Views/                       # DesignSystem, ContentView, Overview, Sources, Settings
└── Tests/                           # 35 tests over the pure logic
```

## Architecture

`MetricsService.refresh()` fans out over every enabled `Source` with a `TaskGroup`, one `RevenueProvider` each. Providers own their platform's quirks (pagination, minor units, interval spelling) and return a `ProviderSnapshot` whose amounts are already in **major units**, kept per currency in a `MoneyBag`. `FXService` then supplies rates and `Aggregate.build` folds everything into the display currency.

Three rules the code sticks to:

1. **Currencies stay separate until a rate exists.** Adding EUR to USD before converting is the classic wrong-MRR bug; `MoneyBag` makes it unrepresentable and reports what it could not convert.
2. **A failing source keeps its last snapshot.** A transient 502 leaves yesterday's figure on screen with an error badge, never a zero — a menu bar that drops to €0 on a network blip is worse than useless.
3. **The number in the menu bar is a pure function.** `MenuBarTitle.text(_:)` takes the aggregate and the settings and returns a string, so the thing users stare at all day is covered by tests.

## Adding a provider

1. Add a case to `ProviderKind` (+ display name, secret label, docs URL).
2. Implement `RevenueProvider.fetch(source:secret:http:)` in `Services/Providers/`.
3. Register it in `ProviderRegistry`.
4. Add the option fields to `SourceEditView.options`.
5. Add a parsing test with a real response body in `Tests/ProviderParsingTests.swift`.

`HTTPClient` is https-only and caps pagination at `maxPages` (25 × 100 rows).

## Verified against live APIs

- **RevenueCat** — checked against a real project: the v2 overview returns `{"currency": "USD", "metrics": [{"id": "mrr", "value": …}]}`. The parser also accepts the flat shape RevenueCat's docs show.
- Every other provider is implemented from its current API reference; response parsing is tolerant (unknown fields ignored, several field spellings accepted) precisely because these APIs move.

## Debug affordances

- `MRRDOCK_SHOW_WINDOW=1` opens the popover content in a plain window (a popover can't be opened from a script — this is how screenshots are taken).

## Releasing

`./release.sh <version> <build>` (local, gitignored: it needs the Developer ID, the notarytool keychain profile, the Sparkle private key and push access to the tap) runs: bump → test → universal build → assemble → smoke test → nested code-sign → notarize → staple → Sparkle EdDSA signature → `appcast.xml` → GitHub release → Homebrew cask bump.

Sparkle reads `appcast.xml` from `raw.githubusercontent.com/.../main/appcast.xml`, so the feed updates the moment the release commit lands. The EdDSA key is the same one StockDock uses — Sparkle's own guidance is one signing key per developer, not per app.

## Roadmap

- App Store Connect / Google Play as first-class sources
- Per-source history, not just the total
- Localisation (the app currently ships English only)
