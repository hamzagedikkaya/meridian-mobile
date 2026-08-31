import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import 'session.dart';

/// Theme, resolved like the language: an explicit choice on this device wins,
/// then the account's `theme_preference`, then the app's dark-first default.
/// Choosing one writes it back to the account.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = PrefKeys.themeMode;

  @override
  ThemeMode build() {
    final stored = ref.watch(sharedPrefsProvider).getString(_key);
    if (stored != null) return _parse(stored);

    final fromAccount = ref.watch(currentUserProvider)?.themePreference;
    if (fromAccount != null) return _parse(fromAccount);

    return ThemeMode.dark;
  }

  /// Returns false when the server rejected or could not be reached — the
  /// theme still applies on this device.
  Future<bool> set(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPrefsProvider).setString(_key, mode.name);
    if (ref.read(sessionProvider) is! SessionLoggedIn) return true;
    try {
      final user =
          await ref.read(repositoryProvider).updateMe(themePreference: mode.name);
      ref.read(sessionProvider.notifier).replaceUser(user);
      return true;
    } catch (_) {
      return false;
    }
  }

  static ThemeMode _parse(String value) => switch (value) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
