# MRRDock — launch kit

Testi pronti per i canali che portano backlink e stelle. Scritti il 12/09/2026, quando il
repo era a 0 stelle e MRRDock non compariva su nessun motore nemmeno cercando il nome.

Perché le stelle contano oltre la vanità: `homebrew-cask` ufficiale (pagina
`formulae.brew.sh/cask/mrrdock`, dominio ad alta autorità) accetta un'autocandidatura solo
con **225 stelle** — oppure 90 fork o 90 watcher — e un repo di almeno **30 giorni**
(Package Acceptance Policy di Homebrew). Fino a lì resta il tap personale.

Sito: <https://mrrdock.simoneruggiero.com> · Repo: <https://github.com/simonsruggi/MRRDock>

---

## Hacker News (Show HN)

Da postare **martedì–giovedì, 14:00–17:00 UTC** (mattina della costa est USA). Una sola
volta: un Show HN ripetuto sullo stesso progetto viene penalizzato.

**Titolo** (max 80 caratteri):

```
Show HN: MRRDock – free macOS menu bar app that sums MRR across payment platforms
```

**Testo del post:**

```
I sell software on four platforms: a SaaS on Stripe, iOS apps through RevenueCat, a desktop
app on Paddle because of VAT, templates on Lemon Squeezy. Answering "how am I doing this
month?" meant four logins and a mental sum that ignored the fact three of them bill in
dollars.

MRRDock reads all of them, prices each subscription item by item, converts everything into
one currency and leaves the total in the menu bar. Stripe, RevenueCat, Paddle Billing, Lemon
Squeezy, Polar, Dodo Payments, Gumroad, plus any HTTPS endpoint of your own (which is how
Superwall, App Store Connect and Google Play fit in).

Two things I cared about more than features:

- No server. There is no MRRDock backend: the app calls your platforms directly from your
  Mac, keys live in the Keychain, and there is no account, no telemetry, no crash reporting.
  MIT licensed with no package dependencies, so the provider code is short enough to read
  before you paste a Stripe key into a desktop app (a restricted read-only key is enough).
- Honest arithmetic. Yearly plans divided by 12 using the average Gregorian month, trials
  counted but never billed, percentage coupons applied, fixed-amount coupons explicitly not
  applied, and usage-based prices flagged as "could not be priced" instead of guessed. Every
  rule is written down, so when MRRDock disagrees with a dashboard you can tell which one is
  simplifying.

macOS 14+, universal binary, signed and notarized.
brew install --cask simonsruggi/tap/mrrdock

Happy to answer anything about the per-platform APIs — the differences between them were the
interesting part of the project.
```

## Product Hunt

Lancio **martedì o mercoledì alle 00:01 PT** (09:01 CET): il ranking guarda le 24 ore dalla
pubblicazione, quindi partire a metà giornata butta via mezza finestra. Un prodotto si lancia
una volta sola.

- **Name:** MRRDock
- **Tagline** (max 60): `Your MRR from every payment platform, in the menu bar`
- **Topics:** Mac, Developer Tools, SaaS, Analytics, Open Source
- **Links:** sito `https://mrrdock.simoneruggiero.com`, repo GitHub
- **Media:** `screenshots/overview.png`, `by-source.png`, `sources.png`, `add-source.png`,
  più l'OG image (`mrrdock-website/public/og.png`) come prima immagine.

**Description:**

```
MRRDock is a free, open-source macOS menu bar app that adds up your monthly recurring revenue
across Stripe, RevenueCat, Paddle, Lemon Squeezy, Polar, Dodo Payments, Gumroad and any custom
HTTPS endpoint, converts it into one currency and keeps the total one glance away.

Several accounts of the same platform are supported, so two Stripe accounts and three
RevenueCat projects add up like anything else. Seven menu bar modes (MRR, 30-day change, ARR,
28-day revenue, active subscriptions, one source at a time, icon only), a trend chart backfilled
from your provider's own MRR series, Discord and Slack milestone alerts, and a privacy mode that
hides every figure for screen sharing.

No account, no server, no subscription: API keys are stored in the macOS Keychain and your
revenue data never leaves your Mac. MIT licensed, no package dependencies, signed and notarized.
```

