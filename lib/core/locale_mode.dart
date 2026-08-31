import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../l10n/app_l10n.dart';
import 'session.dart';

/// UI language, resolved in this order:
///
/// 1. an explicit choice made on this device (Profil → Dil),
/// 2. the signed-in user's `locale` on the server,
/// 3. the phone's language when it is one we ship,
/// 4. Turkish.
///
/// Choosing a language writes it to the account as well, so the web app and a
/// reinstall follow along.
class LocaleController extends Notifier<Locale> {
  static const _key = PrefKeys.locale;

  @override
  Locale build() {
    final stored = ref.watch(sharedPrefsProvider).getString(_key);
    if (_supported(stored)) return Locale(stored!);

    final fromAccount = ref.watch(currentUserProvider)?.locale;
    if (_supported(fromAccount)) return Locale(fromAccount!);

    final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    if (_supported(device)) return Locale(device);

    return const Locale('tr');
  }

  /// Returns false when the server rejected or could not be reached — the
  /// language still applies on this device.
  Future<bool> set(Locale locale) async {
    if (!_supported(locale.languageCode)) return true;
    state = locale;
    await ref.read(sharedPrefsProvider).setString(_key, locale.languageCode);
    return _push(locale: locale.languageCode);
  }

  Future<bool> _push({String? locale, String? themePreference}) async {
    if (ref.read(sessionProvider) is! SessionLoggedIn) return true;
    try {
      final user = await ref
          .read(repositoryProvider)
          .updateMe(locale: locale, themePreference: themePreference);
      ref.read(sessionProvider.notifier).replaceUser(user);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _supported(String? code) =>
      code != null && AppL10n.supportedLocales.any((l) => l.languageCode == code);
}

final localeProvider =
    NotifierProvider<LocaleController, Locale>(LocaleController.new);
