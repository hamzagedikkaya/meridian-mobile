/// A money capture goes to the last-used account (contract §13.5), the one
/// the transaction form starts on.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/read_models.dart';

void main() {
  late FakeApi api;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({PrefKeys.lastAccountId: 2});
    prefs = await SharedPreferences.getInstance();
    api = FakeApi();
    container = containerFor(
      api,
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() => container.dispose());

  test('the line carries the last-used account', () async {
    await container.read(repositoryProvider).quickCapture('-85 kahve');
    expect(api.bodiesOf('POST /quick_captures').single, {
      'text': '-85 kahve',
      'account_id': 2,
    });
  });

  test('"save as a task" names no account', () async {
    await container
        .read(repositoryProvider)
        .quickCapture('yarın dişçi', asTodo: true);
    expect(api.bodiesOf('POST /quick_captures').single, {
      'text': 'yarın dişçi',
      'as': 'todo',
    });
  });

  test('an account the list shows archived is not sent', () async {
    api.on('GET /accounts', {
      'accounts': [
        accountJson(id: 1),
        accountJson(id: 2, archived: true),
      ],
    });
    container.listen(accountsProvider, (_, _) {});
    await container.read(accountsProvider.future);
    await container.read(repositoryProvider).quickCapture('-85 kahve');
    expect(api.bodiesOf('POST /quick_captures').single, {'text': '-85 kahve'});
  });

  test('a 404 (the account is gone): forgotten, and sent again without it',
      () async {
    api.on(
      'POST /quick_captures',
      {'error': 'not_found', 'code': 'not_found'},
      status: 404,
    );
    await expectLater(
      container.read(repositoryProvider).quickCapture('-85 kahve'),
      throwsA(isA<ApiException>()),
    );
    expect(api.bodiesOf('POST /quick_captures'), [
      {'text': '-85 kahve', 'account_id': 2},
      {'text': '-85 kahve'},
    ]);
    expect(prefs.getInt(PrefKeys.lastAccountId), isNull);
  });
}
