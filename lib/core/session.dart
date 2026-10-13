import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import 'api.dart';

class PrefKeys {
  static const serverUrl = 'server_url';
  static const installed = 'installed';
  static const locale = 'locale';
  static const themeMode = 'theme_mode';

  /// The app's own "Reduce motion" switch, `'true'` when on (see
  /// `reduceMotionProvider`).
  static const reduceMotion = 'reduce_motion';

  /// The time-zone pair whose notice on Today was dismissed (see
  /// `zoneMismatchProvider`): account and device offsets in minutes.
  static const zoneNoticeDismissed = 'zone_notice_dismissed';

  /// The account the last transaction was saved on: a new one starts there
  /// unless the user chose a [defaultAccountId].
  static const lastAccountId = 'last_account_id';

  /// The account the user made the default ("Varsayılan hesap" on the
  /// account form): new transactions start there, whatever was used last.
  static const defaultAccountId = 'default_account_id';

  /// Device-level settings that survive a sign-out.
  static const keptOnSignOut = [serverUrl, locale, themeMode, reduceMotion];
}

/// Overridden with the real instance in main().
final sharedPrefsProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

/// The token and the journal drafts never leave this phone: on iOS they are
/// kept in keychain items of a `_this_device` class, which go into no backup
/// and no transfer to a new phone (as Android's backup rules exclude them).
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(iOptions: secureStorageIosOptions),
);

const secureStorageIosOptions = IOSOptions(
  accessibility: KeychainAccessibility.unlocked_this_device,
);

class TokenStore {
  TokenStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'api_token';
  static const _originKey = 'api_token_origin';

  Future<String?> read() => _storage.read(key: _key);

  /// The token is stored together with the server that issued it. A bearer
  /// token is only ever meaningful to that one host, so recording the origin
  /// lets every request check before it hands the credential over.
  Future<void> write(String token, {required String origin}) async {
    await _storage.write(key: _key, value: token);
    await _storage.write(key: _originKey, value: origin);
  }

  /// Returns the token only when it belongs to [origin]. Tokens written by an
  /// older build carry no origin and are still honoured, so upgrading does not
  /// sign anyone out.
  Future<String?> readFor(String origin) async {
    final issuedFor = await _storage.read(key: _originKey);
    if (issuedFor != null && issuedFor != origin) return null;
    return _storage.read(key: _key);
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: _originKey);
  }
}

final tokenStoreProvider =
    Provider<TokenStore>((ref) => TokenStore(ref.watch(secureStorageProvider)));

/// An unsaved journal entry is the most private thing this app holds, and the
/// editor autosaves it every five seconds. Keeping it in SharedPreferences
/// would write it to a world-readable-by-root XML file; the same encrypted
/// store the token lives in costs nothing extra here.
///
/// One draft per entry: the new entry's ([entryId] null) and one for each
/// entry being edited, so an edit left unsaved never turns up in another.
class DraftStore {
  DraftStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'journal_draft';

  static String _keyFor(int? entryId) =>
      entryId == null ? _key : '${_key}_$entryId';

  Future<String?> read({int? entryId}) => _storage.read(key: _keyFor(entryId));
  Future<void> write(String value, {int? entryId}) =>
      _storage.write(key: _keyFor(entryId), value: value);
  Future<void> clear({int? entryId}) => _storage.delete(key: _keyFor(entryId));

  /// Who wrote the drafts: they outlive an expired session (a 401) and a
  /// change of server address, so the next sign-in may be someone else's.
  static const _ownerKey = 'journal_drafts_owner';

  /// The owner key of [user]: id and e-mail, so the same account reached
  /// at another address keeps its drafts while another server's account
  /// with the same id does not get them.
  static String ownerOf(User user) =>
      '${user.id}:${user.email.trim().toLowerCase()}';

  static String _idOf(String owner) => owner.split(':').first;

  /// Hands the drafts to [owner], the account signing in. Drafts of anyone
  /// else — another account, or nobody known — are dropped first: never
  /// shown to it, nor saved over one of its entries that happens to have
  /// the same id.
  Future<void> claimFor(String owner) async {
    final previous = await _storage.read(key: _ownerKey);
    if (previous == owner) return;
    await clearAll();
    await _storage.write(key: _ownerKey, value: owner);
  }

