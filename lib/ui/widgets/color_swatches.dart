import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/entity_color.dart';
import '../screens/finance/finance_utils.dart';

// The swatches live with the other record-colour tokens.
export '../../theme/entity_color.dart' show recordSwatches;

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
    void pick(String hex) {
      Haptics.tick();
      onChanged(hex);
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < swatches.length; i++)
          // One stop per swatch; the InkResponse under it is left out of
          // the tree, so this node answers the double-tap itself.
          Semantics(
            button: true,
            selected: swatches[i] == upper,
            label: l.colorSwatch(i + 1),
            onTap: () => pick(swatches[i]),
            excludeSemantics: true,
            child: InkResponse(
              onTap: () => pick(swatches[i]),
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
