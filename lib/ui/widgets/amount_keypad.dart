import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/haptics.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// The 4×3 amount keypad (design-analysis §4.11): digits in Fraunces
/// (displaySmall 28 sp), the decimal key showing the language's mark (","
/// in Turkish, "." in English; hidden when [showDecimal] is false — GAU and
/// counts) and ⌫, whose long press clears the amount ([onClear]).
///
/// Keys are 64 dp tall — 56 dp on screens up to 780 dp high, so the save
/// button stays in reach — with a round gold ripple. Every key plays the
/// selection tick. Each is one screen-reader button.
///
/// The parent owns the amount ([AmountDraft]); this widget only emits keys.
/// A refused digit (past the 32-bit cent ceiling) is the parent's to show:
/// shake the amount with [RejectShake].
class AmountKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onDot;
  final VoidCallback onBackspace;
  final VoidCallback? onClear;
  final bool showDecimal;

  const AmountKeypad({
    super.key,
    required this.onDigit,
    required this.onDot,
    required this.onBackspace,
    this.onClear,
    this.showDecimal = true,
  });

  /// The key height on a screen [screenHeight] dp tall.
  static double keyHeightFor(double screenHeight) =>
      screenHeight <= 780 ? 56 : 64;

  @override
  Widget build(BuildContext context) {
    final height = keyHeightFor(MediaQuery.sizeOf(context).height);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(context, height, const ['1', '2', '3']),
        _row(context, height, const ['4', '5', '6']),
        _row(context, height, const ['7', '8', '9']),
        _row(context, height, [showDecimal ? _dot : '', '0', _backspace]),
      ],
    );
  }

  static const _dot = '.';
  static const _backspace = '⌫';

  Widget _row(BuildContext context, double height, List<String> keys) {
    return Row(
      children: [
        for (final k in keys) Expanded(child: _key(context, height, k)),
      ],
    );
  }

  Widget _key(BuildContext context, double height, String key) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;

    if (key.isEmpty) return SizedBox(height: height);

    final isBackspace = key == _backspace;
    final isDot = key == _dot;

    void handle() {
      Haptics.tick();
      if (isBackspace) {
        onBackspace();
      } else if (isDot) {
        onDot();
      } else {
        onDigit(key);
      }
    }

    final label = isDot ? decimalMark() : key;
    final longPress = isBackspace ? onClear : null;
    // One stop per key for a screen reader. The key's own InkWell is left
    // out of the tree with everything else under it, so this node answers
    // the double-tap (and on ⌫ the long-press) itself — without them a
    // screen reader, Switch Access or Voice Access could not type at all.
    return Semantics(
      button: true,
      label: isBackspace
          ? l.keypadBackspace
          : (isDot ? l.keypadDecimalMark : key),
      hint: longPress != null ? l.keypadClearHint : null,
      onTap: handle,
      onLongPress: longPress,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: InkResponse(
          onTap: handle,
          onLongPress: longPress,
          containedInkWell: true,
          highlightShape: BoxShape.circle,
          customBorder: const CircleBorder(),
          child: Center(
            child: isBackspace
                ? Icon(Icons.backspace_outlined, size: 24, color: c.inkMid)
                : Text(
                    label,
                    style: text.displaySmall!.copyWith(color: c.inkHi),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Shakes [child] sideways — ±4 dp, two cycles in [Motion.shake] (240 ms)
/// — each time [trigger] changes: a refused keypad digit
/// (design-analysis §4.11). Still under reduced motion.
class RejectShake extends StatefulWidget {
  final int trigger;
  final Widget child;

  const RejectShake({super.key, required this.trigger, required this.child});

  @override
  State<RejectShake> createState() => _RejectShakeState();
}

class _RejectShakeState extends State<RejectShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: Motion.shake);
  late final Animation<Offset> _offset = _shake.drive(_ShakeTween());

  @override
  void didUpdateWidget(RejectShake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && !Motion.reduced(context)) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _offset,
        builder: (context, child) =>
            Transform.translate(offset: _offset.value, child: child),
        child: widget.child,
      );
}

/// Two full sine cycles of ±4 dp.
class _ShakeTween extends Animatable<Offset> {
  @override
  Offset transform(double t) => Offset(4 * math.sin(t * 2 * 2 * math.pi), 0);
}

/// Parses a Turkish-formatted amount string ("1.234,56") into integer cents
/// for the given [subunitToUnit]. Returns 0 for empty/invalid input.
int amountStringToCents(String input, int subunitToUnit) {
  if (input.isEmpty) return 0;
  final cleaned = input.replaceAll('.', '').replaceAll(',', '.');
  final value = double.tryParse(cleaned);
  if (value == null) return 0;
  return (value * subunitToUnit).round();
}

/// The amount typed on an [AmountKeypad] so far — the one money entry every
/// form shares (transaction, opening balance, budget limit, subscription).
///
/// [text] holds the digits with "," as the decimal mark whatever the
/// language shows. Entry stops at what the server can store: every
/// `*_cents` column is a 4-byte integer, so [maxMinorUnits] minor units.
@immutable
class AmountDraft {
  const AmountDraft([this.text = '']);

  final String text;

  /// The most minor units an amount can have (₺21.474.836,47).
  static const maxMinorUnits = 2147483647;

  /// [minorUnits] (its absolute value) as typed digits.
  factory AmountDraft.fromMinorUnits(int minorUnits, int subunitToUnit) {
    final cents = minorUnits.abs();
    if (cents == 0) return const AmountDraft();
    final decimals = decimalsFor(subunitToUnit);
    if (decimals == 0) return AmountDraft('$cents');
    final whole = cents ~/ subunitToUnit;
    final fraction = (cents % subunitToUnit).toString().padLeft(decimals, '0');
    final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
    return AmountDraft(trimmed.isEmpty ? '$whole' : '$whole,$trimmed');
  }

  bool get isEmpty => text.isEmpty;

  /// The amount in minor units of a currency with [subunitToUnit].
  int minorUnits(int subunitToUnit) => amountStringToCents(text, subunitToUnit);

  /// [digit] added — or this same draft when the currency takes no more
  /// decimals, or when the amount would pass [maxMinorUnits] (see
  /// [wouldPassLimit]).
  AmountDraft withDigit(String digit, int subunitToUnit) {
    final parts = text.split(',');
    if (parts.length == 2 && parts[1].length >= decimalsFor(subunitToUnit)) {
      return this;
    }
    // A leading zero is replaced, not followed ("05" is "5").
    final next = text == '0' ? digit : '$text$digit';
    if (amountStringToCents(next, subunitToUnit) > maxMinorUnits) return this;
    return AmountDraft(next);
  }

  /// Whether typing [digit] is refused because the amount would be too
  /// large to store — what the keypad's host says inline.
  bool wouldPassLimit(String digit, int subunitToUnit) {
    final parts = text.split(',');
    if (parts.length == 2 && parts[1].length >= decimalsFor(subunitToUnit)) {
      return false;
    }
    final next = text == '0' ? digit : '$text$digit';
    return amountStringToCents(next, subunitToUnit) > maxMinorUnits;
  }

  /// The decimal mark added — ignored for a currency without decimals, or
  /// when it is already there.
  AmountDraft withDecimalMark(int subunitToUnit) {
    if (decimalsFor(subunitToUnit) == 0 || text.contains(',')) return this;
    return AmountDraft(text.isEmpty ? '0,' : '$text,');
  }

  AmountDraft backspace() =>
      text.isEmpty ? this : AmountDraft(text.substring(0, text.length - 1));

  /// The same digits for a currency with [subunitToUnit]: decimals it does
  /// not take are dropped (a GAU account takes none).
  AmountDraft forCurrency(int subunitToUnit) {
    final decimals = decimalsFor(subunitToUnit);
    final parts = text.split(',');
    if (parts.length < 2) return this;
    if (decimals == 0) return AmountDraft(parts.first);
    if (parts[1].length <= decimals) return this;
    return AmountDraft('${parts.first},${parts[1].substring(0, decimals)}');
  }

  /// The amount as money, as far as it is typed: "1.250,5 ₺", "12, ₺".
  String display(String currency, {bool negative = false}) {
    final parts = text.split(',');
    final whole = parts.first.isEmpty ? '0' : parts.first;
    return formatTypedAmount(
      whole: whole,
      fraction: parts.length == 2 ? parts[1] : null,
      currency: currency,
      negative: negative && !isEmpty,
    );
  }

  @override
  bool operator ==(Object other) => other is AmountDraft && other.text == text;

  @override
  int get hashCode => text.hashCode;
}