  /// The signed-in session learnt who it belongs to ([owner]: a `/me`
  /// answer, an e-mail change). The token is the same, so is the account:
  /// drafts without an owner (kept by an older build of the app) are its,
  /// and a new e-mail moves them along instead of dropping them at the
  /// next sign-in. Another id — which a session never changes to — drops
  /// them all the same.
  Future<void> adopt(String owner) async {
    final previous = await _storage.read(key: _ownerKey);
    if (previous == owner) return;
    if (previous != null && _idOf(previous) != _idOf(owner)) await clearAll();
    await _storage.write(key: _ownerKey, value: owner);
  }

  /// Whether the drafts' account is known; drafts whose account is not are
  /// not kept past the session they were written in.
  Future<bool> hasOwner() async =>
      await _storage.read(key: _ownerKey) != null;

  /// Every draft, and who wrote them.
  Future<void> forget() async {
    await clearAll();
    await _storage.delete(key: _ownerKey);
  }

  /// Every draft's raw value: the new entry's and the edits'.
  Future<List<String>> readAll() async {
    final all = await _storage.readAll();
    return [
      for (final entry in all.entries)
        if (entry.key == _key || entry.key.startsWith('${_key}_')) entry.value,
    ];
  }

  /// Every draft, the new entry's and the edits'.
  Future<void> clearAll() async {
    final all = await _storage.readAll();
    for (final key in all.keys.toList()) {
      if (key == _key || key.startsWith('${_key}_')) {
        await _storage.delete(key: key);
      }
    }
  }
}

final draftStoreProvider =
    Provider<DraftStore>((ref) => DraftStore(ref.watch(secureStorageProvider)));

String defaultServerUrl() {
  if (kIsWeb) return 'http://localhost:3000';
  return 'http://10.0.2.2:3000';
}

String normalizeServerUrl(String input) {
  var url = input.trim();
  if (url.isEmpty) return url;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  // Anything Dio cannot turn into a request URI is rejected here rather than
  // thrown from deep inside the HTTP stack, where nothing catches it.
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return '';
  return url;
}

class ServerUrl extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return prefs.getString(PrefKeys.serverUrl) ?? defaultServerUrl();
  }

  Future<void> set(String url) async {
    final normalized = normalizeServerUrl(url);
    if (normalized == state) return;
    state = normalized;
    await ref.read(sharedPrefsProvider).setString(PrefKeys.serverUrl, normalized);
    // A token belongs to the server that issued it. Pointing the app somewhere
    // else must never replay the old credential against the new host.
    await ref.read(sessionProvider.notifier).serverChanged();
  }
}

final serverUrlProvider = NotifierProvider<ServerUrl, String>(ServerUrl.new);

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(serverUrlProvider);
  final store = ref.watch(tokenStoreProvider);
  return buildDio(
    baseUrl: baseUrl,
    tokenReader: () => store.readFor(baseUrl),
    onUnauthorized: () => ref.read(sessionProvider.notifier).forceLogout(),
  );
});

typedef HealthResult = ({bool ok, int? latencyMs, String? version});

/// Bare ping used by the login screen and server settings — no auth, no shared dio.
Future<HealthResult> pingHealth(String serverUrl) async {
  final base = normalizeServerUrl(serverUrl);
  if (base.isEmpty) return (ok: false, latencyMs: null, version: null);
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 3),
  ));
  final watch = Stopwatch()..start();
  try {
    final res = await dio.get('$base/api/v1/health');
    watch.stop();
    final data = res.data;
    final ok = data is Map && data['ok'] == true;
    return (
      ok: ok,
      latencyMs: watch.elapsedMilliseconds,
      version: ok ? data['version']?.toString() : null,
    );
  } catch (_) {
    return (ok: false, latencyMs: null, version: null);
  } finally {
    dio.close();
  }
}

sealed class SessionState {
  const SessionState();
}

class SessionUnknown extends SessionState {
  const SessionUnknown();
}

class SessionLoggedOut extends SessionState {
  /// True when a mid-session 401 ejected us — the login screen turns this into
  /// a localized notice. State carries the *reason*, never the copy.
  final bool expired;

  /// True when the user signed out but the server could not be told
  /// (`DELETE /session` never got an answer): this phone is signed out, yet
  /// the account's token still works elsewhere. The login screen says so.
  final bool revokeFailed;
  const SessionLoggedOut({this.expired = false, this.revokeFailed = false});
}

class SessionLoggedIn extends SessionState {
  final User? user;
  const SessionLoggedIn({this.user});
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionUnknown();

  /// Requests under way that replace the account's token (a password
  /// change) or end the session (a sign-out). Meanwhile a 401 is expected —
  /// any request that left with the old token gets one — and is not taken
  /// for a session that died.
  var _tokenSwaps = 0;

