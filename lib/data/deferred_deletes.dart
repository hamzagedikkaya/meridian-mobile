/// Deletes that wait out their "Geri al" window before they are sent
/// (design-research §4.3).
///
/// A routine delete — a transaction, a budget, a subscription, an empty
/// account or category — takes the record off every list at once and
/// offers "Geri al" for a few seconds. Nothing is sent meanwhile: undo
/// simply shows the record again, so it can never come back wrong (a new
/// id, a linked counter-transaction the delete took with it, a note a
/// re-created row would lose). The delete is sent when the window closes
/// without an undo, when another undoable delete starts (one undo at a
/// time), or when the app is hidden. If the app is killed first, the record
/// survives — the safe way to fail.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import 'data_scope.dart';
import 'providers.dart';

final deferredDeletesProvider =
    NotifierProvider<DeferredDeletes, Set<DeletedRecord>>(DeferredDeletes.new);

/// One delete waiting out its window.
final class _Waiting {
  _Waiting(this.send, this.onFailed);

  final Future<void> Function() send;
  final void Function(Object error)? onFailed;
}

/// The records hidden from every list ([state]): those whose delete waits
/// out its undo window, and those the server has deleted — their lists
/// catch up with the refetch the delete triggers, and since ids are never
/// reused they simply stay hidden.
final class DeferredDeletes extends Notifier<Set<DeletedRecord>> {
  final _waiting = <DeletedRecord, _Waiting>{};

  @override
  Set<DeletedRecord> build() => const {};

  /// Whether the record [id] of [scope] is to be left out of the lists.
  bool hides(DataScope scope, int id) => state.contains((scope: scope, id: id));

  /// Whether [record]'s delete still waits for its window to close.
  bool isWaiting(DeletedRecord record) => _waiting.containsKey(record);

  /// Whether any delete still waits for its window to close.
  bool get hasWaiting => _waiting.isNotEmpty;

  /// Takes [record] off every list now and holds its delete, [send], until
  /// [commit] — or drops it on [undo]. A delete already waiting is sent
  /// first: one undo is offered at a time.
  ///
  /// [onFailed] hears of a delete the server refused once it is sent: the
  /// record is back on the lists by then, and the user has to be told.
  void stage(
    DeletedRecord record, {
    required Future<void> Function() send,
    void Function(Object error)? onFailed,
  }) {
    for (final older in _waiting.keys.toList()) {
      if (older != record) unawaited(commit(older));
    }
    _waiting[record] = _Waiting(send, onFailed);
    state = {...state, record};
  }

  /// Puts [record] back on the lists without sending anything; false when
  /// its delete was already sent.
  bool undo(DeletedRecord record) {
    if (_waiting.remove(record) == null) return false;
    state = {...state}..remove(record);
    return true;
  }

  /// Sends [record]'s delete now; true once the server has deleted it. A
  /// record the server no longer has (a 404: deleted on the web meanwhile)
  /// counts as deleted. On any other failure the record goes back on the
  /// lists and its `onFailed` hears why. Never throws; does nothing for a
  /// record undone or already sent.
  Future<bool> commit(DeletedRecord record) async {
    final waiting = _waiting.remove(record);
    if (waiting == null) return false;
    try {
      await waiting.send();
    } on ApiException catch (e) {
      if (e.kind != ApiErrorKind.notFound) return _failed(record, waiting, e);
    } catch (e) {
      return _failed(record, waiting, e);
    }
    if (ref.mounted) _forget(record);
    return true;
  }

  /// Sends every delete still waiting: the app is going to the background,
  /// and may not come back to send them.
  Future<void> commitAll() async {
    await Future.wait([
      for (final record in _waiting.keys.toList()) commit(record),
    ]);
  }

  bool _failed(DeletedRecord record, _Waiting waiting, Object error) {
    if (ref.mounted) state = {...state}..remove(record);
    waiting.onFailed?.call(error);
    return false;
  }

  /// What the delete leaves behind in cached lists that a refetch would not
  /// clear on its own.
  void _forget(DeletedRecord record) {
    if (record.scope == DataScope.transactions) {
      forgetDeletedTransaction(ref.container, record.id);
    }
  }
}

/// [items] without the ones of [scope] that are deleted or about to be
/// (see [DeferredDeletes]). [hidden] is the provider's state.
List<T> withoutDeleted<T>(
  Iterable<T> items,
  Set<DeletedRecord> hidden,
  DataScope scope,
  int Function(T item) idOf,
) {
  if (hidden.isEmpty) return items.toList();
  return [
    for (final item in items)
      if (!hidden.contains((scope: scope, id: idOf(item)))) item,
  ];
}
