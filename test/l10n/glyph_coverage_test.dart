/// Every character the app's copy can show exists in the bundled Inter
/// (design-analysis §8.6). A glyph the font lacks renders as a "NO GLYPH"
/// box in the goldens and as an off-palette OEM emoji on a phone — ✦, ☁ and
/// 🔥 did both. Icons are drawn next to text instead.
///
/// The check reads the copy's source (every string literal of the TR and EN
/// files) and the font's `cmap` table directly, so a new string is covered the
/// moment it is written. Mood emoji are content, not copy: they live in
/// `journalMoodEmojis` (ui/screens/journal/widgets/mood.dart), outside l10n.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const copyFiles = [
  'lib/l10n/app_l10n.dart',
  'lib/l10n/app_l10n_tr.dart',
  'lib/l10n/app_l10n_en.dart',
];

/// Glyphs that were in the copy and are in neither bundled font.
const banned = {'✦', '☁', '🔥', '🎉'};

void main() {
  final inter = cmapOf(File('assets/fonts/Inter-Regular.ttf').readAsBytesSync());

  test('the cmap reader sees the basics', () {
    for (final ch in ['a', 'Z', '0', 'ı', 'İ', 'ş', 'ğ', '₺', '—', '·', '“']) {
      expect(inter.contains(ch.runes.single), isTrue, reason: ch);
    }
    expect(inter.contains('🔥'.runes.single), isFalse);
  });

  for (final path in copyFiles) {
    test('every character of $path is in Inter-Regular.ttf', () {
      final missing = <String>[];
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue; // comments and doc comments
        for (final literal in stringLiterals(lines[i])) {
          for (final rune in literal.runes) {
            if (rune < 0x20) continue;
            if (!inter.contains(rune)) {
              missing.add('$path:${i + 1}: U+'
                  '${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} '
                  '"${String.fromCharCode(rune)}" in $literal');
            }
          }
        }
      }
      expect(missing, isEmpty, reason: missing.join('\n'));
    });

    test('no banned glyph in the strings of $path', () {
      final strings = [
        for (final line in File(path).readAsLinesSync())
          if (!line.trimLeft().startsWith('//')) ...stringLiterals(line),
      ].join('\n');
      for (final glyph in banned) {
        expect(strings.contains(glyph), isFalse, reason: glyph);
      }
    });
  }
}

/// The contents of the single-quoted string literals on [line] — the copy
/// files use no other kind. Escapes are dropped; interpolations stay as text
/// (their names are ASCII, which Inter has).
Iterable<String> stringLiterals(String line) sync* {
  var i = 0;
  while (i < line.length) {
    if (line.startsWith('//', i)) return;
    final ch = line[i];
    if (ch == "'" || ch == '"') {
      final quote = ch;
      final buffer = StringBuffer();
      i++;
      while (i < line.length && line[i] != quote) {
        if (line[i] == r'\' && i + 1 < line.length) {
          i += 2;
          continue;
        }
        buffer.write(line[i]);
        i++;
      }
      yield buffer.toString();
    }
    i++;
  }
}

/// The set of code points a TrueType font maps to a glyph, read from its
/// `cmap` table (format 12 when present, else format 4).
Set<int> cmapOf(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final numTables = data.getUint16(4);
  int? cmap;
  for (var t = 0; t < numTables; t++) {
    final record = 12 + 16 * t;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    if (tag == 'cmap') cmap = data.getUint32(record + 8);
  }
  if (cmap == null) throw StateError('no cmap table');

  final subtables = data.getUint16(cmap + 2);
  int? format4;
  int? format12;
  for (var s = 0; s < subtables; s++) {
    final record = cmap + 4 + 8 * s;
    final platform = data.getUint16(record);
    final encoding = data.getUint16(record + 2);
    final offset = cmap + data.getUint32(record + 4);
    final format = data.getUint16(offset);
    final unicode = platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
    if (!unicode) continue;
    if (format == 12) format12 ??= offset;
    if (format == 4) format4 ??= offset;
  }

  final mapped = <int>{};
  if (format12 != null) {
    final groups = data.getUint32(format12 + 12);
    for (var g = 0; g < groups; g++) {
      final group = format12 + 16 + 12 * g;
      final start = data.getUint32(group);
      final end = data.getUint32(group + 4);
      final glyph = data.getUint32(group + 8);
      for (var c = start; c <= end; c++) {
        if (glyph + (c - start) != 0) mapped.add(c);
      }
    }
    return mapped;
  }
  if (format4 == null) throw StateError('no Unicode cmap subtable');

  final segments = data.getUint16(format4 + 6) ~/ 2;
  final ends = format4 + 14;
  final starts = ends + 2 * segments + 2;
  final deltas = starts + 2 * segments;
  final rangeOffsets = deltas + 2 * segments;
  for (var s = 0; s < segments; s++) {
    final end = data.getUint16(ends + 2 * s);
    final start = data.getUint16(starts + 2 * s);
    final delta = data.getInt16(deltas + 2 * s);
    final rangeOffset = data.getUint16(rangeOffsets + 2 * s);
    for (var c = start; c <= end && c != 0xFFFF; c++) {
      int glyph;
      if (rangeOffset == 0) {
        glyph = (c + delta) & 0xFFFF;
      } else {
        final at = rangeOffsets + 2 * s + rangeOffset + 2 * (c - start);
        glyph = data.getUint16(at);
        if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
      }
      if (glyph != 0) mapped.add(c);
    }
  }
  return mapped;
}