  /// Counts the sessions: it moves whenever one starts or ends. An answer
  /// about the signed-in user that was asked for under another number
  /// belongs to an account that is no longer signed in (see [replaceUser]).
  int get epoch => _epoch;
  var _epoch = 0;

  /// Draft ownership changes, one after another: a sign-out's wipe waits
  /// for an e-mail change being recorded, and so on.
  Future<void> _drafts = Future.value();

  Future<void> _onDrafts(Future<void> Function(DraftStore store) change) {
    final store = ref.read(draftStoreProvider);
    final next = _drafts.then((_) async {
      try {
        await change(store);
      } catch (_) {
        // A secure-storage hiccup must not keep anyone signed in or out.
      }
    });
    _drafts = next;
    return next;
  }

  /// Splash gate: token check ≤50ms, optimistic route, /me probe in background.
  Future<void> restore() async {
    final prefs = ref.read(sharedPrefsProvider);
    final store = ref.read(tokenStoreProvider);

    if (!kIsWeb && !(prefs.getBool(PrefKeys.installed) ?? false)) {
      await store.clear();
      // A first run: whatever secure storage kept (an iOS keychain outlives
      // the app) is a previous install's.
      await _onDrafts((drafts) => drafts.forget());
      await prefs.setBool(PrefKeys.installed, true);
      state = const SessionLoggedOut();
      return;
    }

    final token = await store.read();
    if (token == null || token.isEmpty) {
      state = const SessionLoggedOut();
      return;
    }
    _epoch++;
    state = const SessionLoggedIn();
    _probeMe();
  }

