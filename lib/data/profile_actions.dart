/// The account's own settings, its password and signing out — what the
/// Profile screen changes, in one place so every editor sends the same
/// requests and the session follows them.
///
/// The writes go through the repository like any other (it reports what
/// each one changed to `DataSync`); what is the session's — the signed-in
/// user, the token, the local wipe — goes through `SessionController`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../models/user.dart';
import 'deferred_deletes.dart';
import 'providers.dart';

final profileActionsProvider = Provider<ProfileActions>(ProfileActions.new);

final class ProfileActions {
  ProfileActions(this._ref);

  final Ref _ref;

  /// Saves account settings (`PATCH /me`) — pass only what the user
  /// changed — and puts the user the server answers with on every screen:
  /// the header, Today's greeting and avatar, the account's day (its zone's
  /// offset) and every amount's currency. A currency, time zone or language
  /// change also refetches every screen (see `MeridianRepository.updateMe`).
  ///
  /// Throws the server's refusal ([ApiException]) for the editor to show
  /// under its fields; nothing is saved then.
  Future<User> update({
    String? name,
    String? email,
    String? currentPassword,
    String? currency,
    String? timezone,
    int? weeklyReviewDay,
  }) async {
    final epoch = _ref.read(sessionProvider.notifier).epoch;
    final user = await _ref.read(repositoryProvider).updateMe(
          name: name,
          email: email,
          currentPassword: currentPassword,
          currency: currency,
          timezone: timezone,
          weeklyReviewDay: weeklyReviewDay,
        );
    // An answer that lands after a sign-out is not the next account's.
    _ref.read(sessionProvider.notifier).replaceUser(user, epoch: epoch);
    return user;
  }

  /// Changes the password (`PATCH /me/password`). The server replaces the
  /// account's token, which signs out every other device; the new one is
  /// stored before anything else is sent, so this phone stays signed in.
  Future<User> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) {
    final repo = _ref.read(repositoryProvider);
    return _ref.read(sessionProvider.notifier).replacingToken(
          () => repo.changePassword(
            currentPassword: currentPassword,
            password: password,
            passwordConfirmation: passwordConfirmation,
          ),
        );
  }

  /// Whether signing out would throw away unsaved journal writing: any draft
  /// the editor keeps on this phone — the new entry's or an edit's — has
  /// something in it. Signing out deletes them all.
  Future<bool> hasUnsavedDraft() async {
    try {
      final drafts = await _ref.read(draftStoreProvider).readAll();
      return drafts.any(_draftHasContent);
    } catch (_) {
      // Unreadable: say nothing rather than warn about nothing.
      return false;
    }
  }

  /// The journal editor keeps a draft as `{fields, base, updated_at}`: what
  /// is typed, and what the editor opened with. It is unsaved writing when
  /// the two differ (a new date, mood or energy counts as much as text). A
  /// flat draft (an older build's) has something in it when any of its
  /// fields is filled.
  static bool _draftHasContent(String raw) {
    if (raw.trim().isEmpty) return false;
    final Object? draft;
    try {
      draft = jsonDecode(raw);
    } catch (_) {
      return true;
    }
    if (draft is! Map) return true;
    final fields = draft['fields'];
    if (fields is Map) {
      final base = draft['base'];
      if (base is Map) {
        return fields.keys.toSet().union(base.keys.toSet()).any(
          (key) => '${fields[key] ?? ''}' != '${base[key] ?? ''}',
        );
      }
      return _filled(fields);
    }
    return _filled(draft);
  }

  static bool _filled(Map draft) {
    bool filled(Object? value) => value is String && value.trim().isNotEmpty;
    return filled(draft['title']) ||
        filled(draft['body']) ||
        filled(draft['gratitude']) ||
        filled(draft['tags']) ||
        draft['mood'] != null;
  }

  /// Signs out everywhere: deletes still waiting out their undo are sent
  /// first (the token still works), then the server replaces the account's
  /// token (`DELETE /session`) — every device using it is signed out — and
  /// this phone forgets the account. When the server cannot be reached the
  /// phone signs out all the same, and the login screen says the session
  /// could not be ended on the server.
  Future<void> signOut() async {
    try {
      await _ref.read(deferredDeletesProvider.notifier).commitAll();
    } catch (_) {
      // Each failure is reported by its own snackbar.
    }
    final repo = _ref.read(repositoryProvider);
    await _ref.read(sessionProvider.notifier).signOut(() async {
      try {
        await repo.revokeSession();
        return true;
      } on ApiException catch (e) {
        // 401: the token was already replaced — by another device's
        // sign-out or a password change. Nothing is left to revoke.
        return e.kind == ApiErrorKind.unauthorized;
      }
    });
  }
}
