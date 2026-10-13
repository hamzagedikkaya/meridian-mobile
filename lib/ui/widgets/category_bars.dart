import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import 'animated_fraction.dart';
import 'entrance.dart';

/// What a [CategoryBars] row stands for.
enum CategoryBarKind {
  /// A category, in its own colour.
  category,

  /// The categories past the first five, summed: an inkDisabled bar.
  other,

  /// Spending with no category: a hollow bar and "Kategorize et".
  uncategorized,
}

/// One row of [CategoryBars].
class CategoryBarItem {
  const CategoryBarItem({
    required this.name,
    required this.cents,
    this.color,
    this.kind = CategoryBarKind.category,
    this.onTap,
  });

  final String name;
  final int cents;

  /// The category's fill colour (its `EntityTone.fill`); ignored for
  /// [CategoryBarKind.other] and [CategoryBarKind.uncategorized].
  final Color? color;
  final CategoryBarKind kind;

  /// Opens the category's breakdown sheet.
  final VoidCallback? onTap;
}

/// Where the money went, as ranked bars instead of a donut
/// (design-analysis §4.24): the top five categories, then "Diğer", then
/// "Kategorisiz". Each row (≥ 48 dp) has a 10 dp dot, the name
/// (bodyMedium), the amount (`numRow`) and its share (labelSmall inkMid),
/// and under the name a 6 dp bar on the `track`, scaled to the largest row.
///
/// On the first visible frame of a tab's data (the [EntranceGate]) the bars
/// grow from zero in 500 ms, rows [Motion.barStagger] apart; a refresh
/// moves each bar on a [Motion.defaultEffects] spring. Reduced motion draws
/// them as they are. One `CustomPainter` per bar, inside a
/// `RepaintBoundary`; screen readers hear [semanticsLabel] (the chart's
/// sentence) and then each row.
///
/// Laid out by measurement, not by a text-scale threshold, so nothing
/// overflows and no amount is cut at any text size (§8.3):
///
/// * "Kategorize et" sits beside the uncategorized row only while the name,
///   amount and share still fit next to it; otherwise it goes under the bar.
/// * The amount and share sit beside the name while the name keeps at least
///   40% of the width (or all it needs); otherwise they get their own line
///   under it, shrunk to fit only when even that line is too short.
class CategoryBars extends StatelessWidget {
  const CategoryBars({
    super.key,
    required this.items,
    required this.currency,
    required this.subunitToUnit,
    this.onCategorize,
    this.semanticsLabel,
  });

  final List<CategoryBarItem> items;
  final String currency;
  final int subunitToUnit;

  /// The uncategorized row's "Kategorize et": the month's uncategorized
  /// expenses (`GET /transactions?kind=expense&category_id=none&…`).
  final VoidCallback? onCategorize;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final largest = items.fold<int>(
      0,
      (m, item) => item.cents.abs() > m ? item.cents.abs() : m,
    );
    final total = items.fold<int>(0, (sum, item) => sum + item.cents.abs());
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: RepaintBoundary(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              _Row(
                key: ValueKey((items[i].kind, items[i].name)),
                item: items[i],
                index: i,
                fraction: largest == 0 ? 0 : items[i].cents.abs() / largest,
                share: total == 0 ? 0 : items[i].cents.abs() / total,
                currency: currency,
                subunitToUnit: subunitToUnit,
                onCategorize: onCategorize,
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.item,
    required this.index,
    required this.fraction,
    required this.share,
    required this.currency,
    required this.subunitToUnit,
    required this.onCategorize,
  });

