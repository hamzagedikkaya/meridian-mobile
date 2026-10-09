/// Motion tokens (design-analysis §5.1).
///
/// The literal scan is in REPORT mode: it lists every `Duration(…)` literal
/// left outside `lib/theme/app_motion.dart` but does not fail. The Phase B
/// and screen work packages move them onto `Motion` tokens; WP-17 flips
/// [enforce] to true, with [allowed] as the only exceptions.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/theme/app_motion.dart';

const enforce = false;

/// Files that keep literals on purpose: snackbar lengths (4 s / 6 s) and the
/// server-address ping debounce (1500 ms).
const allowed = {
  'lib/ui/widgets/app_snackbar.dart',
  'lib/ui/widgets/server_url_field.dart',
};

/// Where motion lives. Network timeouts and retry back-offs in `lib/core`
/// and `lib/data` are not motion and keep their own constants.
const scanned = ['lib/ui', 'lib/router', 'lib/theme'];

final _literal = RegExp(r'Duration\(\s*(milliseconds|microseconds)\s*:');

void main() {
  test('Duration literals outside app_motion.dart (report)', () {
    final hits = <String>[];
    final files = [
      for (final dir in scanned) ...Directory(dir).listSync(recursive: true),
    ]
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      if (path == 'lib/theme/app_motion.dart' || allowed.contains(path)) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (_literal.hasMatch(line)) hits.add('$path:${i + 1}: $line');
      }
    }
    if (hits.isNotEmpty) {
      // ignore: avoid_print
      print('motion_tokens_test: ${hits.length} Duration literal(s) still '
          'outside app_motion.dart (report mode):\n  ${hits.join('\n  ')}');
    }
    if (enforce) expect(hits, isEmpty);
  });

  test('the token values of §5.1', () {
    expect(Motion.pressIn.inMilliseconds, 80);
    expect(Motion.pressOut.inMilliseconds, 150);
    expect(Motion.quick.inMilliseconds, 200);
    expect(Motion.roll.inMilliseconds, 250);
    expect(Motion.standard.inMilliseconds, 300);
    expect(Motion.collapse.inMilliseconds, 250);
    expect((Motion.sheetIn, Motion.sheetOut), (
      const Duration(milliseconds: 350),
      const Duration(milliseconds: 250),
    ));
    expect((Motion.formIn, Motion.formOut), (
      const Duration(milliseconds: 400),
      const Duration(milliseconds: 300),
    ));
    expect(Motion.countUp.inMilliseconds, 500);
    expect(Motion.sweep.inMilliseconds, 600);
    expect(Motion.skeletonDelay.inMilliseconds, 400);
    expect(Motion.skeletonMinVisible.inMilliseconds, 400);
    expect(Motion.syncHintDelay, const Duration(seconds: 1));
    expect(Motion.spinnerDelay.inMilliseconds, 150);
    expect(Motion.themeChange.inMilliseconds, 250);
    expect(Motion.surfaceIn, const Cubic(0.05, 0.7, 0.1, 1.0));
  });

  test('nothing the user waits on runs past 600 ms', () {
    final full = Motion.staggerStep * Motion.staggerCap + Motion.standard;
    expect(full.inMilliseconds, lessThanOrEqualTo(600));
    for (final d in [
      Motion.quick,
      Motion.standard,
      Motion.sheetIn,
      Motion.formIn,
      Motion.countUp,
      Motion.sweep,
    ]) {
      expect(d.inMilliseconds, lessThanOrEqualTo(600));
    }
    expect(Motion.sheetOut < Motion.sheetIn, isTrue);
    expect(Motion.formOut < Motion.formIn, isTrue);
  });

  test('springs: no visible overshoot, settle within their budgets', () {
    double settle(SpringDescription spring) {
      final sim = SpringSimulation(spring, 0, 1, 0,
          tolerance: const Tolerance(distance: 0.01, velocity: 0.1));
      var t = 0.0;
      var peak = 0.0;
      while (!sim.isDone(t) && t < 2) {
        peak = peak < sim.x(t) ? sim.x(t) : peak;
        t += 0.001;
      }
      expect(peak, lessThan(1.01), reason: 'overshoot');
      return t * 1000;
    }

    expect(settle(Motion.fastSpatial), lessThan(200));
    expect(settle(Motion.defaultSpatial), lessThan(300));
    expect(settle(Motion.fastEffects), lessThan(150));
    expect(settle(Motion.defaultEffects), lessThan(250));
    expect(settle(Motion.slowEffects), lessThan(350));
  });

  testWidgets('reduced motion: no sheet animation, instant implicit ones',
      (tester) async {
    late AnimationStyle sheet;
    late Duration quick;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Builder(builder: (context) {
        sheet = Motion.sheet(context);
        quick = Motion.orInstant(context, Motion.quick);
        return const SizedBox();
      }),
    ));
    expect(sheet, AnimationStyle.noAnimation);
    expect(quick, Duration.zero);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(),
      child: Builder(builder: (context) {
        sheet = Motion.sheet(context);
        quick = Motion.orInstant(context, Motion.quick);
        return const SizedBox();
      }),
    ));
    expect(sheet, Motion.sheetStyle);
    expect(quick, Motion.quick);
  });
}
