import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/haptics.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_typography.dart';
import 'amount_keypad.dart';
import 'form_scaffold.dart';
import 'nok_sheet.dart';
import 'primary_button.dart';

/// A money field of a form: its label and the amount as money. A tap opens
/// the keypad in a sheet — money is never typed on the system keyboard,
/// whose decimal key some keyboards drop in comma-decimal languages
/// (design-research §4.5).
///
/// [minorUnits] null shows nothing typed yet. With [allowDebt] the sheet
/// has a "Borç" (debt) switch and the amount may be negative; with
/// [debtByDefault] that switch starts on while no amount is set (a credit
/// card's opening balance, §7.6).
///
/// The label sits before the amount on one line; above 1.3× text it goes
/// above it, so the amount keeps the whole width and grows with the text
/// rather than shrinking to fit beside the label.
class AmountField extends StatelessWidget {
  final String label;
  final int? minorUnits;
  final String currency;
  final int subunitToUnit;
  final ValueChanged<int> onChanged;
  final bool allowDebt;
  final bool debtByDefault;
  final String? helperText;
  final String? errorText;

  const AmountField({
    super.key,
    required this.label,
    required this.minorUnits,
    required this.currency,
    required this.subunitToUnit,
    required this.onChanged,
    this.allowDebt = false,
    this.debtByDefault = false,
    this.helperText,
    this.errorText,
  });

  Future<void> _edit(BuildContext context) async {
    final value = await showAmountSheet(
      context,
      title: label,
      initial: minorUnits,
      currency: currency,
      subunitToUnit: subunitToUnit,
      allowDebt: allowDebt,
      debtByDefault: debtByDefault,
    );
    if (value != null) onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final value = minorUnits;
    final shown = value == null
        ? formatTypedAmount(whole: '0', currency: currency)
        : formatMoney(value, currency, subunitToUnit);
    final error = errorText;
    final note = error ?? helperText;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final labelText =
        Text(label, style: text.bodyMedium!.copyWith(color: c.inkMid));
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
        // One stop for a screen reader: what the field is and the amount in
        // it. The InkWell under it is left out of the tree, so this node
        // answers the double-tap itself.
        Semantics(
          container: true,
          button: true,
          label: '$label, $shown',
          onTap: () => _edit(context),
          excludeSemantics: true,
          child: FormFieldBox(
            onTap: () => _edit(context),
            hasError: error != null,
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
        // A node of its own, outside the field's (as a text field's helper
        // and error are): a screen reader reads the hint, and says an error
        // the moment it appears.
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Semantics(
              container: true,
              liveRegion: error != null,
              child: Text(
                note,
                style: text.bodySmall!
                    .copyWith(color: error == null ? c.inkLow : c.error),
              ),
            ),
          ),
      ],
    );
  }
}

/// The amount keypad in a sheet; the amount once "Tamam" is tapped, or null
/// when the sheet was dismissed. A cleared amount comes back as 0.
Future<int?> showAmountSheet(
  BuildContext context, {
  required String title,
  int? initial,
  required String currency,
  required int subunitToUnit,
  bool allowDebt = false,
  bool debtByDefault = false,
}) {
  return showNokSheet<int>(
    context,
    title: title,
    showClose: true,
    builder: (_) => _AmountSheet(
      title: title,
      initial: initial,
      currency: currency,
      subunitToUnit: subunitToUnit,
      allowDebt: allowDebt,
      debtByDefault: debtByDefault,
    ),
  );
}

class _AmountSheet extends StatefulWidget {
  final String title;
  final int? initial;
  final String currency;
  final int subunitToUnit;
  final bool allowDebt;
  final bool debtByDefault;

  const _AmountSheet({
    required this.title,
    required this.initial,
    required this.currency,
    required this.subunitToUnit,
    required this.allowDebt,
    this.debtByDefault = false,
  });

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late AmountDraft _draft = AmountDraft.fromMinorUnits(
    widget.initial ?? 0,
    widget.subunitToUnit,
  );
  late bool _debt = widget.allowDebt &&
      ((widget.initial ?? 0) < 0 ||
          (widget.debtByDefault && (widget.initial ?? 0) == 0));
  bool _atLimit = false;

  /// Counts refused digits; each one shakes the amount once.
  int _refused = 0;

  void _digit(String d) {
    final limit = _draft.wouldPassLimit(d, widget.subunitToUnit);
    if (limit) Haptics.danger();
    setState(() {
      _atLimit = limit;
      if (limit) _refused++;
      _draft = _draft.withDigit(d, widget.subunitToUnit);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final cents = _draft.minorUnits(widget.subunitToUnit);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Everything above "Tamam" scrolls: in landscape, or with large
            // text, the keypad does not fit on the screen — and "Tamam"
            // stays in reach, so an amount can always be confirmed.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: RejectShake(
                        trigger: _refused,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _draft.display(widget.currency, negative: _debt),
                            style: text.displayLarge!.copyWith(
                              color: _draft.isEmpty ? c.inkLow : c.inkHi,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // The limit note has its lines kept free — measured at
                    // this width and text size — so the keypad never moves
                    // when it shows.
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final style =
                            text.bodySmall!.copyWith(color: c.warning);
                        final note = l.amountTooLarge(formatMoney(
                            AmountDraft.maxMinorUnits,
                            widget.currency,
                            widget.subunitToUnit));
                        final painter = TextPainter(
                          text: TextSpan(text: note, style: style),
                          textAlign: TextAlign.center,
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout(maxWidth: constraints.maxWidth);
                        final reserved = 4 + painter.height;
                        painter.dispose();
                        return SizedBox(
                          height: reserved,
                          child: _atLimit
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    note,
                                    textAlign: TextAlign.center,
                                    style: style,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                    if (widget.allowDebt) ...[
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        value: _debt,
                        onChanged: (v) {
                          Haptics.tick();
                          setState(() => _debt = v);
                        },
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.accountFormDebt, style: text.titleSmall),
                      ),
                    ],
                    const SizedBox(height: 8),
                    AmountKeypad(
                      onDigit: _digit,
                      onDot: () => setState(() => _draft =
                          _draft.withDecimalMark(widget.subunitToUnit)),
                      onBackspace: () => setState(() {
                        _atLimit = false;
                        _draft = _draft.backspace();
                      }),
                      onClear: () => setState(() {
                        _atLimit = false;
                        _draft = const AmountDraft();
                      }),
                      showDecimal: decimalsFor(widget.subunitToUnit) > 0,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            PrimaryButton(
              label: l.actionDone,
              onPressed: () =>
                  Navigator.of(context).pop(_debt ? -cents : cents),
            ),
          ],
        ),
      ),
    );
  }
}
