import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/models/user.dart';

import 'fake_api.dart';

/// The token store in memory instead of the platform's secure storage.
class MemoryTokenStore extends TokenStore {
  MemoryTokenStore({this.token = 'old-token', this.origin})
      : super(const FlutterSecureStorage());

  String? token;
  String? origin;

  /// Every token written, in order.
  final written = <String>[];

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token, {required String origin}) async {
    this.token = token;
    this.origin = origin;
    written.add(token);
  }

  @override
  Future<String?> readFor(String origin) async =>
      this.origin != null && this.origin != origin ? null : token;

  @override
  Future<void> clear() async {
    token = null;
    origin = null;
  }
}

/// The journal drafts in memory: the new entry's (`value`, key null) and
/// one per edited entry.
class MemoryDraftStore extends DraftStore {
  MemoryDraftStore([String? value]) : super(const FlutterSecureStorage()) {
    this.value = value;
  }

  final Map<int?, String> drafts = {};
  String? owner;

  /// The new entry's draft.
  String? get value => drafts[null];
  set value(String? value) =>
      value == null ? drafts.remove(null) : drafts[null] = value;

  @override
  Future<String?> read({int? entryId}) async => drafts[entryId];

  @override
  Future<void> write(String value, {int? entryId}) async =>
      drafts[entryId] = value;

  @override
  Future<void> clear({int? entryId}) async => drafts.remove(entryId);

  @override
  Future<List<String>> readAll() async => drafts.values.toList();

  @override
  Future<void> clearAll() async => drafts.clear();

  @override
  Future<void> claimFor(String owner) async {
    if (this.owner == owner) return;
    drafts.clear();
    this.owner = owner;
  }

  @override
  Future<void> adopt(String owner) async {
    final previous = this.owner;
    if (previous == owner) return;
    if (previous != null && previous.split(':').first != owner.split(':').first) {
      drafts.clear();
    }
    this.owner = owner;
  }

  @override
  Future<bool> hasOwner() async => owner != null;

  @override
  Future<void> forget() async {
    drafts.clear();
    owner = null;
  }
}

/// Signed in as the fake API's user (`userJson()`), as after a login.
class SignedInSession extends SessionController {
  @override
  SessionState build() => SessionLoggedIn(user: User.fromJson(userJson()));
}

/// The session's providers with in-memory stores, signed in.
List<Override> signedInOverrides({
  required MemoryTokenStore tokens,
  MemoryDraftStore? drafts,
}) =>
    [
      sessionProvider.overrideWith(SignedInSession.new),
      tokenStoreProvider.overrideWithValue(tokens),
      draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
    ];
