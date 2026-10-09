/// `EntityTone` against the two tables of design-analysis §3.5, and the
/// contrast promises it makes for every swatch in both themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/theme/entity_color.dart';

String hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The swatches the tables were computed for — with the old tan, which
/// existing records still carry.
const tableSources = [
  '#D4A853', // gold
  '#6B8E5A', // sage
  '#6B8FA0', // dusty blue
  '#B85450', // clay
  '#D4A574', // tan (old)
  '#7A5C9E', // mauve
  '#5A9E8B', // teal
  '#8B5A00', // amber
];

/// (fill, text, onFill), §3.5 dark table.
const darkTable = [
  ('#D4A853', '#D4A853', '#171310'),
  ('#6B8E5A', '#86AA74', '#171310'),
  ('#6B8FA0', '#81A6B8', '#171310'),
  ('#C45F5A', '#E87F79', '#171310'),
  ('#D4A574', '#D4A574', '#171310'),
  ('#8D6FB3', '#AF90D6', '#171310'),
  ('#5A9E8B', '#69AE9A', '#171310'),
  ('#A67329', '#C7934C', '#171310'),
];

/// (fill, text, onFill), §3.5 light table.
const lightTable = [
  ('#A17718', '#825900', '#171310'),
  ('#648653', '#496A38', '#171310'),
  ('#5F8394', '#446777', '#171310'),
  ('#B85450', '#A2403E', '#FFFFFF'),
  ('#A17444', '#835928', '#171310'),
  ('#7A5C9E', '#715395', '#FFFFFF'),
  ('#468A78', '#286E5D', '#171310'),
  ('#8B5A00', '#855400', '#FFFFFF'),
];

void main() {
  group('matches the §3.5 tables', () {
    for (final (name, c, table) in [
      ('dark', NokturnColors.dark, darkTable),
      ('light', NokturnColors.light, lightTable),
    ]) {
      for (var i = 0; i < tableSources.length; i++) {
        test('$name ${tableSources[i]}', () {
          final tone = entityTone(tableSources[i], c);
          expect(
            (hex(tone.fill), hex(tone.text), hex(tone.onFill)),
            table[i],
          );
        });
      }
    }
  });

  test('the dark fill contrasts of the table (track / s3)', () {
    const c = NokturnColors.dark;
    String pair(String source) {
      final fill = entityTone(source, c).fill;
      return '${contrastRatio(fill, c.track).toStringAsFixed(2)} / '
          '${contrastRatio(fill, c.surface3).toStringAsFixed(2)}';
    }

    expect(pair('#B85450'), '3.08 / 3.64');
    expect(pair('#7A5C9E'), '3.03 / 3.59');
    expect(pair('#8B5A00'), '3.06 / 3.62');
  });

  group('keeps its promises for every swatch', () {
    for (final (name, c) in const [
      ('dark', NokturnColors.dark),
      ('light', NokturnColors.light),
    ]) {
      for (final source in {...recordSwatches, ...tableSources}) {
        test('$name $source', () {
          final tone = entityTone(source, c);
          final surface = name == 'dark' ? c.surface3 : c.bg;
          expect(contrastRatio(tone.fill, c.track), greaterThanOrEqualTo(3));
          expect(contrastRatio(tone.fill, surface), greaterThanOrEqualTo(3));
          final tintOnS1 = Color.alphaBlend(tone.tint, c.surface1);
          final tintOnSurface = Color.alphaBlend(tone.tint, surface);
          expect(contrastRatio(tone.text, surface), greaterThanOrEqualTo(4.5));
          expect(contrastRatio(tone.text, tintOnS1), greaterThan(4.49));
          expect(contrastRatio(tone.text, tintOnSurface), greaterThan(4.49));
          expect(contrastRatio(tone.onFill, tone.fill), greaterThanOrEqualTo(3));
          expect(tone.tint.a, closeTo(0.16, 0.002));
          expect(tone.tint.withValues(alpha: 1), tone.fill);
        });
      }
    }
  });

  group('parseEntityHex', () {
    const fallback = Color(0xFF123456);
    test('reads #RRGGBB and #AARRGGBB in any case, with or without #', () {
      expect(parseEntityHex('#b8860b', fallback: fallback),
          const Color(0xFFB8860B));
      expect(parseEntityHex('B8860B', fallback: fallback),
          const Color(0xFFB8860B));
      expect(parseEntityHex('#80B8860B', fallback: fallback),
          const Color(0xFFB8860B));
    });
    test('falls back on anything else', () {
      for (final bad in [null, '', '#12', 'gold', '#GGGGGG', '#1234567']) {
        expect(parseEntityHex(bad, fallback: fallback), fallback, reason: bad);
      }
    });
    test('an unreadable colour takes the gold tone', () {
      const c = NokturnColors.dark;
      expect(entityTone('nope', c), entityTone('#D4A853', c));
    });
  });

  group('record swatches', () {
    test('eight, tan moved off gold', () {
      expect(recordSwatches, hasLength(8));
      expect(recordSwatches, contains('#C98F6B'));
      expect(recordSwatches, isNot(contains('#D4A574')));
    });
    test('the old tan still names the tan swatch', () {
      expect(RecordSwatch.fromHex('#d4a574'), RecordSwatch.tan);
      expect(RecordSwatch.fromHex('#C98F6B'), RecordSwatch.tan);
      expect(RecordSwatch.fromHex('#6b8e5a'), RecordSwatch.sage);
      expect(RecordSwatch.fromHex('#010203'), isNull);
    });
  });

  group('during a theme animation', () {
    const dark = NokturnColors.dark;
    const light = NokturnColors.light;
    bool between(Color x, Color a, Color b) {
      bool channel(double v, double p, double q) =>
          v >= (p < q ? p : q) - 1e-6 && v <= (p < q ? q : p) + 1e-6;
      return channel(x.r, a.r, b.r) &&
          channel(x.g, a.g, b.g) &&
          channel(x.b, a.b, b.b);
    }

    for (final source in tableSources) {
      test('$source fades between the two table tones', () {
        final from = entityTone(source, dark);
        final to = entityTone(source, light);
        final memo = entityToneMemoSize;
        for (var i = 0; i <= 10; i++) {
          final t = i / 10;
          final tone = entityTone(source, dark.lerp(light, t));
          expect(between(tone.fill, from.fill, to.fill), isTrue,
              reason: 'fill at t=$t is ${hex(tone.fill)}');
          expect(between(tone.text, from.text, to.text), isTrue,
              reason: 'text at t=$t is ${hex(tone.text)}');
          expect(relativeLuminance(tone.fill), lessThan(0.8),
              reason: 'fill at t=$t washed out');
        }
        expect(entityToneMemoSize, memo, reason: 'memo grew with t');
      });
    }

    test('ends on the canonical tones', () {
      expect(entityTone('#7A5C9E', dark.lerp(light, 0)),
          entityTone('#7A5C9E', dark));
      expect(entityTone('#7A5C9E', dark.lerp(light, 1)),
          entityTone('#7A5C9E', light));
      expect(entityTone('nope', dark.lerp(light, 1)),
          entityTone('nope', light));
    });
  });

  test('a tone is memoised per palette', () {
    expect(
      identical(entityTone('#6B8E5A', NokturnColors.dark),
          entityTone('#6b8e5a', NokturnColors.dark)),
      isTrue,
    );
    expect(entityTone('#6B8E5A', NokturnColors.dark),
        isNot(entityTone('#6B8E5A', NokturnColors.light)));
  });
}
