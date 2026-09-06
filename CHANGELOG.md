# Changelog

## Unreleased

- Chart ranges: 24H, 7D, 1Y and a custom range picked on a calendar
- The trend now starts where the business did, not where MRRDock was installed: history is backfilled daily from each provider's own MRR series (RevenueCat today; providers that can't answer keep the local readings)
- Readings from the last 48 hours are kept as they come, so the 24H chart has a shape; older ones still collapse to one per day
- The chart plots time on the x-axis instead of position in the array — a year no longer gives today half the width
- `build-app.sh` signs the bundled Sparkle framework, which otherwise refused to load in a locally built app

## 1.0.0

First release.

- Menu bar MRR aggregated across Stripe, RevenueCat, Paddle, Lemon Squeezy, Polar, Dodo Payments, Gumroad (revenue only) and any custom HTTPS endpoint
- Multi-currency conversion with a 12h rate cache; unconvertible amounts reported instead of dropped
- Menu bar modes: MRR, MRR + 30-day change, ARR, 28-day revenue, active subscriptions, per-source cycling, icon only
- 90-day MRR sparkline and "vs 30 days ago" delta from daily local snapshots
- Privacy mode, light/dark/system appearance, 5 min – 6 h refresh interval
- Discord / Slack notifications: MRR milestones and daily summary
- API keys stored in the macOS Keychain; no account, no telemetry
