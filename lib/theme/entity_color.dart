/// Colours people pick for their own records — habits, goals, accounts,
/// categories, lists, events — made legible on Noktürn's surfaces
/// (design-analysis §3.5).
///
/// A raw swatch is never drawn as-is. [entityTone] derives four colours from
/// it, each with a measured contrast promise:
///
/// | Field | Promise | Use |
/// |---|---|---|
/// | `fill` | ≥ 3:1 against `track` and the tone surface | Ring, check fill, chain cell, bar, dot, inline event/account bar |
/// | `text` | ≥ 4.5:1 against the surface and its own tint (on s1 and on the surface) | Any text or icon drawn in the entity colour |
/// | `tint` | `fill` at 16 % | `LeadingCircle` and pill backgrounds |
/// | `onFill` | white or `#171310`, whichever contrasts more (≥ 3:1) | **Marks only**: the `CheckPop` tick, the swatch tick |
///
/// Never write text on a solid fill: a completed counter is tint background +
/// `text` digits + a 1.5 dp `fill` border (D19).
///
///     final tone = entityTone(habit.color, context.nok);
///     Icon(Icons.check_rounded, color: tone.onFill)
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'app_colors.dart';

typedef EntityTone = ({Color fill, Color text, Color tint, Color onFill});

/// The colours a new record can take, in picker order. Tan is the brick-tan
/// `#C98F6B`: the old `#D4A574` sat 1.01:1 from gold and could not be told
/// apart. Records that already carry the old tan keep it.
enum RecordSwatch {
  gold('#D4A853'),
  sage('#6B8E5A'),
  dustyBlue('#6B8FA0'),
  clay('#B85450'),
  tan('#C98F6B'),
  mauve('#7A5C9E'),
  teal('#5A9E8B'),
  amber('#8B5A00');

  const RecordSwatch(this.hex);

  /// `#RRGGBB`, upper case — the form the API stores.
  final String hex;

  /// The swatch [hex] names (any case, with or without `#`), including the
  /// retired tan `#D4A574`; null for a colour set elsewhere (on the web).
  static RecordSwatch? fromHex(String? hex) {
    final key = _normalized(hex);
    if (key == null) return null;
    if (key == 'D4A574') return RecordSwatch.tan;
    for (final swatch in values) {
      if (swatch.hex.substring(1) == key) return swatch;
    }
    return null;
  }
}

/// The swatch hexes a new record can take, in picker order (accounts,
/// categories, subscriptions, lists, habits, goals).
final List<String> recordSwatches =
    List.unmodifiable([for (final swatch in RecordSwatch.values) swatch.hex]);

/// Parses `#RRGGBB` or `#AARRGGBB` (the `#` is optional, any case) as an
/// opaque colour; anything else is [fallback].
Color parseEntityHex(String? hex, {required Color fallback}) {
  final key = _normalized(hex);
  if (key == null) return fallback;
  final value = int.tryParse(key, radix: 16);
  return value == null ? fallback : Color(0xFF000000 | value);
}

/// The legible tone of a record colour [hex] on palette [c]; an unparseable
/// colour falls back to the palette's gold. Memoised per (colour,
/// brightness).
EntityTone entityTone(String? hex, NokturnColors c) {
  final key = _normalized(hex);
  final value = key == null ? null : int.tryParse(key, radix: 16);
  if (value == null) {
    return _tracking(
      c,
      (b) => _canonicalTone(NokturnColors.of(b).gold.toARGB32(), b),
    );
  }
  return entityToneOf(Color(0xFF000000 | value), c);
}

/// [entityTone] for an already parsed colour.
///
/// Tones are only ever computed against the two canonical palettes and
/// memoised per (colour, brightness), as §3.5 says. A palette caught halfway
/// through a theme animation (a lerp of the two) gets both canonical tones
/// mixed by how far its `bg` has travelled from dark to light, so the colour
/// fades with the theme instead of searching against a mid-grey surface —
/// no wash-out to near-white, no jump when `isDark` flips, no search per
/// frame.
EntityTone entityToneOf(Color source, NokturnColors c) {
  final argb = source.toARGB32() | 0xFF000000;
  return _tracking(c, (b) => _canonicalTone(argb, b));
}

/// How many canonical tones are memoised (for tests).
@visibleForTesting
int get entityToneMemoSize => _memo.length;

/// WCAG 2.x contrast ratio of two colours (alpha ignored), 1–21.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// WCAG 2.x relative luminance of [color] (alpha ignored).
double relativeLuminance(Color color) =>
    0.2126 * _linear(color.r) +
    0.7152 * _linear(color.g) +
    0.0722 * _linear(color.b);

// --- Internals ---------------------------------------------------------------

const _memoLimit = 256;
final _memo = <(int, Brightness), EntityTone>{};

EntityTone _canonicalTone(int argb, Brightness brightness) {
  final key = (argb, brightness);
  final cached = _memo[key];
  if (cached != null) return cached;
  if (_memo.length >= _memoLimit) _memo.clear();
  final c = NokturnColors.of(brightness);
  return _memo[key] = _computeTone(Color(argb), c, c.toneSurface);
}