  final CategoryBarItem item;
  final int index;
  final double fraction;
  final double share;
  final String currency;
  final int subunitToUnit;
  final VoidCallback? onCategorize;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> with SingleTickerProviderStateMixin {
  AnimatedFraction? _fraction;

  static const _dot = 10.0;
  static const _dotGap = 12.0;
  static const _gap = 8.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fraction != null) return;
    final delay = Motion.barStagger * widget.index;
    final total = delay + Motion.countUp;
    _fraction = AnimatedFraction(
      vsync: this,
      target: widget.fraction,
      sweep: entranceShouldPlay(context),
      sweepDuration: total,
      sweepCurve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Motion.enter,
      ),
    );
  }

  @override
  void didUpdateWidget(_Row old) {
    super.didUpdateWidget(old);
    if (widget.fraction != old.fraction) {
      _fraction!.retarget(widget.fraction, reduced: Motion.reduced(context));
    }
  }

  @override
  void dispose() {
    _fraction?.dispose();
    super.dispose();
  }

  /// [text]'s one-line width in [style] at the current text size.
  static double _width(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final l = context.l10n;
    final item = widget.item;
    final kind = item.kind;
    final dotColor = switch (kind) {
      CategoryBarKind.category => item.color ?? c.gold,
      CategoryBarKind.other => c.inkDisabled,
      CategoryBarKind.uncategorized => c.track,
    };
    final amount = formatMoney(
      item.cents.abs(),
      widget.currency,
      widget.subunitToUnit,
      decimals: MoneyDecimals.auto,
    );
    final share = formatPercent((widget.share * 100).round());
    final categorize =
        kind == CategoryBarKind.uncategorized ? widget.onCategorize : null;
    final nameStyle = text.bodyMedium;
    final amountStyle = context.nokText.numRow;
    final shareStyle = text.labelSmall!.copyWith(
      color: c.inkMid,
      fontFeatures: tabularFigures,
    );

    Widget figures() => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(amount, style: amountStyle, maxLines: 1, softWrap: false),
            const SizedBox(width: _gap),
            Text(share, style: shareStyle, maxLines: 1, softWrap: false),
          ],
        );

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: LayoutBuilder(builder: (context, box) {
          final nameW = _width(context, item.name, nameStyle);
          final figuresW = _width(context, amount, amountStyle) +
              _gap +
              _width(context, share, shareStyle);
          // The figures fit beside the name while it keeps 40% of [width]
          // (or all it needs).
          bool inline(double width) {
            final name = nameW < width * 0.4 ? nameW : width * 0.4;
            return name + _gap + figuresW <= width;
          }

          final full = box.maxWidth - _dot - _dotGap;
          // "Kategorize et" beside the row takes its label, the button's
          // 12 dp sides and a gap.
          final button = categorize == null
              ? 0.0
              : _gap +
                  _width(
                    context,
                    l.financeCategorize,
                    theme.textButtonTheme.style?.textStyle?.resolve({}) ??
                        text.labelLarge,
                  ) +
                  2 * 12 +
                  4;
          final beside = categorize != null && inline(full - button);
          final width = beside ? full - button : full;
          final sideBySide = inline(width);
          final categorizeButton = categorize == null
              ? null
              : TextButton(
                  onPressed: categorize,
                  child: Text(l.financeCategorize),
                );

          final name = Text(
            item.name,
            style: nameStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: _dot,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: kind == CategoryBarKind.uncategorized
                        ? Border.all(color: c.inkMid)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: _dotGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sideBySide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(child: name),
                          const SizedBox(width: _gap),
                          figures(),
                        ],
                      )
                    else ...[
                      name,
                      // Their own line; shrunk only if even that is short.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: figures(),
                      ),
                    ],
                    const SizedBox(height: 6),
                    CustomPaint(
                      painter: _BarPainter(
                        fraction: _fraction!,
                        fill: dotColor,
                        track: c.track,
                        outline: kind == CategoryBarKind.uncategorized
                            ? c.inkMid
                            : null,
                      ),
                      child: const SizedBox(height: 6, width: double.infinity),
                    ),
                    if (categorizeButton != null && !beside) categorizeButton,
                  ],
                ),
              ),
              if (categorizeButton != null && beside) ...[
                const SizedBox(width: _gap),
                categorizeButton,
              ],
            ],
          );
        }),
      ),
    );
    final onTap = item.onTap;
    if (onTap == null) return MergeSemantics(child: row);
    return MergeSemantics(
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.fraction,
    required this.fill,
    required this.track,
    required this.outline,
  }) : super(repaint: fraction.controller);

  final AnimatedFraction fraction;
  final Color fill;
  final Color track;
  final Color? outline;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    final w = fraction.value * size.width;
    if (w <= 0) return;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w.clamp(size.height, size.width), size.height),
      radius,
    );
    canvas.drawRRect(bar, Paint()..color = fill);
    final outline = this.outline;
    if (outline != null) {
      canvas.drawRRect(
        bar.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = outline,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction ||
      old.fill != fill ||
      old.track != track ||
      old.outline != outline;
}
