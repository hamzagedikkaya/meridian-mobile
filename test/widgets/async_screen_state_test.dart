import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/sync.dart';
import 'package:meridian_mobile/ui/widgets/sync_hint.dart';

import '../support/fake_api.dart';

/// GET /goals once the server answers again.
Map<String, dynamic> _goals() => {
      'active': [goalJson()],
      'achieved': const [],
      'abandoned': const [],
    };

/// A screen showing a real read model (the Goals tab's) against [api], with
/// the app's retry policy, and every state it was given.
class _Screen {
  _Screen(this.api)
      : container = ProviderContainer.test(
          overrides: [dioProvider.overrideWithValue(api.dio)],
          retry: readRetry,
        ) {
    container.listen(goalsProvider, (_, next) => states.add(next),
        fireImmediately: true);
  }

  final FakeApi api;
  final ProviderContainer container;
  final states = <AsyncValue<Object?>>[];

  AsyncValue<Object?> get now => container.read(goalsProvider);

  /// The error view's or the offline banner's Retry (and a pull, a re-tap).
  void retry() => container.read(dataSyncProvider).refresh([goalsProvider]);

  int get fetches => api.gets.where((path) => path == '/goals').length;

  /// Cancels the midnight timer the read model armed.
  void close() => container.dispose();
}

