/// Every token pair the design promises a contrast for (design-analysis
/// §8.1), computed from the two palettes with the WCAG 2.x formula.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/theme/entity_color.dart';

void main() {
  for (final (name, c) in const [
    ('dark', NokturnColors.dark),
    ('light', NokturnColors.light),
  ]) {
    group('$name palette', () {
      final surfaces = {
        'bg': c.bg,
        'surface1': c.surface1,
        'surface2': c.surface2,
        'surface3': c.surface3,
      };

      void atLeast(String fg, Color f, String bg, Color b, double min) {
        final ratio = contrastRatio(f, b);
        expect(
          ratio,
          greaterThanOrEqualTo(min),
          reason: '$fg on $bg is ${ratio.toStringAsFixed(2)}:1, '
              'needs ${min.toStringAsFixed(1)}:1',
        );
      }

      test('text and icon inks read at 4.5:1 on every surface', () {
        final inks = {
          'inkHi': c.inkHi,
          'inkMid': c.inkMid,
          'inkLow': c.inkLow,
          'gold': c.gold,
          'income': c.income,
          'error': c.error,
          'warning': c.warning,
        };
        for (final ink in inks.entries) {
          for (final surface in surfaces.entries) {
            atLeast(ink.key, ink.value, surface.key, surface.value, 4.5);
          }
        }
      });

      test('on-colours read at 4.5:1 on their fills', () {
        atLeast('onGold', c.onGold, 'gold', c.gold, 4.5);
        atLeast('onError', c.onError, 'error', c.error, 4.5);
        atLeast('onIncome', c.onIncome, 'income', c.income, 4.5);
        atLeast('onWarning', c.onWarning, 'warning', c.warning, 4.5);
        atLeast('onGoldContainer', c.onGoldContainer, 'goldContainer',
            c.goldContainer, 4.5);
      });

      test('each state colour reads at 4.5:1 in its own container', () {
        atLeast('income', c.income, 'incomeContainer', c.incomeContainer, 4.5);
        atLeast('error', c.error, 'errorContainer', c.errorContainer, 4.5);
        atLeast('warning', c.warning, 'warningContainer', c.warningContainer,
            4.5);
      });

      test('secondary text reads on goldContainer; tertiary is not used there',
          () {
        atLeast('inkMid', c.inkMid, 'goldContainer', c.goldContainer, 4.5);
        // §3.4 rule 4: text on goldContainer is always onGoldContainer (or
        // inkMid for meta). inkLow lands at ~4.1:1 there in both themes —
        // pinned here so the rule is not quietly relied on.
        expect(contrastRatio(c.inkLow, c.goldContainer), lessThan(4.5));
      });

      test('component borders and state marks reach 3:1', () {
        for (final surface in surfaces.entries) {
          atLeast('inkDisabled', c.inkDisabled, surface.key, surface.value, 3);
        }
        atLeast('goldDim', c.goldDim, 'surface1', c.surface1, 3);
        atLeast('goldDim', c.goldDim, 'surface2', c.surface2, 3);
        // The sheet drag handle (§4.15).
        atLeast('inkDisabled', c.inkDisabled, 'surface3', c.surface3, 3);
      });

      test('the scrim darkens the page under a sheet', () {
        final dimmed = Color.alphaBlend(c.scrim, c.bg);
        expect(relativeLuminance(dimmed), lessThan(relativeLuminance(c.bg)));
      });
    });
  }

  test('the measured values of §3.1–3.2 hold', () {
    const d = NokturnColors.dark;
    const l = NokturnColors.light;
    double r(Color a, Color b) =>
        double.parse(contrastRatio(a, b).toStringAsFixed(2));
    expect(r(d.inkLow, d.surface3), 4.73);
    expect(r(d.onError, d.error), 6.18);
    expect(r(d.inkDisabled, d.surface3), 3.06);
    expect(r(l.onGold, l.gold), 5.34);
    expect(r(l.income, l.incomeContainer), 4.91);
    expect(r(l.warning, l.warningContainer), 4.94);
    expect(r(l.inkDisabled, l.surface3), 3.84);
  });
}