/// The tone [canonical] gives for [c]'s side; a palette between the two
/// (a theme animation frame) mixes both by its position.
EntityTone _tracking(
  NokturnColors c,
  EntityTone Function(Brightness) canonical,
) {
  const dark = NokturnColors.dark;
  const light = NokturnColors.light;
  if (c.bg == dark.bg) return canonical(Brightness.dark);
  if (c.bg == light.bg) return canonical(Brightness.light);
  final t = _travel(dark.bg, light.bg, c.bg);
  if (t <= 0) return canonical(Brightness.dark);
  if (t >= 1) return canonical(Brightness.light);
  final from = canonical(Brightness.dark);
  final to = canonical(Brightness.light);
  Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
  return (
    fill: mix(from.fill, to.fill),
    text: mix(from.text, to.text),
    tint: mix(from.tint, to.tint),
    onFill: mix(from.onFill, to.onFill),
  );
}

/// Where [x] sits on the straight line from [from] to [to] in sRGB, 0–1
/// (unclamped). A lerped palette's `bg` lies on that line, so this recovers
/// the animation's (curved) progress exactly.
double _travel(Color from, Color to, Color x) {
  final dr = to.r - from.r, dg = to.g - from.g, db = to.b - from.b;
  final length2 = dr * dr + dg * dg + db * db;
  if (length2 == 0) return 0;
  return ((x.r - from.r) * dr + (x.g - from.g) * dg + (x.b - from.b) * db) /
      length2;
}

/// The tint alpha (replaces the old `withValues(alpha: 0.18)`).
const _tintAlpha = 0.16;

/// Lightness step of the search, in OKLab L.
const _step = 0.005;

const _onFillDark = Color(0xFF171310);
const _onFillLight = Color(0xFFFFFFFF);

EntityTone _computeTone(Color source, NokturnColors c, Color surface) {
  final dark = c.isDark;
  final source8 = _quantize(source);

  final fill = _adjustLightness(
    source8,
    lighten: dark,
    accept: (x) =>
        math.min(contrastRatio(x, c.track), contrastRatio(x, surface)) >= 3.0,
  );

  final tint = fill.withValues(alpha: _tintAlpha);
  final tintOnS1 = _quantize(Color.alphaBlend(tint, c.surface1));
  final tintOnSurface = _quantize(Color.alphaBlend(tint, surface));

  // The text search starts again from the source colour, not from the fill.
  final text = _adjustLightness(
    source8,
    lighten: dark,
    accept: (x) =>
        math.min(
          contrastRatio(x, surface),
          math.min(contrastRatio(x, tintOnS1), contrastRatio(x, tintOnSurface)),
        ) >=
        4.5,
  );

  final onFill = contrastRatio(_onFillLight, fill) >
          contrastRatio(_onFillDark, fill)
      ? _onFillLight
      : _onFillDark;

  return (fill: fill, text: text, tint: tint, onFill: onFill);
}

/// Moves [start]'s OKLab lightness by [_step] at a time — up when
/// [lighten], down otherwise — keeping its hue and chroma, until [accept]
/// holds for the 8-bit colour. Gives up at the end of the range and returns
/// the last colour tried.
Color _adjustLightness(
  Color start, {
  required bool lighten,
  required bool Function(Color) accept,
}) {
  final (l, a, b) = _toOklab(start);
  final direction = lighten ? _step : -_step;
  var candidate = start;
  for (var i = 0; i <= (1 / _step).ceil(); i++) {
    final lightness = l + i * direction;
    candidate = _fromOklab(lightness.clamp(0.0, 1.0), a, b);
    if (accept(candidate)) return candidate;
    if (lightness <= 0 || lightness >= 1) break;
  }
  return candidate;
}

String? _normalized(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '').toUpperCase();
  if (h.length == 8) h = h.substring(2);
  if (h.length != 6 || int.tryParse(h, radix: 16) == null) return null;
  return h;
}

Color _quantize(Color c) => Color.fromARGB(
      255,
      (c.r * 255).round().clamp(0, 255),
      (c.g * 255).round().clamp(0, 255),
      (c.b * 255).round().clamp(0, 255),
    );

double _linear(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _gamma(double v) =>
    v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055;

double _cbrt(double v) =>
    v < 0 ? -math.pow(-v, 1 / 3).toDouble() : math.pow(v, 1 / 3).toDouble();

/// sRGB → OKLab (Björn Ottosson, 2020).
(double, double, double) _toOklab(Color color) {
  final r = _linear(color.r), g = _linear(color.g), b = _linear(color.b);
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return (
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  );
}

/// OKLab → 8-bit sRGB, clipped to the gamut channel by channel.
Color _fromOklab(double lightness, double a, double b) {
  final l = math.pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3);
  final m = math.pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3);
  final s = math.pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3);
  final r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  final g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  final bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
  int channel(num v) => (_gamma(v.clamp(0.0, 1.0).toDouble()) * 255).round();
  return Color.fromARGB(255, channel(r), channel(g), channel(bl));
}
