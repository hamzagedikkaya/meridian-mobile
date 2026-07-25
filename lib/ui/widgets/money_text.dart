import 'package:flutter/material.dart';
import '../../core/formats.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

enum MoneyVariant { hero, title, row, meta }

/// All money rendering goes through this widget (design §2.4).
/// Income green with explicit +, expenses inkHi with explicit − — never color-only.
/// Hero money counts up once on first load (§5); refreshes never re-count
/// (data honesty).
class MoneyText extends StatefulWidget {
  final int cents;
  final String currency;
  final int subunitToUnit;
  final MoneyVariant variant;
  final bool signed;
  final bool negative;
  final bool positiveGreen;
  final Color? color;

  const MoneyText(
    this.cents, {
    super.key,
    required this.currency,
    required this.subunitToUnit,
    this.variant = MoneyVariant.row,
    this.signed = false,
    this.negative = false,
    this.positiveGreen = false,
    this.color,
  });

  @override
  State<MoneyText> createState() => _MoneyTextState();
}

class _MoneyTextState extends State<MoneyText> {
  bool _hasAnimated = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;

    final base = switch (widget.variant) {
      MoneyVariant.hero => text.displayLarge!,
      MoneyVariant.title => text.titleLarge!,
      MoneyVariant.row => text.titleSmall!,
      MoneyVariant.meta => text.bodySmall!,
    };

    final isNegative = widget.negative || widget.cents < 0;
    final effectiveColor = widget.color ??
        (isNegative
            ? c.inkHi
            : (widget.positiveGreen && (widget.signed || widget.cents > 0)
                ? c.income
                : c.inkHi));

    final style = base.copyWith(
      color: effectiveColor,
      fontFeatures: tabularFigures,
      fontWeight: FontWeight.w600,
    );

    if (widget.variant == MoneyVariant.hero && !_hasAnimated) {
      final target = widget.cents.abs().toDouble();
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: target),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        onEnd: () {
          if (mounted && !_hasAnimated) setState(() => _hasAnimated = true);
        },
        builder: (context, v, _) => Text(
          formatMoney(v.round(), widget.currency, widget.subunitToUnit,
              signed: widget.signed, negative: isNegative),
          style: style,
        ),
      );
    }

    return Text(
      formatMoney(widget.cents, widget.currency, widget.subunitToUnit,
          signed: widget.signed, negative: widget.negative),
      style: style,
    );
  }
}
