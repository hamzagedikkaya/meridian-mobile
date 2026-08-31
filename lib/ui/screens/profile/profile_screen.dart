import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formats.dart';
import '../../../core/locale_mode.dart';
import '../../../core/session.dart';
import '../../../core/theme_mode.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/user.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/segmented_pill.dart';

const _appVersion = '1.0.0';

/// Bare health ping for the API-status row (re-pings when the URL changes).
/// Public so widget tests can override it with a fixed [HealthResult] instead
/// of hitting the network (a live ping would spin forever under pumpAndSettle).
final apiHealthProvider = FutureProvider.autoDispose<HealthResult>((ref) async {
  final url = ref.watch(serverUrlProvider);
  return pingHealth(url);
});

/// Profile & settings — pushed from the Today avatar (design §4.8).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final l = context.l10n;
    final user = ref.watch(currentUserProvider);
    final host =
        ref.watch(serverUrlProvider).replaceFirst(RegExp(r'^https?://'), '');

    return Scaffold(
      appBar: AppBar(title: Text(l.titleProfile)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _Header(user: user),
          const SizedBox(height: 32),
          SectionHeader(l.profileSectionApp),
          _GroupCard(children: [
            const _ThemeRow(),
            _divider(c),
            const _LanguageRow(),
            _divider(c),
            _SettingRow(
              icon: Icons.payments_outlined,
              title: l.profileCurrency,
              trailing: _ValueText(_currencyLabel(user?.currency)),
            ),
          ]),
          const SizedBox(height: 32),
          SectionHeader(l.profileSectionServer),
          _GroupCard(children: [
            _SettingRow(
              icon: Icons.dns_outlined,
              title: l.serverAddressShort,
              trailing: _ValueText(host),
              showChevron: true,
              onTap: () => context.push('/profile/server'),
            ),
          ]),
          const SizedBox(height: 32),
          SectionHeader(l.profileSectionAbout),
          _GroupCard(children: [
            _SettingRow(
              icon: Icons.info_outline,
              title: l.profileVersion,
              trailing: const _ValueText(_appVersion),
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
              onTap: () => _confirmLogout(context, ref),
            ),
          ]),
        ],
      ),
    );
  }
}

Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final ok = await showConfirmDialog(
    context,
    title: l.profileSignOutTitle,
    message: l.profileSignOutBody,
    confirmLabel: l.profileSignOut,
    destructive: true,
  );
  // No haptic — logout is not data-destructive (design §5). Router redirects
  // to the login screen once the session flips to logged-out.
  if (ok) ref.read(sessionProvider.notifier).logout();
}

String _currencyLabel(String? currency) =>
    currency == null ? '—' : '$currency (${currencySymbol(currency)})';

Divider _divider(NokturnColors c) =>
    Divider(height: 1, thickness: 1, indent: 58, color: c.divider);

// --- Header ------------------------------------------------------------------

class _Header extends StatelessWidget {
  final User? user;
  const _Header({required this.user});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final name = user?.displayName ?? context.l10n.profileFallbackName;
    final email = user?.email ?? '';
    return NokturnCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _InitialsAvatar(initials: _initialsFor(user, name)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: text.headlineMedium,
                  maxLines: 1,
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
        ],
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

/// A grouped surface1 card whose 56dp rows clip to the 16dp radius.
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

/// 56dp settings row: leading icon + title + right-aligned trailing (+chevron).
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    this.iconColor,
    this.trailing,
    this.showChevron = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final row = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(icon, size: 22, color: iconColor ?? c.inkMid),
          const SizedBox(width: 16),
          // The label takes the width it needs and the value gets the rest, so
          // a long label (English is wordier) truncates the value, not itself.
          Flexible(
            child: Text(
              title,
              style: text.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: trailing ?? const SizedBox.shrink(),
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: c.inkLow),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      splashColor: c.gold.withValues(alpha: 0.08),
      child: row,
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
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text.bodyMedium!.copyWith(color: c.inkMid),
    );
  }
}

/// Two-line tile so the 3-segment pill renders at full size on any width;
/// the theme switch is instant (MaterialApp watches themeModeProvider).
class _ThemeRow extends ConsumerWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final mode = ref.watch(themeModeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.brightness_6_outlined, size: 22, color: c.inkMid),
              const SizedBox(width: 16),
              Text(context.l10n.profileTheme, style: text.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedPill<ThemeMode>(
                selected: mode,
                onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
                options: [
                  (ThemeMode.dark, context.l10n.profileThemeDark),
                  (ThemeMode.light, context.l10n.profileThemeLight),
                  (ThemeMode.system, context.l10n.profileThemeSystem),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Language switch, same two-line shape as the theme row. Applying it is
/// instant (MaterialApp watches localeProvider); it is also written to the
/// account, and a failure there is surfaced without undoing the local change.
class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    Locale locale,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await ref.read(localeProvider.notifier).set(locale);
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
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final locale = ref.watch(localeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.language, size: 22, color: c.inkMid),
              const SizedBox(width: 16),
              Text(l.profileLanguage, style: text.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedPill<String>(
                selected: locale.languageCode,
                onChanged: (code) => _select(context, ref, Locale(code)),
                options: [
                  ('tr', l.profileLanguageTr),
                  ('en', l.profileLanguageEn),
                ],
              ),
            ),
          ),
        ],
      ),
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
            Text(label, style: text.bodyMedium!.copyWith(color: color)),
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
    );
  }
}
