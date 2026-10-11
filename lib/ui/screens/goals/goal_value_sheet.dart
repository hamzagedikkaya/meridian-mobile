import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../l10n/app_l10n.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/primary_button.dart';

/// What a goal number is counted in: money ([currency] with its
/// [subunit]) or a free [unit] the user typed ("kitap", "kg"), which takes
/// two decimals.
@immutable
class GoalValueKind {
  const GoalValueKind.money({
    required String this.currency,
    required this.subunit,
  }) : unit = '';

  const GoalValueKind.count(this.unit) : currency = null, subunit = 100;

  final String? currency;
  final int subunit;
  final String unit;

  bool get isMoney => currency != null;

  /// [value] (major units) as the keypad's digits.
  AmountDraft draftOf(double? value) => value == null || value == 0
      ? const AmountDraft()
      : AmountDraft.fromMinorUnits((value * subunit).round(), subunit);

  /// The typed digits as a value in major units.
  double valueOf(AmountDraft draft) => draft.minorUnits(subunit) / subunit;

  /// The typed digits as they read: money as money, a count grouped with
  /// the language's marks and its unit after a no-break space.
  String typed(AmountDraft draft) {
    if (isMoney) return draft.display(currency!);
    final parts = draft.text.split(',');
    final whole = NumberFormat(
      '#,##0',
    ).format(int.tryParse(parts.first.isEmpty ? '0' : parts.first) ?? 0);
    final number = parts.length == 2
        ? '$whole${decimalMark()}${parts[1]}'
        : whole;
    return unit.isEmpty ? number : '$number$nbsp$unit';
  }

  /// [value] as a field shows it once typed.
  String shown(double value) {
    if (isMoney) {
      return formatMoney(
        (value * subunit).round(),
        currency!,
        subunit,
        decimals: MoneyDecimals.auto,
      );
    }
    return typed(draftOf(value));
  }
}

/// Asks for a goal number on the [AmountKeypad] (design-analysis §7.11:
/// "Değer gir" — no system keyboard, whose decimal key some keyboards drop
/// in comma-decimal languages). Resolves to the value in major units, or
/// null when the sheet was dismissed.
///
/// [check] refuses a value with the reason (shown under the amount, with
/// the REJECT haptic and a shake); null takes it. [message] sits under the
/// title (why a higher target is needed). [actionLabel] names the button;
/// "Tamam" by default.
Future<double?> showGoalValueSheet(
  BuildContext context, {
  required String title,
  required GoalValueKind kind,
  double? initial,
  String? message,
  String? Function(double value)? check,
  String? actionLabel,
}) {
  return showNokSheet<double>(
    context,
    title: title,
    showClose: true,
    builder: (_) => _GoalValueSheet(
      kind: kind,
      message: message,
      initial: initial,
      check: check,
      actionLabel: actionLabel,
    ),
  );
}

class _GoalValueSheet extends StatefulWidget {
  final GoalValueKind kind;
  final String? message;
  final double? initial;
  final String? Function(double value)? check;
  final String? actionLabel;

  const _GoalValueSheet({
    required this.kind,
    required this.message,
    required this.initial,
    required this.check,
    required this.actionLabel,
  });

  @override
  State<_GoalValueSheet> createState() => _GoalValueSheetState();
}

class _GoalValueSheetState extends State<_GoalValueSheet> {
  late AmountDraft _draft = widget.kind.draftOf(widget.initial);

  /// The note under the amount: the size limit (warning) or a refusal
  /// (error).
  String? _note;
  bool _noteIsError = false;

  /// Counts refusals; each one shakes the amount once.
  int _refused = 0;

  int get _subunit => widget.kind.subunit;

  void _refuse(String note, {required bool error}) {
    Haptics.reject();
    setState(() {
      _note = note;
      _noteIsError = error;
      _refused++;
    });
  }

  void _digit(String d) {
    if (_draft.wouldPassLimit(d, _subunit)) {
      final l = context.l10n;
      final limit = widget.kind.isMoney
          ? formatMoney(
              AmountDraft.maxMinorUnits,
              widget.kind.currency!,
              _subunit,
            )
          : widget.kind.shown(AmountDraft.maxMinorUnits / _subunit);
      _refuse(l.amountTooLarge(limit), error: false);
      return;
    }
    setState(() {
      _note = null;
      _draft = _draft.withDigit(d, _subunit);
    });
  }

