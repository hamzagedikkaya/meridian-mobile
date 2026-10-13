/// Host side of `integration_test/perf_test.dart` (design-analysis §8.7).
///
/// For every scenario the app traced it writes
/// `build/<scenario>.timeline_summary.json` (and the full
/// `build/<scenario>.timeline.json`), prints the gated metrics, and fails
/// the run when one breaks its 120 Hz budget:
///
/// | Metric                                          | Budget  |
/// |-------------------------------------------------|---------|
/// | `90th_percentile_frame_build_time_millis`       | ≤ 4.0   |
/// | `99th_percentile_frame_build_time_millis`       | ≤ 8.0   |
/// | `99th_percentile_frame_rasterizer_time_millis`  | ≤ 8.0   |
/// | `worst_frame_build_time_millis`                 | ≤ 16    |
/// | `worst_frame_rasterizer_time_millis`            | ≤ 16    |
///
/// `missed_frame_*_budget_count` is counted against a 16 ms budget, so it
/// cannot say anything about 120 Hz and is not used. How to run it: see
/// `integration_test/perf_test.dart` and `docs/qa-2026-10.md`.
library;

import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// The budgets, metric → the most it may be (ms).
const budgets = <String, double>{
  '90th_percentile_frame_build_time_millis': 4.0,
  '99th_percentile_frame_build_time_millis': 8.0,
  '99th_percentile_frame_rasterizer_time_millis': 8.0,
  'worst_frame_build_time_millis': 16,
  'worst_frame_rasterizer_time_millis': 16,
};

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) {
          throw StateError('the app reported no data');
        }
        final broken = <String>[];
        for (final MapEntry(key: name, value: value) in data.entries) {
          // A traced scenario is a timeline; anything else (Today's first
          // content, in ms) is a plain reported number.
          if (value is! Map<String, dynamic> ||
              !value.containsKey('traceEvents')) {
            stdout.writeln('$name: $value');
            continue;
          }
          final summary = driver.TimelineSummary.summarize(
            driver.Timeline.fromJson(value),
          );
          await summary.writeTimelineToFile(
            name,
            pretty: true,
            includeSummary: true,
          );
          final json = summary.summaryJson;
          stdout.writeln('$name:');
          for (final MapEntry(key: metric, value: budget) in budgets.entries) {
            final measured = (json[metric] as num?)?.toDouble();
            final ok = measured != null && measured <= budget;
            stdout.writeln(
              '  ${ok ? 'ok  ' : 'FAIL'} $metric = '
              '${measured?.toStringAsFixed(2) ?? 'n/a'} (≤ $budget)',
            );
            if (!ok) broken.add('$name $metric = $measured (budget $budget)');
          }
          stdout.writeln('  frames: ${json['frame_count']}');
        }
        if (broken.isNotEmpty) {
          throw StateError(
            'frame budgets broken (§8.7):\n  ${broken.join('\n  ')}',
          );
        }
      },
    );
