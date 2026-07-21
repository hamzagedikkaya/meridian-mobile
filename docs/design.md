# Meridian Mobile — Design Direction Decision

## Part 1 — Scorecard

Brand ground truth (verified in `/Users/user-hg/Documents/Personal/meridian/app/assets/tailwind/application.css`): warm near-black `#0A0908`, cream `#F5F1E8`, gold ramp seeded at `#B8860B`, desaturated income/expense `#6B8E5A`/`#B85450`, white-alpha hairline borders, **Fraunces display font** + DM Sans body. Team ground truth (memory): solo dev with zero mobile experience; dev preview is **Flutter Web in Chrome**, not an emulator; login → accounts slice already works.

| Criterion | C1 Noktürn (Sakin lüks) | C2 Kehribar (M3E) | C3 Akış (Akışkan minimal) |
|---|---|---|---|
| (a) Beauty / currency | **9** — quiet-luxury warm dark + serif display numerals is exactly where premium personal-finance design sits in 2026; disciplined gold keeps it from feeling themed | **8** — M3 Expressive is current but reads "stock Google 2025"; the springs are fresh, the tonal surfaces less distinctive | **8.5** — content-first monochrome with iOS physics is timeless and elegant, but slightly austere for a life-OS that includes journaling and streak celebration |
| (b) Usability | **8** — 5 tabs map 1:1 to the app's domains; amount-first keypad; quick capture in app bar; one weak spot: no error-state offline fallback | **7** — demoting Hedefler off the tab bar hurts a core domain's discoverability; the FAB menu adds a tap to every create action; otherwise solid | **8.5** — 5 tabs, edge-to-edge lists, offline cached-data banner, swipe-to-delete; long-press stepper sheet for multi-count habits is slightly hidden |
| (c) Feasibility (Flutter stable, small team) | **8** — standard curves/widgets only, springs deliberately rejected, custom bits (keypad, chain strips, one confetti) are small CustomPainters; no unvetted packages | **6** — six items flagged [MANUAL], three "vet first" packages (`material_new_shapes`, `m3e_collection`, `expressive_loading_indicator`), spring-driven bottom sheets and shape morphs — a lot of physics engineering for a first-time mobile dev | **8** — springs are used but scoped; `OpenContainer` is off-the-shelf; painters small. Spring-driven sheet settle is the one fiddly bit |
| (d) Brand fit (gold-on-warm-dark) | **10** — Fraunces is *literally* the web's display font; espresso surfaces sit in the same warm family as `#0A0908`; gold `#D4A853` ≈ web accent-300/400 (correct dark-mode lift of the `#B8860B` seed); hairline-not-shadow matches web borders | **7** — warm charcoal + gold, yes, but Manrope + tonal M3 geometry abandons the serif signature that makes Meridian look like Meridian; brightest gold of the three drifts toward generic amber | **8** — white-alpha hairlines are an exact match to the web's border system and terracotta expense `#E07B6B` is close kin to web `#B85450`, but Inter-only drops the Fraunces signature |
| (e) Coherence / completeness | **9** — every value resolved, full API contract with error shapes, motion + haptics tables, GAU handled everywhere | **8** — thorough, but "vet first" and "or custom grid" leave open choices, which is exactly what this brief penalizes | **8.5** — complete and internally consistent; a couple of "or" choices (heatmap widget, HTML renderer) |
| **Total** | **44** | **36** | **41.5** |

## Part 2 — Verdict and grafts

**Winner: Concept 1 "Noktürn".** It is the only concept that keeps the product looking like Meridian (Fraunces + warm espresso + disciplined gold), it is the most buildable by this specific team, and it is the most fully resolved.

**Grafted from Concept 2 (Kehribar):** (1) the 6-month grouped income/expense bar chart on the Para screen — Noktürn shipped the `SixMonthBars` widget and API field but forgot to place it; (2) the budget projection note "Ay sonu tahmini: ₺X" when over-pace; (3) tappable deep-linking stat chips on Bugün; (4) the collapsed server row after successful ping on login ("✓ 192.168.1.20:3000", tap to re-edit); (5) mood-strip tap-to-filter on Günlük; (6) error presented as an inline retry card (never a full-screen takeover) when any cached data exists.

**Grafted from Concept 3 (Akış):** (1) the offline banner "Çevrimdışı · son güncelleme HH:mm" over cached last-good data; (2) swipe-left-to-delete on transaction rows (with confirm); (3) latency readout on the server connection test ("Bağlandı · 38 ms"); (4) todo priority as a quiet 3dp left edge bar instead of pills; (5) `PressableScale` press feedback on tappable cards (re-tempered to a curve, no spring); (6) the concrete Android config details (minSdk 26, target API 36, `enableOnBackInvokedCallback`); (7) `kIsWeb`-aware default server URL (web → `localhost:3000`); (8) "no counting animation on refresh — data honesty" rule made explicit.

**Deliberately rejected:** Kehribar's FAB menu, spring physics system, shape morphs, and unvetted M3E packages (feasibility); Akış's Inter-only typography (brand); Kehribar's 4-tab structure (usability). One resolved deviation from the web brand: body font is **Inter, not DM Sans**, because Inter has guaranteed `tnum` tabular figures and this app is numeral-dense; Fraunces carries the brand signature.

---

# FINAL DESIGN DOCUMENT — Meridian Mobile: **"Noktürn" v1.1**

Android-first, dark-primary, Turkish UI, self-hosted Rails API over LAN. Dev preview runs as Flutter Web in Chrome; release target is a sideloaded Android APK. Every value below is final.

## 1. Design Language: Noktürn

Warm-dark private banking crossed with Day One: deep espresso blacks (never pure `#000`), a single disciplined gold reserved for emphasis and primary actions, serif display type (Fraunces — the same display face as the Meridian web app) for hero numbers and headings over a quiet Inter body. Nothing shouts — motion is slow and settled (300–400ms, easeOutCubic, no springs, no overshoot except one check-off pop), charts are understated and desaturated, and green/red are used strictly semantically so the gold stays precious. Elevation is expressed by surface steps and 1dp hairlines, never shadows (dark theme). Gold never means "good/bad"; it means "yours".

## 2. Design Tokens

### 2.1 Dark palette (primary theme)

