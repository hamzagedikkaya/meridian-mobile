import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';

/// 4×3 amount keypad (design §4.4 İşlem Ekle). 64dp keys, selectionClick per
/// key. The decimal key is hidden when [showDecimal] is false (GAU accounts).
/// The parent owns the amount string; this widget only emits key events.
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
        _row(context, ['1', '2', '3']),
        _row(context, ['4', '5', '6']),
        _row(context, ['7', '8', '9']),
        _row(context, [showDecimal ? ',' : '', '0', '⌫']),
      ],
    );
  }

  Widget _row(BuildContext context, List<String> keys) {
    return Row(
      children: [
        for (final k in keys) Expanded(child: _key(context, k)),
      ],
    );
  }

  Widget _key(BuildContext context, String label) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;

    if (label.isEmpty) return const SizedBox(height: 64);

    final isBackspace = label == '⌫';

    void handle() {
      Haptics.tick();
      if (isBackspace) {
        onBackspace();
      } else if (label == ',') {
        onDot();
      } else {
        onDigit(label);
      }
    }

    return SizedBox(
      height: 64,
      child: InkWell(
        onTap: handle,
        onLongPress: isBackspace ? onClear : null,
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
