<p align="center"><sub><b>English</b> · <a href="README.tr.md">Türkçe</a></sub></p>

<h1 align="center">
  <img src="docs/icon.svg" alt="" width="44" valign="middle" />
  &nbsp;Meridian Mobile
</h1>

<p align="center"><i>Your life, beautifully organized — now in your pocket.</i></p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white" alt="Flutter 3.44">
  <img src="https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white" alt="Dart 3.12">
  <img src="https://img.shields.io/badge/Riverpod-3-4E56A6" alt="Riverpod 3">
  <img src="https://img.shields.io/badge/i18n-T%C3%BCrk%C3%A7e%20%C2%B7%20English-D4A853" alt="Türkçe · English">
  <img src="https://img.shields.io/badge/Android-8.0%2B%20(API%2026)-3DDC84?logo=android&logoColor=white" alt="Android 8.0+">
  <a href="https://github.com/hamzagedikkaya/meridian"><img src="https://img.shields.io/badge/server-Meridian%20(Rails%208)-CC0000?logo=rubyonrails&logoColor=white" alt="Meridian server"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20NC%201.0.0-blue" alt="License"></a>
</p>

<p align="center">
  <a href="#-highlights">Highlights</a> ·
  <a href="#-quick-start">Quick start</a> ·
  <a href="#-architecture">Architecture</a> ·
  <a href="#-design-system">Design</a> ·
  <a href="#-api-surface">API</a> ·
  <a href="#-tests">Tests</a>
</p>

---

