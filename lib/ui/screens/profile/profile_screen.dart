import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/locale_mode.dart';
import '../../../core/reduce_motion.dart';
import '../../../core/session.dart';
import '../../../core/theme_mode.dart';
import '../../../core/turkish_case.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/user.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/settings_row.dart';
import 'profile_editors.dart';

const _appVersion = '1.0.0';

/// Bare health ping for the server row (re-pings when the URL changes).
/// Public so widget tests can override it with a fixed [HealthResult] instead
/// of hitting the network (a live ping would spin forever under pumpAndSettle).
final apiHealthProvider = FutureProvider.autoDispose<HealthResult>((ref) async {
  final url = ref.watch(serverUrlProvider);
  return pingHealth(url);
});

/// Profile & settings — pushed from the Today avatar (design-analysis
/// §7.13).
///
/// A calm list of labelled values in [SettingsRow]s: every setting is one
/// row — its name, what it is set to, a chevron — and tapping it opens its
/// editor (a sheet; see `profile_editors.dart`). Long values (the e-mail,
/// the time zone, the server) sit under their name and are never cut.
///
/// * **Hesap** — name, e-mail, password, currency, time zone, weekly review.
/// * **Uygulama** — theme, language, and "Hareketi azalt", the app's own
///   reduce-motion switch (it applies at once, on top of the system's).
/// * **Veri** — every management page, one row away (§6.7).
/// * **Sunucu** — one row: the address, whether it answers, how fast.
/// * **Hakkında**, then signing out on its own card.
///
/// Pull to refresh re-reads the account (`GET /me`), which the web may have
/// changed, and pings the server again.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(apiHealthProvider);
    ref.invalidate(meOptionsProvider);
    await settleRefresh([
      ref.read(sessionProvider.notifier).refreshMe(),
      ref.read(apiHealthProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final l = context.l10n;
    final user = ref.watch(currentUserProvider);
    final weeklyDay = user?.weeklyReviewDay;

    // Account rows edit what the server last said; until it has answered
    // there is nothing to edit (pull to refresh asks again).
    VoidCallback? edit(Future<void> Function(BuildContext, User) open) =>
        user == null ? null : () => open(context, user);

    return Scaffold(
      appBar: AppBar(title: Text(l.titleProfile)),
      body: RefreshIndicator(
        // Armed (§5.8): the pull let go past its threshold.
        onRefresh: () {
          Haptics.armed();
          return _refresh(ref);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            Insets.gutter,
            Gap.sm,
            Insets.gutter,
            Gap.x4,
          ),
          children: [
            _Header(
              user: user,
              onTap: edit((context, user) => showNameEditor(context, user: user)),
            ),
            const SizedBox(height: Gap.xxl),
            SectionHeader(l.profileSectionAccount),
            _Group([
              SettingsRow(
                icon: Icons.badge_outlined,
                title: l.profileName,
                value: user?.displayName ?? '—',
                valuePlacement: ValuePlacement.below,
                onTap:
                    edit((context, user) => showNameEditor(context, user: user)),
              ),
              SettingsRow(
                icon: Icons.alternate_email_rounded,
                title: l.profileEmail,
                value: user?.email ?? '—',
                valuePlacement: ValuePlacement.below,
                onTap: edit(
                    (context, user) => showEmailEditor(context, user: user)),
              ),
              SettingsRow(
                icon: Icons.lock_outline_rounded,
                title: l.profilePassword,
                value: l.profilePasswordAction,
                onTap: () => showPasswordEditor(context),
              ),
              SettingsRow(
                icon: Icons.payments_outlined,
                title: l.profileCurrency,
                value: _currencyLabel(user?.currency, l),
                onTap: edit(
                    (context, user) => showCurrencyEditor(context, user: user)),
              ),
              _TimeZoneRow(user: user),
              SettingsRow(
                icon: Icons.event_repeat_outlined,
                title: l.profileWeeklyReview,
                value: weeklyDay == null
                    ? '—'
                    : weekdayName(weeklyDay, locale: l.localeCode),
                onTap: edit((context, user) =>
                    showWeeklyReviewEditor(context, user: user)),
              ),
            ]),
            const SizedBox(height: Gap.xxl),
            SectionHeader(l.profileSectionApp),
            const _Group([
              _ThemeRow(),
              _LanguageRow(),
              _ReduceMotionRow(),
            ]),
            const SizedBox(height: Gap.xxl),
            SectionHeader(l.profileSectionData),
            _Group([
              for (final (icon, title, location) in _dataPages(l))
                SettingsRow(
                  icon: icon,
                  title: title,
                  onTap: () => context.push(location),
                ),
            ]),
            const SizedBox(height: Gap.xxl),
            SectionHeader(l.profileSectionServer),
            const _Group([_ServerRow()]),
            const SizedBox(height: Gap.xxl),
            SectionHeader(l.profileSectionAbout),
            _Group([
              SettingsRow(
                icon: Icons.info_outline_rounded,
                title: l.profileVersion,
                value: _appVersion,
              ),
            ]),
            const SizedBox(height: Gap.x3),
            _Group([
              SettingsRow(
                icon: Icons.logout_rounded,
                iconColor: c.inkHi,
                title: l.profileSignOut,
                subtitle: l.profileSignOutEverywhere,
                chevron: false,
                onTap: () => showSignOutSheet(context),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The management pages, each also reachable from its own area
/// (design-analysis §6.7, "two homes").
List<(IconData, String, String)> _dataPages(AppL10n l) => [
  (Icons.account_balance_outlined, l.profileDataAccounts, '/finance/accounts'),
  (Icons.category_outlined, l.profileDataCategories, '/finance/categories'),
  (
    Icons.autorenew_rounded,
    l.profileDataSubscriptions,
    '/finance/subscriptions',
  ),
  (Icons.checklist_rounded, l.profileDataLists, '/agenda/lists'),
  (Icons.archive_outlined, l.profileDataArchivedHabits, '/habits/archived'),
  (Icons.flag_outlined, l.profileDataGoals, '/goals'),
];

/// "TRY · ₺" — the code, then its symbol when it has another one.
String _currencyLabel(String? currency, AppL10n l) {
  if (currency == null) return '—';
  final symbol = currencySymbol(currency, locale: l.localeCode);
  return symbol == currency ? currency : '$currency · $symbol';
}

/// "+3", "+5:30", "-4": a zone's offset as people say it.
String _shortOffset(Duration offset) {
  final minutes = offset.inMinutes.abs();
  final sign = offset.isNegative ? '-' : '+';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0
      ? '$sign$hours'
      : '$sign$hours:${rest.toString().padLeft(2, '0')}';
}

// --- Header ------------------------------------------------------------------

/// The avatar, the name and the e-mail; tapping it edits the name.
class _Header extends StatelessWidget {
  final User? user;
  final VoidCallback? onTap;
  const _Header({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final name = user?.displayName ?? l.profileFallbackName;
    final email = user?.email ?? '';
    final avatar = ExcludeSemantics(
      child: _InitialsAvatar(initials: _initialsFor(user, name)),
    );
    final editIcon = onTap == null
        ? null
        : Icon(Icons.edit_outlined, size: 20, color: c.inkLow);
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: text.headlineMedium),
        if (email.isNotEmpty) ...[
          const SizedBox(height: Gap.xxs),
          Text(email, style: text.bodySmall!.copyWith(color: c.inkMid)),
        ],
      ],
    );
    // In large text the name gets the card's whole width, under the avatar,
    // so it breaks between words rather than inside them.
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return NokturnCard(
      padding: const EdgeInsets.all(Gap.lg),
      onTap: onTap,
      child: Semantics(
        hint: onTap == null ? null : l.profileEditName,
        child: large
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      avatar,
                      const Spacer(),
                      ?editIcon,
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  words,
                ],
              )
            : Row(
                children: [
                  avatar,
                  const SizedBox(width: Gap.lg),
                  Expanded(child: words),
                  if (editIcon != null) ...[
                    const SizedBox(width: Gap.sm),
                    editIcon,
                  ],
                ],
              ),
      ),
    );
  }

  String _initialsFor(User? user, String name) {
    final fromApi = user?.initials ?? '';
    if (fromApi.isNotEmpty) return trUpper(fromApi);
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    // Turkish casing: "ilker" → "İ", not "I".
    return words
        .take(2)
        .map((w) => trUpper(String.fromCharCode(w.runes.first)))
        .join();
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String initials;
  const _InitialsAvatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.goldContainer, shape: BoxShape.circle),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(Gap.sm),
          child: Text(
            initials,
            style: text.headlineMedium!.copyWith(
              color: c.onGoldContainer,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

// --- Rows --------------------------------------------------------------------

/// A section's card: [SettingsRow]s on surface1, 1 dp dividers between them.
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group(this.children);

  @override
  Widget build(BuildContext context) {
    return NokturnCard(
      variant: NokCardVariant.list,
      child: Column(
        children: [
          for (final (i, row) in children.indexed) ...[
            if (i > 0) SettingsRow.divider(),
            row,
          ],
        ],
      ),
    );
  }
}

/// The account's time zone — the one every day and time in the app follows
/// (see `data/current_day.dart`): "Europe/Istanbul, UTC+3" under the title,
/// and, when this phone is in another zone, a line saying so. Tapping it
/// opens the time-zone picker.
class _TimeZoneRow extends ConsumerWidget {
  final User? user;
  const _TimeZoneRow({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final user = this.user;
    final offset = user?.utcOffset;
    final value = user == null
        ? '—'
        : offset == null
            ? user.zoneName
            : l.profileTimeZoneValue(user.zoneName, _shortOffset(offset));
    final mismatch = ref.watch(zoneMismatchProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsRow(
          icon: Icons.schedule_rounded,
          title: l.profileTimeZone,
          value: value,
          valuePlacement: ValuePlacement.below,
          onTap: user == null
              ? null
              : () => showTimeZoneEditor(context, user: user),
        ),
        if (mismatch != null)
          Padding(
            // Under the title, past the icon (20 + 24 + 16).
            padding: const EdgeInsets.fromLTRB(60, 0, Insets.rowH, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: c.warning,
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Text(
                    l.profileTimeZoneDeviceDiffers(
                      formatUtcOffset(mismatch.device),
                    ),
                    style: text.bodySmall!.copyWith(color: c.warning),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The theme, picked in a sheet. It applies at once (MaterialApp watches
/// themeModeProvider) and is written to the account as well; a failure
/// there is said without undoing the change on this device.
class _ThemeRow extends ConsumerWidget {
  const _ThemeRow();

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
  ) async {
    final l = context.l10n;
    final picked = await showPickerSheet<ThemeMode>(
      context,
      title: l.profileTheme,
      selected: mode,
      options: [
        for (final (value, label) in _options(l))
          PickerOption(value: value, label: label),
      ],
    );
    if (picked == null || picked == mode || !context.mounted) return;
    final saved = await ref.read(themeModeProvider.notifier).set(picked);
    if (!saved && context.mounted) {
      showAppSnack(context, context.l10n.profileThemeSaveFailed);
    }
  }

  static List<(ThemeMode, String)> _options(AppL10n l) => [
    (ThemeMode.dark, l.profileThemeDark),
    (ThemeMode.light, l.profileThemeLight),
    (ThemeMode.system, l.profileThemeSystem),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final mode = ref.watch(themeModeProvider);
    final label = _options(l).firstWhere((o) => o.$1 == mode).$2;
    return SettingsRow(
      icon: Icons.brightness_6_outlined,
      title: l.profileTheme,
      value: label,
      onTap: () => _pick(context, ref, mode),
    );
  }
}

/// The language, picked in a sheet. Applying it is instant (MaterialApp
/// watches localeProvider); it is also written to the account — which has
/// every screen refetched, so the server's own text follows — and a failure
/// there is said without undoing the change on this device.
class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  Future<void> _pick(BuildContext context, WidgetRef ref, Locale now) async {
    final l = context.l10n;
    final picked = await showPickerSheet<String>(
      context,
      title: l.profileLanguage,
      selected: now.languageCode,
      options: [
        PickerOption(value: 'tr', label: l.profileLanguageTr),
        PickerOption(value: 'en', label: l.profileLanguageEn),
      ],
    );
    if (picked == null || picked == now.languageCode || !context.mounted) {
      return;
    }
    final saved = await ref.read(localeProvider.notifier).set(Locale(picked));
    if (!saved && context.mounted) {
      showAppSnack(context, context.l10n.profileLanguageSaveFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final locale = ref.watch(localeProvider);
    return SettingsRow(
      icon: Icons.language_rounded,
      title: l.profileLanguage,
      value: locale.languageCode == 'en'
          ? l.profileLanguageEn
          : l.profileLanguageTr,
      onTap: () => _pick(context, ref, locale),
    );
  }
}

/// "Hareketi azalt": the app's own reduce-motion switch, on top of the
/// system's "Remove animations" (design-analysis §5.9). It applies at once
/// — `MeridianApp` folds it into `MediaQuery.disableAnimations` — and stays
/// on this device.
class _ReduceMotionRow extends ConsumerWidget {
  const _ReduceMotionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final on = ref.watch(reduceMotionProvider);
    void set(bool value) => ref.read(reduceMotionProvider.notifier).set(value);
    return SettingsRow(
      icon: Icons.motion_photos_off_outlined,
      title: l.profileReduceMotion,
      subtitle: l.profileReduceMotionNote,
      trailing: Switch(value: on, onChanged: set),
      onTap: () => set(!on),
    );
  }
}

/// The server, in one row (design-analysis §7.13): its address under the
/// title, then a dot — income when it answers, error when not — the word
/// for it and the round trip: "192.168.1.24:3000 · ● Bağlı · 38 ms". Opens
/// the server settings.
class _ServerRow extends ConsumerWidget {
  const _ServerRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final host =
        ref.watch(serverUrlProvider).replaceFirst(RegExp(r'^https?://'), '');
    final health = ref.watch(apiHealthProvider);
    // The last answer stays up while a new ping is out.
    final last = health.value;
    final (Color dot, String status, int? latency) = last != null
        ? last.ok
            ? (c.income, l.profileApiOnline, last.latencyMs)
            : (c.error, l.profileApiUnreachable, null)
        : health.hasError
            ? (c.error, l.profileApiUnreachable, null)
            : (c.inkDisabled, l.profileServerChecking, null);
    final valueStyle = text.bodyMedium!.copyWith(color: c.inkMid);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final value = Text.rich(
      TextSpan(
        style: valueStyle,
        children: [
          TextSpan(text: '$host · '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ExcludeSemantics(
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: Gap.xs),
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
            ),
          ),
          TextSpan(text: status),
          // No-break spaces around the second dot: "Bağlı · 38 ms" wraps
          // as one piece, never starting a line with "· 38 ms".
          if (latency != null)
            TextSpan(text: '\u00A0·\u00A0${l.serverLatency(latency)}'),
        ],
      ),
    );

    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.serverAddressShort,
          style: text.titleMedium,
          maxLines: large ? null : 2,
        ),
        value,
      ],
    );
    final icon = SizedBox(
      width: 24,
      child: Icon(Icons.dns_outlined, size: 22, color: c.inkMid),
    );
    final chevron =
        Icon(Icons.chevron_right_rounded, size: 20, color: c.inkLow);

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: () => context.push('/profile/server'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.rowH,
                vertical: Insets.rowV,
              ),
              // In large text the words get the row's whole width, under
              // the icon and the chevron, so the address does not break
              // a few letters at a time.
              child: large
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            icon,
                            const Spacer(),
                            chevron,
                          ],
                        ),
                        const SizedBox(height: Gap.xs),
                        words,
                      ],
                    )
                  : Row(
                      children: [
                        icon,
                        const SizedBox(width: Gap.lg),
                        Expanded(child: words),
                        const SizedBox(width: Gap.xs),
                        chevron,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
