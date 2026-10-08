import 'package:flutter/material.dart';

import '../../../core/formats.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';

/// Parse a "#RRGGBB" (or "#AARRGGBB") goal color, falling back to gold.
Color goalColor(String hex) {
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return const Color(0xFFD4A853);
  return Color(int.tryParse(h, radix: 16) ?? 0xFFD4A853);
}

String goalTypeOverline(AppL10n l, String targetType) => switch (targetType) {
      'financial' => l.goalsTypeFinancial,
      'habit' => l.goalsTypeHabit,
      _ => l.goalsTypeCustom,
    };

String goalStatusLabel(AppL10n l, String status) => switch (status) {
      'achieved' => l.goalsStatusAchieved,
      'abandoned' => l.goalsStatusAbandoned,
      _ => l.goalsStatusActive,
    };

bool goalIsFinancial(Goal g) => g.targetType == 'financial';

/// Currency + subunit for a financial goal: prefer the linked account, else
/// treat `unit` as the currency code (GAU → 1 subunit, else 100).
({String currency, int subunit}) goalMoneyMeta(Goal g) {
  final currency = g.related?.currency ?? g.unit;
  final subunit = g.related?.subunitToUnit ?? (currency == 'GAU' ? 1 : 100);
  return (currency: currency, subunit: subunit);
}

/// A number typed into a goal field. Either mark can be the decimal one,
/// since a phone's number keypad often offers only "." — so "12.5", "12,5",
/// "0.5" all read 12.5 / 0.5 in both languages. A mark is read as grouping
/// only where the text can mean nothing else: well-formed groups of three
/// ("1.234.567", or "1.234,5" with the other mark as the decimal one).
/// Null when it is not a number, or when it is ambiguous
/// ([goalNumberIsAmbiguous]).
num? parseGoalNumber(String text) => _readGoalNumber(text).value;

/// True when [text] could be read two ways: one mark followed by exactly
/// three digits that the language uses for grouping ("1.234" in Turkish is
/// 1234 there, but 1.234 on a keypad that only has "."). Such input is
/// refused with [goalNumberError] instead of guessed.
bool goalNumberIsAmbiguous(String text) => _readGoalNumber(text).ambiguous;

/// The field error for [text], or null when it reads as a number: the
/// "write the decimal mark" hint for an ambiguous one, else [invalid].
String goalNumberError(AppL10n l, String text, {required String invalid}) =>
    goalNumberIsAmbiguous(text) ? l.goalsNumberAmbiguous(decimalMark()) : invalid;

final _digits = RegExp(r'^\d+$');
final _groupedInt = RegExp(r'^\d{1,3}$');

({num? value, bool ambiguous}) _readGoalNumber(String text) {
  const none = (value: null, ambiguous: false);
  var t = text.trim().replaceAll(' ', '').replaceAll('\u00A0', '');
  var negative = false;
  if (t.startsWith('-') || t.startsWith('\u2212')) {
    negative = true;
    t = t.substring(1);
  }
  if (t.isEmpty) return none;

  ({num? value, bool ambiguous}) result(String whole, String fraction) {
    if (!_digits.hasMatch(whole) ||
        (fraction.isNotEmpty && !_digits.hasMatch(fraction))) {
      return none;
    }
    final v = num.tryParse(fraction.isEmpty ? whole : '$whole.$fraction');
    if (v == null || !v.isFinite) return none;
    return (value: negative ? -v : v, ambiguous: false);
  }

  /// "1.234.567" split on [sep]: the whole part when its groups are
  /// well formed, else null.
  String? ungroup(String s, String sep) {
    final groups = s.split(sep);
    if (!_groupedInt.hasMatch(groups.first)) return null;
    if (groups.skip(1).any((g) => g.length != 3 || !_digits.hasMatch(g))) {
      return null;
    }
    return groups.join();
  }

  final dots = '.'.allMatches(t).length;
  final commas = ','.allMatches(t).length;
  if (dots == 0 && commas == 0) return result(t, '');

  if (dots > 0 && commas > 0) {
    // Both marks: the last one is the decimal mark, the other groups.
    final dec = t.lastIndexOf('.') > t.lastIndexOf(',') ? '.' : ',';
    final group = dec == '.' ? ',' : '.';
    if (dec.allMatches(t).length != 1) return none;
    final at = t.indexOf(dec);
    final whole = ungroup(t.substring(0, at), group);
    if (whole == null) return none;
    return result(whole, t.substring(at + 1));
  }

  final sep = dots > 0 ? '.' : ',';
  final count = dots > 0 ? dots : commas;
  if (count > 1) {
    // The same mark several times can only be grouping.
    final whole = ungroup(t, sep);
    return whole == null ? none : result(whole, '');
  }
  // One mark: the decimal one — unless it is the language's grouping mark
  // followed by a well-formed group, which could be either.
  final at = t.indexOf(sep);
  final whole = t.substring(0, at);
  final fraction = t.substring(at + 1);
  final looksGrouped = sep != decimalMark() &&
      fraction.length == 3 &&
      _groupedInt.hasMatch(whole) &&
      !whole.startsWith('0');
  if (looksGrouped && _digits.hasMatch(fraction)) {
    return (value: null, ambiguous: true);
  }
  return result(whole, fraction);
}

/// [v] as a goal field starts with it: no trailing zeros, the language's
/// decimal mark, no grouping (so it reads back with [parseGoalNumber]).
String goalNumberInput(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  final text = v.toString();
  return decimalMark() == ',' ? text.replaceAll('.', ',') : text;
}

/// Trim a trailing `.0` from goal values (kg / level / days).
/// Written with the language's decimal mark, as the goal fields read it
/// back ("7,50" in Turkish, "7.50" in English).
String formatGoalNumber(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toStringAsFixed(2).replaceAll('.', decimalMark());

/// Money-correct rendering of a raw goal value (major units) for financial goals.
String formatGoalMoney(Goal g, double value) {
  final m = goalMoneyMeta(g);
  return formatMoney((value * m.subunit).round(), m.currency, m.subunit);
}

/// "42 / 100 kg" or, for financial goals, money on both sides. The unit comes
/// from the server (the user typed it), so it is not translated.
String goalProgressLabel(Goal g) {
  if (goalIsFinancial(g)) {
    return '${formatGoalMoney(g, g.currentValue)} / ${formatGoalMoney(g, g.targetValue)}';
  }
  final unit = g.unit.isEmpty ? '' : ' ${g.unit}';
  return '${formatGoalNumber(g.currentValue)} / ${formatGoalNumber(g.targetValue)}$unit';
}

/// Target-only label used in the achieved/abandoned rows.
String goalTargetLabel(Goal g) {
  if (goalIsFinancial(g)) return formatGoalMoney(g, g.targetValue);
  final unit = g.unit.isEmpty ? '' : ' ${g.unit}';
  return '${formatGoalNumber(g.targetValue)}$unit';
}

/// Scales the ProgressRing smoothly during the Hero flight (72dp ↔ 160dp).
Widget goalRingFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) {
  final hero =
      (direction == HeroFlightDirection.push ? toContext : fromContext).widget
          as Hero;
  return Material(
    color: Colors.transparent,
    child: FittedBox(fit: BoxFit.contain, child: hero.child),
  );
}
