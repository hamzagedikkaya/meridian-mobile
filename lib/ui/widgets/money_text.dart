import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../data/sync.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import 'entrance.dart';
import 'rolling_number.dart';

/// The size of a [MoneyText] (design-analysis §4.19).
///
/// | Variant | Style | Motion |
/// |---|---|---|
/// | [hero] | displayLarge 40 (Fraunces), [RollingNumber] | by cause |
/// | [display] | displayMedium 32 (Fraunces), [RollingNumber] | by cause |
/// | [title] | headlineSmall 20 (Fraunces), [RollingNumber] | by cause |
/// | [row] | `numRow` (Inter 15, tabular) | none |
/// | [meta] | `numMeta` w500 (Inter 13, tabular) | none |
enum MoneyVariant { hero, display, title, row, meta }

/// All money on screen goes through this widget (design §2.4, §3.7, §4.19).
///
/// **Colour** ([color] overrides): above zero and signed → `income`; below
/// zero → `inkHi`, never red; an exact zero → "₺0" in `inkMid`, unsigned.
/// [positiveGreen] also greens an unsigned amount above zero.
///
/// **Motion** (Fraunces variants): the hero counts up only on the first
/// visible frame of a tab's data (the `EntranceGate`); a value the user
/// changed on this device (≤ 5 s after their write) rolls digit by digit; a
/// refresh cross-fades in 200 ms. [cause] overrides that choice. Row and
/// meta amounts never move.
///
/// An amount is never cut with "…": the Fraunces variants shrink to fit.
class MoneyText extends StatefulWidget {
  final int cents;
  final String currency;
  final int subunitToUnit;
  final MoneyVariant variant;
  final bool signed;
  final bool negative;
  final bool positiveGreen;
  final Color? color;

  /// The sign rule; [MoneySign.auto] defers to [signed] / [negative].
  final MoneySign sign;

  final MoneyDecimals decimals;

  /// Why the value is what it is now; null works it out (see above).
  final NumberCause? cause;

  /// What a screen reader hears; null is the formatted amount.
  final String? semanticsLabel;

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
    this.sign = MoneySign.auto,
    this.decimals = MoneyDecimals.always,
    this.cause,
    this.semanticsLabel,
  });

  /// Whether [variant] is set in Fraunces digit slots and may move.
  static bool rolls(MoneyVariant variant) =>
      variant == MoneyVariant.hero ||
      variant == MoneyVariant.display ||
      variant == MoneyVariant.title;

  @override
  State<MoneyText> createState() => _MoneyTextState();
}

class _MoneyTextState extends State<MoneyText> {
  bool _built = false;

  NumberCause _cause() {
    final given = widget.cause;
    if (!_built) {
      _built = true;
      if (given != null) return given;
      // Without a gate above it, only the hero counts (as it always did).
      final gated = EntranceGate.maybeOf(context) != null;
      return gated || widget.variant == MoneyVariant.hero
          ? NumberCause.firstLoad
          : NumberCause.background;
    }
    return given ??
        (DataSync.userWroteRecently ? NumberCause.user : NumberCause.background);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final nums = context.nokText;

    final base = switch (widget.variant) {
      MoneyVariant.hero => text.displayLarge!,
      MoneyVariant.display => text.displayMedium!,
      MoneyVariant.title => text.headlineSmall!,
      MoneyVariant.row => nums.numRow,
      MoneyVariant.meta => nums.numMeta,
    };

    final cents = widget.cents;
    final sign = widget.sign != MoneySign.auto
        ? widget.sign
        : widget.negative
            ? MoneySign.negative
            : widget.signed
                ? MoneySign.always
                : MoneySign.auto;
    final isNegative = cents < 0 || (sign == MoneySign.negative && cents != 0);
    final showsPlus = sign == MoneySign.always && cents > 0;
    final color = widget.color ??
        (cents == 0
            ? c.inkMid
            : isNegative
                ? c.inkHi
                : (showsPlus || widget.positiveGreen)
                    ? c.income
                    : c.inkHi);

    final style = base.copyWith(
      color: color,
      fontFeatures: tabularFigures,
      fontWeight: widget.variant == MoneyVariant.meta
          ? FontWeight.w500
          : FontWeight.w600,
    );
    final formatted = formatMoney(
      cents,
      widget.currency,
      widget.subunitToUnit,
      sign: sign,
      decimals: widget.decimals,
    );

    if (!MoneyText.rolls(widget.variant)) {
      return Text(
        formatted,
        style: style,
        semanticsLabel: widget.semanticsLabel,
      );
    }
    return RollingNumber(
      text: formatted,
      style: style,
      cause: _cause(),
      semanticsLabel: widget.semanticsLabel,
    );
  }
}
