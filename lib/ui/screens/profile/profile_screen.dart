import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formats.dart';
import '../../../core/locale_mode.dart';
import '../../../core/session.dart';
import '../../../core/theme_mode.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/user.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/section_header.dart';
import 'profile_editors.dart';

const _appVersion = '1.0.0';

/// Bare health ping for the API-status row (re-pings when the URL changes).
/// Public so widget tests can override it with a fixed [HealthResult] instead
/// of hitting the network (a live ping would spin forever under pumpAndSettle).
final apiHealthProvider = FutureProvider.autoDispose<HealthResult>((ref) async {
  final url = ref.watch(serverUrlProvider);
  return pingHealth(url);
});

/// Profile & settings — pushed from the Today avatar (design-research §5.7).
///
/// A calm list of labelled values: every setting is one row — its name, what
/// it is set to, a chevron — and tapping it opens its editor (a sheet; see
/// `profile_editors.dart`). Pull to refresh re-reads the account (`GET /me`),
/// which the web may have changed, and pings the server again.
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
    final host =
        ref.watch(serverUrlProvider).replaceFirst(RegExp(r'^https?://'), '');
    final weeklyDay = user?.weeklyReviewDay;

    // Account rows edit what the server last said; until it has answered
    // there is nothing to edit (pull to refresh asks again).
    VoidCallback? edit(Future<void> Function(BuildContext, User) open) =>
        user == null ? null : () => open(context, user);

    return Scaffold(
      appBar: AppBar(title: Text(l.titleProfile)),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _Header(
              user: user,
              onTap: edit((context, user) => showNameEditor(context, user: user)),
            ),
            const SizedBox(height: 32),
            SectionHeader(l.profileSectionAccount),
            _GroupCard(children: [
              _SettingRow(
                icon: Icons.badge_outlined,
                title: l.profileName,
                value: user?.displayName ?? '—',
                onTap:
                    edit((context, user) => showNameEditor(context, user: user)),
              ),
              _divider(c),
              _SettingRow(
                icon: Icons.alternate_email,
                title: l.profileEmail,
                value: user?.email ?? '—',
                onTap: edit(
                    (context, user) => showEmailEditor(context, user: user)),
              ),
              _divider(c),
              _SettingRow(
                icon: Icons.lock_outline,
                title: l.profilePassword,
                value: l.profilePasswordAction,
                onTap: () => showPasswordEditor(context),
              ),
              _divider(c),
              _SettingRow(
                icon: Icons.payments_outlined,
                title: l.profileCurrency,
                value: _currencyLabel(user?.currency),
                onTap: edit(
                    (context, user) => showCurrencyEditor(context, user: user)),
              ),
              _divider(c),
              _TimeZoneRow(user: user),
              _divider(c),
              _SettingRow(
                icon: Icons.event_repeat_outlined,
                title: l.profileWeeklyReview,
                value: weeklyDay == null
                    ? '—'
                    : weekdayName(weeklyDay, locale: l.localeCode),
                onTap: edit((context, user) =>
                    showWeeklyReviewEditor(context, user: user)),
              ),
            ]),
            const SizedBox(height: 32),
            SectionHeader(l.profileSectionApp),
            _GroupCard(children: [
              const _ThemeRow(),
              _divider(c),
              const _LanguageRow(),
            ]),
            const SizedBox(height: 32),
            SectionHeader(l.profileSectionServer),
            _GroupCard(children: [
              _SettingRow(
                icon: Icons.dns_outlined,
                title: l.serverAddressShort,
                value: host,
                onTap: () => context.push('/profile/server'),
              ),
            ]),
            const SizedBox(height: 32),
            SectionHeader(l.profileSectionAbout),
            _GroupCard(children: [
              _SettingRow(
                icon: Icons.info_outline,
                title: l.profileVersion,
                value: _appVersion,
              ),
              _divider(c),
              const _ApiStatusRow(),
            ]),
            const SizedBox(height: 32),
            _GroupCard(children: [
              _SettingRow(
                icon: Icons.logout,
                iconColor: c.inkHi,
                title: l.profileSignOut,
                subtitle: l.profileSignOutEverywhere,
                showChevron: false,
                onTap: () => showSignOutSheet(context),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

String _currencyLabel(String? currency) =>
    currency == null ? '—' : '$currency (${currencySymbol(currency)})';

Divider _divider(NokturnColors c) =>
    Divider(height: 1, thickness: 1, indent: 58, color: c.divider);

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
    return Semantics(
      button: onTap != null,
      hint: onTap == null ? null : l.profileEditName,
      child: NokturnCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: c.gold.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: _InitialsAvatar(initials: _initialsFor(user, name)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: text.headlineMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: text.bodySmall!.copyWith(color: c.inkMid),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.edit_outlined, size: 20, color: c.inkLow),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initialsFor(User? user, String name) {
    final fromApi = user?.initials ?? '';
    if (fromApi.isNotEmpty) return fromApi;
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
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
      child: Text(
        initials,
        style: text.headlineMedium!.copyWith(color: c.gold, height: 1),
      ),
    );
  }
}

// --- Rows --------------------------------------------------------------------

/// A grouped surface1 card whose rows clip to the 16dp radius.
class _GroupCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return NokturnCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }
}

/// A settings row, at least 56dp tall (it grows with the text size): icon,
/// title (and an optional line under it), the value on the right, and a
/// chevron when tapping it opens an editor. Read out as one item: "Para
/// birimi, TRY (₺), button".
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    this.iconColor,
    this.subtitle,
    this.value,
    this.trailing,
    this.showChevron = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final value = this.value;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor ?? c.inkMid),
            const SizedBox(width: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    // The title takes what it needs, up to 60% of the row;
                    // the value gets the rest, so a long server address or
                    // e-mail is cut on the right, never the label.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.6,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: text.titleMedium),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: text.bodySmall!.copyWith(color: c.inkMid),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child:
                            trailing ??
                            (value == null
                                ? const SizedBox.shrink()
                                : _ValueText(value)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showChevron && onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: c.inkLow),
            ],
          ],
        ),
      ),
    );
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          splashColor: c.gold.withValues(alpha: 0.08),
          child: row,
        ),
      ),
    );
  }
}