/// The skeleton / error view / data decision every screen makes, against a
/// real read model and its quick retry (the app's policy), so that no
/// refresh or retry ever flashes a skeleton, a blip the retry heals never
/// shows a failure, and a failure once shown is never withdrawn by a retry
/// that fails again.
void main() {
  test('every read model retries inside its fetch: Riverpod\'s own retry, '
      'which would withdraw a failure on screen while it runs, is off', () {
    for (final model in allReadModels) {
      final retry = model.retry;
      expect(retry, isNotNull, reason: '$model');
      expect(retry!(0, ApiException(ApiErrorKind.network)), isNull,
          reason: '$model');
    }
  });

  testWidgets('a first load that blips: the skeleton through the quick retry, '
      'then the data', (tester) async {
    final api = FakeApi()..blip('GET /goals');
    final screen = _Screen(api);
    expect(screen.now.isFirstLoad, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    expect(screen.fetches, 1, reason: 'failed; the retry is pending');
    expect(screen.now.isFirstLoad, isTrue);
    expect(screen.now.hasFailed, isFalse);

    await tester.pump(const Duration(milliseconds: 800));
    expect(screen.fetches, 2);
    expect(screen.now.hasValue, isTrue);
    expect(screen.states.where((s) => s.hasFailed), isEmpty);
    screen.close();
  });

  testWidgets('a first load that fails for good: the skeleton through the '
      'quick retry, then the error view', (tester) async {
    final api = FakeApi()..failNetwork('GET /goals');
    final screen = _Screen(api);

    await tester.pump(const Duration(milliseconds: 100));
    expect(screen.now.isFirstLoad, isTrue);
    expect(screen.now.hasFailed, isFalse);

    await tester.pump(const Duration(milliseconds: 800));
    expect(screen.fetches, 2);
    expect(screen.now.hasFailed, isTrue);
    expect(screen.now.isFirstLoad, isFalse);
    expect(screen.now.isRefetching, isFalse);
    screen.close();
  });

  testWidgets('a retry from the error view while the server still refuses: '
      'the error view stays up throughout, under the hint — never the '
      'skeleton', (tester) async {
    final api = FakeApi()..failNetwork('GET /goals');
    final screen = _Screen(api);
    await tester.pump(const Duration(seconds: 1));
    expect(screen.now.hasFailed, isTrue);

    for (var retry = 1; retry <= 2; retry++) {
      screen.states.clear();
      screen.retry();
      await tester.pump(const Duration(milliseconds: 20));
      // The first attempt failed and its quick retry is pending.
      expect(screen.now.hasFailed, isTrue, reason: 'retry $retry');
      expect(screen.now.isFirstLoad, isFalse, reason: 'retry $retry');
      expect(screen.now.isRefetching, isTrue, reason: 'retry $retry');

      await tester.pump(const Duration(milliseconds: 900));
      expect(screen.now.isLoading, isFalse, reason: 'retry $retry');
      expect(screen.states, isNotEmpty);
      expect(screen.states, everyElement(isA<AsyncValue<Object?>>()
          .having((s) => s.hasFailed, 'hasFailed', isTrue)
          .having((s) => s.isFirstLoad, 'isFirstLoad', isFalse)),
          reason: 'retry $retry: every state the screen was given');
    }
    expect(screen.fetches, 6, reason: 'each fetch got its quick retry');

    // The server is back: the retry lands, and only then the view goes.
    api.on('GET /goals', _goals());
    screen.retry();
    await tester.pump(const Duration(milliseconds: 20));
    expect(screen.now.hasValue, isTrue);
    expect(screen.now.hasFailed, isFalse);
    expect(screen.now.isLoading, isFalse);
    screen.close();
  });

  testWidgets('a background refresh that blips and heals on the quick retry '
      'never shows the offline banner', (tester) async {
    final api = FakeApi();
    final screen = _Screen(api);
    await tester.pump(const Duration(milliseconds: 20));
    final before = screen.now.value;
    expect(before, isNotNull);

    for (var refresh = 1; refresh <= 2; refresh++) {
      api.blip('GET /goals');
      screen.retry();
      await tester.pump(const Duration(milliseconds: 20));
      expect(screen.now.isRefetching, isTrue, reason: 'refresh $refresh');
      expect(screen.now.refreshFailed, isFalse, reason: 'refresh $refresh');
      expect(screen.now.hasValue, isTrue, reason: 'kept on screen');

      await tester.pump(const Duration(milliseconds: 900));
      expect(screen.now.hasError, isFalse, reason: 'refresh $refresh');
      expect(screen.now.isLoading, isFalse, reason: 'refresh $refresh');
    }
    expect(screen.states.where((s) => s.refreshFailed), isEmpty);
    expect(screen.fetches, 5);
    screen.close();
  });

  testWidgets('a refresh that fails for good puts the offline banner up once '
      'its quick retry has failed too; a second failed refresh keeps it up '
      'throughout', (tester) async {
    final api = FakeApi();
    final screen = _Screen(api);
    await tester.pump(const Duration(milliseconds: 20));

    api.failNetwork('GET /goals');
    screen.retry();
    await tester.pump(const Duration(milliseconds: 20));
    expect(screen.now.refreshFailed, isFalse, reason: 'the retry is pending');
    expect(screen.now.isRefetching, isTrue);
    await tester.pump(const Duration(milliseconds: 900));
    expect(screen.now.refreshFailed, isTrue);
    expect(screen.now.hasValue, isTrue);
    expect(screen.now.isLoading, isFalse);

    // Pulled, resumed or re-tapped while the server still refuses.
    screen.states.clear();
    screen.retry();
    await tester.pump(const Duration(milliseconds: 20));
    expect(screen.now.refreshFailed, isTrue);
    expect(screen.now.isRefetching, isTrue);
    await tester.pump(const Duration(milliseconds: 900));
    expect(screen.now.isLoading, isFalse);
    expect(screen.states, isNotEmpty);
    expect(screen.states, everyElement(isA<AsyncValue<Object?>>()
        .having((s) => s.refreshFailed, 'refreshFailed', isTrue)),
        reason: 'the banner never comes down while the refresh runs');

    // The server is back: the banner goes once the refresh lands.
    api.on('GET /goals', _goals());
    screen.retry();
    await tester.pump(const Duration(milliseconds: 20));
    expect(screen.now.refreshFailed, isFalse);
    expect(screen.now.isLoading, isFalse);
    screen.close();
  });

  test('a 404 says the record is gone; other failures do not', () {
    AsyncValue<Object?> failed(Object error) =>
        AsyncError<Object?>(error, StackTrace.empty);
    expect(failed(ApiException(ApiErrorKind.notFound, status: 404)).isGone,
        isTrue);
    expect(failed(ApiException(ApiErrorKind.network)).isGone, isFalse);
    expect(failed(ApiException(ApiErrorKind.server, status: 500)).isGone,
        isFalse);
    expect(const AsyncData<Object?>(1).isGone, isFalse);
  });
}
