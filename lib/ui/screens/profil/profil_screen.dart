import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formats.dart';
import '../../../core/session.dart';
import '../../../core/theme_mode.dart';
import '../../../models/user.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/segmented_pill.dart';

const _appVersion = '1.0.0';

/// Bare health ping for the "API durumu" row (re-pings when the URL changes).
/// Public so widget tests can override it with a fixed [HealthResult] instead
/// of hitting the network (a live ping would spin forever under pumpAndSettle).
final apiHealthProvider = FutureProvider.autoDispose<HealthResult>((ref) async {
  final url = ref.watch(serverUrlProvider);
  return pingHealth(url);
});

/// Profil & Ayarlar — pushed from the Bugün avatar (design §4.8).
class ProfilScreen extends ConsumerWidget {
  const ProfilScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final user = ref.watch(currentUserProvider);
    final host =
        ref.watch(serverUrlProvider).replaceFirst(RegExp(r'^https?://'), '');

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _Header(user: user),
          const SizedBox(height: 32),
          const SectionHeader('Uygulama'),
          _GroupCard(children: [
            const _ThemeRow(),
            _divider(c),
            _SettingRow(
              icon: Icons.language,
              title: 'Dil',
              trailing: _ValueText(_localeLabel(user?.locale)),
            ),
            _divider(c),
            _SettingRow(
              icon: Icons.payments_outlined,
              title: 'Para birimi',
              trailing: _ValueText(_currencyLabel(user?.currency)),
            ),
          ]),
          const SizedBox(height: 32),
          const SectionHeader('Sunucu'),
          _GroupCard(children: [
            _SettingRow(
              icon: Icons.dns_outlined,
              title: 'Sunucu adresi',
              trailing: _ValueText(host),
              showChevron: true,
              onTap: () => context.push('/profil/sunucu'),
            ),
          ]),
          const SizedBox(height: 32),
          const SectionHeader('Hakkında'),
          _GroupCard(children: [
            _SettingRow(
              icon: Icons.info_outline,
              title: 'Sürüm',
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
              title: 'Çıkış Yap',
              onTap: () => _confirmLogout(context, ref),
            ),
          ]),
        ],
      ),
    );
  }
}

Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final ok = await showConfirmDialog(
    context,
    title: 'Çıkış yapılsın mı?',
    message: 'Oturumun kapatılacak. Sunucu adresi kayıtlı kalır.',
    confirmLabel: 'Çıkış Yap',
    destructive: true,
  );
  // No haptic — logout is not data-destructive (design §5). Router redirects
  // to /giris once the session flips to logged-out.
  if (ok) ref.read(sessionProvider.notifier).logout();
}

String _localeLabel(String? locale) => switch (locale) {
      'en' => 'English',
      'tr' || null => 'Türkçe',
      _ => locale,
    };

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
    final name = user?.displayName ?? 'Kullanıcı';
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
          Expanded(
            flex: 5,
            child: Text(
              title,
              style: text.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
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
              Text('Tema', style: text.titleMedium),
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
                options: const [
                  (ThemeMode.dark, 'Koyu'),
                  (ThemeMode.light, 'Açık'),
                  (ThemeMode.system, 'Sistem'),
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
      error: (_, _) => status(c.error, 'Ulaşılamıyor'),
      data: (r) => r.ok
          ? status(c.income, 'Çevrimiçi')
          : status(c.error, 'Ulaşılamıyor'),
    );

    return _SettingRow(
      icon: Icons.cloud_outlined,
      title: 'API durumu',
      trailing: trailing,
    );
  }
}
