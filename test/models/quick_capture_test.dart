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

  group('guessQuickAddKind mirrors the server\'s rules (contract §11)', () {
    void expectGuess(String line, QuickAddKind? kind) =>
        expect(guessQuickAddKind(line), kind, reason: line);

    test('blank: no guess', () {
      expectGuess('', null);
      expectGuess('   ', null);
    });

    test('a sign then a number is money', () {
      expectGuess('-250 kahve', QuickAddKind.expense);
      expectGuess('−85 kahve', QuickAddKind.expense);
      expectGuess('– 12,50 simit', QuickAddKind.expense);
      expectGuess('+1.500 maaş', QuickAddKind.income);
      expectGuess('+ 1500', QuickAddKind.income);
      // A number without a sign is not money.
      expectGuess('3 yumurta al', QuickAddKind.task);
      // Money wins over a day word.
      expectGuess('-250 yarın market', QuickAddKind.expense);
    });

    test('habit: and alışkanlık:, any case, with or without Turkish '
        'letters', () {
      expectGuess('habit: run', QuickAddKind.habit);
      expectGuess('alışkanlık: su', QuickAddKind.habit);
      expectGuess('ALIŞKANLIK: su', QuickAddKind.habit);
      expectGuess('aliskanlik:koşu', QuickAddKind.habit);
      expectGuess('Habit : yoga', QuickAddKind.habit);
      expectGuess('my habit: yoga', QuickAddKind.task);
    });

    test('a whole day word is an event', () {
      expectGuess('yarın 15:00 dişçi', QuickAddKind.event);
      expectGuess('Yarin dişçi', QuickAddKind.event);
      expectGuess('cuma toplantı', QuickAddKind.event);
      expectGuess('meeting on Monday.', QuickAddKind.event);
      expectGuess('bu pazar piknik', QuickAddKind.event);
      expectGuess('pazar günü piknik', QuickAddKind.event);
      // A bare "pazar" is Sunday with a time.
      expectGuess('pazar 10:00 kahvaltı', QuickAddKind.event);
      expectGuess('pazar saat 9 koşu', QuickAddKind.event);
      expectGuess("pazar 9'da kahvaltı", QuickAddKind.event);
      expectGuess('pazar 3pm brunch', QuickAddKind.event);
      // Another day word wins over a bare "pazar".
      expectGuess('pazar alışverişi yarın', QuickAddKind.event);
    });

    test('a time without a day word is a task, as the server saves it', () {
      expectGuess('dişçi 15:00', QuickAddKind.task);
      expectGuess('dişçi 15.30', QuickAddKind.task);
      expectGuess('saat 9 koşu', QuickAddKind.task);
      expectGuess("9'da kahvaltı", QuickAddKind.task);
      expectGuess('call mom 3pm', QuickAddKind.task);
      expectGuess('ekmek 12.50', QuickAddKind.task);
    });

    test('not an event: suffixed day words, pazar alone, words containing a '
        'day, prices', () {
      expectGuess('yarınki toplantı notları', QuickAddKind.task);
      expectGuess("Cuma'ya kadar rapor", QuickAddKind.task);
      expectGuess('pazar alışverişi', QuickAddKind.task);
      expectGuess('pazar 12.50 TL', QuickAddKind.task);
      expectGuess('masalı oku', QuickAddKind.task);
      expectGuess('süt al 15.30 TL', QuickAddKind.task);
      expectGuess('süt al', QuickAddKind.task);
    });
  });

  group('splitQuickAmount reads the number as the server does', () {
    void expectSplit(
      String line,
      int? minor,
      String description, {
      int subunit = 100,
    }) => expect(splitQuickAmount(line, subunitToUnit: subunit), (
      minorUnits: minor,
      description: description,
    ), reason: line);

    test('the amount and the rest', () {
      expectSplit('−85 kahve', 8500, 'kahve');
      expectSplit('-1.250,50 market', 125050, 'market');
      expectSplit('+1.500 maaş', 150000, 'maaş');
      expectSplit('+1,500 salary', 150000, 'salary');
      expectSplit('kahve 12,5', 1250, 'kahve');
      expectSplit('kahve 12.50 TL', 1250, 'kahve');
      expectSplit('250₺ kira', 25000, 'kira');
      expectSplit('0,250 çay', 25, 'çay');
      expectSplit('1,250.50 rent', 125050, 'rent');
    });

    test('no number, or one that cannot be read', () {
      expectSplit('kahve', null, 'kahve');
      expectSplit('-1.25.0 x', null, 'x');
      expectSplit('-0 x', null, 'x');
    });

    test('in the account currency\'s minor units', () {
      expectSplit('-2 altın', 2, 'altın', subunit: 1);
      expectSplit('-1,5 x', 1500, 'x', subunit: 1000);
      expectSplit('-1,234 x', 1234000, 'x', subunit: 1000);
    });
  });
}
