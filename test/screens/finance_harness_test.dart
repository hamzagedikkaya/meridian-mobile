/// The finance harness's clock: [pumpFinance] fixes it at `now` (the
/// fixture's day unless given), and a test that brings its own
/// `clockProvider` override keeps it — no duplicate override.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/current_day.dart';

import '../support/app_harness.dart' show fixtureNow;
import '../support/fake_api.dart';
import '../support/finance_harness.dart';

void main() {
  testWidgets('the clock is the fixture\'s day unless given', (tester) async {
    await pumpFinance(tester, FakeApi(), const SizedBox());
    expect(tester.container().read(clockProvider)(), fixtureNow);

    final then = DateTime(2027, 3, 1, 9);
    await pumpFinance(tester, FakeApi(), const SizedBox(), now: then);
    expect(tester.container().read(clockProvider)(), then);
  });

  testWidgets('a clockProvider override of the test\'s own is kept',
      (tester) async {
    final own = DateTime(2026, 12, 31, 23);
    await pumpFinance(
      tester,
      FakeApi(),
      const SizedBox(),
      overrides: [clockProvider.overrideWithValue(() => own)],
    );
    expect(tester.takeException(), isNull);
    expect(tester.container().read(clockProvider)(), own);
  });
}