| Token | Hex | Use |
|---|---|---|
| `bg` | `#171310` | Scaffold canvas |
| `surface1` | `#1E1915` | Cards, list containers |
| `surface2` | `#262019` | Elevated cards, bottom nav, chips, input fill |
| `surface3` | `#2D2620` | Bottom sheets, dialogs, snackbars |
| `hairline` | `#322A22` | 1dp card/list borders (replaces shadow) |
| `divider` | `#2A231C` | In-list separators |
| `inkHi` | `#EFE9DF` | Primary text, default amounts |
| `inkMid` | `#B3A895` | Secondary text, metadata |
| `inkLow` | `#7A7060` | Tertiary, placeholders, disabled labels |
| `inkFaint` | `#4E463B` | Disabled icons, skeleton bones base |
| `gold` (primary) | `#D4A853` | Primary CTA fill, active tab, FAB, progress fills |
| `goldBright` | `#E7C883` | Pressed-state text on dark, streak flame, focus ring |
| `goldDim` | `#8C6D2C` | Inactive gold accents, rest-state track fills |
| `onGold` | `#221805` | Text/icon on gold fills |
| `goldContainer` | `#3B2F14` | Selected chip bg, gold icon circles |
| `onGoldContainer` | `#EBD9A9` | Text on goldContainer |
| `income` | `#6FC08D` | Income amounts (+ prefix), positive deltas |
| `incomeContainer` | `#17301F` | Income icon circles, positive pills |
| `error` | `#E07862` | Over-budget, overdue, destructive, validation |
| `errorContainer` | `#351E19` | Error pill bg |
| `warning` | `#E39A4E` | Budget :warning state, deadline ≤7d badges |
| `warningContainer` | `#33240F` | Warning pill bg |

**Rules:** expense amounts render in `inkHi` with explicit `−` prefix (a wall of red is alarming); `error` red only for over-budget, overdue, destructive. Income always `income` green with explicit `+`. Sign prefixes are mandatory — never color-only (color-blind safety).

