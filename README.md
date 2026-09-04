<div align="center">

# MRRDock

**A free, open-source macOS menu bar app that shows your MRR — from every platform you get paid on, added up in one number.**

Stripe, RevenueCat, Paddle, Lemon Squeezy, Polar, Dodo Payments, Gumroad, or any endpoint of your own. Your API keys stay in your Keychain; nothing is sent anywhere except to the platforms you connect.

[![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://github.com/simonsruggi/MRRDock/releases/latest)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/github/license/simonsruggi/MRRDock?color=blue)](LICENSE)
[![Star](https://img.shields.io/github/stars/simonsruggi/MRRDock?style=social)](https://github.com/simonsruggi/MRRDock)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-EA4AAA?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/simonsruggi)

**[✨ Features](#features)** · **[🔌 Supported platforms](#supported-platforms)** · **[🛠 Build it](#build-it-yourself)** · **[🔒 Privacy](#privacy)** · **[🐛 Report a bug](https://github.com/simonsruggi/MRRDock/issues)**

</div>

---

Same idea as [StockDock](https://github.com/simonsruggi/StockDock), different number: instead of your portfolio, the menu bar carries the one figure a founder actually checks all day — monthly recurring revenue.

## Features

- **One number across every platform.** Two Stripe accounts, RevenueCat for the apps, Paddle for the SaaS: MRRDock adds them up and shows the total.
- **MRR computed properly.** Yearly plans divided by twelve, weekly plans multiplied by 4.35, seats and quantities counted, percentage coupons applied, trials counted but priced at zero.
- **Multi-currency.** Every source is converted into your display currency with live rates. What can't be converted is shown separately instead of silently dropped.
- **Menu bar, your way.** MRR · MRR + 30-day change · ARR · revenue over 28 days · active subscriptions · one source at a time (cycling) · icon only.
- **Trend at a glance.** A daily MRR snapshot builds a 90-day sparkline and the "vs 30 days ago" delta — no account, no server, just a local file.
- **Privacy mode.** Hides every figure behind `•••` for screen sharing, and reveals it with one click.
- **Discord / Slack notifications.** MRR milestones ("just crossed €5.000") and an optional daily summary.
- **Honest totals.** Failing sources, missing exchange rates and usage-based subscriptions that can't be priced are all called out — MRRDock would rather say "partial" than show a confident wrong number.
- **Native and light.** Pure SwiftUI, no dependencies, universal binary, no telemetry.

## Supported platforms

| Platform | What it reads | How |
| --- | --- | --- |
| **Stripe** | MRR, active subs, trials, optional 28-day revenue | Live subscription list, priced item by item (`/v1/subscriptions`) |
| **RevenueCat** | MRR, active subs, trials, 28-day revenue | Project overview metrics (`/v2/projects/{id}/metrics/overview`) |
| **Paddle** (Billing) | MRR, active subs, trials | `/subscriptions`, priced per item |
| **Lemon Squeezy** | MRR, active subs, trials | `/v1/subscriptions` + the price of each plan |
| **Polar** | MRR, 28-day revenue, active subs | `/v1/metrics` |
| **Dodo Payments** | MRR, active subs | `/subscriptions`, priced per subscription |
| **Gumroad** | 28-day revenue only | `/v2/sales` — Gumroad exposes no subscription pricing, so it contributes revenue, not MRR |
| **Custom endpoint** | Anything you can serve as JSON | Your own HTTPS URL |

Every key is used read-only. On Stripe, create a **restricted key** with read access to Subscriptions (and Charges if you want the revenue figure).

### Superwall, App Store Connect, Chargebee, anything else

Platforms without a public revenue API — Superwall today, for instance — go through the **custom endpoint**: point MRRDock at an HTTPS URL of yours (a Cloudflare Worker, a small Lambda, a file on your server) that returns

```json
{ "mrr": 4820.50, "currency": "EUR", "active_subscriptions": 312, "trials": 24, "revenue_28d": 6100 }
```

`currency`, `active_subscriptions`, `trials` and `revenue_28d` are optional; `mrr` (or `monthly_recurring_revenue`) is all you need. A bearer token can be sent with the request, and the response may be wrapped in `data` or `result`. This is also the way to keep a payment key off your laptop entirely: let your own backend hold it and expose only the aggregate.

## Screenshots

<div align="center">

<img src="screenshots/overview.png" alt="MRRDock overview: total MRR, 30-day change, sparkline and per-source breakdown" width="380">
<img src="screenshots/by-source.png" alt="MRR split by source across Stripe, RevenueCat, Paddle, Lemon Squeezy and Gumroad" width="380">

<img src="screenshots/sources.png" alt="Connected sources, each one switchable" width="380">
<img src="screenshots/add-source.png" alt="Adding a RevenueCat source, with a Test button that validates the key before saving" width="380">

<img src="screenshots/settings.png" alt="Settings: display currency, menu bar mode, refresh interval and notifications" width="380">
<img src="screenshots/overview-dark.png" alt="MRRDock in dark mode" width="380">

<sub>Figures in the screenshots are demo data.</sub>

</div>

## Install

Download the latest release, or build it yourself. MRRDock is not notarized yet, so the first launch needs a right-click → **Open**.

## Build it yourself

```bash
git clone https://github.com/simonsruggi/MRRDock.git
cd MRRDock
./build-app.sh          # universal MRRDock.app in ./build
open build/MRRDock.app
```

Or run the binary straight from SwiftPM:

```bash
swift run MRRDock
swift test               # the pure logic: MRR maths, aggregation, menu bar, parsing
```

Requires macOS 14+ and the Swift 5.9 toolchain (Xcode 15).

## How MRR is calculated

For every recurring line item MRRDock knows the price, the interval, the quantity and any percentage discount:

```
monthly = unit_price × quantity × (interval_per_month / interval_count) × (1 − discount)
```

with `interval_per_month` = 30.4375 for daily, 4.348 for weekly, 1 for monthly, 1/12 for yearly — the average Gregorian month, so twelve monthly plans and one yearly plan reconcile exactly.

Deliberate choices worth knowing:

- **Trials are not revenue.** They're counted and shown separately, never added to MRR.
- **Usage-based and tiered prices are not guessed.** They're reported as "could not be priced" so an under-reported total is visible.
- **Fixed-amount coupons are not applied** (percentage ones are): prorating a €5-off coupon across a multi-item subscription needs data these APIs don't return.
- **Taxes are excluded** where the provider separates them (Dodo's `recurring_pre_tax_amount`, Paddle's unit price).
- **Nothing is annualised for you.** ARR is exactly MRR × 12, shown as such.

## Privacy

- API keys are stored in the **macOS Keychain**, never in the app's JSON file.
- Requests go **only** to the platforms you configure (plus Yahoo Finance for exchange rates, with no identifying data).
- No account, no analytics, no telemetry, no crash reporting.
- Settings, sources and MRR history live in `~/Library/Application Support/MRRDock/`.
- Webhook notifications go only to Discord or Slack hosts.

## Contributing

New providers are welcome and small: add a case to `ProviderKind`, an implementation of `RevenueProvider`, and a parsing test. See [PROJECT.md](PROJECT.md) for the architecture.

## License

MIT — see [LICENSE](LICENSE).

<div align="center">

Made with ❤️ by [Simone Ruggiero](https://simoneruggiero.com?utm_source=MRRDock&utm_medium=readme)

</div>
