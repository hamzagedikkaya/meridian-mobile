/// The session's own bookkeeping: whose journal drafts are kept on this
/// phone, the token's server, and answers that land after the account they
/// were asked for has gone.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/profile_actions.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/ui/flows/flows.dart';
import 'package:meridian_mobile/ui/screens/finance/subscriptions_screen.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/start_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/fake_stores.dart';
import '../support/read_models.dart';

Map<String, dynamic> _other() => {
      ...userJson(),
      'id': 12,
      'email': 'baska@meridian.local',
    };

void main() {
  late FakeApi api;
  late ProviderContainer container;
  const storage = FlutterSecureStorage();

  SessionController session() => container.read(sessionProvider.notifier);
  Future<String?> draft([int? id]) =>
      storage.read(key: id == null ? 'journal_draft' : 'journal_draft_$id');
  Future<String?> owner() => storage.read(key: 'journal_drafts_owner');

  Future<void> signInAs(Map<String, dynamic> user) async {
    api.on('POST /session', {'token': 't${user['id']}', 'user': user});
    await session().login('${user['email']}', 'x');
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'installed': true,
      PrefKeys.serverUrl: 'http://a.test',
    });
    final prefs = await SharedPreferences.getInstance();
    api = FakeApi();
    container = containerFor(
      api,
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() => container.dispose());

  group('journal drafts belong to an account', () {
    test('a restored session records whose they are: after a 401 another '
        'account signing in starts without them', () async {
      // Signed in when the app was updated: drafts, no owner yet.
      FlutterSecureStorage.setMockInitialValues({
        'api_token': 't9',
        'journal_draft': '{"fields":{"body":"A\'nın özel günlüğü"}}',
        'journal_draft_20': '{"fields":{"title":"A\'nın düzenlemesi"}}',
      });
      await session().restore();
      await settle();
      expect(await owner(), '9:demo@meridian.local');

      await session().forceLogout();
      expect(await draft(), isNotNull, reason: 'a 401 keeps them');

      await signInAs(_other());
      expect(await draft(), isNull);
      expect(await draft(20), isNull);
    });

    test('a restored session that never learnt its account does not hand '
        'them to the next sign-in', () async {
      FlutterSecureStorage.setMockInitialValues({
        'api_token': 't9',
        'journal_draft': '{"fields":{"body":"A\'nın özel günlüğü"}}',
      });
      api.failNetwork('GET /me');
      await session().restore();
      await settle();
      expect(await owner(), isNull);

      await session().forceLogout();
      await signInAs(_other());
      expect(await draft(), isNull);
    });

    test('the same account under a new e-mail finds them after a 401', () async {
      FlutterSecureStorage.setMockInitialValues({});
      await signInAs(userJson());
      final renamed = {...userJson(), 'email': 'yeni@meridian.local'};
      api.on('PATCH /me', {'user': renamed});
      await container
          .read(profileActionsProvider)
          .update(email: 'yeni@meridian.local', currentPassword: 'pw');
      await storage.write(key: 'journal_draft', value: '{"fields":{}}');

      await session().forceLogout();
      await signInAs(renamed);
      expect(await draft(), '{"fields":{}}');
      expect(await owner(), '9:yeni@meridian.local');
    });

    test('a server change keeps them only when it is known whose they are',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'journal_draft': '{"fields":{}}',
      });
      await session().serverChanged();
      expect(await draft(), isNull);
    });
  });

  test('a sign-in answered after the server changed stores no token and '
      'signs nobody in', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final tokens = MemoryTokenStore(token: null);
    container.dispose();
    final prefs = await SharedPreferences.getInstance();
    container = containerFor(
      api,
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(tokens),
      ],
    );
    container.read(sessionProvider);
    api
      ..on('POST /session', {'token': 'tok-from-A', 'user': userJson()})
      ..hold('POST /session');
    final login = session().login('demo@meridian.local', 'x');
    await settle();
    await container.read(serverUrlProvider.notifier).set('http://b.test');
    api.release('POST /session');
    await expectLater(
      login,
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiErrorKind.network)),
    );
    expect(tokens.written, isEmpty);
    expect(container.read(sessionProvider), isA<SessionLoggedOut>());
  });

  test('a /me answer that lands after a sign-out is not the next account\'s',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    await signInAs(userJson());
    api.hold('GET /me');
    final refresh = session().refreshMe();
    await settle();
    await session().logout();
    await signInAs(_other());
    api.release('GET /me');
    await refresh;
    expect(container.read(currentUserProvider)?.id, 12);
  });

  group('what the app keeps about an account goes with its session', () {
    for (final (name, end) in <(String, Future<void> Function(SessionController))>[
      ('a sign-out', (s) => s.logout()),
      ('a 401', (s) => s.forceLogout()),
      ('a server change', (s) => s.serverChanged()),
    ]) {
      test(name, () async {
        FlutterSecureStorage.setMockInitialValues({});
        await signInAs(userJson());
        container.listen(agendaOverdueProvider, (_, _) {});
        container.listen(habitCadenceProvider, (_, _) {});
        container.listen(todayStartFlagsProvider, (_, _) {});
        container
            .read(agendaOverdueProvider.notifier)
            .report(Fetched(5, DateTime.now()));
        container
            .read(habitCadenceProvider.notifier)
            .learn([Habit.fromJson(habitJson())]);
        container.read(todayStartFlagsProvider.notifier).dismiss();
        container.listen(subscriptionDueOverridesProvider, (_, _) {});
        container.listen(subscriptionChargesInFlightProvider, (_, _) {});
        container
            .read(subscriptionDueOverridesProvider.notifier)
            .set(3, DateTime(2026, 11, 5));
        container.read(subscriptionChargesInFlightProvider.notifier).claim(3);

        await end(session());
        await signInAs(_other());
        expect(container.read(agendaOverdueProvider), isNull);
        expect(container.read(habitCadenceProvider), isEmpty);
        expect(container.read(todayStartFlagsProvider).dismissed, isFalse);
        expect(container.read(subscriptionDueOverridesProvider), isEmpty);
        expect(container.read(subscriptionChargesInFlightProvider), isEmpty);
      });
    }
  });
}
