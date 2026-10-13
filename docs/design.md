# Meridian Mobile — Design System: **Noktürn v2**

Android-first, dark by default, Turkish and English, talking to a self-hosted
Rails API over the LAN. This document describes the design system as it is
built: every value below is read from the code, and the code is the source of
truth when the two disagree (`lib/theme/**`, `lib/core/formats.dart`,
`lib/core/haptics.dart`, `lib/ui/widgets/**`). It replaces "Noktürn v1.1";
the identity is the same, how it feels in the hand is new.

Contents: [1 Language](#1-language-and-principles) ·
[2 Colour](#2-colour) · [3 Type and numbers](#3-type-and-numbers) ·
[4 Space, shape, surfaces](#4-space-shape-surfaces-icons) ·
[5 Motion](#5-motion) · [6 Haptics](#6-haptics) ·
[7 Components](#7-component-inventory) ·
[8 Navigation and interaction](#8-navigation-and-interaction) ·
[9 Screen patterns](#9-screen-patterns) ·
[10 Empty states and the zero rules](#10-first-run-empty-states-and-the-zero-rules) ·
[11 Accessibility and performance](#11-accessibility-and-performance-gates) ·
[12 Tests and goldens](#12-tests-goldens-and-qa)

---

## 1. Language and principles

**"Calm luxury, instant answer."** Warm espresso surfaces (never `#000`), one
disciplined gold that means *yours*, Fraunces numerals as the signature, and
hairlines instead of shadows. What v2 changes is the feel:

- every touch answers in the same frame — the network catches up later;
- numbers roll instead of blinking;
- finished things fold away;
- mistakes are undone, not prevented with dialogs;
- the most important thing on each screen is the biggest thing.

Motion is quick, physical and settled: no visible bounce, and every animation
explains a change. Taken from 2025–26: Android 16 edge-to-edge and predictive
back, labelled primary actions in the thumb zone, semantic haptics, damped
springs, rolling digits, charts that come with a sentence, stadium buttons.
Deliberately not taken: Liquid Glass and blur, wallpaper colour, M3 Expressive
shape morphs, FAB menus, bento grids, donut charts, confirm dialogs for
routine work.

**Principles** (each comes with a test a reviewer can run):

1. **Same-frame answer.** A tap changes the screen before the server answers.
   With the server slowed by 1 s every check, counter, delete and archive still
   updates in one frame; with a forced 500 the change rolls back with a message
   and the REJECT haptic.
2. **Never empty what is known.** Backgrounding, a tab re-tap or a save never
   swaps visible content for a skeleton, spinner or gap, and never replays an
   entrance or a count-up.
3. **One hero per screen.** Squint at a screenshot: the first thing read is the
   hero §9 names for that screen.
4. **Thumb first, always a word.** At 360×780 dp, one hand: the create action
   and every form's Save sit in the bottom 45 % or right above the keyboard,
   are ≥ 48 dp and are labelled with a verb.
5. **Undo instead of asking.** A dialog in front of an undoable action is a bug.
   The few dialogs left name the object and the outcome with numbers, and the
   button is a verb ("Sil ve taşı", never "Onayla").
6. **Calm, exact, forward-looking words.** Red only for a real overrun,
   overdue, error or destructive button; every negative state has a number and
   a next step; no exclamation marks, no "aşıldı", never a flame beside a 0.
7. **Motion explains a change.** For each animation one can say what changed
   or where it went; with "Remove animations" on every screen shows its end
   state in one frame.
8. **Every gesture has a tap.** Every swipe, long press and drag can be done
   with plain taps and with TalkBack; every icon-only control has a label.

---

## 2. Colour

Tokens live in `NokturnColors` (`lib/theme/app_colors.dart`), a
`ThemeExtension` read through `context.nok`. `NokturnColors.lerp` really
interpolates, so the 250 ms light ↔ dark change fades every token.

### 2.1 Palettes

| Token | Dark (default) | Light (warm paper) | Role |
|---|---|---|---|
| `bg` | `#171310` | `#F6F1E8` | Page |
| `surface1` | `#1E1915` | `#FCFAF5` | Cards |
| `surface2` | `#262019` | `#FFFFFF` | Nav bar, inputs, chip rail |
| `surface3` | `#2D2620` | `#FFFFFF` | Sheets, dialogs, snackbars, menus |
| `hairline` | `#322A22` | `#E5DDCE` | Card, list and nav edge (decorative) |
| `divider` | `#2A231C` | `#EAE2D3` | Separators inside a list (decorative) |
| `inkHi` | `#EFE9DF` | `#262019` | Primary text |
| `inkMid` | `#B3A895` | `#5F574A` | Secondary text, meta, default icons |
| `inkLow` | `#9A907F` | `#736B5E` | Hints, axis labels, inactive nav, placeholders |
| `inkDisabled` | `#7A7060` | `#8A8172` | Component borders, disabled text, "missing" marks (≥ 3:1, not running text) |
| `inkFaint` | `#4E463B` | `#B5AC9C` | Dashed ghost borders, rules — never text or a state |
| `gold` | `#D4A853` | `#86661A` | The accent: primary actions, selection, "yours" |
| `goldBright` | `#E7C883` | `#7A5D14` | The streak flame, emphasis on gold containers |
| `goldDim` | `#8C6D2C` | `#A48842` | Gold borders and state marks (≥ 3:1) |
| `onGold` | `#221805` | `#FFFFFF` | Text on gold |
| `goldContainer` / `onGoldContainer` | `#3B2F14` / `#EBD9A9` | `#F0E3C2` / `#4A3A10` | Selected chip, milestone card, notices |
| `income` / `incomeContainer` / `onIncome` | `#6FC08D` / `#17301F` / `#171310` | `#287148` / `#DDEEE2` / `#FFFFFF` | Income and real positives |
| `error` / `errorContainer` / `onError` | `#E07862` / `#351E19` / `#171310` | `#A83E2A` / `#F6DFD9` / `#FFFFFF` | Overrun, overdue, error, destructive |
| `warning` / `warningContainer` / `onWarning` | `#E39A4E` / `#33240F` / `#171310` | `#8F5216` / `#F3E4C8` / `#FFFFFF` | Due soon, attention |
| `track` | `#3A3229` | `#E6DDCC` | The groove under a ring or bar (the value is always also text) |
| `skeletonBone` | `#2D2620` | `#EDE6D8` | Skeleton bones |
| `overlayBorder` | `#3D342A` | `#E5DDCE` | 1 dp edge of snackbar, menu, tooltip |
| `scrim` | `#8F000000` (black 56 %) | `#52171310` | Modal barrier — never written at a call site |
| `chart` | `#C9A45C #7FA3C0 #8FBF9F #B08FB3 #C98F7A #A8A86B` | `#A98436 #5F84A3 #5F9871 #906E93 #A96E58 #83833F` | Category series |
| `chartIncome` / `chartExpense` | `#8FBF9F` / `#C9A45C` | `#5F9871` / `#A98436` | Six-month bars (also told apart by shape) |

`buildTheme(brightness)` (`lib/theme/app_theme.dart`) maps these onto a
Material 3 `ColorScheme` and themes every Material component (buttons, chips,
inputs, sheets, dialogs, snackbars, nav bar, switches, progress, tooltips,
menus, page transitions). `surfaceTint` is transparent; ripple highlight is
gold at 4 %.

### 2.2 Contrast promises (enforced by `test/theme/contrast_test.dart`)

- **Text and icons that carry information** — `inkHi`, `inkMid`, `inkLow`,
  `gold`, `income`, `error`, `warning` on `bg`/`s1`/`s2`/`s3`, every `on*`
  token on its colour, every state colour on its container, `inkLow` and
  `inkMid` on `goldContainer`: **≥ 4.5:1**.
- **Borders and state marks** — `inkDisabled` on every surface, `goldDim` on
  `s1`/`s2`, an entity tone's `fill`: **≥ 3:1**.
- **Decorative only** — `hairline`, `divider`, `inkFaint`, `track`: no promise,
  never information.

### 2.3 Usage rules

1. Text on `goldContainer` is always `onGoldContainer`.
2. Red only for a real overrun, overdue item, error or destructive action. A
   negative month net is not red and never carries an exclamation mark.
3. Green only for income and real positives — zero is not green.
4. Opacity never describes a state ("loading" at 50 %, "inactive" at 50 %):
   disabled is `inkDisabled`, selection is shape and edge. The one exception
   is the documented filter wait (old results dim to 0.5 only after a 150 ms
   timer, §5.4 of the analysis).
5. A state is never told by colour alone — a shape, an icon or a word goes
   with it.

### 2.4 Record colours: `EntityTone`

People colour their own records (habits, goals, accounts, categories, lists,
events). A raw hex is never painted as-is: `entityTone(hex, context.nok)`
(`lib/theme/entity_color.dart`, memoised per colour and brightness) derives

| Field | Promise | Use |
|---|---|---|
| `fill` | ≥ 3:1 against `track` and the tone surface (s3 dark, bg light) | Ring, check fill, chain cell, bar, dot, the inline event/account bar |
| `text` | ≥ 4.5:1 against the surface and its own tint | Any text or icon in the record's colour |
| `tint` | `fill` at 16 % | `LeadingCircle`, pill backgrounds |
| `onFill` | white or `#171310`, whichever contrasts more | Marks only: the check tick, the swatch tick |

Never text on a solid fill: a completed counter is tint + `text` digits + a
1.5 dp `fill` border. New records pick from `RecordSwatch` — gold `#D4A853`,
sage `#6B8E5A`, dusty blue `#6B8FA0`, clay `#B85450`, tan `#C98F6B`, mauve
`#7A5C9E`, teal `#5A9E8B`, amber `#8B5A00` — rotating so consecutive records
differ (`nextSwatch`). The retired tan `#D4A574` (1.01:1 from gold) is still
read for old records. `test/theme/entity_tone_test.dart` checks all eight in
both themes.

---

## 3. Type and numbers

### 3.1 Type scale (`lib/theme/app_typography.dart`)

Fraunces SemiBold (600) for headlines and big numbers; Inter 400/500/600 for
the interface. w700 is never asked for (it is not bundled). Fraunces is never
used under 20 sp, in running text, chips, buttons or overlines.

| Role | Face, size/line | Use |
|---|---|---|
| `displayLarge` | Fraunces 40/46, −0.5 | Finance hero net, amount entry |
| `displayMedium` | Fraunces 32/38, −0.25 | Account balance, goal %, 160 dp ring centre |
| `displaySmall` | Fraunces 28/34 | Keypad digits, journal day number |
| `headlineLarge` | Fraunces 26/32 | Tab-root titles, Today greeting |
| `headlineMedium` | Fraunces 22/28 | Dialog titles, entity sheet titles |
| `headlineSmall` | Fraunces 20/26 | Pushed page and form app bars, EmptyState |
| `titleLarge` | Inter 18/24 w600 | Sheet titles |
| `titleMedium` | Inter 16/22 w600 | Row, section and card titles |
| `titleSmall` | Inter 14/20 w600 | Day headers (mixed case, inkMid) |
| `bodyLarge` | Inter 15/22 | Input text |
| `bodyMedium` | Inter 14/20 | Body copy, empty states |
| `bodySmall` | Inter 13/18, inkMid | Row meta |
| `labelLarge` | Inter 14/20 w500 | Chip and text-button labels |
| `labelMedium` | Inter 12/16 w500, +0.8, inkMid | UPPERCASE overlines only (upper-cased in l10n, never with `toUpperCase()`) |
| `labelSmall` | Inter 11/14 w500, inkMid | Badges, axes, nav labels |

`context.nokText` (`NokturnText`) adds the styles Material does not have, all
Inter: `numRow` 15/20 w600 tabular (row amounts), `numStat` 20/24 w600
tabular (StatTile values), `numMeta` 13/18 w500 tabular (meta numbers,
counters, "x / y"), `time` 13/18 w500 tabular (agenda times), `button` 15/20
w600 (filled buttons, FAB), `reading` 17/28 (journal body).

### 3.2 Numbers and money (`lib/core/formats.dart`)

| Case | TR | EN |
|---|---|---|
| Amount | `₺1.234,56` | `₺1,234.56` |
| Signed income | `+₺1.500,00` | `+₺1,500.00` |
| Expense | `−₺250,00` (true minus U+2212) | `−₺250.00` |
| Exact zero, any variant | `₺0` — never signed | `₺0` |
| Compact (≥ 10 000, narrow slots) | `₺47,5B`, `₺1,2Mn`, `₺3,4Mr` | `₺47.5K`, `₺1.2M`, `₺3.4B` |
| `MoneyDecimals.auto` (chips, tiles, totals) | `₺42.750`, `₺42.750,50` | same rule |
| Gram gold (GAU) | `412 gr` — labelled "Altın" in totals | `412 g` — "Gold" |
| Currency without a symbol | `CHF 1.234,56` | `CHF 1,234.56` |

Symbols (₺ $ € £) sit before the number with no space, the sign before the
symbol. Codes and units are joined with U+00A0, never a plain space (a lone
"₺" or "gr" cannot fall onto its own line). API: `formatMoney(cents,
currency, subunit, {sign, decimals})`, `formatMoneyCompact`,
`formatPercent` (TR `%62`, EN `62%`), `decimalMark()`, `formatTypedAmount`.
Money is never parsed with `double.tryParse(text.replaceAll(',', '.'))` and
never typed on the system keyboard — `AmountKeypad` + `AmountDraft` own it.

**Digit slots.** Fraunces has no tabular figures, so a Fraunces number that
changes is drawn by `RollingNumber` in `DigitSlots`: each digit centred in the
widest digit's advance (measured once per style and text scale), separators
at their natural width, the fraction at 0.6 em on the same baseline, the
whole thing in `FittedBox(scaleDown)` on one line — an amount is shrunk,
never cut with "…" and never wrapped.

---

## 4. Space, shape, surfaces, icons

### 4.1 Spacing and hit targets (`lib/theme/app_metrics.dart`)

`Gap`: 2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 (`xxs` … `x5`).
`Insets`: `gutter` 20 (screen edge), `card` 20 (16 in the goal grid,
`cardGrid`), `rowH` 20 / `rowV` 10, `sheetH` / `formH` 20, `fabClearance` 96,
`captureBarClearance` 84. `Hit.min` 48 dp for anything tappable (the visual
may be smaller), adjacent targets ≥ 8 dp apart.

Rhythm: 12 dp between stacked cards · 24 dp before a 48 dp `SectionHeader` ·
4 dp between a header and its card · 32 dp between sections without a header
· list cards pad 4 dp vertically and let rows bring their own 20 dp.

Rows, cards and headers use `minHeight`, never a fixed height: text grows to
200 % without overflow.

### 4.2 Radii

| Token | dp | Where |
|---|---|---|
| `Radii.xs` | 4 | Bars, skeleton text bones |
| `Radii.sm` | 8 | Tooltip, keypad ripple mask, chart tooltip |
| `Radii.md` | 12 | Input, picker row, StatTile, notice card, snackbar, popup menu |
| `Radii.lg` | 16 | Card, FAB, account tile |
| `Radii.xl` | 24 | Sheet top corners, dialog |
| `StadiumBorder` | — | Chip, pill, segment, badge, Filled and Outlined buttons |

Plain circular corners; no superellipse, no shape morphs.

### 4.3 Surfaces and elevation

| Layer | Dark | Light |
|---|---|---|
| Card | s1 + 1 dp hairline, no shadow | same |
| Nav bar, input, chip rail | s2 (+ top hairline on the nav) | white |
| Sheet | s3, 24 dp top radius, no shadow; scrim | white, modal elevation 8, shadow `#33171310` |
| Dialog | s3, 24 dp, no shadow | white, elevation 6 |
| Snackbar, menu, tooltip | s3 + 1 dp `overlayBorder` | white + border, elevation 6 |
| FAB | gold, elevation 0 | gold, elevation 3 |
| App bar | bg; s1 while content scrolls under it | same |
| Status bar | Today and Finance scroll under a 24 dp bg → transparent fade (`StatusBarScrim`) | same |

**Edge-to-edge.** `main()` sets `SystemUiMode.edgeToEdge`; both system bars
are transparent (`AppBarTheme.systemOverlayStyle`, or an
`AnnotatedRegion` on routes without an app bar). Insets come from
`MediaQuery.paddingOf` / `viewInsetsOf` — the nav bar, every FAB, the
CaptureBar, the keypad's last row and Save, sheets over the keyboard.

No blur, no `BackdropFilter`, no translucency, no wallpaper colour.

### 4.4 Icons

Flutter's built-in `Icons`. Line glyphs are `*_rounded`; shape glyphs are
`*_outlined` at rest and filled `*_rounded` when active. Sizes: 24 app bar,
nav, `IconButton` · 22 settings row lead · 20 row, status, snackbar, filled
button · 18 outlined/text button · 16 chip tick, chevron-down, pill · 14
inline meta (flame) · 28 inside the EmptyState circle. Colour: inkMid by
default, gold when active, error for destructive, inkDisabled when disabled,
`tone.text` for a record. Emoji are never icons (the streak is
`local_fire_department_rounded` in goldBright, "Hepsi tamam" is
`auto_awesome_rounded`); mood emoji are content and stay.

Navigation: Bugün `wb_sunny`, Ajanda `event_note`, Finans
`account_balance_wallet`, Alışkanlık `check_circle(_outline)`, Günlük
`auto_stories`.

---

## 5. Motion

One source: `Motion` in `lib/theme/app_motion.dart`. No `Duration(…)` or
`Curves.…` literal belongs anywhere else in `lib/ui`, `lib/router`,
`lib/theme` or `lib/main.dart` — `test/theme/motion_tokens_test.dart` fails on
one. The documented exceptions are not motion: snackbar reading times
(`app_snackbar.dart`), the server-address ping debounce
(`server_url_field.dart`), the journal draft interval, the milestone answer
window, the Today clock's minute wake-up, the resume-refresh threshold
(`freshness_gate.dart`) and the retired-scroll-controller timer. Overshooting
curves (`easeOutBack`, `elasticOut`, `bounceOut`) are banned everywhere.

### 5.1 Durations

| Token | ms | For |
|---|---|---|
| `pressIn` / `pressOut` | 80 / 150 | Press scale down / back |
| `quick` | 200 | Colour, chip, counter, cross-fade, filter |
| `roll` / `rollOut` | 250 / 180 | Incoming / outgoing rolling digit |
| `typeIn` / `typeDelete` / `typeClear` | 120 / 90 / 150 | The amount being typed |
| `standard` | 300 | Tab fade-through, entrance item, row insert, shared-axis step |
| `collapse` | 250 | Row exit, linger collapse, sheet content resize |
| `sheetIn` / `sheetOut` | 350 / 250 | Bottom sheets |
| `formIn` / `formOut` | 400 / 300 | Full-screen forms |
| `countUp` / `sweep` | 500 / 600 | Hero count-up, first ring/bar sweep |
| `staggerStep` × `staggerCap` | 50 × 6 | Entrance stagger (rise `entranceRise` 12 dp) |
| `barStagger` / `barGrow` | 40 / 350 | Category bars one after another; chart bars growing |
| `skeletonDelay` / `skeletonMinVisible` / `skeletonCrossFade` | 400 / 400 / 250 | First load only |
| `pulse` | 1200 | One skeleton breath (bone → 55 % → bone), no shimmer |
| `syncHintDelay` / `spinnerDelay` / `hintIn` | 1000 / 150 / 150 | Background-sync line, button spinner, small hint fade |
| `busyMinimum` | 300 | A busy button stays busy at least this long |
| `stepSendDelay` | 400 | A stepper sends its value after the last tap |
| `highlight` / `linger` | 1200 / 4000 | "What changed" wash; a checked task lingers |
| `holdChecked` / `doneHold` | 1200 / 2000 | A habit checked on Today stays among the open ones; "Hepsi tamam" before a checklist folds |
| `refreshMinimum` | 500 | Pull-to-refresh never flashes |
| `popUp` / `popSettle` / `fillIn` | 170 / 130 / 250 | Check pop up and settle; check fill |
| `strike` / `swell` / `shake` | 220 / 220 / 240 | Task strike-through; counter swell at target; rejected keypad digit |
| `confetti`, `milestoneIn` / `Hold` / `Out`, `pillDelay` / `pillIn` | 800, 350 / 2500 / 250, 120 / 250 | Celebrations |
| `filterOut` / `filterIn` | 90 / 160 | Journal mood filter |
| `themeChange` | 250 | Light ↔ dark |
| `tooltipWait` | 500 | Tooltip delay |

Press scale: cards 0.98 (`pressScale`), chips and small controls 0.95.

### 5.2 Curves and springs

Curves: `enter` easeOutCubic · `exit` easeInCubic · `press` easeOut ·
`settle` easeInOutCubic · `fadeOut` easeIn / `fadeIn` easeOut · `surfaceIn`
`Easing.emphasizedDecelerate` (sheets, forms, milestone card only) ·
`themeCurve` easeInOutCubic.

Springs (mass 1; ratio 1.0 never overshoots): `fastSpatial` 1400/0.9
(≈ 140 ms), `defaultSpatial` 700/0.9 (≈ 195 ms), `fastEffects` 3800/1.0,
`defaultEffects` 1600/1.0 (≈ 165 ms), `slowEffects` 800/1.0 (≈ 235 ms).

### 5.3 Rules

1. **Springs only** when motion starts from a finger or the target moves
   mid-flight (fling release, quick ± taps, progress after typing, scrub
   release, segment drag). Everything else uses a curve. Drive them with
   `AnimationController.unbounded(animationBehavior: AnimationBehavior.normal)`
   — the default `preserve` is not shortened under reduced motion.
2. **One overshoot:** the check pop, 0.9 → 1.05 → 1.0.
3. **Ceilings:** nothing the user waits on runs past 600 ms; a full stagger is
   ≤ 550 ms; exits are ~25 % shorter than entrances.
4. **Animation stays in the leaf:** `FadeTransition` / `SlideTransition` /
   `ScaleTransition` / `SizeTransition`; painters take `repaint:`; a
   `RepaintBoundary` around the check painter, rings and bars, every chart,
   the celebration layer, the sync hint and the amount display.
5. **Tune on the phone** in a profile build, never in a desktop preview.

### 5.4 Transitions

| From → to | Transition |
|---|---|
| Tab ↔ tab | `FadeThroughBranches`, 300 ms (out 90 ms, in 210 ms with 0.92 → 1.0) |
| List → detail (push) | Theme `PredictiveBackPageTransitionsBuilder` on `MaterialPage` |
| Anywhere → create/edit form | `SlideUpPageRoute`, 400 in / 300 out, follows the back gesture |
| Anywhere → sheet | `showNokSheet`, 350 / 250; content resizes over 250 ms |
| Step inside one surface | `SheetStepSwitcher` (shared axis, 300 ms) |
| Splash / login → Today | Shell `FadeThroughTransition` 350 / 250 |
| Goal ring, account balance | `Hero` with gesture-aware flights |
| Tab re-tap | Scroll to top (jump to 1.5 viewports first if far), refresh only when already at the top |

### 5.5 Loading, lists, values

- **First load:** `LoadPhaseSwitcher` shows nothing for 400 ms, then a
  skeleton that mirrors the real layout and stays ≥ 400 ms; content enters
  once (`EntranceGate`: only on the tab's first visible frame of data, max 6
  staggered items). A refresh never shows a skeleton, a spinner or an
  entrance again — `SyncHint` draws a 2 dp line after 1 s instead.
- **Lists:** `RowEnter` / `RowExit`, `RemovalAwareList`, `HighlightWash` for
  what changed; a checked task lingers 4 s (`LingeringTodos`), then
  collapses.
- **Values:** a value the user changed rolls (`RollingNumber`); a value a
  refresh changed cross-fades in 200 ms; rings and bars retarget with a
  spring (`AnimatedFraction`).

### 5.6 Reduced motion

One signal: `MeridianApp` folds the system's "Remove animations" and the
app's own Profil › Uygulama › "Hareketi azalt" (`reduceMotionProvider`) into
`MediaQuery.disableAnimations`; `Motion.reduced(context)` is the only check.
Then tab switches, pushes, sheets and forms are instant; no entrance, count-up
or digit roll; rings and bars show their value; the check fills at once
(haptic kept); no particles (the pill and the milestone card appear still);
skeletons and the sync line are still; `scrollToTop` / `ensureVisible` jump;
no press scale, no Hero. Delays (skeleton 400 ms, sync hint 1 s, spinner
150 ms) are timers, not animation, and stay — indicators never flicker.

---

## 6. Haptics

The one way the app touches the vibrator: `Haptics` (`lib/core/haptics.dart`).
Call it by meaning; the Android constant and its fallback are chosen there.

| Call | Plays | Below API 30 | Where |
|---|---|---|---|
| `tick()` | `selectionClick` (CLOCK_TICK) | same | Keypad key, counter step, segment, picker, mood, energy, swatch and chip choice, swipe threshold, chart scrub, goal stepper step |
| `check()` | `lightImpact` (VIRTUAL_KEY) | same | One habit or task checked by the user's own tap: a `CheckPop` or `CounterPill`, a habit logged from quick capture, "Bugünü işaretle" on a goal |
| `armed()` | `mediumImpact` (KEYBOARD_TAP) | same | A pull-to-refresh let go past its threshold |
| `confirm()` | `successNotification` (CONFIRM) | `lightImpact` | Every form save, a subscription paid, sign-in, the day done, a goal at 100 %, a milestone |
| `reject()` | `errorNotification` (REJECT) | `vibrate()` | A write taken back, a 422 or validation error, an error snackbar, a quick-capture failure, a refused delete or keypad digit, a wrong password |
| — | `Feedback.forLongPress(context)` | platform | Every long press |

The API level is read once at start-up over `MethodChannel('meridian/device')`
(`MainActivity.kt`, `sdkInt`); web is silent.

**One per gesture.** Requests made while one event is handled are queued and
the highest one plays once in a microtask — the tap that finishes the day
plays `confirm` only, not `check` then `confirm`. A request within 80 ms of the
last one is dropped unless it outranks it. A sheet's check and its Kaydet are
two gestures: checking in the habit log sheet plays `check`, saving it plays
`confirm` (the analysis's §8.9 scenario 2 counted one; the test pins the two,
`test/screens/haptics_test.dart`).

**Never from data.** No haptic for navigation, scrolling, a refresh landing,
un-checking, undo, sign-out, routine deletes or archives, or any widget's
`didUpdateWidget`. Every haptic has a visual twin; it is never the only
signal. (Pinned by `test/core/haptics_unit_test.dart` and
`test/screens/haptics_test.dart`.)

---

## 7. Component inventory

All in `lib/ui/widgets/` unless noted. Screens compose these; a screen does
not re-implement a component locally.

**Surfaces and rows**

| Component | File | What it is |
|---|---|---|
| `NokturnCard` | `nokturn_card.dart` | The card: a `Material` (so ripples show) on s1 with a hairline; `list`, `hero`, `notice` variants; forwards tap and long press |
| `GhostCard` | `nokturn_card.dart` | Dashed stand-in for a card that does not exist yet, with one action and "Gizle"; above 1.3× text the actions move under a message that wraps whole |
| `PressableScale`, `PressableClaim` | `pressable_scale.dart` | Press feedback from pointer-down (0.98 / 0.95), long press with platform feedback; a `PressableClaim` control inside keeps its touches to itself |
| `SectionHeader` | `section_header.dart` | 48 dp section title (a semantic header) with "Tümü ›" and/or "+" targets |
| `NokturnRow`, `LeadingCircle` | `nokturn_row.dart` | The list row (min height, merged semantics, custom actions); the 40 dp record/transfer/uncategorised lead |
| `TodoRow`, `EventRow` | `agenda_rows.dart` | The agenda family: 56 dp lead slot, check area, time column, priority edge |
| `DayHeader` | `day_header.dart` | Mixed-case day heading in lists (semantic header) |
| `SettingsRow` | `settings_row.dart` | Icon · title · value · switch/chevron; the value moves below when wider than 40 % (measured); above 1.3× text the row stacks so long words wrap whole |
| `SwipeAction`, `SwipeSpec` | `swipe_action.dart` | A row's swipe actions: label legible to the threshold, one tick on crossing, each swipe also a semantics action |
| `RowEnter`, `RowExit`, `HighlightWash`, `RowMotion`, `RemovalAwareList`, `FinishedSummaryRow` | `row_motion.dart` | List insert/remove motion and the "what changed" wash |

**Controls and inputs**

| Component | File | What it is |
|---|---|---|
| `PrimaryButton` | `primary_button.dart` | Full-width stadium filled button; loading keeps its colour and shows a spinner after 150 ms (loading ≠ disabled) |
| `CollapsingFab`, `CollapsingFabScope` | `collapsing_fab.dart` | Labelled extended FAB that collapses on scroll and never covers a row's control |
| `CaptureBar`, `CaptureBarLayout` | `capture_bar.dart` | The thumb-zone "Ekle: görev, harcama, etkinlik…" bar of Today and Agenda — a labelled stand-in for a FAB |
| `NokChip` | `nok_chip.dart` | Filter / choice chip (stadium, tick when selected, tick haptic) |
| `ChoiceWrap`, `Choice` | `choice_wrap.dart` | Wrapping single-choice chips (mutually exclusive semantics) |
| `SegmentedPill` | `segmented_pill.dart` | 40 / 32 dp segmented control with a sliding thumb |
| `ColorSwatchRow` | `color_swatches.dart` | Record colours as 36 dp swatches in 48 dp targets; `nextSwatch`, `rotatingSwatch` |
| `AmountKeypad`, `AmountDraft`, `RejectShake` | `amount_keypad.dart` | The 4×3 money keypad (56/64 dp keys, grows with text), the typed amount's model, the refused-digit shake |
| `AmountField`, `showAmountSheet` | `amount_field.dart` | A form row that opens the amount sheet |
| `FormScaffold`, `FormLabel`, `FormPickerRow`, `FormFieldBox`, `FormInlineError`, `confirmDiscard` | `form_scaffold.dart` | Full-screen form chrome: Save above the keyboard, `revealInvalid` scroll + REJECT, discard prompt only for dirty forms |
| `SlideUpPageRoute` | `slide_up_route.dart` | The form route (400/300, gesture-following back) |
| `ServerUrlField` | `server_url_field.dart` | Server address input with a debounced ping |

**Sheets, dialogs, feedback**

| Component | File | What it is |
|---|---|---|
| `showNokSheet`, `SheetHeader`, `SheetActions`, `SheetStepSwitcher` | `nok_sheet.dart` | The one sheet: root navigator, theme scrim, drag handle, visible close, keyboard-aware; never a sheet over a sheet |
| `showPickerSheet`, `PickerOption` | `picker_sheet.dart` | Single-choice list in a sheet |
| `showConfirmDialog`, `showInfoDialog` | `confirm_dialog.dart` | The dialog — only for the five cases in §8.6 |
| `showAppSnack`, `deleteWithUndo`, `deleteNow`, `SnackTone` | `app_snackbar.dart` | Snackbars above the FAB and CaptureBar; 6 s undo; error tone plays REJECT; persistent under accessible navigation |
| `EmptyState` | `empty_state.dart` | page / inline / all-done / error variants; one filled CTA or starter chips |
| `OfflineBanner`, `OfflineBannerSlot` | `offline_banner.dart` | "Çevrimdışı · son güncelleme HH:mm" live region with a 48 dp retry |
| `SyncHint` | `sync_hint.dart` | 2 dp gold line for a background refetch, after 1 s |
| `NokSkeleton`, `Bone` | `skeletons.dart` | Layout-true skeleton bones with a slow pulse |
| `LoadPhaseSwitcher` | `load_phase_switcher.dart` | waiting → skeleton → content/error with the delays of §5.5 |
| `Entrance`, `EntranceGate`, `EntranceHost` | `entrance.dart` | The once-only first-load entrance |
| `StatusBarScrim` | `status_bar_scrim.dart` | bg → transparent fade under the status bar |
| `CelebrationLayer`, `ConfettiBurst` | `celebration_layer.dart` | Tier 2 (day done: 14-particle burst from the finishing control + "Hepsi tamam" pill, once per day; `forget(day)` gives it back when the write is refused) and tier 3 (milestone card) over every route |

**Numbers, progress, charts**

| Component | File | What it is |
|---|---|---|
| `MoneyText` | `money_text.dart` | Money in its variants (hero/display/title/row/meta) with the full signed amount for screen readers |
| `RollingNumber`, `DigitSlots` | `rolling_number.dart` | Slot-aligned Fraunces digits that roll on a user change, count up once, cross-fade on refresh |
| `HeroStat`, `HeroStatSupport` | `hero_stat.dart` | A screen's hero: overline, value, support, footnote, insight |
| `StatTile`, `StatTileRow` | `stat_tile.dart` | 64 dp tiles, three across (two above 1.3×), every tile of a line equally tall |
| `MoneyGlance` | `money_glance.dart` | Today's one-line month-net chip (`MoneyDecimals.auto`), or "open a cash account" |
| `StreakFlame` | `streak_flame.dart` | Flame + days, or "Yeni seri · Rekor n" — never a flame beside 0 |
| `ProgressRing` | `progress_ring.dart` | Ring with sweep on mount and spring retarget; value semantics |
| `PacedProgressBar` | `paced_progress_bar.dart` | Budget/goal bar with a pace mark |
| `AnimatedFraction` | `animated_fraction.dart` | The spring-driven 0…1 that rings and bars share |
| `CheckPop` | `check_pop.dart` | The one check control (circle or rounded square): fill, tick, pop, `check()` haptic from the finger only |
| `CounterPill` | `lib/ui/screens/habits/widgets/counter_pill.dart` | Multi-count habit control: ± steps, odometer digits, swell at the target, never "9/8" |
| `HabitDayCell`, `HabitMonthCalendar`, `HabitDayCellBox`, `HabitDayEditor` | `lib/ui/screens/habits/widgets/` | Chain, perfect day, heatmap and calendar cells (told by shape, not colour alone); the month calendar's out-of-range days stay tappable and readable (inkLow); the editor under it logs or explains a day |
| `SixMonthBars`, `ChartLegendDot` | `charts.dart` | Income (hollow) vs expense (filled) for six months with the average line; drawn only with ≥ 2 months of data |
| `CategoryBars` | `category_bars.dart` | Sorted category bars with amount and share, laid out by measurement (no cut amounts) — replaces the donut |
| `PaceLine` | `pace_line.dart` | This month's cumulative spend vs last month, scrub to read a day |
| `Monogram` | `monogram.dart` | Initials avatar |

---

## 8. Navigation and interaction

### 8.1 Tabs

Five tabs: **Bugün** `/today` · **Ajanda** `/agenda` · **Finans** `/finance` ·
**Alışkanlık** `/habits` (screen title "Alışkanlıklar") · **Günlük**
`/journal`. Hedefler is a pushed page (`/goals`), reached from Today's goals
section, the Habits overflow, a habit's "tracked by" chips, an account's
linked goals and Profil › Veri. Back on a tab root goes to Today; back on
Today leaves the app. A tab tap is silent; re-tapping the current tab scrolls
to the top, or refreshes when already there. Ajanda carries the overdue-task
badge ("Ajanda, 3 gecikmiş görev"). Nav labels grow to 1.3× and no further —
the only text-scale clamp in the app.

### 8.2 Routes

Shell branches use `NoTransitionPage` inside `FadeThroughBranches`; pushed
pages are `MaterialPage` on the root navigator (predictive back):
`/agenda/lists`, `/finance/transactions`, `/finance/account/:id`,
`/finance/accounts` (`?archived=1`), `/finance/categories`,
`/finance/subscriptions`, `/habits/archived`, `/journal/:id`, `/goals`,
`/goals/:id` (the goal passed as `extra` so the ring Hero has its first
frame), `/profile`, `/profile/server`, `/search`. One-shot queries:
`/today?capture=1` (quick add), `/finance?new=tx` (transaction form),
`/journal?new=1` (editor). Old `/todos…` links redirect to the agenda. A 401
goes to `/login?from=<where you were>` and returns there after sign-in.

### 8.3 Which surface

| Surface | For |
|---|---|
| Inline | Checking, counting, the inbox's date chips, "+ Bugün için görev ekle" |
| Sheet (`showNokSheet`) | ≤ 3 inputs + 1 decision; viewing a record and its actions; pickers. Handle, visible ✕ when it has inputs, back closes it, never a sheet over a sheet |
| Full-screen form (`SlideUpPageRoute` + `FormScaffold`) | 4+ inputs or a keypad: transaction, account, habit, goal, event, subscription, journal entry |
| Confirmation sheet | A recurring event's scope, sign-out |
| Dialog | Only §8.6's five cases |
| Pushed page | Management lists, detail pages, Hedefler, Arama |

### 8.4 One interaction grammar

"Tap the row = open it, tap the control = change it", in every list:

| Row | Tap | Control | Long press | Swipe |
|---|---|---|---|---|
| Task | Task sheet | 76×56 check area, undoable | Edit · Tomorrow · Pick date · Priority · Delete | → Done, ← Tomorrow |
| Habit (Today, Habits) | Detail sheet | Ring / pill logs (+1) | Log sheet | — |
| Event | Event sheet | — | — | — |
| Transaction | Detail sheet | — | Edit · Copy to today · Delete | ← Delete (undo) |
| Goal | Detail | — | Add progress (manual) · Edit · Abandon | — |
| Account tile | Detail | — | Edit · Archive | — |
| Journal card | Detail | — | Edit · Delete | — |
| Subscription | Sheet | "Ödendi" inline when due | Edit · Skip · Pause · Delete | — |
| Category | Edit sheet | — | — | — |

Every swipe and long-press action is also a TalkBack `CustomSemanticsAction`.
Detail surfaces show Edit plainly (full-width primary in a sheet, a pencil in
a page's app bar); destructive actions come last (≥ 24 dp below, an error
`TextButton`, or the overflow menu). A pushed page's title is the record
itself (the account's name, the goal's name, the entry's date).

### 8.5 Where creating lives

Today and Agenda: the `CaptureBar` (+ a secondary "İşlem ekle" / "Etkinlik
ekle"), plus Today's inline task row. Finance, Transactions, account detail:
extended FAB "İşlem". Accounts: "Hesap". Subscriptions / Categories:
"Abonelik" / "Kategori". Habits and Goals: an app-bar "Yeni" (Habits adds a
dashed "+ Yeni alışkanlık" row; empty, they show starter chips / the three
goal kinds). Journal: extended FAB "Yaz". The same create action never shows
twice on one screen; when an empty state or setup card carries the CTA, the
FAB hides. Never an icon-only FAB, never a FAB menu, never Save in the app
bar.

### 8.6 Delete, archive, undo

Routine deletes (transaction, task, single event, journal entry, goal,
budget, subscription, an empty account or unused category) disappear at once
with a 6 s "… silindi · Geri al" and a deferred `DELETE`
(`lib/data/deferred_deletes.dart`). Archiving an account or a habit is
immediate with undo and is not red. Abandoning a goal, "Ödendi" on a
subscription and "Hepsini bugüne al" are undoable. Dialogs remain for exactly
five things: deleting a category in use (with counts and where to move them),
deleting an account with consequences, deleting a list that has tasks (keep
or delete them), archiving a habit that feeds a goal, and deleting a habit for
good (with its day count). Each names the object and the outcome and its
button is a verb.

### 8.7 Two homes for management pages

Every management or archive page is reachable from its own area's menu and
from Profil › Veri: Hesaplar (+ archive), Kategoriler, Abonelikler, Görev
listeleri, Arşivlenmiş alışkanlıklar, Hedefler.

---

## 9. Screen patterns

| Screen | Hero | Structure |
|---|---|---|
| Splash, Giriş, Sunucu | The sign-in card | Two-step login (server, then account) with a live server ping; FadeThrough into Today |
| **Bugün** | Today's habits (first ring ≤ 260 dp from the top) | Greeting header with the `MoneyGlance` chip and one nudge slot (or the first-run card) → habits → the Today card (agenda + inline add) → goals; `CaptureBar` at the thumb |
| Hızlı ekle | The line being typed | Sheet: type chips with the app's guess ("Otomatik · Harcama"), one verb button naming the result and the account, steps inside the same sheet |
| **Ajanda** | The next things to do | Upcoming / inbox / overdue / done views, day groups with `DayHeader`, list filter, `CaptureBar`; overdue chip only when there is something |
| **Finans** | This month's net (`HeroStat`) with its sentence | Present first: hero → setup → accounts (tiles) → upcoming payments → budgets → recent transactions → categories (`CategoryBars`) → six months (`SixMonthBars`); FAB "İşlem" |
| Hesaplar, hesap detayı | Totals per currency / the balance (Hero from the tile) | Grouped by type, archive group; reconcile sheet; linked goals |
| İşlemler, işlem formu | The list / the amount | Search (`q`), filter chips, pinned day headers, ← delete with undo; the form is bottom-up — amount, keypad, category chips between the digits and Save |
| Abonelikler, kategoriler, bütçeler | Monthly total / the list / the limit | Inline "Ödendi" when due; category sheet with move-on-delete; budget sheet with the keypad |
| **Alışkanlıklar** | Today's count ("2 / 5 tamamlandı"), then "Hepsi tamam" with the perfect-day streak | Habit cards: dot, name, streak (`StreakFlame`), 30-day rate once there is a day of history, `CheckPop` / `CounterPill`, period pill; detail sheet with heatmap and stats; log sheet for past days |
| Hedefler, hedef detayı | The ring | Grid of goal cards (one column from 1.55×), detail with ring Hero, manual stepper (sends after 400 ms), stat tiles |
| **Günlük** | Today's card (mood buttons) | Entry count and week streak (only when there is one), mood distribution filter, month groups; editor saves on leave, drafts encrypted |
| Profil | The user | Account, app (theme, language, reduce motion as sheets/switches), Veri centre, server, sign-out sheet |
| Arama | The results | Grouped by type, recent searches, opens each record's own surface |

---

## 10. First run, empty states and the zero rules

| Where | When | Shows |
|---|---|---|
| Bugün | New account | The start card "Başlayalım · 0/4" in the nudge slot: open a cash account (one tap) · pick a habit · add the first task · write today; "Gizle" remembers; at 4/4 "Hepsi tamam" for 2 s, then it folds |
| Finans | No account · setup incomplete · no budget or subscription | First-run card · "Kurulum n/4" · `GhostCard` + "Gizle" |
| İşlemler | None ever · none for the filter | "Henüz işlem yok" + "İşlem ekle" · "Bu filtreyle işlem yok" + "Filtreleri temizle" |
| Kategoriler | None | "Hazır kategorileri ekle" |
| Ajanda | Inbox or overdue empty · nothing upcoming | Chip hidden (no 0) · "Önümüzdeki günler sakin" + CaptureBar |
| Alışkanlıklar | None | Starter chips |
| Hedefler | None | The three goal kinds |
| Günlük | Nothing today · empty range | Today card · "Bu aralıkta kayıt yok" + "Tüm kayıtlar" |
| Archives | Empty | Calm text, no CTA |
| Anywhere | Server unreachable, nothing cached | `EmptyState.error` (the Tailscale hint) |

"Nothing planned" and "everything done" differ: the first invites an action,
the second shows the gold "Hepsi tamam" with no CTA.

**Zero rules** — never on screen: a signed zero ("+0,00", "−₺0"), "🔥 0",
"0 seri", "%0 hafta", a 30-day rate before a habit has a day of history
("%0 (30g)"), "0 kayıt" over an empty journal, "₺0 gelir · ₺0 gider" over an
empty transaction list, a record of "0" (shown as "–"), or a chart with
nothing on its axis (six-month bars need two months of data; the pace line
and category bars need something spent). `test/screens/zero_rule_test.dart`
walks every page and the habit sheet with the fixtures, a brand-new account
and an all-zero account, in both languages.

---

## 11. Accessibility and performance gates

- **Contrast:** token pairs in `test/theme/contrast_test.dart` and
  `entity_tone_test.dart`; on real screens `test/widgets/a11y_sweep_test.dart`
  runs Flutter's `textContrastGuideline` on every tab root, Hedefler, Profil
  and the main sheets and forms (quick add, transaction form, task sheet,
  event form, habit detail, habit log, habit form, goal form, journal editor,
  account form, budget sheet), in both themes, every screenful. That
  guideline only reaches a text whose semantics node carries it alone —
  text inside merged rows, tiles, cards and calendar cells is skipped — so
  the sweep also checks every visible paragraph itself: its style colour
  (with any opacity above it) against the most frequent pixel around it,
  disabled controls and icon glyphs exempt.
- **Targets and labels:** the same sweep runs `androidTapTargetGuideline`
  (48×48 dp) and `labeledTapTargetGuideline`. A FAB never covers a row's
  control at any scroll position. Inside a sheet's scrollable the stock tap
  target check skips content below the fold (it compares rects in different
  spaces); the habit calendar's 44 dp-wide cells are the one allowed
  exception there.
- **Text to 200 %:** no overflow, no fixed-height rows, amounts never cut;
  goal grid one column from 1.55×, stat tiles two across and settings rows
  stacked above 1.3×. The only clamp is the nav label (1.3×).
- **Semantics:** `CheckPop` is a checked button with the habit's name;
  `CounterPill` has value / increase / decrease; single-choice chips and
  segments are mutually exclusive; money reads as a full signed amount with
  the digit cells excluded; rings read "%62"; charts read their sentence;
  rows merge and expose swipe/long-press actions; the offline banner is a
  live region; section and day headers are headers. Focus goes into a sheet
  and back to its trigger. Under accessible navigation the undo snackbar
  stays until dismissed.
- **Language:** every string in TR and EN (`AppL10n` is abstract — a missing
  one fails the build); every glyph is in the bundled Inter
  (`test/l10n/glyph_coverage_test.dart`); no `toUpperCase()` on Turkish text.
- **Performance budgets (§8.7 of the analysis)**, on the Android 16 phone,
  120 Hz, profile build: tab switch, a 500-row transaction fling, sheet open,
  check-off on Today and Habits and eight keypad keys a second all keep every
  frame within budget — p90 build ≤ 4 ms, p99 build ≤ 8 ms, p99 raster
  ≤ 8 ms, worst build and raster ≤ 16 ms. Today's content within 1 s of a cold
  start (LAN, token cached), the skeleton only after 400 ms, press feedback
  within 16 ms of pointer-down, an unreachable server reported within ≈ 6 s.
- **Rebuild discipline:** watch only the field you read
  (`ref.watch(provider.select(...))`); a habit tap rebuilds its card and the
  header only; a keypad key rebuilds only the amount display
  (`ValueNotifier<AmountDraft>`); `MediaQuery.sizeOf` / `viewInsetsOf`, not
  `MediaQuery.of`.

---

## 12. Tests, goldens and QA

| What | Where | Run |
|---|---|---|
| Unit and widget suites | `test/` | `flutter test` (use `--concurrency=2` on an 8 GB machine) |
| Motion tokens (mandatory literal scan) | `test/theme/motion_tokens_test.dart` | part of `flutter test` |
| Reduced motion and motion regressions | `test/widgets/motion_test.dart` | part of `flutter test` |
| Haptic regressions | `test/core/haptics_unit_test.dart`, `test/screens/haptics_test.dart` | part of `flutter test` |
| Accessibility sweep | `test/widgets/a11y_sweep_test.dart` | part of `flutter test` |
| Zero rules | `test/screens/zero_rule_test.dart` | part of `flutter test` |
| Large text | `test/screens/large_text_test.dart`, `keypad_sheets_test.dart`, component tests | part of `flutter test` |
| Goldens | `test/golden/<area>_golden_test.dart` + `golden_harness.dart` | `flutter test test/golden --run-skipped` (compare) · `… --update-goldens` (refresh) |
| Live API conformance | `test/live/` | `flutter test test/live --run-skipped` (needs a throwaway server account) |
| Performance | `integration_test/perf_test.dart` + `test_driver/perf_driver.dart` | `flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart -d <device>` |
| Device checklist | `docs/qa-2026-10.md` | by hand on the phone |

**Golden matrix.** Every screen in `tr-dark-1.0`, `en-dark-1.0` and
`tr-light-1.0`; main screens also in `tr-dark-2.0` (and `tr-light-2.0` where an
area adds it). The clock is pinned to Sunday 4 October 2026, 09:41; real
fonts at 360×780 dp, 3×. Images live in
`test/golden/images/<lang>-<theme>-<scale>/<screen>.png`. Goldens are tagged
`golden` and skipped by default because pixels depend on the host's font
rasteriser.

**Anti-patterns rejected in review** (the full list is in the design
analysis): a spinner or a disabled control while a toggle is in flight;
haptics or celebrations from data; skeletons, gaps or replayed entrances over
known data; confirm dialogs for routine, undoable work; showing ✓ before a
record exists; losing input after a 422 or a 401; overshooting curves on a
clipping tween; widget-type swaps after the first frame; `CustomTransitionPage`
on a push; a sheet on a sheet; swipe-only actions; icon-only or menu FABs;
Save in the app bar; the system keyboard for money; a lone "₺"; "…" in an
amount; proportional Fraunces digits in a changing number; text below 4.5:1;
state told by opacity; fixed row heights; `toUpperCase()` on Turkish; red for
a negative net; a flame beside 0; celebrating a past-day log, a refresh or an
undo; donut charts or charts without a sentence; blur, translucency, shimmer,
or loops that ignore reduced motion.
