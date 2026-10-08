/// The profile's writes (contract §2): account settings, the password — whose
/// new token the session must keep — and signing out everywhere.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/data_scope.dart';
import 'package:meridian_mobile/data/deferred_deletes.dart';
import 'package:meridian_mobile/data/profile_actions.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/fake_stores.dart';
import '../support/read_models.dart';

Map<String, dynamic> _refusal(
  String code,
  Map<String, List<Map<String, Object?>>> details,
) => {
  'errors': {
    for (final field in details.keys) field: ['raw'],
  },
  'code': code,
  'details': details,
};

void main() {
  late FakeApi api;
  late MemoryTokenStore tokens;
  late MemoryDraftStore drafts;
  late SharedPreferences prefs;
  late ProviderContainer container;

  ProfileActions actions() => container.read(profileActionsProvider);
  SessionState session() => container.read(sessionProvider);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      PrefKeys.serverUrl: 'http://meridian.test',
      PrefKeys.lastAccountId: 1,
    });
    prefs = await SharedPreferences.getInstance();
    api = FakeApi();
    tokens = MemoryTokenStore(origin: 'http://meridian.test');
    drafts = MemoryDraftStore();
    container = containerFor(
      api,
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        ...signedInOverrides(tokens: tokens, drafts: drafts),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('update (PATCH /me)', () {
    test(
      'sends only what changed and puts the answer on every screen',
      () async {
        api.on('PATCH /me', {'user': userJson(name: 'Hamza Gedik')});
        await actions().update(name: 'Hamza Gedik');
        expect(api.bodiesOf('PATCH /me').single, {'name': 'Hamza Gedik'});
        expect(container.read(currentUserProvider)?.displayName, 'Hamza Gedik');
      },
    );

    test(
      'a new e-mail goes with the current password, and nothing else',
      () async {
        await actions().update(
          email: 'yeni@example.com',
          currentPassword: 'x1',
        );
        expect(api.bodiesOf('PATCH /me').single, {
          'email': 'yeni@example.com',
          'current_password': 'x1',
        });
      },
    );

    test('the weekly review day is sent as a number', () async {
      api.on('PATCH /me', {
        'user': {...userJson(), 'weekly_review_day': 1},
      });
      final user = await actions().update(weeklyReviewDay: 1);
      expect(api.bodiesOf('PATCH /me').single, {'weekly_review_day': 1});
      expect(user.weeklyReviewDay, 1);
    });

    test('a currency or time zone change refetches every screen and the '
        'signed-in user', () async {
      await showEverything(container, api);
      api.on('PATCH /me', {
        'user': {...userJson(), 'currency': 'USD'},
      });
      await actions().update(currency: 'USD');
      expect(container.read(currentUserProvider)?.currency, 'USD');
      await settle(api);
      expect(api.gets.toSet(), {...readModelsByPath().keys, '/me'});
    });

    test(
      'a time zone change moves the account\'s day with the answer',
      () async {
        api.on('PATCH /me', {
          'user': {
            ...userJson(),
            'timezone': 'Tokyo',
            'timezone_iana': 'Asia/Tokyo',
            'utc_offset': '+09:00',
          },
        });
        await actions().update(timezone: 'Tokyo');
        final user = container.read(currentUserProvider)!;
        expect(user.timezone, 'Tokyo');
        expect(user.utcOffset, const Duration(hours: 9));
      },
    );

    test(
      'a refusal keeps the user as it was and says which field and why',
      () async {
        api.on(
          'PATCH /me',
          _refusal('invalid_current_password', {
            'current_password': [
              {'error': 'invalid'},
            ],
          }),
          status: 422,
        );
        await expectLater(
          actions().update(email: 'a@b.c', currentPassword: 'wrong'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', 'invalid_current_password')
                .having((e) => e.details.keys, 'fields', ['current_password']),
          ),
        );
        expect(
          container.read(currentUserProvider)?.email,
          'demo@meridian.local',
        );
      },
    );
  });

  test('fetchMeOptions reads the currencies and the zones', () async {
    final options = await container.read(repositoryProvider).fetchMeOptions();
    expect(options.currencies.map((c) => c.code), [
      'TRY',
      'USD',
      'EUR',
      'GBP',
      'GAU',
    ]);
    expect(options.timezones, hasLength(4));
    expect(options.timezones[2].iana, 'Europe/Istanbul');
    expect(options.timezones[2].utcOffset, const Duration(hours: 3));
  });

  group('changePassword (PATCH /me/password)', () {
    test(
      'stores the new token before anything else and stays signed in',
      () async {
        api.on('PATCH /me/password', {
          'token': 'CiF1Cc5Po4rf4tFXgh2kXDmW',
          'user': userJson(name: 'Hamza'),
        });
        await actions().changePassword(
          currentPassword: 'eski-sifre',
          password: 'yeni-sifre-1',
          passwordConfirmation: 'yeni-sifre-1',
        );
        expect(api.bodiesOf('PATCH /me/password').single, {
          'current_password': 'eski-sifre',
          'password': 'yeni-sifre-1',
          'password_confirmation': 'yeni-sifre-1',
        });
        expect(tokens.token, 'CiF1Cc5Po4rf4tFXgh2kXDmW');
        expect(tokens.origin, 'http://meridian.test');
        expect(session(), isA<SessionLoggedIn>());
        expect(container.read(currentUserProvider)?.displayName, 'Hamza');
      },
    );

    test('a 401 elsewhere while the token is being replaced does not sign '
        'out', () async {
      api.hold('PATCH /me/password');
      final change = actions().changePassword(
        currentPassword: 'eski-sifre',
        password: 'yeni-sifre-1',
        passwordConfirmation: 'yeni-sifre-1',
      );
      await Future<void>.delayed(Duration.zero);
      // A refetch that left with the old token is refused meanwhile.
      await container.read(sessionProvider.notifier).forceLogout();
      expect(session(), isA<SessionLoggedIn>());
      api.release('PATCH /me/password');
      await change;
      expect(tokens.token, 'new-token');
      expect(session(), isA<SessionLoggedIn>());
    });

    test('a refusal keeps the old token', () async {
      api.on(
        'PATCH /me/password',
        _refusal('validation_failed', {
          'password': [
            {'error': 'too_short', 'count': 6},
          ],
        }),
        status: 422,
      );
      await expectLater(
        actions().changePassword(
          currentPassword: 'eski-sifre',
          password: '123',
          passwordConfirmation: '123',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(tokens.token, 'old-token');
      expect(tokens.written, isEmpty);
      expect(session(), isA<SessionLoggedIn>());
    });

    test('the rate limit (429) is reported as such', () async {
      api.on('PATCH /me/password', {
        'error': 'too_many_requests',
        'code': 'too_many_requests',
      }, status: 429);
      await expectLater(
        actions().changePassword(
          currentPassword: 'a',
          password: 'bbbbbb',
          passwordConfirmation: 'bbbbbb',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.rateLimited,
          ),
        ),
      );
      expect(tokens.token, 'old-token');
    });

    test(
      'a 401 on the change itself: the session was over, so sign out',
      () async {
        api.on('PATCH /me/password', {
          'error': 'unauthorized',
          'code': 'unauthorized',
        }, status: 401);
        await expectLater(
          actions().changePassword(
            currentPassword: 'a',
            password: 'bbbbbb',
            passwordConfirmation: 'bbbbbb',
          ),
          throwsA(isA<ApiException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          session(),
          isA<SessionLoggedOut>().having((s) => s.expired, 'expired', isTrue),
        );
      },
    );

    test('a 401 on a second change sent before the first one answered: it '
        'left with the replaced token, so the new one stays', () async {
      final first = Completer<({String token, User user})>();
      final second = Completer<({String token, User user})>();
      final notifier = container.read(sessionProvider.notifier);
      final a = notifier.replacingToken(() => first.future);
      final b = notifier.replacingToken(() => second.future);
      await Future<void>.delayed(Duration.zero);
      first.complete((token: 'new-token-1', user: User.fromJson(userJson())));
      await a;
      second.completeError(
        ApiException(
          ApiErrorKind.unauthorized,
          status: 401,
          code: 'unauthorized',
        ),
      );
      await expectLater(b, throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      expect(tokens.token, 'new-token-1');
      expect(session(), isA<SessionLoggedIn>());
    });

    test('an answer without a token is not taken for success', () async {
      api.on('PATCH /me/password', {'user': userJson()});
      await expectLater(
        actions().changePassword(
          currentPassword: 'a',
          password: 'bbbbbb',
          passwordConfirmation: 'bbbbbb',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(tokens.token, 'old-token');
    });
  });

  group('signOut (DELETE /session)', () {
    test(
      'revokes the token on the server, then forgets the account here',
      () async {
        drafts.value = '{"body":"yarım"}';
        await actions().signOut();
        expect(api.requests, contains('DELETE /session'));
        expect(
          session(),
          isA<SessionLoggedOut>()
              .having((s) => s.revokeFailed, 'revokeFailed', isFalse)
              .having((s) => s.expired, 'expired', isFalse),
        );
        expect(tokens.token, isNull);
        expect(drafts.value, isNull);
        expect(prefs.getInt(PrefKeys.lastAccountId), isNull);
        expect(prefs.getString(PrefKeys.serverUrl), 'http://meridian.test');
      },
    );

    test('the server cannot be reached: signed out here all the same, and '
        'the state says the server session could not be revoked', () async {
      api.failNetwork('DELETE /session');
      await actions().signOut();
      expect(
        session(),
        isA<SessionLoggedOut>().having(
          (s) => s.revokeFailed,
          'revokeFailed',
          isTrue,
        ),
      );
      expect(tokens.token, isNull);
    });

    test('a server error is not a revoke either', () async {
      api.fail('DELETE /session', 500);
      await actions().signOut();
      expect(
        session(),
        isA<SessionLoggedOut>().having(
          (s) => s.revokeFailed,
          'revokeFailed',
          isTrue,
        ),
      );
    });

    test(
      '401: the token was already replaced elsewhere — nothing to revoke',
      () async {
        api.on('DELETE /session', {
          'error': 'unauthorized',
          'code': 'unauthorized',
        }, status: 401);
        await actions().signOut();
        expect(
          session(),
          isA<SessionLoggedOut>()
              .having((s) => s.revokeFailed, 'revokeFailed', isFalse)
              .having((s) => s.expired, 'expired', isFalse),
        );
      },
    );

    test(
      'a delete still waiting out its undo is sent before the token goes',
      () async {
        final repo = container.read(repositoryProvider);
        container.read(deferredDeletesProvider.notifier).stage((
          scope: DataScope.transactions,
          id: 316,
        ), send: () => repo.deleteTransaction(316));
        await actions().signOut();
        final deletes = api.requests.where((r) => r.startsWith('DELETE'));
        expect(deletes, ['DELETE /transactions/316', 'DELETE /session']);
      },
    );

    test(
      'a 401 elsewhere while signing out is not an expired session',
      () async {
        api.hold('DELETE /session');
        final out = actions().signOut();
        await Future<void>.delayed(Duration.zero);
        await container.read(sessionProvider.notifier).forceLogout();
        expect(session(), isA<SessionLoggedIn>());
        api.release('DELETE /session');
        await out;
        expect(
          session(),
          isA<SessionLoggedOut>().having((s) => s.expired, 'expired', isFalse),
        );
      },
    );
  });

  group('hasUnsavedDraft', () {
    test('a draft with something in it', () async {
      drafts.value = jsonEncode({'title': '', 'body': 'Bugün...'});
      expect(await actions().hasUnsavedDraft(), isTrue);
      drafts.value = jsonEncode({'title': '', 'body': '', 'mood': 'good'});
      expect(await actions().hasUnsavedDraft(), isTrue);
    });

    test('no draft, or an empty one', () async {
      expect(await actions().hasUnsavedDraft(), isFalse);
      drafts.value = jsonEncode({
        'title': ' ',
        'body': '',
        'gratitude': '',
        'tags': '',
        'mood': null,
      });
      expect(await actions().hasUnsavedDraft(), isFalse);
    });
  });
}
