/// The READMEs show the app through its golden images: every local image
/// they embed has to exist, or the repository page shows broken pictures
/// (the goldens moved into `test/golden/images/<lang>-<theme>-<scale>/`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final readme in ['README.md', 'README.tr.md']) {
    test('every local image $readme embeds exists', () {
      final sources = RegExp(r'''<img[^>]*\bsrc="([^"]+)"|!\[[^\]]*\]\(([^)\s]+)''')
          .allMatches(File(readme).readAsStringSync())
          .map((m) => m.group(1) ?? m.group(2)!)
          .where((src) => !src.contains('://'))
          .toList();
      expect(sources, isNotEmpty);
      final missing = [
        for (final src in sources)
          if (!File(src).existsSync()) src,
      ];
      expect(missing, isEmpty);
    });
  }
}