Meridian Mobile is the Flutter client for [**Meridian**](https://github.com/hamzagedikkaya/meridian) — the self-hosted, local-first personal life OS. It talks to *your* Rails server over *your* Wi-Fi: no cloud tenant, no third-party analytics, no account to create. Point the app at `http://192.168.1.20:3000`, sign in, and your money, habits, goals and journal are on your phone.

Android-first, dark by default, fully bilingual — every screen speaks **Turkish and English**, switchable from the app and remembered on your account. Every number is rendered from integer cents with the right subunit per currency, in the notation the language expects.

<p align="center">
  <img src="test/golden/images/en/login.png" alt="Two-step login" width="24%" />
  <img src="test/golden/images/en/today.png" alt="Today — the day at a glance" width="24%" />
  <img src="test/golden/images/en/habits.png" alt="Habits" width="24%" />
  <img src="test/golden/images/en/goals.png" alt="Goals" width="24%" />
</p>

<p align="center"><sub>Real renders from the golden harness — bundled fonts, realistic fixtures, phone metrics (360×780 @3x). <a href="#-tests">See Tests</a>.</sub></p>

## ✨ Highlights

Five tabs, one per domain — plus a pushed profile stack.

### ☀️ Today — the day, in one scroll
Time-aware greeting over the month's net in Fraunces display numerals, with a 7-day spending sparkline underneath. Three stat chips (streaks · open todos · weekly habit rate) that deep-link into their own tab. Today's events and due todos share one card — priority shows as a quiet 3dp edge bar, overdue dates turn red, and checking a todo animates instantly, offers **Undo** for six seconds (until dismissed, while a screen reader is on), and reconciles with the server afterwards (tapping a checked row reopens it). Below that: today's habits with tap-to-complete rings — a daily habit done several times a day goes up one per tap (`/home` does not say how often a habit repeats, so the Habits list is read once for it; until then a ring is simply done or not), and a long-press (or a tap on a full ring) opens the day's log to step it back or reset it — and the top three goals with paced progress bars. The ⚡ icon opens **quick capture** — one field that routes `-250 coffee` / `+1500 salary` to a transaction, `habit: run` / `alışkanlık: koşu` to a habit log, and anything else to a todo. The confirmation says what was saved (`Expense added · −250,00 ₺ · coffee`); a line that names a day (`tomorrow 15:00 dentist`) saves nothing and says so, offering to save it as a task instead; and a refusal stays in the sheet with its next step — create the account a money line needs, or the habit a `habit:` line names. A capture whose answer never came back may have been saved, so the sheet says that instead of offering a blind retry, which could save it twice. Overdue todos surface as a red count badge on the tab itself.

### 💰 Finance — money without the spreadsheet
Month/year segmented hero with the income–expense split. Accounts are a snapping card carousel, each rendered in its own currency (`412 gr` for gram-gold, `1.234,56 ₺` for lira) with a Hero flight into account detail. Then a six-month grouped income/expense bar chart, a category donut with tap-to-drill-down breakdown sheet, and budget rows with a **pace tick** — the vertical mark showing where you *should* be today — plus a month-end projection line when you're outrunning the budget. Upcoming subscriptions and recent transactions close the screen.

**Transactions** is the full feed: sticky filter chips (kind · account · category · date range), day-grouped headers (`Today` / `Yesterday` / `12 July`), infinite scroll, swipe-left-to-delete with confirmation, and a detail sheet with edit/delete. Creating a transaction is **amount-first**: a giant serif figure driven by a custom 4×3 keypad, then account, category, date, description — with the decimal key hidden for gram-gold accounts.

### 🔥 Habits — streaks that mean something
A "2 / 5 done" progress bar, a 30-dot **perfect-day chain**, then one card per habit: streak, 30-day completion rate, a 14-day chain strip, and either a tap ring or a `− 5/8 +` counter pill (a daily habit done several times a day). A weekly or monthly habit counts *days* toward its period, so its day is a ring and its pill shows the week or month. Every tap sends the count it shows, never a flip, so a screen that is out of date cannot turn a habit the wrong way; ticks apply optimistically and roll back with a snackbar that says why if the server refuses — and a habit archived on the web meanwhile drops from the lists instead of being refused tap after tap. Completing the last habit of the day fires the app's only confetti burst — 12 hand-painted particles, once. Habit detail adds an 84-day heatmap and archive.

### 🎯 Goals — progress you can see
Two-column cards with animated progress rings, a type overline (`FINANCIAL` / `HABIT` / `CUSTOM`) and colour-coded deadline badges (`3d late`, `today`, `5d left`). Achieved goals collapse into their own section. Detail flies the ring in as a Hero and shows the right panel for the type: a `−10 −1 +1 +10` stepper for custom goals, the linked streak and day count for habit-linked ones, and recalculate-from-balance for financial ones.

### 📓 Journal — a calm place to write
Range pill (7d / 30d / 6mo / 1y / All), a mood distribution strip you can **tap to filter**, then Day One-style entry cards: date block in Fraunces, mood emoji, energy as five dots, tag pills, and a gratitude marker. Detail renders the server's rich text. The editor opens with a mood check-in, autofocuses the body, and autosaves a draft every 5 seconds.

### 👤 Profile — yours, and the server's
Theme (dark / light / system), **language (Türkçe / English)**, currency, live API status, app version — and a dedicated **server page** that pings `/health` and reports `✓ Connected · Meridian v1.0.0 · 38 ms`. Saving an unreachable URL asks for confirmation. Logout wipes the token and the account state, keeping only the server address, language and theme so the login screen still looks like yours.

<p align="center">
  <img src="test/golden/images/en/finance.png" alt="Finance dashboard" width="24%" />
  <img src="test/golden/images/en/transactions.png" alt="Transaction feed" width="24%" />
  <img src="test/golden/images/en/journal.png" alt="Journal" width="24%" />
  <img src="test/golden/images/en/profile.png" alt="Profile and settings" width="24%" />
</p>

<p align="center"><sub>Finance · Transactions · Journal · Profile</sub></p>

### Cross-cutting behaviour
| | |
|---|---|
| **Bilingual, end to end** | Two typed string sets (`lib/l10n/`), an abstract contract the analyzer enforces, and a switch in Profile that re-renders the app immediately. The choice is stored on the device *and* pushed to the account, so the web app and a reinstall follow. Turkish is the default; the phone's language is used on first run when it is one of the two. |
| **Language-correct numbers** | `%82` in Turkish, `82%` in English. `1.234,56 ₺` vs `1,234.56 ₺`. `75B` vs `75K` on chart axes. `27 Ağustos` vs `August 27`. One `Intl.defaultLocale`, kept in sync by the localization delegate. |
| **Offline honesty** | A failed refresh keeps the last good data on screen under a hairline banner — `Offline · last updated 12:40` with retry. The full-screen error state appears only when there is nothing cached to show. |
| **Optimistic writes** | Checks, counters and deletes update the UI first, then reconcile; failures roll back with an error snackbar. |
| **Skeletons, not spinners** | Every screen has a bone layout that mirrors its real geometry, cross-fading into content. No blocking dialogs anywhere. |
| **Money in one place** | Integer `*_cents` + per-currency `subunit_to_unit`, formatted by a single function. Gram-gold (`GAU`) has a subunit of 1, so it renders `412 gr` — never `4,12`. |
| **Signs, not just colours** | `+` for income in green, `−` for expense in default ink. Never colour-only — a wall of red is alarming, and colour alone fails for colour-blind users. |
| **Errors carry a reason, not a sentence** | The API layer raises a typed `ApiErrorKind`; the UI turns it into copy in the active language. Server-side validation messages are shown as-is — Rails already localizes them per user. |
| **Haptics** | A four-level map: tick on selection, light on success, medium on celebration, heavy on destructive confirm. Silent no-ops on web. |

## 🧰 Tech Stack

| Layer | Choice |
|---|---|
| Framework | Flutter 3.44 · Dart 3.12 (Material 3) |
| State | `flutter_riverpod` ^3.3.2 — no codegen; `AsyncValue` with last-good retention |
| Routing | `go_router` ^17.3.0 — `StatefulShellRoute.indexedStack`, 5 branches, root-level modal routes |
| Networking | `dio` ^5.10.0 — Bearer interceptor, `401` → sign-out, errors normalised to one `ApiException` |
| Localization | typed string classes + a `LocalizationsDelegate` (no `.arb`, no codegen) · `flutter_localizations` |
| Storage | `flutter_secure_storage` ^10.3.1 (token bound to its server, journal drafts) · `shared_preferences` ^2.5.5 (server URL, language, theme) |
| Charts | `fl_chart` ^1.2.0 — donut, sparkline, grouped six-month bars |
| Motion | `animations` ^2.2.0 (fade-through) · `flutter_animate` ^4.5.2 (entrance staggers only) |
| Loading | `skeletonizer` ^2.1.3 |
| Rich text | `flutter_widget_from_html_core` ^0.17.2 — journal `body_html` |
| Formatting | `intl` ^0.20.2 — money, dates and month names per locale |
| Type | Fraunces + Inter bundled as `.ttf` under `assets/fonts/` — no runtime font fetch |
| Quality | `flutter_lints` ^6.0.0 · `flutter_test` · `matchesGoldenFile` |

## 🚀 Quick Start

**Requirements** — Flutter 3.44+ stable (Dart 3.12+), Android SDK with API 26+ for a device build, and a running [Meridian](https://github.com/hamzagedikkaya/meridian) server exposing `/api/v1`.

```bash
git clone https://github.com/hamzagedikkaya/meridian-mobile.git
cd meridian-mobile
flutter pub get
flutter run                 # Android device or emulator
```

For the layout/data preview in the browser:

```bash
flutter run -d chrome --web-browser-flag=--disable-web-security
```

> The Meridian server ships no CORS middleware, so the browser preview needs that flag (or a dev-only `rack-cors`). Native builds are unaffected.

### Connecting to your server

The address field on the login screen prefills sensibly and remembers your last choice:

| Where you run it | Prefilled address |
|---|---|
| Chrome (web preview) | `http://localhost:3000` |
| Android emulator | `http://10.0.2.2:3000` |
| Physical device | last used — enter your machine's LAN IP, e.g. `http://192.168.1.20:3000` |

Type the address, wait for the ✓, then sign in with any Meridian user — the server's seeds create `demo@meridian.local`, whose password you set when you seeded it. The credentials section stays dimmed until the health ping succeeds, so a wrong address can never look like a wrong password.

Cleartext `http://` to a LAN server is enabled through `network_security_config.xml` in the **main** manifest, so debug and release builds both reach a bare LAN IP. That's a deliberate trade-off: anyone on the same network can read the traffic, bearer token included. Put the server behind HTTPS (a reverse proxy with a local CA, or Tailscale) and set `cleartextTrafficPermitted` to `false` to close it.

Release builds are signed only with your own key: create one with `keytool`, then write `storeFile`, `storePassword`, `keyAlias` and `keyPassword` into the gitignored `android/key.properties`. Without it the release APK stays unsigned and won't install — it never falls back to the debug keystore.

### Everyday commands

```bash
flutter analyze                                          # static analysis — currently clean
flutter test                                             # unit + widget suites
flutter test --run-skipped test/golden                   # compare the screenshots
flutter test --run-skipped --update-goldens test/golden  # refresh both sets
flutter build apk --release                              # sideloadable APK
```

## 🧱 Architecture

```
lib/
├─ main.dart          ProviderScope + MaterialApp.router, all intl locales loaded
├─ core/              api.dart          dio factory, Bearer interceptor, ApiErrorKind
│                     session.dart      token store, server URL, auth state machine, /health
│                     locale_mode.dart  UI language: device choice → account → phone → tr
│                     theme_mode.dart   dark/light/system, resolved the same way
│                     formats.dart      money, dates, decimals — value shaping only
│                     haptics.dart      the four-level haptics map
├─ l10n/              app_l10n.dart     the abstract contract + delegate + context.l10n
│                     app_l10n_tr.dart · app_l10n_en.dart   one class per language
├─ models/            immutable models: lenient fromJson + pure optimistic patches — one file per domain
├─ data/              repository.dart   one async method per endpoint; writes say what they change
│                     providers.dart    Riverpod providers → AsyncValue<Fetched<T>>
│                     sync.dart         change → cached screens table, DataSync, refresh helpers
│                     actions.dart      optimistic habit / todo writes (explicit state) with rollback
│                     current_day.dart  the account's today, rolled over at its midnight
├─ theme/             app_colors.dart   Noktürn tokens as a ThemeExtension (dark + light)
│                     app_typography.dart · app_theme.dart
├─ router/            app_router.dart   shell branches, auth redirect, fade-through pages
└─ ui/
   ├─ widgets/        two dozen shared pieces: NokturnCard, NokturnRow, MoneyText,
   │                  ProgressRing, PacedProgressBar, AmountKeypad, PickerSheet…
   └─ screens/        today · finance · habits · goals · journal · profile · shell
                      (+ login, splash) — each with its own widgets/ folder
```

Routes mirror the folders — `/today`, `/finance`, `/finance/transactions`, `/habits`, `/goals/:id`, `/journal/:id`, `/profile/server` — so the code stays in one language while the UI speaks two.

**Localization.** `AppL10n` is an abstract class with one member per string; `AppL10nTr` and `AppL10nEn` implement it. A new string that is only written in one language does not compile, which is the whole point — there is no runtime fallback to silently hide a gap. API values (`mood`, `account_type`, `frequency`) are mapped by small `switch` methods rather than stored copy, and the delegate keeps `Intl.defaultLocale` in step so `core/formats.dart` shapes numbers and dates for the active language without threading a locale through the tree.

**The read path.** A screen watches a provider, which asks the repository, which calls dio. Providers return `Fetched<T>` — the data plus the timestamp it arrived — and Riverpod 3 carries the previous value through a refetch and through a failed refresh. What a screen draws is decided by one rule, `AsyncScreenState` (`ui/widgets/sync_hint.dart`), the same on every screen: data on screen is never replaced while newer data loads (`isRefetching` only adds a thin progress line); a skeleton only for `isFirstLoad`, before anything was ever shown; the full error view only for `hasFailed`, when the load failed and there is nothing to show; and the offline banner, with the time of the last good data, only for `refreshFailed` — data is on screen and its last refresh failed. The one quick retry runs inside each fetch (`retried` in `data/providers.dart`; Riverpod's own retry is off for read models), so a screen only ever sees a fetch's outcome: a blip the retry heals never flashes the banner, and a failure once shown — banner or error view — stays up through every retry that fails again, until one lands. The cache is per session and in memory; nothing is persisted to disk.

**The write path.** Every write goes through the repository, which reports what it changed — transactions, habit check-ins, goals, todos, journal entries — to `DataSync` (`data/sync.dart`). One table there maps each kind of change to every cached screen whose server data depends on it: `/home` folds transactions, habit logs, todos and goals together, the finance dashboard sums transactions, and goals recalculate from balances and check-ins. `/home` shows each goal's progress as the server stored it the last time the goals were read, so whenever both are due the goals are read alongside `/home` — neither waits for the other — and `/home` is asked once more if the recalculation moved a goal it shows: a check-in or a transaction moves Today's goal bars too. Exactly those screens refetch — visible ones at once, hidden tabs the moment they are shown — so no screen decides what to refresh, and a write still refreshes everything when its form was closed before the server answered. Ticking a habit or a todo patches the cache first, so Today and Habits flip in the same frame, and rolls back if the server refuses. The tap's result is worked out once, from what was on screen, and both the patch and the request *state* it — a habit day's count (`PUT /habits/:id/logs/:date`), a todo done or not (`done: true|false`) — rather than toggling: a refetch that already has the tap in it stays as it is, a retried request lands on the same state, and a screen that is out of date can never flip a habit or reopen a todo by mistake. The patch stays pending until a refetch that left after the server's answer lands: a refetch already in flight is shown with the tick applied to it — its news kept, the tick never flicking back — and quick taps on one habit are sent in order rather than dropped. A tap leaves the rest of the screen as it was — a refetch on its way keeps its progress line, a failed refresh its banner — and an answer that belongs to another day than the list's (a tick sent just before midnight) is left out of it.

**Staying fresh.** The same place refreshes on app resume (after 30 s away), on a re-tap of the current tab (which also scrolls it to the top), at the account's midnight, and when a screen is shown again with data older than a minute — edits made on the web turn up without a pull. A detail screen that finds its record deleted elsewhere (a `404`) says so — rather than the offline banner, whose retry could only get another `404` — and refetches every list that still shows it, so going back never lands on a ghost row. A refresh never blanks a screen: the current data stays up under a thin progress line, a skeleton appears only before anything was ever shown, a failed screen keeps its error view (and a stale one its banner) while a retry runs, and a failure surfaces in seconds (one quick retry per fetch, for a dropped connection or a 5xx only, never Riverpod's default 40–90 s of silent retries). The transactions feed is an `AsyncNotifier` keyed by an immutable `TxFilters` record, so the feed and account detail can paginate side by side without sharing state; a refresh reloads the first pages — up to five, 250 rows — and keeps the rows loaded beyond them, so a long scroll keeps its length and its place; an edit or a delete made in the app is applied to its row wherever it is — an edit that moves a row to another day moves it there, also past the reloaded pages — and infinite scroll pages on from the rows on screen, so it never skips one.

**Time zones.** The server counts days in the account's time zone (`user.timezone`): Today's habits, todos due today, month totals, the journal's ranges. The phone's own zone can differ — a trip abroad, a phone set to UTC — so the app follows the account's zone, from the offset `/me` reports: "today", the midnight refresh, `Today`/`Yesterday` labels and the default date of a new record are the account's, and every server datetime is shown as the account's wall clock (it arrives with the account's offset; the app reads the date and time as written instead of converting to the phone's zone). A "today" write sends the date the server reported, never the phone's. When the two zones differ, Today says which zone days and times follow (dismissible) and Profile shows both. Only the greeting follows the phone's clock — it is about the person, not the records.

**Auth.** The splash gate reads the token, routes optimistically, and probes `/me` in the background; a `401` from anywhere trips the dio interceptor, wipes the token and ejects to login with a notice. `go_router`'s redirect is driven by a three-state session machine (`unknown` → `loggedOut` / `loggedIn`), so there is exactly one place that decides where you land.

## 🎨 Design System

The visual language is **Noktürn** — warm-dark private banking crossed with Day One. Deep espresso blacks (never pure `#000`), one disciplined gold reserved for emphasis and primary actions, serif display type for hero numbers. Full specification, including every token and screen: [`docs/design.md`](docs/design.md).

<p align="center">
  <img src="https://img.shields.io/badge/-%23171310-171310?style=flat-square" alt="#171310 bg">
  <img src="https://img.shields.io/badge/-%231E1915-1E1915?style=flat-square" alt="#1E1915 surface1">
  <img src="https://img.shields.io/badge/-%23D4A853-D4A853?style=flat-square" alt="#D4A853 gold">
  <img src="https://img.shields.io/badge/-%23EFE9DF-EFE9DF?style=flat-square" alt="#EFE9DF inkHi">
  <img src="https://img.shields.io/badge/-%236FC08D-6FC08D?style=flat-square" alt="#6FC08D income">
  <img src="https://img.shields.io/badge/-%23E07862-E07862?style=flat-square" alt="#E07862 error">
  <img src="https://img.shields.io/badge/-%23E39A4E-E39A4E?style=flat-square" alt="#E39A4E warning">
</p>

- **Colour** — 26 named tokens per theme, exposed as a `ThemeExtension` and read with `context.nok`. Gold never means good or bad; it means *yours*. Green and red stay strictly semantic, which is what keeps the gold precious.
- **Elevation** — surface steps plus 1dp hairlines, never shadows. `bg` → `surface1` (cards) → `surface2` (nav, inputs, chips) → `surface3` (sheets, dialogs).
- **Type** — Fraunces 600 for display and headings, Inter for everything else. All amounts use tabular figures so columns never wobble in either language.
- **Motion** — 350ms `easeOutCubic` by default, no springs. Fade-through between tabs, 400ms slide-up for create/edit modals, exactly two Hero flights in the whole app, and one deliberate overshoot: the check-off pop. Hero numbers count up on first load and cross-fade on refresh — a refresh that re-animates its numbers is lying about what changed.
- **Light theme** — a full second palette on warm paper, with gold darkened to `#96731D` to hold AA contrast.

## 🔌 API Surface

All endpoints live under `/api/v1`, authenticated with `Authorization: Bearer <api_token>`. Money always crosses the wire as integer `*_cents` alongside the currency's `subunit_to_unit`.

| Endpoint | Feeds |
|---|---|
| `GET /health` | login ping and server settings test (unauthenticated; the client times it itself) |
| `POST /session` · `GET /me` | login, token validity probe, display name and preferences |
| `PATCH /me` | the language and theme chosen on the phone, stored on the account |
| `GET /home` | the entire Today screen in one round trip |
| `GET /finance/dashboard` · `GET /accounts` | Finance: net, six-month series, category pie, budgets, subscriptions, recents |
| `GET/POST/PATCH/DELETE /transactions` · `GET /finance_categories` | the transaction feed, filters, create/edit/delete |
| `GET /habits` · `PUT /habits/:id/logs/:date` · `archive` | habit cards, chains, perfect-day strip, optimistic ticks set to an explicit count |
| `GET /goals` · `PATCH /goals/:id/update_progress` · `recalculate` | goal cards, rings, per-type actions |
| `GET/POST/PATCH/DELETE /journal_entries` | journal list, detail (`body_html`), editor |
| `GET /todos` · `PATCH /todos/:id/toggle` (`done`) · `GET /events` | the Today card and todo sheet |
| `POST /quick_captures` | the ⚡ one-field router (`as: "todo"` to save a line as a task) |

Error contract: every refusal carries a stable `code` — `401 unauthorized` → sign-out · `404 not_found` · `422 validation_failed` with `details` per field, or a named refusal (`no_account`, `unknown_habit`, `future_date`, `invalid_amount` with its `reason`, …). The app words every code itself, in the active language, and a validation detail under the field it is about — never the server's raw sentence. A failed action says why when the server said why, and what did not happen otherwise; network failure says what to check: *"Can't reach the server — make sure you're on the same Wi-Fi network."*

## 🧪 Tests

```bash
flutter analyze                          # no issues
flutter test                             # 348 tests, golden suite skipped
flutter test --run-skipped test/golden   # 16 screenshots, both languages
```

| Suite | What it covers |
|---|---|
| [`test/models_test.dart`](test/models_test.dart), [`test/models/`](test/models/) | every payload shape → model, including nulls, envelopes, multi-currency accounts and the integer counts of a partial habit day; the optimistic patches mirror what the server stores for a day's count; datetimes read as the account's wall clock |
| [`test/data/`](test/data/) | the refresh architecture against a fake API: each kind of write refetches exactly the screens whose data it changed, failed writes, writes in flight, taps that land while a refetch is on its way, the account's midnight (across daylight-saving changes too, and with the phone in another zone than the account, both checked in a second Dart VM under other time zones), resume, explicit-state writes, quick capture's answers, and pagination that survives a refresh without moving the list |
| [`test/core/`](test/core/) | the error shape: every `code` worded in both languages, validation details per field, and when a failed action says why |
| [`test/formats_test.dart`](test/formats_test.dart) | money and date shaping: TRY, USD, and gram-gold's subunit-of-1 rule |
| [`test/l10n_test.dart`](test/l10n_test.dart) | the localization layer: locale resolution, percent placement, grouping and month order per language, relative days, API-value maps, and the error contract in both languages |
| [`test/screens/`](test/screens/), [`test/widgets/`](test/widgets/) | widget smoke tests per screen with overridden providers — populated *and* empty states, plus switching the app to English at runtime; tab re-taps, switching back to Today, app resume, and ticks that never flick back; heroes when a route opens over the tabs; detail screens whose record was deleted elsewhere; the one skeleton / data / error-view rule against a real read model and its quick retry; quick capture's answers (what was saved, a line that saved nothing, refusals with their next step); Today's undo and the day's habit log; the time-zone notice; a long feed that keeps its place through a refresh |
| [`test/golden/`](test/golden/) | all eight screens rendered at 360×780 @3x **in both languages**, with the real bundled fonts and translated fixtures |

The golden suite is a **visual review harness**, not a pass/fail gate. Its fixtures are relative to now (`Today`, `Yesterday`, `5d left`) so the screenshots look like a live phone — which also means they drift as the clock moves. It is therefore tagged `golden` and skipped by default (`dart_test.yaml`), keeping `flutter test` deterministic; run it deliberately with `--run-skipped` and refresh with `--update-goldens`. Its data is translated alongside the UI, so `images/en/` reads like an English user's phone rather than an English shell over Turkish content. Emoji glyphs fall back to boxes in the test renderer — they render normally on a device.

## 🗺 Roadmap

Shipped: the five tabs, Turkish/English UI with an in-app switch, transaction create/edit/delete, habit and goal writes, journal editor, quick capture, profile and server settings.

Not there yet:

- **Account create/edit** — the Finance screen says adding accounts is coming soon, and means it
- **Standalone todo and agenda pages** — todos are read and toggled from the Today sheet; events are read-only
- **Web-only modules** — calendar, insights, weekly review, backups and global search stay on the Rails app for now
- **Release polish** — the launcher icon and splash are still Flutter defaults, and there is no CI workflow
- **Disk cache** — last-good data is in-memory per session; a cold start with no server shows the empty state

## 📄 License

Meridian Mobile is part of the Meridian project and is released under the [**PolyForm Noncommercial License 1.0.0**](LICENSE) — the same terms as the server. Personal, research and educational use is free; commercial use is not granted by this license. Open an issue if you'd like to discuss a separate arrangement.

---

<p align="center"><sub>Meridian Mobile — your life beautifully organized, on your own network.</sub></p>
