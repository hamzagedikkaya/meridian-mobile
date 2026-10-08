import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/haptics.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';

/// 4×3 amount keypad (design §4.4 İşlem Ekle). 64dp keys, selectionClick per
/// key. The decimal key carries the language's mark ("," in Turkish, "." in
/// English) and is hidden when [showDecimal] is false (GAU accounts).
/// The parent owns the amount ([AmountDraft]); this widget only emits keys.
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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(context, const ['1', '2', '3']),
        _row(context, const ['4', '5', '6']),
        _row(context, const ['7', '8', '9']),
        _row(context, [showDecimal ? _dot : '', '0', _backspace]),
      ],
    );
  }

  static const _dot = '.';
  static const _backspace = '⌫';

  Widget _row(BuildContext context, List<String> keys) {
    return Row(
      children: [
        for (final k in keys) Expanded(child: _key(context, k)),
      ],
    );
  }

  Widget _key(BuildContext context, String key) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;

    if (key.isEmpty) return const SizedBox(height: 64);

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
        height: 64,
        child: InkWell(
          onTap: handle,
          onLongPress: longPress,
          borderRadius: BorderRadius.circular(16),
          splashColor: c.gold.withValues(alpha: 0.08),
          child: Center(
            child: isBackspace
                ? Icon(Icons.backspace_outlined, size: 24, color: c.inkMid)
                : Text(
                    label,
                    style: text.headlineMedium!.copyWith(color: c.inkHi),
                  ),
          ),
        ),
      ),
    );
  }
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