**Chart palette (dark)** — 6 desaturated series, contrast-checked on `surface1`: `#C9A45C` (gold-1, always series #1), `#7FA3C0` (dusty blue), `#8FBF9F` (sage), `#B08FB3` (mauve), `#C98F7A` (clay), `#A8A86B` (olive). Six-month bar chart: income bars `#8FBF9F`, expense bars `#C9A45C`. Gridlines `#2A231C`, axis labels `inkLow` 11sp.

### 2.2 Light palette (secondary, `theme_preference` respected)

`bg #F6F1E8` (warm paper) · `surface1 #FCFAF5` · `surface2 #FFFFFF` · `surface3 #FFFFFF` (+shadow `BoxShadow(0,8,24, #26201908)`) · `hairline #E5DDCE` · `inkHi #262019` · `inkMid #5F574A` · `inkLow #8A8172` · `gold #96731D` (darkened for AA on paper) · `onGold #FFFFFF` · `goldContainer #F0E3C2` · `onGoldContainer #4A3A10` · `income #2C7A4F` · `error #B5432E` · `warning #A9631F`.

### 2.3 Surface hierarchy
`bg` → `surface1` (cards, 1dp hairline border, **no shadow**) → `surface2` (nav bar, inputs, nested chips) → `surface3` (sheets/dialogs; dark: no shadow; light: shadow above). No M3 surface-tint overlays — explicit hex per level.

### 2.4 Typography — Fraunces (display) + Inter (body), both bundled as .ttf assets via `google_fonts` (no runtime fetch)

| Role | Font | Size/Line | Weight | Tracking |
|---|---|---|---|---|
| displayLarge (hero money) | Fraunces | 40/46 | 600 | −0.5 |
| displayMedium | Fraunces | 32/38 | 600 | −0.25 |
| headlineLarge (screen titles) | Fraunces | 26/32 | 600 | 0 |
| headlineMedium (section heroes) | Fraunces | 22/28 | 600 | 0 |
| titleLarge | Inter | 18/24 | 600 | 0 |
| titleMedium (card/row titles) | Inter | 16/22 | 600 | 0 |
| titleSmall | Inter | 14/20 | 600 | +0.1 |
| bodyLarge | Inter | 15/22 | 400 | 0 |
| bodyMedium | Inter | 14/20 | 400 | 0 |
| bodySmall (row metadata) | Inter | 13/18 | 400 | +0.1 |
| labelLarge (buttons) | Inter | 14/20 | 500 | +0.1 |
| labelMedium (overlines, UPPERCASE) | Inter | 12/16 | 500 | +0.8 |
| labelSmall (badges) | Inter | 11/14 | 500 | +0.4 |

**Money rule:** all amounts Inter w600 with `FontFeature.tabularFigures()`. Hero money (dashboard net, account balance) uses Fraunces w600, tabular. All money formatted client-side from `*_cents / subunit_to_unit` per currency — **GAU has `subunit_to_unit: 1`** ("412 gr", never /100). TRY renders `1.234,56 ₺` (trailing symbol, Turkish convention); decimals at 0.7em/`inkMid` in hero contexts. `MoneyText` is the only place money math lives.

### 2.5 Spacing, radii, borders
- **Spacing (dp):** 4, 8, 12, 16, 20, 24, 32, 40. Screen horizontal padding **20dp**. Between cards 12dp; between sections 32dp; section header → content 12dp.
- **Radii:** cards 16; bottom sheets 24 top; dialogs 24; inputs 12; chips/badges 999; primary buttons 14; FAB 16; icon circles full. Plain circular radii only — no superellipse (web-renderer fallback risk).
- **Borders:** every `surface1` card gets `Border.all(hairline, 1)`. Focused input: 1.5dp `gold`.
- **Touch targets:** ≥48dp everywhere; list rows 64dp; habit check target 48dp.
- **Press feedback (grafted from Akış):** every tappable card/chip wraps in `PressableScale` — scale to 0.98 over 100ms easeOut on press, back over 150ms on release. Ripples (`gold` at 8%) only on list rows, not cards.

## 3. Navigation Architecture

**Bottom navigation — 5 tabs**, 64dp M3 `NavigationBar` on `surface2` with top hairline, `go_router 17.3.0` `StatefulShellRoute.indexedStack`:

| # | Turkish label | Icon (outlined → filled active) | Route |
|---|---|---|---|
| 1 | **Bugün** | `wb_sunny_outlined` → `wb_sunny` | `/bugun` |
| 2 | **Para** | `account_balance_wallet_outlined` → filled | `/para` |
| 3 | **Alışkanlıklar** | `check_circle_outline` → `check_circle` | `/aliskanliklar` |
| 4 | **Hedefler** | `flag_outlined` → `flag` | `/hedefler` |
| 5 | **Günlük** | `auto_stories_outlined` → filled | `/gunluk` |

Active tab: icon+label `gold`, 32×20dp `goldContainer` pill behind icon. Inactive: `inkLow`. Only badge: Bugün gets an `error`-colored numeric dot-pill for overdue todos when > 0.

- **Profile/settings:** 32dp initials avatar (`goldContainer` bg, gold initials) top-right of Bugün app bar → pushes `/profil`. Logout at the bottom of Profil, plain-styled, red only inside its confirm dialog.
- **No center FAB menu.** Each tab has its own gold FAB (specs in §4). Quick capture is a bolt icon in the Bugün app bar.
- **Sub-pages:** detail pages are pushed `GoRoute`s under the shell; create/edit forms are **full-screen modal routes** (`fullscreenDialog: true`, slide-up) above the shell (`parentNavigatorKey: root`); quick pickers (category, account, mood) are **modal bottom sheets** on `surface3`, 24dp top radius, 32×4dp `inkFaint` drag handle. Max 2 levels below a tab; everything else is a sheet.
- Tab switches: `NoTransitionPage` branches wrapped in 300ms `FadeThroughTransition`. Pushes: `PredictiveBackPageTransitionsBuilder` (Android 14+, `android:enableOnBackInvokedCallback="true"`, `PopScope` only — never `WillPopScope`).

## 4. Screen-by-Screen Spec

### 4.0 Shared list-item anatomy ("Noktürn row")
64dp height, 20dp horizontal padding, transparent bg inside a `surface1` card group, 1dp `divider` between rows (inset 72dp left):
- **Leading:** 40dp circle, entity color at 18% opacity bg, entity-colored 20dp icon.
- **Center:** `titleMedium` `inkHi` title (1 line, ellipsis); `bodySmall` `inkMid` metadata below: `Kategori · 12 Tem` pattern, `·` separators.
- **Trailing:** right-aligned tabular amount (`+` in `income` / `−` in `inkHi`), or 20dp `inkLow` chevron, or `🔥 n` streak.

### 4.1 Splash / auto-login gate
- **Native splash** (`flutter_native_splash`, Android 12 API): `bg #171310`, centered 96dp gold Meridian monogram "M", fade-out disabled. First Flutter frame reproduces the identical layout (zero-flicker handoff). No shimmer effect (dropped for web-renderer parity — static monogram only).
- Logic: read token from `flutter_secure_storage` (≤50ms). **No token →** fade-through to Giriş, 350ms. **Token →** route optimistically to Bugün immediately; fire `GET /me` (2.5s timeout) in background — a 401 anywhere (dio interceptor) wipes token and ejects to Giriş with SnackBar "Oturum süresi doldu, tekrar giriş yap". First-run: if `SharedPreferences` install flag missing, wipe secure storage (Keychain uninstall survival; skip this logic when `kIsWeb`).
- Total gate target <1s, no artificial delay.

### 4.2 Giriş (Login) — single screen, two-step
Column, 24dp padding, keyboard-safe scroll:
1. 64dp gold monogram; "Meridian" displayMedium Fraunces; "Kişisel yaşam merkezin" bodyMedium `inkMid`. 40dp gap.
2. **Step 1 — Sunucu:** `ServerUrlField` "Sunucu adresi". Prefill: `kIsWeb` → `http://localhost:3000`; Android debug/emulator → `http://10.0.2.2:3000`; else last-used from `SharedPreferences` (grafted from Akış). Trailing 24dp status slot: idle `inkLow` globe → 16dp spinner during `GET /api/v1/health` (1.5s debounce after typing stops) → `check_circle` `income` green, or `error_outline` red + inline errorText "Sunucuya ulaşılamadı — adresi ve Wi-Fi'yi kontrol et". **On success (grafted from Kehribar/Akış): the field collapses to a compact hairline row "✓ 192.168.1.20:3000 · Değiştir"** (tap re-expands), and the credentials section animates from 40% opacity/`IgnorePointer` to full + slides up 8dp, 350ms easeOutCubic.
3. **Step 2 — Kimlik:** `AutofillGroup`: "E-posta" (`emailAddress`, `AutofillHints.email`, `next`) and "Şifre" (`obscureText`, 48dp eye toggle, `autocorrect:false`, `enableSuggestions:false`, `AutofillHints.password`, `done` → submit). Inputs: `surface2` fill, 12dp radius, 16dp content padding, label `inkMid`, focus 1.5dp gold.
4. 401 error line "E-posta veya şifre hatalı" bodySmall `error` above the button; clears on next keystroke; values preserved.
5. **"Giriş Yap"** — full-width 52dp gold filled button, `onGold` labelLarge. Loading: `onPressed: null`, label swaps to 20dp `CircularProgressIndicator(strokeWidth: 2, color: onGold)`, button size fixed. Success: `TextInput.finishAutofillContext()`, persist token, fade-through to Bugün 400ms. No full-screen spinners, no dialogs, ever.

### 4.3 Bugün (Home) — `GET /home`
`CustomScrollView`, `RefreshIndicator.adaptive` (gold, `mediumImpact` on arm, `onRefresh` ≥500ms):
1. **App bar** (transparent, 20dp): greeting bodyMedium `inkMid` by hour (05–12 İyi sabahlar / 12–18 İyi günler / 18–23 İyi akşamlar / else İyi geceler) over `display_name` headlineLarge Fraunces. Right: bolt icon (quick capture) + 32dp avatar.
2. **Hero card** (`surface1`, 20dp pad): overline "BU AY NET" labelMedium; `month_net_cents` displayLarge Fraunces tabular (sign prefix; `income` green if ≥0 else `inkHi`); 7-day spending sparkline beneath (fl_chart LineChart, 48dp, `goldDim` 2dp line, no dots/axes, gold→transparent 12% gradient fill).
3. **Stat strip** — 3 equal `StatChip`s (`surface1`, 12dp radius/pad): "🔥 `active_streaks` seri" · "`open_todos` açık görev" · "%`habit_completion_pct` hafta". Numbers titleLarge tabular, labels labelSmall `inkMid`. **Each chip deep-links (grafted from Kehribar):** seri → Alışkanlıklar tab, görev → Görevler page, hafta → Alışkanlıklar tab.
4. **"Bugün" section** — `SectionHeader` (trailing "Tümü →" gold text button → Ajanda/Görevler page). One `surface1` card mixing:
   - Events (`today_events`, max 4): 3dp color bar + `HH:mm` labelMedium tabular `inkMid` + title titleSmall. All-day events first with "Tüm gün" pill.
   - Todos due today: 24dp rounded-square checkbox rows; **priority = 3dp left edge bar (grafted from Akış): urgent `error` / high `warning` / medium `goldDim` / low transparent**; overdue rows show due text in `error`. Check = todo toggle micro-interaction (§5), `PATCH /todos/:id/toggle`, optimistic.
   - Empty: "Bugün plan yok — sakin bir gün ☁" bodyMedium `inkLow`, centered, no CTA.
5. **"Alışkanlıklar" section** (max 6 from `today_habits`): 56dp compact rows — name + `🔥 streak` meta, trailing 48dp `HabitCheck` ring (or `CounterPill` when `target_count > 1`, showing `count/target`). All-done: header gains a gold "✦ Hepsi tamam" pill.
6. **"Hedefler" section** (top 3 active): name titleSmall + 6dp `PacedProgressBar` (goal color on `surface2` track) + `progress_percent%` labelSmall. Row → goal detail.
7. 96dp bottom padding.
- **No FAB on Bugün.** Bolt icon opens `QuickCaptureSheet`: one text field "Ne oldu? (−250 kahve, habit: koşu, süt al…)" → `POST /quick_captures` → SnackBar "Harcama eklendi ✓" with "Gör" action.
- **Loading:** `skeletonizer 2.1.3` mirroring exact layout (hero bone 160×40, 3 stat bones, 4 row bones), bones `#241E18`, 1200ms pulse (no shimmer sweep), `enableSwitchAnimation: true`.
- **Error policy (grafted from Kehribar + Akış), applies to every screen:** if cached last-good data exists → show it under a hairline banner "Çevrimdışı · son güncelleme 12:40" with a "Tekrar dene" text action; a full-screen `EmptyState` (48dp `cloud_off`, "Sunucuya ulaşılamıyor", "Aynı Wi-Fi ağında olduğundan emin ol", outlined "Tekrar dene" + "Sunucu ayarları" text button) appears only when there is nothing cached to show. Cache = in-memory per session (Riverpod `AsyncValue` previous data), no disk persistence in v1.

### 4.4 Para (Finance) — `GET /finance/dashboard` + `GET /accounts`
1. App bar: "Para" headlineLarge; trailing `SegmentedPill` (Ay / Yıl) scoping the hero + pie.
2. **Hero:** "BU AY NET" + net displayLarge; beneath: "+ Gelir X" `income` / "− Gider Y" `inkHi`, titleSmall tabular.
3. **Hesaplar** — horizontal snap `PageView` (viewportFraction .88) of 140dp `AccountCard`s: `surface1`, left 4dp account-color bar, name titleMedium, Turkish type label labelSmall `inkMid` (Nakit/Banka/Kredi Kartı/Birikim/Kripto), balance displayMedium Fraunces tabular per that account's `subunit_to_unit` (**GAU → "412 gr"**). Tap → Hesap Detay (Hero flight on color bar + name; detail = full-width header + that account's transaction list + "Arşivle" in overflow). 6dp page dots, active gold. Last card: dashed-hairline "＋ Hesap ekle" ghost.
4. **Son 6 ay (grafted from Kehribar):** `surface1` card with fl_chart grouped `BarChart` from `six_month_series` — income `#8FBF9F` / expense `#C9A45C` bars, radius-4 tops, month labels labelSmall `inkLow`, 350ms animate-in on first build, no gridline clutter (y-axis 3 labels max).
5. **Kategoriler (bu ay)** — `surface1` card: fl_chart donut 160dp (centerSpaceRadius 56, sectionsSpace 2, series = `pie[]` roots using API colors), center = total expense titleLarge tabular; top-5 legend rows below (10dp dot, name bodyMedium, amount + % trailing). Slice tap → breakdown bottom sheet (subcategory list, cents-formatted).
6. **Bütçeler** — one row per budget: category name + `PacedProgressBar`: `surface2` track, fill color by `state` (:under `income` / :warning `warning` / :over `error`), 2dp vertical `inkLow` **pace tick** at `pace_percent`; trailing "kalan `remaining`" bodySmall. Over rows: amount `error` + "aşıldı" labelSmall `errorContainer` pill. **When `projected_cents > limit_cents` (grafted from Kehribar): second meta line "Ay sonu tahmini: X" bodySmall `warning`.**
7. **Yaklaşan abonelikler** (5): rows with relative `next_charge_on` ("3 gün sonra") + amount.
8. **Son işlemler** (8) + "Tümü →" → İşlemler page.
- **FAB:** gold 56dp `＋` → **İşlem Ekle** full-screen modal: kind `SegmentedPill` (Gider/Gelir/Transfer, default Gider) → amount-first: giant Fraunces amount + custom `AmountKeypad` (4×3, 64dp keys, `selectionClick` per key, decimal key hidden for GAU accounts) → account picker sheet → category picker sheet (2-level roots/children) → date (default bugün) + description. Transfer swaps category for related-account picker. Submit: 52dp gold button, `POST /transactions`, `lightImpact`, pop + SnackBar. Client sends `amount_cents` already multiplied by the account's subunit.
- **İşlemler (pushed):** sticky filter chip bar (Tümü/Gelir/Gider/Transfer + Hesap + Kategori + tarih aralığı; active chips `goldContainer`; each opens a sheet picker); slim summary "`filtered_income` gelir · `filtered_expense` gider" bodySmall. Infinite scroll (`page`, PAGE_LIMIT 50), day-grouped sticky headers labelMedium `inkMid` ("Bugün", "Dün", "12 Temmuz"). Rows: Noktürn row — category-color leading circle (transfer: `swap_horiz` on `inkLow`), title = description ?? category name, meta = `Kategori · Hesap`, trailing signed amount. Row tap → detail sheet (`surface3`) with Düzenle/Sil. **Swipe-left on a row = delete (grafted from Akış): `error` bg reveal, then confirm dialog; `heavyImpact` on confirm.**
- Empty accounts: EmptyState "İlk hesabını ekle" + gold CTA. Empty filtered transactions: "Bu filtreyle işlem yok" + "Filtreleri temizle". Loading: hero bone, 1 account card bone + peeking second, 6 row bones.

