import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/session.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import 'pressable_scale.dart';

/// How a [NokturnCard] pads its content (design-analysis §4.1).
enum NokCardVariant {
  /// 20 dp all round — the everyday card.
  standard,

  /// 20 dp — the one hero card of a screen (Finance net, …).
  hero,

  /// 16 dp — the goal grid only.
  grid,

  /// 4 dp top and bottom, nothing at the sides: a card that holds rows,
  /// which bring their own 20 dp (`NokturnRow`, `SettingsRow`).
  list,
}

/// The card: surface1, a 1 dp hairline, 16 dp corners — never a shadow
/// (design-analysis §4.1, §3.10).
///
/// It is a [Material], so the ripple of every `InkWell` inside it (a row, a
/// button) paints on top of the card's colour; a `Container` would hide it.
/// Its content is clipped to the rounded shape.
///
/// With [onTap] or [onLongPress] the whole card is one button: it scales
/// to 0.98 under the finger ([PressableScale]) and a screen reader reads it
/// as a single button ([MergeSemantics]). Give a card with controls of its
/// own (a check, a counter) no [onTap] — tap its rows instead.
///
///     NokturnCard(child: …)                                  // 20 dp
///     NokturnCard(variant: NokCardVariant.list, child: Column(children: rows))
///     NokturnCard(onTap: open, onLongPress: actions, child: …)
class NokturnCard extends StatelessWidget {
  final Widget child;

  /// Overrides the [variant]'s padding.
  final EdgeInsetsGeometry? padding;
  final NokCardVariant variant;
  final VoidCallback? onTap;

  /// The card's long-press actions (an action sheet; IA-20).
  final VoidCallback? onLongPress;

  /// The card's surface; surface1 by default.
  final Color? color;

  const NokturnCard({
    super.key,
    required this.child,
    this.padding,
    this.variant = NokCardVariant.standard,
    this.onTap,
    this.onLongPress,
    this.color,
  });

  /// The padding of [variant].
  static EdgeInsetsGeometry paddingOf(NokCardVariant variant) =>
      switch (variant) {
        NokCardVariant.standard ||
        NokCardVariant.hero =>
          const EdgeInsets.all(Insets.card),
        NokCardVariant.grid => const EdgeInsets.all(Insets.cardGrid),
        NokCardVariant.list => const EdgeInsets.symmetric(vertical: Gap.xs),
      };

  /// The card's shape: 16 dp corners and the hairline. `AccountTile` and
  /// other card-like surfaces reuse it.
  static ShapeBorder shapeOf(NokturnColors c) => RoundedRectangleBorder(
        borderRadius: Radii.lgAll,
        side: BorderSide(color: c.hairline),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final card = SizedBox(
      width: double.infinity,
      child: Material(
        color: color ?? c.surface1,
        shape: shapeOf(c),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding ?? paddingOf(variant),
          child: child,
        ),
      ),
    );
    if (onTap == null && onLongPress == null) return card;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: PressableScale(
          onTap: onTap,
          onLongPress: onLongPress,
          child: card,
        ),
      ),
    );
  }
}

/// A dashed stand-in for a card that does not exist yet — "add your first
/// account" in an empty state (design-analysis §4.1).
///
/// Transparent, with a 1 dp dashed inkFaint border (6 on, 4 off) and 16 dp
/// corners: a 20 dp [icon], up to two lines of [message], the gold
/// [actionLabel] and — with a [dismissKey] — "Gizle", which hides it for
/// good on this device (SharedPreferences `ghost.<dismissKey>.dismissed`).
class GhostCard extends ConsumerStatefulWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Makes the card dismissible: "Gizle" hides it and remembers that.
  final String? dismissKey;

  /// Called after "Gizle" hid the card.
  final VoidCallback? onDismissed;

  const GhostCard({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.dismissKey,
    this.onDismissed,
  });

  /// The SharedPreferences key that remembers a dismissed ghost card.
  static String prefKey(String dismissKey) => 'ghost.$dismissKey.dismissed';

  @override
  ConsumerState<GhostCard> createState() => _GhostCardState();
}

class _GhostCardState extends ConsumerState<GhostCard> {
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    final key = widget.dismissKey;
    if (key != null) {
      _hidden = _prefs()?.getBool(GhostCard.prefKey(key)) ?? false;
    }
  }

  /// The device's preferences — absent in tests that do not provide them,
  /// where a dismissal lasts as long as the card.
  SharedPreferences? _prefs() {
    try {
      return ref.read(sharedPrefsProvider);
    } catch (_) {
      return null;
    }
  }

  void _dismiss() {
    setState(() => _hidden = true);
    _prefs()?.setBool(GhostCard.prefKey(widget.dismissKey!), true);
    widget.onDismissed?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final action = widget.actionLabel;
    final buttons = [
      if (action != null)
        TextButton(onPressed: widget.onAction, child: Text(action)),
      if (widget.dismissKey != null)
        TextButton(
          onPressed: _dismiss,
          style: TextButton.styleFrom(foregroundColor: c.inkMid),
          child: Text(l.actionHide),
        ),
    ];
    // Above 1.3x text the actions move under the message, which then wraps
    // over as many lines as it needs: at 2.0x on a 360 dp phone two lines
    // cut it (§8.3: text grows, it is never cut).
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final message = Text(
      widget.message,
      maxLines: large ? null : 2,
      overflow: large ? null : TextOverflow.ellipsis,
      style: text.bodyMedium!.copyWith(color: c.inkMid),
    );
    return CustomPaint(
      painter: _DashedBorderPainter(color: c.inkFaint),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.sm, Gap.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: large
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.sm),
                      child: Row(
                        children: [
                          Icon(widget.icon, size: 20, color: c.inkMid),
                          const SizedBox(width: Gap.md),
                          Expanded(child: message),
                        ],
                      ),
                    ),
                    Wrap(alignment: WrapAlignment.end, children: buttons),
                  ],
                )
              : Row(
                  children: [
                    Icon(widget.icon, size: 20, color: c.inkMid),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                        child: message,
                      ),
                    ),
                    ...buttons,
                  ],
                ),
        ),
      ),
    );
  }
}

/// A 1 dp dashed rounded rectangle (6 dp dash, 4 dp gap), walked along the
/// path's metrics so the dashes follow the corners.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  static const _dash = 6.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(Radii.lg)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
