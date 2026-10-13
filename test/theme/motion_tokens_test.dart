/// Motion tokens (design-analysis §5.1).
///
/// The literal scan is MANDATORY (WP-17): a `Duration(…)` or a curve literal
/// (`Curves.…`, `Cubic(…)`) anywhere in [scanned] outside
/// `lib/theme/app_motion.dart` fails, unless [allowed] names it below with
/// its reason. A new timing goes into `Motion` under a name that says what
/// it is for; a new non-motion timer (a debounce, a data horizon) is added
/// to [allowed] with one line saying why it is not motion.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/theme/app_motion.dart';

/// The documented exceptions: file → the snippets on its allowed lines (an
/// empty list allows the whole file). None of these is motion.
const allowed = <String, List<String>>{
  // Snackbar lengths (4 s / 6 s / 8 s): reading time, not animation.
  'lib/ui/widgets/app_snackbar.dart': [],
  // The server-address ping debounce (1500 ms).
  'lib/ui/widgets/server_url_field.dart': [],
  // How often the journal editor puts a draft aside.
  'lib/ui/screens/journal/journal_editor.dart': ['journalDraftInterval ='],
  // How long after a tap a change back counts as its write having failed.
  'lib/ui/widgets/check_pop.dart': ['rollbackWindow ='],
  // How long after a tap the server's answer may still earn a milestone.
  'lib/ui/screens/habits/habits_screen.dart': ['_milestoneWindow ='],
  // The clock's wake-up at the next minute.
  'lib/ui/screens/today/widgets/today_clock.dart': [
    'Duration(milliseconds: 50)',
    'Duration(seconds: 1)',
  ],
  // How long the app must be away before a resume refreshes it.
  'lib/ui/screens/shell/freshness_gate.dart': ['Duration(seconds: 30)'],
  // When retired scroll controllers are disposed (long after the fade).
  'lib/ui/screens/finance/transactions_screen.dart': ['_retireTimer = Timer('],
};

/// Where motion lives. Network timeouts and retry back-offs in `lib/core`
/// and `lib/data` are not motion and keep their own constants.
const scanned = ['lib/ui', 'lib/router', 'lib/theme', 'lib/main.dart'];

/// Sub-minute literals: days, hours and minutes are calendar arithmetic
/// (an event's default hour, a 30-day range), never motion.
final _duration =
    RegExp(r'Duration\(\s*(seconds|milliseconds|microseconds)\s*:');
final _curve = RegExp(r'\bCurves\.\w+|\bCubic\(');

/// Never anywhere, app_motion.dart included (§5.1 rule 3: one overshoot).
final _overshoot = RegExp(r'easeOutBack|elasticOut|elasticIn|bounceOut');

List<File> _dartFiles() => [
      for (final entry in scanned)
        if (FileSystemEntity.isDirectorySync(entry))
          ...Directory(entry).listSync(recursive: true)
        else
          File(entry),
    ]
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  test('no Duration or curve literal outside app_motion.dart', () {
    final hits = <String>[];
    for (final file in _dartFiles()) {
      final path = file.path.replaceAll(r'\', '/');
      if (path == 'lib/theme/app_motion.dart') continue;
      final exempt = allowed[path];
      if (exempt != null && exempt.isEmpty) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (!_duration.hasMatch(line) && !_curve.hasMatch(line)) continue;
        if (exempt != null && exempt.any(line.contains)) continue;
        hits.add('$path:${i + 1}: $line');
      }
    }
    expect(hits, isEmpty,
        reason: 'Move these onto Motion tokens (lib/theme/app_motion.dart) '
            'or document them in `allowed`:\n  ${hits.join('\n  ')}');
  });

  test('every documented exception still exists', () {
    for (final MapEntry(key: path, value: snippets) in allowed.entries) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is gone');
      final source = file.readAsStringSync();
      for (final snippet in snippets) {
        expect(source.contains(snippet), isTrue,
            reason: '$path no longer has `$snippet`: drop it from allowed');
      }
    }
  });

  test('no overshooting curve anywhere', () {
    for (final file in _dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        expect(_overshoot.hasMatch(line), isFalse,
            reason: '${file.path}:${i + 1}: $line');
      }
    }
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
