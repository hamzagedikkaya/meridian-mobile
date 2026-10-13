/// İşlemler's date presets count days on the calendar: "Son 30 gün" starts
/// 30 calendar days back, also in the month after the clocks spring forward
/// (a 23-hour day), where 30 × 24 hours would reach one day further.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/ui/screens/finance/date_presets.dart';

/// The Dart VM that ships with the Flutter running these tests.
String? _dartVm() {
  final flutter = Platform.environment['FLUTTER_ROOT'];
  if (flutter == null) return null;
  final dart = File([
    flutter,
    'bin',
    'cache',
    'dart-sdk',
    'bin',
    Platform.isWindows ? 'dart.exe' : 'dart',
  ].join(Platform.pathSeparator));
  return dart.existsSync() ? dart.path : null;
}

void main() {
  test('the presets, on an ordinary day', () {
    final today = DateTime(2026, 10, 4);
    expect(txDatePreset('30d', today),
        (from: DateTime(2026, 9, 4), to: today));
    expect(txDatePreset('month', today),
        (from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31)));
    expect(txDatePreset('year', today),
        (from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31)));
    expect(txDatePreset('week', today), isNull);
  });

  // The test VM keeps the machine's zone, which may never change its clocks
  // (Türkiye's has not since 2016): a second VM runs in one that does.
  for (final (zone, days) in const [
    ('Europe/Berlin', ['2026-03-30', '2026-04-10', '2026-04-28']),
    ('America/New_York', ['2026-03-20', '2026-04-07']),
  ]) {
    test('"Son 30 gün" after the clocks spring forward, in $zone', () async {
      final dart = _dartVm();
      if (dart == null) {
        markTestSkipped('no Dart VM next to Flutter (FLUTTER_ROOT unset)');
        return;
      }
      final run = await Process.run(
        dart,
        [
          '--packages=.dart_tool/package_config.json',
          'test/support/tx_preset_probe.dart',
          ...days,
        ],
        environment: {'TZ': zone},
      );
      final out = '${run.stdout}${run.stderr}';
      expect(run.exitCode, 0, reason: out);
      expect(out.split('\n').where((l) => l.startsWith('ok ')),
          hasLength(days.length),
          reason: out);
    });
  }
}
