import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/models/quick_capture.dart';

import '../support/fake_api.dart';

void main() {
  test('a saved todo: the record parses as a todo', () {
    final r = QuickCaptureResult.fromJson(captureTodoJson());
    expect(r.saved, isTrue);
    expect(r.capturedType, 'todo');
    expect(r.recordId, 40);
    expect(r.todo!.title, 'süt al');
    expect(r.transaction, isNull);
    expect(r.habitLog, isNull);
    expect(r.suggestion, isNull);
  });

  test('a saved transaction: amount, account and description', () {
    final r = QuickCaptureResult.fromJson({
      'saved': true,
      'captured_type': 'transaction',
      'record_id': 1237,
      'summary': 'market',
      'message': 'İşlem olarak yakalandı.',
      'record': {
        ...transactionJson(id: 1237),
        'amount_cents': 125050,
        'description': 'market',
      },
    });
    final tx = r.transaction!;
    expect(tx.amountCents, 125050);
    expect(tx.kind, 'expense');
    expect(tx.account.currency, 'TRY');
  });

  test('a saved habit log: the day, the count and whether it is done', () {
    final r = QuickCaptureResult.fromJson({
      'saved': true,
      'captured_type': 'habit_log',
      'record_id': 1151,
      'summary': 'Su',
      'record': {
        'id': 1151,
        'habit_id': 1065,
        'date': '2026-10-04',
        'count': 3,
        'completed': true,
      },
    });
    expect(r.habitLog!.date, DateTime(2026, 10, 4));
    expect(r.habitLog!.count, 3);
    expect(r.habitLog!.completed, isTrue);
  });

  test('an event suggestion saved nothing and says what it read', () {
    final r = QuickCaptureResult.fromJson({
      'saved': false,
      'captured_type': 'event_suggestion',
      'record_id': null,
      'summary': 'yarın 15:00 dişçi',
      'suggestion': {
        'title': 'dişçi',
        'date': '2026-10-05',
        'time': '15:00',
        'start_at': '2026-10-05T15:00:00.000+03:00',
        'all_day': false,
        'keyword': 'yarın',
      },
    });
    expect(r.saved, isFalse);
    expect(r.isEventSuggestion, isTrue);
    final s = r.suggestion!;
    expect(s.title, 'dişçi');
    expect(s.date, DateTime(2026, 10, 5));
    expect(s.time, '15:00');
    expect(
      s.startAt,
      DateTime(2026, 10, 5, 15),
      reason: 'the account\'s clock',
    );
    expect(s.allDay, isFalse);
    expect(s.keyword, 'yarın');
  });

  test('an all-day suggestion has no time', () {
    final s = EventSuggestion.fromJson({
      'title': 'cuma toplantı',
      'date': '2026-10-09',
      'time': null,
      'start_at': null,
      'all_day': true,
      'keyword': 'cuma',
    })!;
    expect(s.time, isNull);
    expect(s.startAt, isNull);
    expect(s.allDay, isTrue);
  });

  test('a server from before G1 sends no "saved": all but an event '
      'suggestion was saved', () {
    expect(
      QuickCaptureResult.fromJson({
        'captured_type': 'todo',
        'record_id': 1,
        'summary': 'x',
      }).saved,
      isTrue,
    );
    expect(
      QuickCaptureResult.fromJson({
        'captured_type': 'event_suggestion',
        'record_id': null,
        'summary': 'yarın dişçi',
      }).saved,
      isFalse,
    );
    // No type at all: assumed saved, so everything it may have touched is
    // refreshed (see the repository).
    expect(QuickCaptureResult.fromJson({'summary': 'x'}).saved, isTrue);
  });

  test('a record that does not parse does not fail the capture', () {
    final r = QuickCaptureResult.fromJson({
      'saved': true,
      'captured_type': 'transaction',
      'record_id': 5,
      'summary': 'x',
      'record': {'id': 'not-an-id'},
    });
    expect(r.saved, isTrue);
    expect(r.transaction, isNull);
  });
}