**Primo commento (maker comment):**

```
Hi PH — I ship a SaaS and a handful of iOS apps, which means my revenue is spread across four
platforms that each bill in their own currency. I built MRRDock because I was opening four
dashboards a day to do arithmetic.

Two decisions are worth calling out. First, there is no backend: the app talks to Stripe,
RevenueCat and the rest directly from your Mac, keys in the Keychain, no account, no analytics.
Nobody — including me — can see your numbers. Second, the MRR rules are written down: yearly
plans divided by twelve, trials counted but not billed, usage-based prices flagged rather than
guessed. When MRRDock disagrees with a dashboard, you can see which one is simplifying.

It's free and MIT licensed, and new providers are a small PR (one case in an enum, one protocol
implementation, one parsing test). Happy to answer anything.
```

## Reddit

Niente link nudi: su queste community il post che funziona racconta il problema. Un subreddit
al giorno, non tutti insieme.

- **r/macapps** — titolo: `I built a free, open-source menu bar app that shows my MRR from
  Stripe, RevenueCat, Paddle and four other platforms`. Corpo: versione breve del testo HN,
  con screenshot e la riga `brew install`.
- **r/SaaS** e **r/indiehackers** — angolo diverso, quello dei numeri che non tornano:
  perché i dashboard MRR non concordano mai (prorate, tasse, coupon a importo fisso, prezzi
  a consumo) e quali regole ha scelto MRRDock. Il link va in fondo.
- **r/swift** / **r/SwiftUI** — angolo tecnico: app menu bar SwiftUI senza dipendenze, sette
  provider dietro un solo protocollo, chiavi nel Keychain, 37 test sulla logica pura.

## Indie Hackers

Product page su <https://www.indiehackers.com/products> + un post in "Building in public"
che riusa il testo HN. Il profilo prodotto va compilato con il sito, non con il repo.

## AlternativeTo

Serve l'account (nessuna API pubblica): accedere, icona utente in alto a destra →
**Suggest new application**. Campi: piattaforma macOS, licenza Open Source / Free,
descrizione (quella di Product Hunt accorciata), tag `mrr`, `saas`, `menu-bar`,
`revenue-tracking`. Dichiarare MRRDock come alternativa a **Baremetrics**, **ChartMogul**,
**ProfitWell**, **CatBar** e **IndieBar**: sono quelle pagine — non la nostra — a rankare per
"X alternative", ed è da lì che arriva il traffico.

Una nuova app resta in coda mesi; 5 $ una volta la spostano in testa.

## Già fatto (12/09/2026)

- PR alle due awesome list che contano: [open-source-mac-os-apps#1367](https://github.com/serhii-londar/open-source-mac-os-apps/pull/1367)
  (50k stelle) e [awesome-mac#2856](https://github.com/jaywcjlove/awesome-mac/pull/2856)
  (113k stelle, voce in en/zh/ja/ko accanto a StockDock).
- Sito su <https://mrrdock.simoneruggiero.com> (JSON-LD SoftwareApplication + FAQPage,
  llms.txt, sitemap in Search Console, IndexNow a ogni deploy).
- Social preview del repo, campo *homepage*, description e topic rifatti.
- Post Medium: <https://medium.com/@simonsruggi/i-built-a-free-macos-menu-bar-app-that-shows-my-mrr-across-every-payment-platform-78997b76a2f3>

## Da fare quando arrivano le stelle

- 225 stelle (o 90 fork/watcher) → PR su `Homebrew/homebrew-cask` per
  `formulae.brew.sh/cask/mrrdock`. Dichiarare l'uso di AI/LLM nella PR, come chiede il
  CONTRIBUTING di Homebrew, e non metterlo come co-autore del commit.
- Cross-post del pezzo Medium su dev.to con `canonical_url` verso Medium.
- Pin del repo sul profilo GitHub: si fa solo da UI, l'API non lo espone.
