import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/entity_color.dart';

/// The 40 dp circle that leads a row (design-analysis §4.4): an entity's
/// [EntityTone] — its tint behind, a 20 dp icon (or an initial) in its
/// readable text colour.
///
///     LeadingCircle(color: categoryColor, icon: Icons.shopping_cart_outlined)
///     LeadingCircle.tone(entityTone(hex, c), initial: 'M')
///     const LeadingCircle.transfer()
///     const LeadingCircle.uncategorized()
class LeadingCircle extends StatelessWidget {
  /// The entity's colour; its tone is derived ([entityToneOf]).
  final Color? color;

  /// An already derived tone (wins over [color]).
  final EntityTone? tone;
  final IconData? icon;

  /// One letter instead of an icon (a category's initial; uppercase it with
  /// `trUpper`).
  final String? initial;
  final _LeadingKind _kind;

  const LeadingCircle({
    super.key,
    required Color this.color,
    required IconData this.icon,
  })  : tone = null,
        initial = null,
        _kind = _LeadingKind.entity;

  const LeadingCircle.tone(
    EntityTone this.tone, {
    super.key,
    this.icon,
    this.initial,
  })  : color = null,
        _kind = _LeadingKind.entity,
        assert(icon != null || initial != null);

  /// A transfer: surface3 behind `swap_horiz_rounded` in inkMid.
  const LeadingCircle.transfer({super.key})
      : color = null,
        tone = null,
        icon = Icons.swap_horiz_rounded,
        initial = null,
        _kind = _LeadingKind.transfer;

  /// No category: surface2 behind `category_outlined` in inkMid.
  const LeadingCircle.uncategorized({super.key})
      : color = null,
        tone = null,
        icon = Icons.category_outlined,
        initial = null,
        _kind = _LeadingKind.uncategorized;

  static const size = 40.0;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final (Color background, Color foreground) = switch (_kind) {
      _LeadingKind.transfer => (c.surface3, c.inkMid),
      _LeadingKind.uncategorized => (c.surface2, c.inkMid),
      _LeadingKind.entity => () {
          final t = tone ?? entityToneOf(color!, c);
          return (t.tint, t.text);
        }(),
    };
    final initial = this.initial;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: initial != null && icon == null
          ? Text(
              initial,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall!
                  .copyWith(color: foreground, height: 1),
            )
          : Icon(icon, size: 20, color: foreground),
    );
  }
}

enum _LeadingKind { entity, transfer, uncategorized }

/// The shared list row (design-analysis §4.4): at least 64 dp tall — taller
/// when larger text needs it — 20 dp at the sides and 10 dp top and bottom,
/// 12 dp between its parts.
///
/// * [title] titleMedium inkHi — one line, two above 1.3× text.
/// * [meta] bodySmall inkMid, up to two lines (join parts with " · ").
/// * [trailing]: a `numRow` amount, a `Switch`, … — or [chevron] for a row
///   that opens something. Above 1.3× text a [trailing] widget moves under
///   the meta (as a `SettingsRow`'s value does), so the title keeps the
///   row's width rather than breaking mid-word beside a wide amount.
///
/// States: pressed shows the theme's gold ripple (rows never scale);
/// [selected] (a picker's choice) turns the title gold with a gold check;
/// [enabled] false greys the texts to inkDisabled and ignores taps.
///
/// One screen-reader stop ([MergeSemantics]); swipe and long-press actions
/// go in [semanticActions] so TalkBack can reach them (§8.4).
///
/// Separate rows with [NokturnRow.divider] (inset 72 dp: past the leading
/// circle).
class NokturnRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The row is a picker's current choice.
  final bool selected;
  final bool enabled;

  /// A chevron at the end (when there is no [trailing]).
  final bool chevron;

  /// Gesture-only actions (swipe, long press) as TalkBack custom actions.
  final Map<CustomSemanticsAction, VoidCallback>? semanticActions;

  const NokturnRow({
    super.key,
    this.leading,
    required this.title,
    this.meta,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.chevron = false,
    this.semanticActions,
  });

  /// The 1 dp divider between rows, inset past the leading circle
  /// (20 + 40 + 12 = 72 dp).
  static Widget divider({double indent = dividerIndent}) =>
      Divider(height: 1, thickness: 1, indent: indent);

  static const dividerIndent = Insets.rowH + LeadingCircle.size + Gap.md;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final meta = this.meta;
    final titleColor = !enabled
        ? c.inkDisabled
        : selected
            ? c.gold
            : c.inkHi;
    // Large text: the trailing widget goes under the texts.
    final below = large ? trailing : null;
    final end = below != null
        ? null
        : trailing ??
            (selected
                ? Icon(Icons.check_rounded, size: 20, color: c.gold)
                : chevron
                    ? Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: c.inkLow,
                      )
                    : null);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.rowH,
          vertical: Insets.rowV,
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: Gap.md)],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleMedium!.copyWith(color: titleColor),
                    maxLines: large ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta != null && meta.isNotEmpty)
                    Text(
                      meta,
                      style: text.bodySmall!.copyWith(
                        color: enabled ? c.inkMid : c.inkDisabled,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (below != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.xs),
                      child: below,
                    ),
                ],
              ),
            ),
            if (end != null) ...[const SizedBox(width: Gap.md), end],
          ],
        ),
      ),
    );
    return MergeSemantics(
      child: Semantics(
        selected: selected ? true : null,
        customSemanticsActions: enabled ? semanticActions : null,
        child: InkWell(
          onTap: enabled ? onTap : null,
          // InkWell plays the platform's long-press feedback itself.
          onLongPress: enabled ? onLongPress : null,
          child: row,
        ),
      ),
    );
  }
}
