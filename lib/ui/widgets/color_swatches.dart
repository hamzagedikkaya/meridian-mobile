import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/entity_color.dart';

/// The swatch a new record starts with when [existing] records already
/// exist: the colours rotate, so consecutive records differ.
String rotatingSwatch(int existing) =>
    recordSwatches[existing % recordSwatches.length];

/// The swatch to suggest after [last] — the colour the user picked most
/// recently — so a run of new records walks the eight colours in turn.
/// Gold when there is no last colour, or it is not one of the swatches.
String nextSwatch(String? last) {
  final swatch = RecordSwatch.fromHex(last);
  if (swatch == null) return recordSwatches.first;
  return recordSwatches[(swatch.index + 1) % recordSwatches.length];
}

/// A row of record colours (design-analysis §4.14): 36 dp swatches in 48 dp
/// targets, 8 dp apart, drawn in each colour's [EntityTone] fill.
///
/// The selected one carries a 2 dp inkHi ring 3 dp outside it and an
/// 18 dp tick in its `onFill` — told by shape, not colour alone. A colour
/// not among [recordSwatches] (one set on the web) shows as an extra,
/// selected swatch.
///
/// Each swatch is a screen-reader button named by its colour ("Adaçayı" /
/// "Sage"; "Renk 9" for a web colour) that says whether it is selected. A
/// pick plays the selection tick.
class ColorSwatchRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const ColorSwatchRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const swatchSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final upper = selected.toUpperCase();
    final current = RecordSwatch.fromHex(upper)?.hex ?? upper;
    final swatches = [
      ...recordSwatches,
      if (!recordSwatches.contains(current)) current,
    ];
    void pick(String hex) {
      Haptics.tick();
      onChanged(hex);
    }

    return Wrap(
      spacing: Gap.sm,
      runSpacing: 0,
      children: [
        for (var i = 0; i < swatches.length; i++)
          _swatch(
            context,
            c,
            hex: swatches[i],
            selected: swatches[i] == current,
            label: switch (RecordSwatch.fromHex(swatches[i])) {
              final swatch? => l.colorName(swatch),
              null => l.colorSwatch(i + 1),
            },
            onTap: () => pick(swatches[i]),
          ),
      ],
    );
  }

  Widget _swatch(
    BuildContext context,
    NokturnColors c, {
    required String hex,
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    final tone = entityTone(hex, c);
    // One stop per swatch; the InkResponse under it is left out of the
    // tree, so this node answers the double-tap itself.
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        customBorder: const CircleBorder(),
        radius: Hit.min / 2,
        child: SizedBox.square(
          dimension: Hit.min,
          child: Center(
            child: Container(
              // The ring: 2 dp, 3 dp clear of the swatch (a Container adds
              // its border to the padding).
              padding: EdgeInsets.all(selected ? 3 : 3 + 2),
              decoration: selected
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.inkHi, width: 2),
                    )
                  : null,
              child: Container(
                width: swatchSize,
                height: swatchSize,
                decoration:
                    BoxDecoration(color: tone.fill, shape: BoxShape.circle),
                child: selected
                    ? Icon(Icons.check_rounded, size: 18, color: tone.onFill)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
