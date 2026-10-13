import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';

/// Where a [SettingsRow] shows its value (design-analysis D15).
enum ValuePlacement {
  /// At the end of the row, beside the title — for short values ("Koyu",
  /// "TRY · ₺"). Falls back to [below] when it would not fit.
  trailing,

  /// Under the title, wrapping as needed — for values that must never be
  /// cut (an e-mail, a server address, a time zone).
  below,
}

/// A row of a settings list (design-analysis §4.7): a 22 dp icon, the
/// [title], its [value], and a chevron or a control.
///
/// * At least 56 dp tall (64 with the value below); 20 dp at the sides,
///   10 dp top and bottom.
/// * [ValuePlacement.trailing] keeps the value (bodyMedium inkMid) to at
///   most 40 % of the row; a value that is wider — measured, not guessed —
///   moves [ValuePlacement.below], and so does one that would leave the
///   title too narrow for its two lines, or a word of it too wide for its
///   column ("değerlendirme" beside "Çarşamba" at 115 %). Above 1.3× text
///   every value goes below.
///   A value is never cut.
/// * Above 1.3× text the row stacks: the icon and the end control share
///   the first line and the title, subtitle and value get the full width
///   under them, so a long word ("değerlendirme") wraps whole instead of
///   breaking mid-word in a narrow column (§4.7, §8.3).
/// * The end: [trailing] (a `Switch`), else a chevron when the row opens
///   something ([onTap] and [chevron]).
///
/// One screen-reader stop that reads the title and the value, as a button
/// when it opens something. Separate rows with [SettingsRow.divider].
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final ValuePlacement valuePlacement;

  /// A quieter second line under the title (not the value).
  final String? subtitle;

  /// A control at the end, instead of the chevron.
  final Widget? trailing;

  /// The icon's colour; inkMid by default (error for "Çıkış yap").
  final Color? iconColor;

  /// The title's colour; inkHi by default.
  final Color? titleColor;
  final bool chevron;
  final VoidCallback? onTap;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.valuePlacement = ValuePlacement.trailing,
    this.subtitle,
    this.trailing,
    this.iconColor,
    this.titleColor,
    this.chevron = true,
    this.onTap,
  });

  /// The 1 dp divider between settings rows, inset past the icon
  /// (20 + 24 + 16 = 60 dp) — or by the row's own inset when the rows stack
  /// ([stacks]), where the title starts under the icon.
  static Widget divider() => Builder(
    builder: (context) => Divider(
      height: 1,
      thickness: 1,
      indent: stacks(MediaQuery.textScalerOf(context)) ? Insets.rowH : 60,
    ),
  );

  /// Above 1.3× text the row stacks: the icon line, then the title.
  static bool stacks(TextScaler scaler) => scaler.scale(1) > 1.3;

  /// The widest a trailing value may be, as a share of the row.
  static const trailingShare = 0.4;

  /// Whether the title fits beside a trailing value, the row being [room]
  /// wide without it: two lines at most, no word broken.
  bool _titleFits(
    BuildContext context,
    TextStyle style,
    TextScaler scaler,
    double room,
  ) {
    // The padding, the icon and its gap, the gap before the value, and
    // the end (a chevron, or a control).
    final endWidth = trailing != null
        ? 60.0
        : (chevron && onTap != null ? 20.0 + Gap.xs : 0.0);
    final width = room - 2 * Insets.rowH - 24 - Gap.lg - Gap.md - endWidth;
    if (width <= 0) return false;
    final direction = Directionality.of(context);
    TextPainter measure(String text, {int? maxLines}) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: maxLines,
    )..layout(maxWidth: width);
    final lines = measure(title, maxLines: 2);
    var fits = !lines.didExceedMaxLines;
    lines.dispose();
    for (final word in title.split(RegExp(r'\s+'))) {
      if (!fits) break;
      if (word.isEmpty) continue;
      final w = measure(word);
      fits = w.width <= width && w.computeLineMetrics().length <= 1;
      w.dispose();
    }
    return fits;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final value = this.value;
    final valueStyle = text.bodyMedium!.copyWith(color: c.inkMid);
    final titleStyle = text.titleMedium!.copyWith(color: titleColor);

    final row = LayoutBuilder(
      builder: (context, constraints) {
        final large = stacks(scaler);
        var below = valuePlacement == ValuePlacement.below || large;
        if (!below && value != null && constraints.hasBoundedWidth) {
          final painter = TextPainter(
            text: TextSpan(text: value, style: valueStyle),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          below = painter.width > constraints.maxWidth * trailingShare;
          if (!below) {
            below = !_titleFits(
              context,
              titleStyle,
              scaler,
              constraints.maxWidth - painter.width,
            );
          }
          painter.dispose();
        }
        final titleBlock = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Two lines at most (§4.7) — except in large text, where the
            // stacked title has the row's width and wraps as it needs.
            Text(title, style: titleStyle, maxLines: large ? null : 2),
            if (subtitle != null) Text(subtitle!, style: text.bodySmall),
            if (below && value != null) Text(value, style: valueStyle),
          ],
        );
        final end = trailing ??
            (chevron && onTap != null
                ? Icon(Icons.chevron_right_rounded, size: 20, color: c.inkLow)
                : null);
        final leading = SizedBox(
          width: 24,
          child: Icon(icon, size: 22, color: iconColor ?? c.inkMid),
        );
        if (large) {
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.rowH,
                vertical: Insets.rowV,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      leading,
                      const Spacer(),
                      ?end,
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  titleBlock,
                ],
              ),
            ),
          );
        }
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: below && value != null ? 64 : 56,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.rowH,
              vertical: Insets.rowV,
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: Gap.lg),
                Expanded(child: titleBlock),
                if (!below && value != null) ...[
                  const SizedBox(width: Gap.md),
                  Text(value, style: valueStyle, textAlign: TextAlign.end),
                ],
                if (end != null) ...[const SizedBox(width: Gap.xs), end],
              ],
            ),
          ),
        );
      },
    );

    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}
