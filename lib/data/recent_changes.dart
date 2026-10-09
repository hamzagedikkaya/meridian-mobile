/// Which records this device just changed — the only rows that animate
/// (design-analysis §4.29).
///
/// A refetch, a page, a filter: rows appear, move and vanish without motion.
/// Only a record the user created, edited, restored or removed here, in the
/// last [RecentChanges.ttl], gets `RowEnter`, the `HighlightWash` or a
/// collapsing ghost. Repository writes report them through
/// `DataSync.noteChange`; a delete the server confirmed is noted by
/// `DataSync` itself.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data_scope.dart';

/// What happened to a record.
enum ChangeKind {
  /// Created here: the row grows in and is washed.
  inserted,

  /// Edited here: the row is washed.
  updated,

  /// Brought back ("Geri al"): the row grows back in and is washed.
  restored,

  /// Deleted from a sheet or a menu: the row's ghost collapses.
  removed,
}

/// A record by kind and id.
typedef RecordKey = ({DataScope scope, int id});

final recentChangesProvider =
    NotifierProvider<RecentChanges, Map<RecordKey, RecentChange>>(
      RecentChanges.new,
    );

/// One change and when it was made.
typedef RecentChange = ({ChangeKind kind, DateTime at});

/// The changes of the last [ttl], by record. Entries expire by their time
/// stamp — no timers, so nothing is left pending when the app (or a test)
/// winds down.
final class RecentChanges extends Notifier<Map<RecordKey, RecentChange>> {
  /// How long a change counts as recent: long enough for the row to be
  /// built after the write's refetch lands, short enough that scrolling back
  /// later never replays it.
  static const ttl = Duration(milliseconds: 1500);

  @override
  Map<RecordKey, RecentChange> build() => const {};

  /// Notes that record [id] of [scope] was just [kind] on this device.
  void record(DataScope scope, int id, ChangeKind kind) {
    final now = DateTime.now();
    state = {
      for (final MapEntry(:key, :value) in state.entries)
        if (now.difference(value.at) <= ttl) key: value,
      (scope: scope, id: id): (kind: kind, at: now),
    };
  }

  /// What happened to record [id] of [scope] in the last [ttl], or null.
  ChangeKind? of(DataScope scope, int id) {
    final change = state[(scope: scope, id: id)];
    if (change == null) return null;
    return DateTime.now().difference(change.at) <= ttl ? change.kind : null;
  }
}
