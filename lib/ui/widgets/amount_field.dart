import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/haptics.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import 'amount_keypad.dart';

/// A money field of a form: its label and the amount as money. A tap opens
/// the keypad in a sheet — money is never typed on the system keyboard,
/// whose decimal key some keyboards drop in comma-decimal languages
/// (design-research §4.5).
///
/// [minorUnits] null shows nothing typed yet. With [allowDebt] the sheet
/// has a "Borç" (debt) switch and the amount may be negative.
class AmountField extends StatelessWidget {
  final String label;
  final int? minorUnits;
  final String currency;
  final int subunitToUnit;
  final ValueChanged<int> onChanged;
  final bool allowDebt;
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
          child: Material(
            color: c.surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: error == null ? c.hairline : c.error),
            ),
            child: InkWell(
              onTap: () => _edit(context),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style:
                                  text.bodySmall!.copyWith(color: c.inkMid)),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              shown,
                              style: text.titleLarge!.copyWith(
                                fontFeatures: tabularFigures,
                                color: value == null ? c.inkLow : c.inkHi,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.dialpad, size: 20, color: c.inkLow),
                  ],
                ),
              ),
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
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (_) => _AmountSheet(
      title: title,
      initial: initial,
      currency: currency,
      subunitToUnit: subunitToUnit,
      allowDebt: allowDebt,
    ),
  );
}

class _AmountSheet extends StatefulWidget {
  final String title;
  final int? initial;
  final String currency;
  final int subunitToUnit;
  final bool allowDebt;

  const _AmountSheet({
    required this.title,
    required this.initial,
    required this.currency,
    required this.subunitToUnit,
    required this.allowDebt,
  });

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late AmountDraft _draft = AmountDraft.fromMinorUnits(
    widget.initial ?? 0,
    widget.subunitToUnit,
  );
  late bool _debt = widget.allowDebt && (widget.initial ?? 0) < 0;
  bool _atLimit = false;

  void _digit(String d) {
    final limit = _draft.wouldPassLimit(d, widget.subunitToUnit);
    setState(() {
      _atLimit = limit;
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
                    Text(widget.title, style: text.titleLarge),
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _draft.display(widget.currency, negative: _debt),
                          style: text.displayLarge!.copyWith(
                            fontFeatures: tabularFigures,
                            color: _draft.isEmpty ? c.inkLow : c.inkHi,
                          ),
                        ),
                      ),
                    ),
                    if (_atLimit)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          l.amountTooLarge(formatMoney(
                              AmountDraft.maxMinorUnits,
                              widget.currency,
                              widget.subunitToUnit)),
                          textAlign: TextAlign.center,
                          style: text.bodySmall!.copyWith(color: c.warning),
                        ),
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
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_debt ? -cents : cents),
              child: Text(l.actionDone),
            ),
          ],
        ),
      ),
    );
  }
}
