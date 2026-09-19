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

  /// Device-level settings that survive a sign-out.
  static const keptOnSignOut = [serverUrl, locale, themeMode];
}

/// Overridden with the real instance in main().
final sharedPrefsProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

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
class DraftStore {
  DraftStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'journal_draft';

  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  Future<void> clear() => _storage.delete(key: _key);
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
  const SessionLoggedOut({this.expired = false});
}

class SessionLoggedIn extends SessionState {
  final User? user;
  const SessionLoggedIn({this.user});
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionUnknown();

  /// Splash gate: token check ≤50ms, optimistic route, /me probe in background.
  Future<void> restore() async {
    final prefs = ref.read(sharedPrefsProvider);
    final store = ref.read(tokenStoreProvider);

    if (!kIsWeb && !(prefs.getBool(PrefKeys.installed) ?? false)) {
      await store.clear();
      await prefs.setBool(PrefKeys.installed, true);
      state = const SessionLoggedOut();
      return;
    }

    final token = await store.read();
    if (token == null || token.isEmpty) {
      state = const SessionLoggedOut();
      return;
    }
    state = const SessionLoggedIn();
    _probeMe();
  }

  Future<void> _probeMe() async {
    try {
      final res = await ref.read(dioProvider).get(
            '/me',
            options: Options(receiveTimeout: const Duration(milliseconds: 2500)),
          );
      final user =
          User.fromJson((res.data as Map)['user'] as Map<String, dynamic>);
      if (state is SessionLoggedIn) state = SessionLoggedIn(user: user);
    } on DioException {
      // Offline keeps the optimistic session; a 401 is ejected by the interceptor.
    }
  }

  Future<void> login(String email, String password) async {
    try {
      final res = await ref.read(dioProvider).post(
        '/session',
        data: {'email': email.trim(), 'password': password},
      );
      final data = res.data as Map<String, dynamic>;
      await ref.read(tokenStoreProvider).write(
            data['token'] as String,
            origin: ref.read(serverUrlProvider),
          );
      state = SessionLoggedIn(
        user: User.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Adopts a fresh `/me` payload (e.g. after the language or theme changed)
  /// without disturbing the logged-in state.
  void replaceUser(User user) {
    if (state is SessionLoggedIn) state = SessionLoggedIn(user: user);
  }

  Future<void> logout() async {
    await _wipeLocal();
    state = const SessionLoggedOut();
  }

  Future<void> forceLogout() async {
    if (state is SessionLoggedOut) return;
    await _wipeLocal();
    state = const SessionLoggedOut(expired: true);
  }

  /// The server address changed: drop the token and every account-scoped value
  /// before anything can be requested from the new host.
  Future<void> serverChanged() async {
    await _wipeLocal();
    if (state is! SessionLoggedOut) state = const SessionLoggedOut();
  }

  /// Signing out drops everything about the account but keeps the three
  /// device-level settings: which server to talk to, and the language and theme
  /// the login screen should still be rendered in.
  Future<void> _wipeLocal() async {
    await ref.read(tokenStoreProvider).clear();
    await ref.read(draftStoreProvider).clear();
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