### 4.5 Alışkanlıklar — `GET /habits`
1. App bar "Alışkanlıklar" + trailing history icon → 84-day view.
2. **Bugün kartı:** `X / Y tamamlandı` titleLarge + 8dp gold progress bar; on transition to X==Y: one-time confetti burst (12 gold/sage particles, 800ms, hand-rolled CustomPainter — the only confetti in the app) + `mediumImpact`.
3. **Mükemmel gün zinciri:** 30 dots in a wrap (10dp circles, 6dp gap): `:perfect` gold filled / `:partial` gold 40% / `:missed` `surface2`+hairline / `:no_habits` transparent; caption "Mükemmel seri: 🔥 n · Rekor: m" bodySmall `inkMid`.
4. **Habit cards** — one `surface1` card per habit, 72dp core row:
   - Leading 12dp habit-color dot; title titleMedium; meta `🔥 current_streak · %completion_rate_30d (30g)`.
   - Trailing: `target_count == 1` → 48dp `HabitCheck` ring (2dp `inkLow` circle; tap fills habit color with the §5 pop, white check draws in). `target_count > 1` → `CounterPill` 96×40dp `− n/target ＋` (`PATCH toggle_today` with `delta`); fills habit color when complete.
   - Beneath (8dp gap): 14-day `ChainRow` — 8dp squares, 3dp gap, 2dp radius: completed = habit color / partial = 40% / today-pending = gold hairline outline / missed = `surface2`. Weekly/monthly habits show a period pill instead: "Bu hafta 2/3" labelSmall, check icon when complete.