  void _done() {
    final value = widget.kind.valueOf(_draft);
    final refusal = widget.check?.call(value);
    if (refusal != null) {
      _refuse(refusal, error: true);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final note = _note;
    final noteStyle = text.bodySmall!.copyWith(
      color: _noteIsError ? c.error : c.warning,
    );
    // Two lines are kept free for the note, so the keypad never moves when
    // one shows.
    final noteHeight =
        MediaQuery.textScalerOf(context).scale(noteStyle.fontSize!) *
        (noteStyle.height ?? 1.3) *
        2;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.sheetH,
          0,
          Insets.sheetH,
          Gap.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Everything above the button scrolls: in landscape, or with
            // large text, the keypad does not fit — and the button stays in
            // reach, so a value can always be confirmed.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Scrolls with the keypad: at large text a long reason
                    // would otherwise push the button off the screen.
                    if (widget.message != null) ...[
                      Text(
                        widget.message!,
                        style: text.bodyMedium!.copyWith(color: c.inkMid),
                      ),
                      const SizedBox(height: Gap.lg),
                    ],
                    Semantics(
                      liveRegion: true,
                      child: RejectShake(
                        trigger: _refused,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.kind.typed(_draft),
                            maxLines: 1,
                            style: text.displayLarge!.copyWith(
                              color: _draft.isEmpty ? c.inkLow : c.inkHi,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: Gap.xs + noteHeight,
                      ),
                      child: note == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(top: Gap.xs),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  note,
                                  textAlign: TextAlign.center,
                                  style: noteStyle,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: Gap.sm),
                    AmountKeypad(
                      onDigit: _digit,
                      onDot: () => setState(
                        () => _draft = _draft.withDecimalMark(_subunit),
                      ),
                      onBackspace: () => setState(() {
                        _note = null;
                        _draft = _draft.backspace();
                      }),
                      onClear: () => setState(() {
                        _note = null;
                        _draft = const AmountDraft();
                      }),
                      showDecimal: decimalsFor(_subunit) > 0,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            PrimaryButton(
              label: widget.actionLabel ?? l.actionDone,
              onPressed: _done,
            ),
          ],
        ),
      ),
    );
  }
}

/// A goal number in a form — the target, the progress so far — in the box
/// every tappable field shares; a tap opens [showGoalValueSheet]. Money uses
/// the shared `AmountField` instead.
class GoalValueField extends StatelessWidget {
  final String label;
  final double? value;
  final GoalValueKind kind;
  final ValueChanged<double> onChanged;
  final String? errorText;

  const GoalValueField({
    super.key,
    required this.label,
    required this.value,
    required this.kind,
    required this.onChanged,
    this.errorText,
  });

  Future<void> _edit(BuildContext context) async {
    final picked = await showGoalValueSheet(
      context,
      title: label,
      kind: kind,
      initial: value,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final value = this.value;
    final shown = value == null
        ? kind.typed(const AmountDraft())
        : kind.shown(value);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final labelText = Text(
      label,
      style: text.bodyMedium!.copyWith(color: c.inkMid),
    );
    final amount = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: large
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: Text(
        shown,
        maxLines: 1,
        style: text.titleSmall!.copyWith(
          fontFeatures: tabularFigures,
          color: value == null ? c.inkLow : c.inkHi,
        ),
      ),
    );
    final keypadIcon = Icon(Icons.dialpad_rounded, size: 20, color: c.inkLow);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          button: true,
          label: '$label, $shown',
          onTap: () => _edit(context),
          excludeSemantics: true,
          child: FormFieldBox(
            onTap: () => _edit(context),
            hasError: errorText != null,
            child: large
                ? Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [labelText, amount],
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      keypadIcon,
                    ],
                  )
                : Row(
                    children: [
                      labelText,
                      const SizedBox(width: Gap.md),
                      Expanded(child: amount),
                      const SizedBox(width: Gap.xs),
                      keypadIcon,
                    ],
                  ),
          ),
        ),
        FormInlineError(errorText),
      ],
    );
  }
}