  Future<void> _probeMe({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final epoch = _epoch;
    try {
      final res = await ref.read(dioProvider).get(
            '/me',
            options: Options(receiveTimeout: timeout),
          );
      final user =
          User.fromJson((res.data as Map)['user'] as Map<String, dynamic>);
      if (ref.mounted) replaceUser(user, epoch: epoch);
    } catch (_) {
      // Offline keeps the optimistic session (the next resume or Today
      // refresh asks again); a 401 is ejected by the interceptor; an
      // unreadable payload leaves the last good user in place.
    }
  }

  /// Re-reads the signed-in user (`GET /me`): name, initials, currency,
  /// language and theme may have changed on the web, or the probe at launch
  /// may have failed. Called when the app comes back to the foreground and on
  /// Today's pull-to-refresh. Never throws.
  Future<void> refreshMe() async {
    if (state is! SessionLoggedIn) return;
    await _probeMe(timeout: const Duration(seconds: 10));
  }

  /// Signs in. The token is stored as the server's the request went to;
  /// should the address change before the answer arrives, the token is
  /// dropped and the sign-in fails as if that server could not be reached
  /// — the new one is asked nothing with another server's credential.
  Future<void> login(String email, String password) async {
    final origin = ref.read(serverUrlProvider);
    final dio = ref.read(dioProvider);
    try {
      final res = await dio.post(
        '/session',
        data: {'email': email.trim(), 'password': password},
      );
      if (ref.read(serverUrlProvider) != origin) {
        throw ApiException(ApiErrorKind.network, code: 'server_changed');
      }
      final data = res.data as Map<String, dynamic>;
      await ref
          .read(tokenStoreProvider)
          .write(data['token'] as String, origin: origin);
      final user = User.fromJson(data['user'] as Map<String, dynamic>);
      await _onDrafts((drafts) => drafts.claimFor(DraftStore.ownerOf(user)));
      _epoch++;
      state = SessionLoggedIn(user: user);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Adopts a fresh `/me` payload (e.g. after the language or theme changed)
  /// without disturbing the logged-in state. An answer asked for in an
  /// earlier session ([epoch], from [SessionController.epoch] before the
  /// request left) or about another account is dropped: it is not the
  /// signed-in account's.
  void replaceUser(User user, {int? epoch}) {
    final current = state;
    if (current is! SessionLoggedIn) return;
    if (epoch != null && epoch != _epoch) return;
    if (current.user != null && current.user!.id != user.id) return;
    state = SessionLoggedIn(user: user);
    // The same account under its new e-mail keeps its journal drafts.
    unawaited(_onDrafts((drafts) => drafts.adopt(DraftStore.ownerOf(user))));
  }

  /// Sends [change] — a request that replaces the account's token
  /// (`PATCH /me/password`) — and stores the token it answers with before
  /// anything else can be sent, then adopts the user. Until then a 401 on
  /// another request (one that left with the old token) does not sign the
  /// user out; and a request that left with the old token and is answered
  /// later is not taken for a dead session either (see `buildDio`).
  ///
  /// A 401 on [change] itself means the session was already over: the user
  /// is signed out, as by any other 401 — unless the token it left with has
  /// been replaced meanwhile (a second change sent before the first one
  /// answered), which says nothing about the new one.
  ///
  /// Should the session end or the server change before the answer, its
  /// token is not stored: it belongs to a session that is gone.
  Future<User> replacingToken(
    Future<({String token, User user})> Function() change,
  ) async {
    _tokenSwaps++;
    var dead = false;
    final store = ref.read(tokenStoreProvider);
    final origin = ref.read(serverUrlProvider);
    final epoch = _epoch;
    final sentWith = await store.read();
    try {
      final answer = await change();
      if (epoch != _epoch || ref.read(serverUrlProvider) != origin) {
        throw ApiException(ApiErrorKind.unauthorized, code: 'session_ended');
      }
      await store.write(answer.token, origin: origin);
      replaceUser(answer.user, epoch: epoch);
      return answer.user;
    } on ApiException catch (e) {
      dead = epoch == _epoch &&
          e.kind == ApiErrorKind.unauthorized &&
          await store.read() == sentWith;
      rethrow;
    } finally {
      _tokenSwaps--;
      if (dead) unawaited(forceLogout());
    }
  }

  /// Signs out: [revoke] tells the server (`DELETE /session`) and says
  /// whether it heard; this phone is signed out either way, and everything
  /// about the account is wiped from it. When the server could not be told,
  /// the logged-out state says so ([SessionLoggedOut.revokeFailed]).
  ///
  /// Meanwhile a 401 on another request — the token is being replaced — is
  /// not taken for an expired session.
  Future<void> signOut(Future<bool> Function() revoke) async {
    _tokenSwaps++;
    try {
      var revoked = false;
      try {
        revoked = await revoke();
      } catch (_) {
        // Not revoked; the phone signs out all the same.
      }
      try {
        // A sign-out the user asked for: unsaved journal drafts go too (the
        // sign-out sheet warns about them), unlike a 401 or a server change.
        await _wipeLocal(drafts: true);
      } finally {
        _epoch++;
        state = SessionLoggedOut(revokeFailed: !revoked);
      }
    } finally {
      _tokenSwaps--;
    }
  }

  /// Signs out on this phone only, without telling the server.
  /// Signing out on purpose drops the journal drafts too.
  Future<void> logout() async {
    await _wipeLocal(drafts: true);
    _epoch++;
    state = const SessionLoggedOut();
  }

  /// The session expired (a 401). Unsaved journal drafts stay — the user
  /// signs back in and finds them where they left them — when it is known
  /// whose they are; otherwise the next account to sign in could be
  /// someone else, and they go.
  Future<void> forceLogout() async {
    if (state is SessionLoggedOut || _tokenSwaps > 0) return;
    await _wipeLocal();
    _epoch++;
    state = const SessionLoggedOut(expired: true);
  }

  /// The server address changed: drop the token and every account-scoped value
  /// before anything can be requested from the new host. Journal drafts stay
  /// (the same server is often reached at a second address, over a VPN) when
  /// it is known whose they are, as after a 401.
  Future<void> serverChanged() async {
    await _wipeLocal();
    _epoch++;
    if (state is! SessionLoggedOut) state = const SessionLoggedOut();
  }

  /// Signing out drops everything about the account but keeps the four
  /// device-level settings ([PrefKeys.keptOnSignOut]): which server to talk
  /// to, the language and theme the login screen should still be rendered in,
  /// and reduced motion. Journal drafts go with [drafts] — a sign-out the
  /// user asked for — and whenever nobody is known to have written them.
  Future<void> _wipeLocal({bool drafts = false}) async {
    await ref.read(tokenStoreProvider).clear();
    await _onDrafts((store) async {
      if (drafts) {
        await store.forget();
      } else if (!await store.hasOwner()) {
        await store.clearAll();
      }
    });
    final prefs = ref.read(sharedPrefsProvider);
    final kept = {
      for (final key in PrefKeys.keptOnSignOut)
        if (prefs.getString(key) != null) key: prefs.getString(key)!,
    };
    await prefs.clear();
    await prefs.setBool(PrefKeys.installed, true);
    for (final entry in kept.entries) {
      await prefs.setString(entry.key, entry.value);
    }
  }
}

final sessionProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

final currentUserProvider = Provider<User?>((ref) {
  final session = ref.watch(sessionProvider);
  return session is SessionLoggedIn ? session.user : null;
});