5. Habit tap → detail sheet (90% height): 30-day chain + legend, stats grid (Seri / Rekor / 30g oranı), 84-day 12-week mini-heatmap (custom widget), archive action.
- **FAB** `＋` → habit form modal (name, frequency segmented Günlük/Haftalık/Aylık, target stepper, 8-swatch color row with gold default, optional goal link). Toggles are optimistic with rollback SnackBar on failure.
- Empty: "İlk alışkanlığını oluştur — küçük başla" + CTA. Loading: 4 habit-card bones with chain bones.

### 4.6 Hedefler — `GET /goals`
1. App bar "Hedefler".
2. **Aktif** grid (2-col, 12dp gutter): `GoalCard` — top: 10dp color dot + type overline labelMedium (`FİNANSAL`/`ALIŞKANLIK`/`ÖZEL`) + `DeadlineBadge` (overdue `errorContainer` "3g gecikti" / today `warningContainer` "bugün" / ≤7d `warningContainer` "5g kaldı" / far `surface2` `inkMid` date); name titleMedium 2-line; bottom: 72dp `ProgressRing` (6dp stroke, goal color on `surface2` track, 600ms easeOutCubic sweep on first build) with `%` centered; `current / target unit` bodySmall tabular beneath (financial goals format with the linked account's currency — GAU "gr").
3. **Başarılanlar** — collapsed expansion section: flat rows, name + green check + `target unit` in `income`.
4. **Goal detail** (push, Hero on ProgressRing): 160dp ring, displayMedium % inside; stats grid (Durum/Bitiş/Kalan gün); type-specific action card — **custom:** `[−10][−1][＋1][＋10]` 44dp `surface2` stepper (`selectionClick` each) + direct value field → `PATCH update_progress`; **habit:** linked streak + "X / target gün" + gold "Bugünü işaretle"; **financial:** linked account balance (subunit-correct) + "Yenile" (`PATCH recalculate`, inline button spinner ≥300ms). Footer: "Bırakıldı olarak işaretle" plain `inkLow` text button + confirm dialog.
- **FAB** `＋` → goal form modal. Empty: "İlk hedefini koy" + CTA. Loading: 4 GoalCard bones.

### 4.7 Günlük — `GET /journal_entries?range=30d`
1. App bar "Günlük"; trailing range pill (7g/30g/6ay/1y/Tümü, default 30g). Meta line: "`entries_count` kayıt · 🔥 `journal_streak`" (`goldContainer` flame pill, hidden at 0).
2. **Mood dağılımı** slim card: 5 emoji + counts. **Tap an emoji to filter the list to that mood (grafted from Kehribar); tap again to clear; active emoji full opacity, others 50%.** (Client-side filter over the loaded range.)
3. **Entry cards** — full-width `surface1`, 16dp pad (single column, Day One-calm):
   - Top row: date block (weekday labelSmall `inkMid` over day number headlineMedium Fraunces) · 24sp mood emoji right · `energy_level` as 5 tiny dots (filled gold = level).
   - Title titleMedium (fallback "Adsız" `inkLow` italic); `body_plain` bodyMedium `inkMid`, maxLines 4 (200-char server truncation).
   - Footer: first 3 tags as `surface2` pills labelSmall + `favorite` 14dp `goldDim` icon when `has_gratitude`.
4. Entry tap → **Detail** push: full date Fraunces headline, mood+energy, rendered `body_html` via `flutter_widget_from_html_core`, gratitude in a `goldContainer`-tinted bordered box labeled "MİNNET", all tags, weather line; overflow: Düzenle / Sil.
- **FAB** `＋` → **Editor**, full-screen: step 1 = mood check-in overlay (5 emoji 56dp, `selectionClick`, "Geç" skip); then chrome-minimal editor — date row, title field (titleLarge, "Başlık" hint), body multiline plain text with autofocus (keyboard up immediately), bottom accessory bar: gratitude field toggle, weather, tags, energy 5-dot picker. Autosave draft to SharedPreferences every 5s; "Kaydet" text button top-right.
- Empty: "Bugün nasıldı? İlk kaydını yaz" + CTA. Loading: 3 entry-card bones.

### 4.8 Profil & Ayarlar (push from avatar)
Grouped `surface1` cards of 56dp rows (icon `inkMid` + title + trailing value/chevron):
1. **Header:** 64dp initials avatar, `display_name` headlineMedium, email bodySmall `inkMid`.
2. **Uygulama:** Tema (Koyu/Açık/Sistem segmented → `theme_preference`), Dil (tr/en), Para birimi (read-only).
3. **Sunucu:** current URL row → **Sunucu ayarı page:** same `ServerUrlField` as login + "Bağlantıyı test et" outlined button → inline result row — **success: "✓ Bağlandı · Meridian vX · 38 ms" green (latency grafted from Akış)** / failure red. Saving a URL that fails ping requires "Yine de kaydet" confirm. Save updates SharedPreferences and rebuilds the dio base URL.
4. **Hakkında:** sürüm, API durumu.
5. **Çıkış Yap** — bottom, plain `inkHi` row + `logout` icon; confirm dialog ("Çıkış yapılsın mı?", "Vazgeç" text + "Çıkış Yap" filled `error`); confirm → `signOutAndWipeLocal()` (secure-storage token delete + Riverpod user-scope invalidation + prefs wipe except server URL) → router redirect to Giriş. No haptic (not data-destructive).

## 5. Motion Language — slow, settled, never bouncy

Global: **350ms default, `Curves.easeOutCubic`**; nothing under 200ms except ripples, nothing over 600ms except hero rings. No springs/overshoot — one exception below.

| Navigation pair | Transition | Duration |
|---|---|---|
| Tab ↔ tab | FadeThrough (`animations 2.2.0` via `CustomTransitionPage`) | 300ms easeOutCubic in / easeInCubic out |
| List → detail | Predictive back builder (falls back FadeForwards) | system default |
| Any → create/edit form | Slide-up full-screen modal | 400ms easeOutCubic in / 300ms easeInCubic out |
| Any → picker/detail sheet | Modal bottom sheet, scrim `#171310` @ 60% | 350ms easeOutCubic |
| Splash → Giriş/Bugün | FadeThrough | 350ms |
| Login → Bugün | FadeThrough | 400ms |

- **Hero flights — exactly two:** AccountCard color bar+name → Hesap Detay header; GoalCard ProgressRing → detail ring (wrap in `Material`, `flightShuttleBuilder` for size change). Nowhere else.
- **List entrance stagger:** first load only (never pagination/refresh): `flutter_animate` `.fadeIn(300.ms).slideY(begin: 0.06)` with `delay: (50 * index).ms`, capped at first 6 items.
- **Check-off (habit ring / todo checkbox):** press 0→80ms scale to 0.9 → 250ms entity-color fill sweep + check path draw (easeOutCubic) + scale 0.9→1.05→1.0 over 300ms easeOutBack (**the single allowed overshoot**). Uncheck = plain 200ms fade, no celebration. Streak/amount counters animate with 300ms `AnimatedSwitcher` slide-up-fade.
- **Hero numbers:** count-up `TweenAnimationBuilder` 500ms easeOutCubic **on first load only; refreshes cross-fade with no counting — data honesty (rule from Akış).**
- **Progress bars/rings:** animate from 0 on first build (600ms easeOutCubic); subsequent changes animate previous→new (350ms), never re-zero.
- **Skeleton → content:** 300ms skeletonizer switch fade.

**Haptics map** (`HapticFeedback`, unconditional — no-op on web):

| Action | Call |
|---|---|
| Habit check complete, todo done, transaction saved, login success | `lightImpact` |
| Counter ±, keypad key, segmented/mood/tab select, picker tick, account card snap | `selectionClick` |
| Pull-to-refresh armed, all-habits-done, goal reaches 100% | `mediumImpact` |
| Delete confirm, over-budget crossing, error SnackBar | `heavyImpact` |
| Scroll, page load, uncheck, logout | none |

## 6. Component Inventory (`lib/ui/widgets/`)

`AppScaffold` (nav shell) · `NokturnCard` (surface1 + hairline + 16r) · `PressableScale` (0.98 press wrapper, curve-based) · `SectionHeader` (title + optional "Tümü →") · `MoneyText` (cents + currency + subunitToUnit → formatted, sign, tabular; hero/row variants — the only money math in the app) · `HeroStat` (overline + Fraunces number + sparkline slot) · `StatChip` (tappable, deep-link) · `NokturnRow` (64dp list item) · `LeadingCircle` · `AmountKeypad` · `SegmentedPill` · `FilterChipBar` · `AccountCard` · `PacedProgressBar` (fill + pace tick + projection note slot) · `ProgressRing` · `HabitCheck` (48dp ring toggle) · `CounterPill` · `ChainRow` · `PerfectDayDots` · `StreakFlame` · `DeadlineBadge` · `GoalCard` · `MoodPicker` / `MoodEmoji` · `EnergyDots` · `TagPill` · `JournalCard` · `EventRow` / `TodoRow` (priority edge bar) · `QuickCaptureSheet` · `PickerSheet<T>` · `ServerUrlField` (debounced ping + status slot + collapsed-row state) · `PrimaryButton` (52dp gold, inline-spinner loading) · `ConfirmDialog` (destructive variant) · `EmptyState` · `OfflineBanner` ("Çevrimdışı · son güncelleme HH:mm" + retry) · `SkeletonScreen` per tab · `AppSnackBar` (surface3, gold action) · `DonutChart` / `Sparkline` / `SixMonthBars` (fl_chart wrappers, Noktürn theming baked in) · `ConfettiBurst` (hand-rolled, single use).

## 7. Packages (pubspec)

| Package | Version | Note |
|---|---|---|
| `go_router` | ^17.3.0 | StatefulShellRoute.indexedStack |
| `flutter_riverpod` | ^3.3.2 | state; no codegen initially |
| `dio` | ^5.10.0 | 401 InterceptorsWrapper → signOut |
| `flutter_secure_storage` | ^10.3.1 | token (web fallback accepted for dev preview) |
| `shared_preferences` | ^2.x | server URL, install flag, drafts, theme |
| `google_fonts` | ^8.1.0 | **Fraunces + Inter bundled in assets** (original filenames, no runtime fetch) |
| `fl_chart` | ^1.2.0 | donut, sparkline, 6-month bars |
| `animations` | ^2.2.0 | FadeThrough |
| `flutter_animate` | ^4.5.2 | staggers only (no shimmer/blur effects) |
| `skeletonizer` | ^2.1.3 | loading states |
| `flutter_native_splash` | ^2.x | Android 12 splash |
| `flutter_widget_from_html_core` | latest stable | journal body_html |
| `intl` | ^0.20.x | tr_TR money/date formatting |

Custom, no package: heatmap/chain widgets, AmountKeypad, ConfettiBurst (~40 lines). **Android config (from Akış):** `minSdk 26`, target API 36, `android:enableOnBackInvokedCallback="true"`, `network_security_config.xml` allowing cleartext to LAN ranges (10.0.0.0/8, 192.168.0.0/16, 10.0.2.2) — required for `http://` on Android 9+. No superellipse shapes anywhere. No M3E packages.

## 8. API Endpoints (all `/api/v1`, Bearer `api_token`; all money integer `*_cents` + `subunit_to_unit` per currency — **GAU: 1, symbol "gr"**)

**Existing — reuse as-is:** `POST /session` (`{email, password}` → `{token, user:{id, name, email, currency}}` | 401 `{error:"invalid_credentials"}`) · `GET /accounts` (`{accounts:[{id, name, account_type, currency, subunit_to_unit, color, initial_balance_cents, balance_cents, archived}]}`).

**New:**
- `GET /health` (auth skipped) → `{ok: true, app: "meridian", version}` — login ping + settings test (client measures latency itself).
- `GET /me` → `{id, name, display_name, initials, email, currency, subunit_to_unit, locale, timezone, theme_preference}` — also the token-validity probe.
- `GET /home` → `{currency, subunit_to_unit, month_net_cents, active_streaks, open_todos, overdue_count, today_events_count, habit_completion_pct, spending_7d:[{date, cents}], today_habits:[{id, name, color, target_count, completed_today, today_count, current_streak}], upcoming_todos:[{id, title, due_at, overdue, priority}], today_events:[{id, title, start_at, end_at, all_day, color}], active_goals:[{id, name, color, progress_percent}], perfect_day:{chain:[{date, status}], current_streak}}`
- `GET /finance/dashboard?range=m1|y1` → `{currency, subunit_to_unit, month:{income_cents, expense_cents, net_cents}, year:{income_cents, expense_cents}, six_month_series:{labels:[], income_cents:[], expense_cents:[]}, pie:[{id, name, color, amount_cents, breakdown:[{id, name, amount_cents, is_root}]}], budgets:[{category:{id, name}, color, limit_cents, spent_cents, remaining_cents, percent_used, pace_percent, projected_cents, state}], upcoming_subscriptions:[{id, name, amount_cents, frequency, next_charge_on, account:{id, name, currency, subunit_to_unit}}], recent_transactions:[Transaction×8]}` — **serialize six_month_series as cents arrays, not the web's /100.0 floats (GAU bug avoidance).**
- `GET /transactions?kind&account_id&category_id&from&to&page` → `{transactions:[Transaction], meta:{total_count, page, page_limit:50, filtered_income_cents, filtered_expense_cents}}`; **Transaction** = `{id, kind, amount_cents, date, description, note, account:{id, name, color, currency, subunit_to_unit}, category:{id, name, color, parent_id}|null, related_account:{id, name}|null}`
- `POST /transactions` / `PATCH /transactions/:id` / `DELETE` — body `{kind, amount_cents, date, description, note, account_id, finance_category_id, related_account_id}` (client sends cents already multiplied by the account's subunit) → Transaction | 422 `{errors:{field:[msg]}}`
- `GET /finance_categories` → `{categories:[{id, name, kind, color, parent_id, position}]}`
- `GET /habits` → `{habits:[{id, name, description, frequency, target_count, color, goal_id, current_streak, longest_streak, completion_rate_30d, today:{date, completed, count}, period:{range_start, range_end, completed_count, complete}|null, chain:[{date, status, completed, possible}]×14}], meta:{completed_today, total_active, perfect_day:{chain:[…×30], current_streak, longest_streak}}}` (use batched `streaks_for`/`chain_windows_for`); `GET /habits/:id?days=84` for detail.
- `PATCH /habits/:id/toggle_today` (optional `{delta}`) → updated habit + `meta` (same shape — one round trip refreshes the header). `POST /habits` / `PATCH /habits/:id` / `PATCH /habits/:id/archive`.
- `GET /goals` → `{active:[Goal], achieved:[Goal], abandoned:[Goal]}` (server recalculates active on index; **fix the web's `/100.0` → `subunit_to_unit` in CalculateProgress for GAU-linked accounts**); **Goal** = `{id, name, description, target_type, status, color, unit, deadline, days_remaining, deadline_badge:{state:"overdue|today|soon|far", days}|null, target_value, current_value, progress_percent, related:{type, id, name, current_streak?, completed_days?, balance_cents?, currency?, subunit_to_unit?}|null}`
- `PATCH /goals/:id/update_progress` `{current_value | delta}` → Goal · `PATCH /goals/:id/recalculate` → Goal · CRUD with composite `related: "Account-12"|"Habit-7"|"none"`.
- `GET /journal_entries?range=7d|30d|6mo|1y|all&page` → `{entries:[{id, date, title, body_plain, mood, mood_emoji, energy_level, weather, tags:[], has_gratitude, created_at}], meta:{entries_count, journal_streak, mood_counts:{great:n,…}, range}}`; `GET /journal_entries/:id` adds `body_html, gratitude`; `POST/PATCH/DELETE` accept `{date, title, body, mood, weather, energy_level, gratitude, tags}` (tags comma-joined string).
- `GET /todos?filter=today|week|overdue|done&list_id&priority&page` → `{todos:[{id, title, body, status, priority, due_at, overdue, position, todo_list:{id, name, color}|null, subtask_count}], meta:{open_count, overdue_count}}`; `PATCH /todos/:id/toggle` → `{id, status, completed_at}`; CRUD.
- `GET /events?from=&to=` → `{events:[{id, title, start_at, end_at, all_day, color, event_type, location, duration_minutes, occurrences:[dates]}]}` (expand via `occurrences_between`).
- `POST /quick_captures` `{text}` → `{captured_type:"transaction"|"habit_log"|"todo"|"event_suggestion", record_id, summary}`.

Error contract: 401 `{error:"unauthorized"}` (dio interceptor → signOut) · 404 `{error:"not_found"}` · 422 `{errors:{…}}` → inline field errors. Dates ISO-8601 in user timezone (Istanbul).

---

# Build-Order Plan

Existing state: Rails API branch `feat/mobile-api` has session + accounts; Flutter app already does login → accounts end-to-end. Build order (each step ships runnable):

1. **Design system foundation** — `lib/theme/app_colors.dart` (both palettes as `ThemeExtension`), `lib/theme/app_typography.dart` (Fraunces/Inter TextTheme, bundle .ttf under `assets/fonts/`), `lib/theme/app_theme.dart` (ThemeData light/dark, input/button/sheet themes). Then the atoms in dependency order: `MoneyText` (+ unit tests: TRY, USD, **GAU**), `NokturnCard`, `PressableScale`, `SectionHeader`, `PrimaryButton`, `AppSnackBar`, `EmptyState`, `ConfirmDialog`.
2. **Shell + routing** — `lib/router/app_router.dart` (StatefulShellRoute, 5 branches, fade-through `CustomTransitionPage`, auth redirect), `AppScaffold` + nav bar, placeholder screens per tab. Restyle the existing login screen to §4.2 (`ServerUrlField` with debounced `/health` ping + collapsed row) and the splash gate to §4.1. Backend: add `GET /health`, `GET /me`.
3. **Bugün read-only** — backend `GET /home`; widgets `HeroStat`, `Sparkline`, `StatChip`, `TodoRow`, `EventRow`, `PacedProgressBar`; `SkeletonScreen` + `OfflineBanner` + error policy plumbing (this generic Riverpod `AsyncValue`-with-last-good pattern gets reused by every later screen).
4. **Para read** — restyle existing accounts into `AccountCard` PageView; backend `GET /finance/dashboard`; `DonutChart`, `SixMonthBars`, budget rows with pace tick.
5. **İşlemler read** — backend `GET /transactions` + `GET /finance_categories`; `NokturnRow`/`TxRow`, `FilterChipBar`, `PickerSheet<T>`, infinite scroll, day headers.
6. **First write: transaction create** — `AmountKeypad`, İşlem Ekle modal, `POST /transactions`, 422 → inline errors; then edit/delete + swipe-delete.
7. **Habits** — backend `GET /habits` + `toggle_today`; `HabitCheck` (the §5 check-off animation), `CounterPill`, `ChainRow`, `PerfectDayDots`, `ConfettiBurst`; optimistic toggle with rollback.
8. **Hedefler** — backend `GET /goals` + progress endpoints (including the GAU CalculateProgress fix); `GoalCard`, `ProgressRing`, `DeadlineBadge`, detail with Hero.
9. **Günlük** — read (cards, mood strip + filter, detail with `flutter_widget_from_html_core`), then editor with draft autosave.
10. **Todos/events full pages** + toggle from Bugün (may land earlier with step 3 if `/home` needs it wired anyway; toggle endpoint is trivial).
11. **Profil/Ayarlar** — theme switch, server page with test+latency, `signOutAndWipeLocal()`.
12. **Quick capture** — backend `POST /quick_captures` + `QuickCaptureSheet`.
13. **Polish pass** — entrance staggers, haptics audit, light theme QA, native splash config, release APK sideload (Faz 4).

Rationale: 1–3 give a styled, navigable app against mostly-existing endpoints; the error/skeleton/offline plumbing is built once in step 3 and inherited everywhere; writes start only at step 6, after the read patterns are stable.

# Risk List — what might not work on Flutter web debug preview (Chrome)

1. **CORS** — Meridian has no rack-cors; keep running `flutter run -d chrome --web-browser-flag=--disable-web-security` (current workflow) or add rack-cors dev-only. Any teammate who forgets the flag sees every request fail — document it in the app README.
2. **`10.0.2.2` default is emulator-only** — unreachable from the browser. The `kIsWeb → http://localhost:3000` prefill in §4.2 is mandatory, not cosmetic (already the pattern in `config.dart`).
3. **`flutter_secure_storage` on web** is an experimental WebCrypto/localStorage shim — token persistence across hard reloads can be flaky, and the Keychain "uninstall survival wipe" logic is meaningless there (spec already skips it on `kIsWeb`). Accept lower security in dev preview.
4. **Haptics** — all `HapticFeedback` calls are silent no-ops on web. The check-off and keypad interactions will feel flatter than they will on the phone; judge them on the APK, not Chrome.
5. **Predictive back / `PopScope`** — Android-only; on web the browser back button drives go_router instead. Test push/pop behavior separately on the phone.
6. **Native splash** — `flutter_native_splash` web output differs (or is absent); the zero-flicker handoff can only be verified on Android.
7. **Autofill** — `AutofillGroup`/`TextInput.finishAutofillContext()` map to browser password-manager heuristics on web; Chrome may overlay its own save-password UI over the obscured field. Behavior differs from Android's autofill service.
8. **Tabular figures** — `FontFeature.tabularFigures()` requires the CanvasKit/Skwasm renderer (current default). If the HTML renderer is ever forced, money columns will wobble.
9. **Debug-mode jank** — web debug (dartdevc, no WASM opt) makes the 50ms staggered entrances, count-ups, and donut animate-ins stutter. Do not tune animation timings in Chrome; tune on a profile/release Android build.
10. **Sheets and swipe gestures with a mouse** — modal-bottom-sheet drag-to-dismiss and the swipe-to-delete row are awkward with mouse input and may feel broken in preview; both are tap-reachable too (detail sheet has Sil), so functionality is never gesture-only.
11. **dio timeouts** — the browser fetch adapter can't distinguish DNS/connect failures; the login field's 1.5s-debounced health ping may report "unreachable" more slowly or generically on web than on Android.
12. **`flutter_widget_from_html_core`** renders fine on web, but Trix-generated `body_html` with attachments/embeds may lay out differently between web preview and the phone — verify journal detail on both.
13. **Scroll physics** — `RefreshIndicator` pull-to-refresh does not trigger with a mouse wheel; add nothing web-specific, just know refresh is testable only via the retry buttons in preview.

The web preview is a layout/data-correctness tool; anything involving haptics, gestures, splash, back navigation, autofill, or animation feel gets final judgment on the sideloaded APK.