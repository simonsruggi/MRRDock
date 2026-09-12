# I built a free macOS menu bar app that shows my MRR across every payment platform

### Stripe, RevenueCat, Paddle, Lemon Squeezy, Polar, Dodo and Gumroad, added up once every fifteen minutes. No account, no server, MIT licensed.

---

I sell software in more places than I'd like to admit.

The iOS apps report through RevenueCat. A web product bills on Stripe. Paddle handles a desktop app because it's a merchant of record and VAT is not a hobby I want. Templates sit on Lemon Squeezy. Three of those bill in dollars, I think in euros.

So the question "how am I actually doing this month?" costs me four logins, four dashboards, and a mental sum with a currency conversion in the middle of it. I was asking that question roughly twenty times a day, and answering it badly.

MRRDock is the answer to that question, sitting in the menu bar:

```bash
brew install --cask simonsruggi/tap/mrrdock
```

One number. All platforms. Your currency. Free, open source, and the data never leaves your Mac.

## What it does

It's a menu bar app — no Dock icon, no window. You add your sources once, and from then on the total MRR is always visible. Click it and the popover breaks the number down.

- **Multi-platform aggregation.** Stripe, RevenueCat, Paddle Billing, Lemon Squeezy, Polar, Dodo Payments, Gumroad, plus any HTTPS endpoint of your own. Multiple accounts of the same platform are fine: two Stripe accounts and four RevenueCat projects add up like anything else.
- **Multi-currency.** Every source converts into your display currency with live rates cached for 12 hours. Amounts that can't be converted are shown separately, never silently folded into the total.
- **A real MRR trend.** 24H, 7D, 1Y or a custom range, with a "vs 30 days ago" delta.
- **Seven menu bar modes.** MRR, MRR + 30-day change, ARR, 28-day revenue, active subscriptions, one source at a time cycling every four seconds, or icon only.
- **Privacy mode.** One click replaces every figure with `•••` for screen sharing or a café.
- **Discord and Slack notifications.** MRR milestones ("just crossed €5,000") and an optional daily summary.

## The part I care about: honest arithmetic

Anyone can call four APIs and add up the numbers. The interesting work is in deciding what a number *means*, and being loud about the cases where you don't know.

Every recurring line item gets priced the same way:

```
monthly = unit_price × quantity × (intervals_per_month ÷ interval_count) × (1 − discount)
```

`intervals_per_month` is **30.4375** for daily, **4.348** for weekly, **1** for monthly and **1/12** for yearly. That's the average Gregorian month — 365.25 ÷ 12 — chosen so that twelve monthly plans and one yearly plan reconcile to the cent instead of quietly drifting apart over a year.

Then there are the judgement calls. These are the ones that make any two dashboards disagree, so MRRDock documents all of them:

| Case | What MRRDock does |
| --- | --- |
| Free trial | Counted in **Trials**, contributes **€0** to MRR |
| Yearly plan | Divided by 12 |
| Seats / quantity | Multiplied |
| Percentage coupon (−20%) | Applied |
| Fixed-amount coupon (−€5) | **Not** applied — prorating it across a multi-item subscription needs data these APIs don't return |
| Usage-based / metered price | **Not guessed.** Flagged as "could not be priced" so the understatement is visible |
| Past due / grace period | Follows the provider's own status |
| ARR | Exactly MRR × 12, nothing smoothed behind your back |

The rule I kept coming back to: **an understated total you can see beats a confident total that's wrong.** A metered plan MRRDock can't price shows up as a warning in the popover, not as a zero it hopes you won't notice.

Gumroad gets the same treatment at the source level. Its API exposes sales, not a subscription ledger you can price — so deriving an MRR from one-off sales would be a guess. That source contributes 28-day revenue only, and the UI says exactly that.

## When my app disagreed with RevenueCat, and both were right

Two days after I started using it, MRRDock said 303.76 € across four RevenueCat projects. The RevenueCat dashboard said 306 €. It also said 11 active trials against my 9.

The instinct is to assume you have a bug. I spent an evening proving I didn't, and the answer is a nice illustration of why aggregation is harder than it looks:

1. **`/v2/metrics/overview` returns MRR rounded to whole dollars.** Four projects reporting 181, 127, 27 and 18 dollars carry up to ±2 $ of rounding — about ±1.7 € once converted. That's most of the gap right there.
2. **We use different exchange rates.** Mine come from Yahoo, cached for 12 hours. RevenueCat uses its own, at its own moment.
3. **The trials were mine.** Four RevenueCat projects were sitting at zero MRR so I never bothered adding them to MRRDock — but one of them had 2 live trials. 9 + 2 = 11. Not a bug: an incomplete configuration, which the per-source breakdown made obvious in about ten seconds.

Expected residual drift: around 0.7%. Neither number is wrong. That's worth knowing *before* you go looking for a bug in your own code at midnight.

## The chart should show the business, not the install date

The first version stored a daily snapshot locally and drew a sparkline from it. Which means a brand-new install shows a flat line, and your MRR history "starts" the day you discovered the app. Useless.

So MRRDock backfills from the provider's own daily MRR series. RevenueCat exposes it:

```
GET /v2/projects/{project}/charts/mrr?resolution=day
    &start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
```

Same series the dashboard draws. Two things cost me time and are worth writing down: the dates **must** be `YYYY-MM-DD` (epoch timestamps get a 400), and outside the range where data exists the API answers with zeros rather than an empty array — so you have to trim the leading zeros yourself or your chart opens with a cliff that never happened. The last point comes back with `incomplete: true`, meaning today-so-far: discard it.

Providers that can't answer keep their locally recorded readings. You get the longest honest history each source can give you.

## Your keys, your Mac

There is no MRRDock backend. There is nothing to sign up for. I could not see your revenue if I wanted to.

- API keys live in the **macOS Keychain**, never in the app's JSON file, never in logs, never in a config you might paste into a GitHub issue.
- Requests go only to the platforms you configure, plus Yahoo Finance for exchange rates — a currency pair, nothing about you.
- No account, no login, no analytics, no telemetry, no crash reporting.
- HTTPS only: a custom endpoint on `http://` is refused rather than handed your token in clear.
- **Read-only by construction.** The app issues `GET` requests and nothing else. A key with write scope still can't change anything through MRRDock.

That last point is why the *custom endpoint* source exists, incidentally. Some platforms have no public revenue API at all — Superwall, App Store Connect. Point MRRDock at any HTTPS URL of yours that returns the numbers, and it becomes a source like the others.

## What it isn't

It's not a replacement for ChartMogul, Baremetrics or the RevenueCat dashboard. Cohorts, LTV, churn analysis — those belong on a real screen, and I'm not going to do them worse inside a popover.

MRRDock answers the one question you ask twenty times a day, without opening a browser.

## Try it

Native SwiftUI, no third-party dependencies, macOS 14+, universal binary, signed with a Developer ID and notarized by Apple, with built-in auto-updates. MIT licensed.

```bash
brew install --cask simonsruggi/tap/mrrdock
```

Or grab the zip from the [releases page](https://github.com/simonsruggi/MRRDock/releases/latest).

The code is on GitHub: **[github.com/simonsruggi/MRRDock](https://github.com/simonsruggi/MRRDock)**. Issues and pull requests welcome — especially if you sell through a platform I haven't covered yet.

If the number goes up, that's on you. I just made it easier to look at.
