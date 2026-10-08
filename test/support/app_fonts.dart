import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader, rootBundle;

/// Loads the app's bundled Inter and Fraunces into the test, so text is
/// measured as on a phone. The test font draws every glyph a full em wide,
/// which overflows what fits on a device and fits what overflows there.
///
/// Once loaded they stay for every test of the file (its isolate).
Future<void> loadAppFonts() async {
  final fraunces = FontLoader('Fraunces')
    ..addFont(_font('assets/fonts/Fraunces-Regular.ttf'))
    ..addFont(_font('assets/fonts/Fraunces-SemiBold.ttf'));
  final inter = FontLoader('Inter')
    ..addFont(_font('assets/fonts/Inter-Regular.ttf'))
    ..addFont(_font('assets/fonts/Inter-Medium.ttf'))
    ..addFont(_font('assets/fonts/Inter-SemiBold.ttf'));
  await Future.wait([fraunces.load(), inter.load()]);
}

Future<ByteData> _font(String path) async {
  try {
    return await rootBundle.load(path);
  } catch (_) {
    return ByteData.sublistView(await File(path).readAsBytes());
  }
}