/// The account's time zone — the one every day and time in the app follows
/// (see `data/current_day.dart`) — and, when this phone is in another one,
/// a line saying so. Tapping it opens the time-zone picker.
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
            : l.profileTimeZoneValue(user.zoneName, formatUtcOffset(offset));
    final mismatch = ref.watch(zoneMismatchProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingRow(
          icon: Icons.schedule,
          title: l.profileTimeZone,
          value: value,
          onTap: user == null
              ? null
              : () => showTimeZoneEditor(context, user: user),
        ),
        if (mismatch != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(58, 0, 20, 14),
            child: Text(
              l.profileTimeZoneDeviceDiffers(formatUtcOffset(mismatch.device)),
              style: text.bodySmall!.copyWith(color: c.warning),
            ),
          ),
      ],
    );
  }
}

class _ValueText extends StatelessWidget {
  final String value;
  const _ValueText(this.value);

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Text(
      value,
      textAlign: TextAlign.end,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text.bodyMedium!.copyWith(color: c.inkMid),
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
    return _SettingRow(
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
    final messenger = ScaffoldMessenger.of(context);
    final saved = await ref.read(localeProvider.notifier).set(Locale(picked));
    if (!saved && context.mounted) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.l10n.profileLanguageSaveFailed)),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final locale = ref.watch(localeProvider);
    return _SettingRow(
      icon: Icons.language,
      title: l.profileLanguage,
      value: locale.languageCode == 'en'
          ? l.profileLanguageEn
          : l.profileLanguageTr,
      onTap: () => _pick(context, ref, locale),
    );
  }
}

class _ApiStatusRow extends ConsumerWidget {
  const _ApiStatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final health = ref.watch(apiHealthProvider);

    Widget status(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium!.copyWith(color: color),
              ),
            ),
          ],
        );

    final trailing = health.when(
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => status(c.error, l.profileApiUnreachable),
      data: (r) => r.ok
          ? status(c.income, l.profileApiOnline)
          : status(c.error, l.profileApiUnreachable),
    );

    return _SettingRow(
      icon: Icons.cloud_outlined,
      title: l.profileApiStatus,
      trailing: trailing,
      showChevron: false,
      // The ping runs once per visit; a tap checks again (e.g. once the Mac
      // is awake), keeping the last answer up meanwhile.
      onTap: () => ref.invalidate(apiHealthProvider),
    );
  }
}
