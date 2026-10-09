import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import 'nokturn_card.dart';

enum _EmptyVariant { page, inline, allDone, error }

/// What a screen, a section or a list shows when it has nothing to show
/// (design-analysis §4.25, §7.15). Never a bare "0".
///
/// **Page** (the default constructor): centred, at most 280 dp wide — a
/// 64 dp surface2 circle with a 28 dp [icon], 16 dp, the [title]
/// (headlineSmall), 8 dp, the [subtitle] (bodyMedium inkMid), 24 dp, the
/// primary action ([actionLabel] — always a filled button, D23), a
/// [secondaryLabel] text button and, optionally, starter [chips] (`NokChip`s,
/// 8 dp apart). Place it with `SliverFillRemaining(hasScrollBody: false)` so
/// pull-to-refresh still works.
///
/// **[EmptyState.inline]**: a section's quiet line inside a card — icon,
/// message, an optional text button.
///
/// **[EmptyState.allDone]**: the calm "Hepsi tamam" with its sparkle; no
/// action.
///
/// **[EmptyState.error]**: "Sunucuya ulaşılamıyor" — "Tekrar dene" and
/// "Sunucu ayarları".
///
/// When an empty state offers the screen's create action, hide the
/// screen's FAB (`CollapsingFab(hidden: true)`): one control per action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Starter templates under the actions (page variant).
  final List<Widget>? chips;
  final _EmptyVariant _variant;

  const EmptyState({
    super.key,
    this.icon = Icons.blur_on,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.chips,
  }) : _variant = _EmptyVariant.page;

  /// A section's empty line inside a [NokturnCard]: a 20 dp inkMid [icon],
  /// the [message] (bodyMedium inkMid) and an optional text button.
  const EmptyState.inline({
    super.key,
    required this.icon,
    required String message,
    this.actionLabel,
    this.onAction,
  })  : title = message,
        subtitle = null,
        secondaryLabel = null,
        onSecondary = null,
        chips = null,
        _variant = _EmptyVariant.inline;

  /// "Hepsi tamam": a 16 dp gold `auto_awesome_rounded` and the words in
  /// titleSmall gold. [label] replaces the words.
  const EmptyState.allDone({super.key, String? label})
      : icon = Icons.auto_awesome_rounded,
        title = label ?? '',
        subtitle = null,
        actionLabel = null,
        onAction = null,
        secondaryLabel = null,
        onSecondary = null,
        chips = null,
        _variant = _EmptyVariant.allDone;

  /// The server cannot be reached: `cloud_off_rounded`, "Sunucuya
  /// ulaşılamıyor", "Wi-Fi veya Tailscale bağlantını kontrol et", and the
  /// actions [onRetry] ("Tekrar dene") and [onServerSettings].
  const EmptyState.error({
    super.key,
    required VoidCallback onRetry,
    VoidCallback? onServerSettings,
  })  : icon = Icons.cloud_off_rounded,
        title = '',
        subtitle = null,
        actionLabel = null,
        onAction = onRetry,
        secondaryLabel = null,
        onSecondary = onServerSettings,
        chips = null,
        _variant = _EmptyVariant.error;

  @override
  Widget build(BuildContext context) => switch (_variant) {
        _EmptyVariant.page => _page(
            context,
            title: title,
            subtitle: subtitle,
            actionLabel: actionLabel,
            secondaryLabel: secondaryLabel,
          ),
        _EmptyVariant.error => _page(
            context,
            title: context.l10n.errServerUnreachable,
            subtitle: context.l10n.errCheckWifi,
            actionLabel: context.l10n.actionRetry,
            secondaryLabel:
                onSecondary == null ? null : context.l10n.errServerSettings,
          ),
        _EmptyVariant.inline => _inline(context),
        _EmptyVariant.allDone => _allDone(context),
      };

  Widget _page(
    BuildContext context, {
    required String title,
    required String? subtitle,
    required String? actionLabel,
    required String? secondaryLabel,
  }) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final chips = this.chips;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.gutter,
          vertical: Gap.x3,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.hairline),
                ),
                child: Icon(icon, size: 28, color: c.inkMid),
              ),
              const SizedBox(height: Gap.lg),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  subtitle,
                  style: text.bodyMedium!.copyWith(color: c.inkMid),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null || secondaryLabel != null)
                const SizedBox(height: Gap.xxl),
              if (actionLabel != null)
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
              if (secondaryLabel != null) ...[
                if (actionLabel != null) const SizedBox(height: Gap.xs),
                TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
              ],
              if (chips != null && chips.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: Gap.sm,
                  children: chips,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _inline(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final action = actionLabel;
    return NokturnCard(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.sm, Gap.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Hit.min),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.inkMid),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                child: Text(
                  title,
                  style: text.bodyMedium!.copyWith(color: c.inkMid),
                ),
              ),
            ),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }

  Widget _allDone(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome_rounded, size: 16, color: c.gold),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            title.isEmpty ? context.l10n.labelAllDone : title,
            style: text.titleSmall!.copyWith(color: c.gold),
          ),
        ),
      ],
    );
  }
}
