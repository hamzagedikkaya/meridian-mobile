import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../screens/finance/finance_utils.dart';

/// The eight colours a new record can take (accounts, categories,
/// subscriptions), the same set the habit and goal forms offer.
const recordSwatches = [
  '#D4A853', // gold
  '#6B8E5A', // sage
  '#6B8FA0', // dusty blue
  '#B85450', // clay
  '#D4A574', // tan
  '#7A5C9E', // mauve
  '#5A9E8B', // teal
  '#8B5A00', // amber
];

/// The swatch a new record starts with when [existing] records already
/// exist: the colours rotate, so consecutive records differ.
String rotatingSwatch(int existing) =>
    recordSwatches[existing % recordSwatches.length];

/// A row of colour swatches; the selected one carries a check. A colour not
/// among them (one set on the web) shows as an extra, selected swatch.
class ColorSwatchRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const ColorSwatchRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final upper = selected.toUpperCase();
    final swatches = [
      ...recordSwatches,
      if (!recordSwatches.contains(upper)) upper,
    ];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < swatches.length; i++)
          Semantics(
            button: true,
            selected: swatches[i] == upper,
            label: l.colorSwatch(i + 1),
            excludeSemantics: true,
            child: InkResponse(
              onTap: () {
                Haptics.tick();
                onChanged(swatches[i]);
              },
              radius: 24,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: hexColor(swatches[i]),
                      shape: BoxShape.circle,
                      border: swatches[i] == upper
                          ? Border.all(color: c.inkHi, width: 2)
                          : null,
                    ),
                    child: swatches[i] == upper
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
