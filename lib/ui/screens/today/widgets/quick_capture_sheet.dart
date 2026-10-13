import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api.dart';
import '../../../../core/formats.dart';
import '../../../../core/haptics.dart';
import '../../../../core/turkish_case.dart';
import '../../../../data/actions.dart';
import '../../../../data/current_day.dart';
import '../../../../data/data_scope.dart';
import '../../../../data/deferred_deletes.dart';
import '../../../../data/providers.dart';
import '../../../../data/recent_changes.dart';
import '../../../../data/repository.dart';
import '../../../../data/sync.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/account.dart';
import '../../../../models/home.dart';
import '../../../../models/json_read.dart';
import '../../../../models/quick_capture.dart';
import '../../../../models/todo.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/entity_color.dart';
import '../../../flows/create_flows.dart';
import '../../../flows/flows.dart' as flows;
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/choice_wrap.dart';
import '../../../widgets/nok_chip.dart';
import '../../../widgets/nok_sheet.dart';
import '../../../widgets/primary_button.dart';
import '../../finance/finance_utils.dart' show preferredAccountIds;
import '../../finance/transaction_form_screen.dart' as tx_form;

/// Quick add (design-analysis §7.3): one line that becomes a task, an
/// expense or an income, an event or a habit check-in.
///
/// * **Type chips.** "Otomatik" (the default) shows the app's guess
///   ("Otomatik · Harcama", [guessQuickAddKind]) and the add button says
///   what will happen. A line that looks like a task is added as "Görev"
///   adds one, on the day quick add was opened for; any other line goes to
///   `POST /quick_captures`, which decides what it is. Picking a type
///   routes the line itself: a task is `POST /todos`, due on the day quick
///   add was opened for ([ctx], [day]: today on Today, none from Agenda's
///   upcoming list, the day of a held day heading); an expense or an
///   income opens the transaction form with the amount and the
///   description read from the line, on the account the form starts on;
///   an event opens the event form, with the day and time the server reads
///   from a line that names a day; a habit turns the sheet to today's
///   habits, where a tap logs one.
/// * **Examples** under an empty field teach the syntax; a tap writes one in.
/// * **The result.** The sheet closes as soon as something is saved, and
///   the snackbar names it — the account a money line went to included,
///   since the server picks it — with "Düzenle" and "Geri al".
/// * **What did not save** stays in the sheet, under the line, with the
///   text kept and the next step where there is one: a line that names a
///   day offers the event form (opened at once when the button said so)
///   or "save as a task"; `no_account` opens a cash account, then sends the
///   line again; `unknown_habit` creates the habit, then logs it.
///
/// [context] is the screen's: the snackbar floats above its capture bar or
/// FAB, and "Düzenle" opens from it once the sheet is gone.
Future<void> showQuickCaptureSheet(
  BuildContext context, {
  flows.QuickAddContext ctx = flows.QuickAddContext.today,
  DateTime? day,
}) => showNokSheet<void>(
  context,
  title: context.l10n.quickAddTitle,
  showClose: true,
  builder: (_) => _QuickCaptureSheet(opener: context, ctx: ctx, day: day),
);

/// What the sheet shows under the line after an answer that saved nothing.
sealed class _Inline {
  const _Inline();
}

/// A refusal, worded by its code, and the next step when there is one.
final class _Problem extends _Inline {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Problem(this.message, {this.actionLabel, this.onAction});
}

/// The line names a day: nothing was saved.
final class _Suggestion extends _Inline {
  final EventSuggestion suggestion;

  const _Suggestion(this.suggestion);
}

/// What was saved, for the result snackbar: its [message], and what
/// "Geri al" and "Düzenle" do (null: not offered).
typedef _Saved = ({String message, VoidCallback? undo, VoidCallback? edit});

class _QuickCaptureSheet extends ConsumerStatefulWidget {
  const _QuickCaptureSheet({
    required this.opener,
    required this.ctx,
    required this.day,
  });

  final BuildContext opener;
  final flows.QuickAddContext ctx;
  final DateTime? day;

  @override
  ConsumerState<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends ConsumerState<_QuickCaptureSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  _Inline? _inline;

  /// The type picked; null is "Otomatik".
  QuickAddKind? _kind;

  /// Whether the sheet shows today's habits instead of the line.
  bool _pickingHabit = false;

  /// The server's reading of the line as it is now — kept when the type
  /// changes, so "Etkinlik" opens the form with its day and time.
  ({String text, EventSuggestion suggestion})? _suggested;

  /// The answer under the line, to scroll it into view. A new one each
  /// time the line comes back from the habit step: the outgoing line stays
  /// in the tree for the step's transition.
  var _inlineKey = GlobalKey();

  String get _text => _controller.text.trim();

  /// What the line will become: the type picked, else the guess.
  QuickAddKind? get _resolved => _kind ?? guessQuickAddKind(_controller.text);

  /// What a save's confirmation needs, kept current while the sheet is
  /// up: the sheet can be closed while a request is on its way (its close
  /// button, back, a drag), and an answer that lands after that is still
  /// named — with "Geri al" — on the screen it was opened from, when the
  /// sheet's own context and ref are gone.
  late AppL10n _l;
  late DeferredDeletes _deletes;
  late MeridianRepository _repo;
  late HabitActions _habitActions;
  late DataSync _sync;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l = context.l10n;
    _deletes = ref.read(deferredDeletesProvider.notifier);
    _repo = ref.read(repositoryProvider);
    _habitActions = ref.read(habitActionsProvider);
    _sync = ref.read(dataSyncProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // --- Answers -----------------------------------------------------------------

  /// Shows [inline] under the line, with the sheet ready for the next step,
  /// and scrolls it into view: on a small phone with the keyboard up, the
  /// answer — and the action it offers — can fall below what the sheet has
  /// room for.
  void _answer(_Inline inline) {
    setState(() {
      _busy = false;
      if (_pickingHabit) _inlineKey = GlobalKey();
      _pickingHabit = false;
      _inline = inline;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealAnswer());
  }

  void _revealAnswer() {
    final shown = _inlineKey.currentContext;
    if (!mounted || _inline == null || shown == null || !shown.mounted) return;
    Scrollable.ensureVisible(
      shown,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      duration: Motion.orInstant(context, Motion.collapse),
      curve: Motion.enter,
    );
  }

  /// Closes the sheet and names what was saved, with "Geri al" and
  /// "Düzenle" when there are ones — on the screen's messenger, above its
  /// capture bar.
  ///
  /// The sheet already closed (an answer that came after it was), the
  /// screen still says what was saved.
  void _done(_Saved saved) {
    final l = _l;
    final opener = widget.opener;
    final undo = saved.undo;
    final edit = saved.edit;
    if (!mounted && !opener.mounted) return;
    showAppSnack(
      opener.mounted ? opener : context,
      saved.message,
      tone: SnackTone.success,
      actionLabel: undo != null
          ? l.actionUndo
          : edit != null
          ? l.actionEdit
          : null,
      onAction: undo ?? edit,
      secondaryLabel: undo != null && edit != null ? l.actionEdit : null,
      onSecondary: undo != null ? edit : null,
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// Rows the line created grow in and are washed where they land (§5.4),
  /// as from any other add.
  void _noteCreated(DataScope scope, int id) =>
      _sync.noteChange(scope, id, ChangeKind.inserted);

  // --- Sending -------------------------------------------------------------------

  /// The add button: by the type picked. For "Otomatik", a line that looks
  /// like a task is added as one — on the day quick add was opened for, as
  /// the button ("Görev ekle") says; the server would file it under no day
  /// — and any other line goes to the server, which reads it.
  Future<void> _submit() async {
    if (_busy) return;
    switch (_kind) {
      case null:
        if (guessQuickAddKind(_controller.text) == QuickAddKind.task) {
          await _addTask();
        } else {
          await _capture();
        }
      case QuickAddKind.task:
        await _addTask();
      case QuickAddKind.expense:
        await _openMoneyForm(income: false);
      case QuickAddKind.income:
        await _openMoneyForm(income: true);
      case QuickAddKind.event:
        await _openEvent();
      case QuickAddKind.habit:
        _showHabits();
    }
  }

  /// "Otomatik": sends the line (`POST /quick_captures`); [asTodo] saves it
  /// as it is, as a task.
  Future<void> _capture({bool asTodo = false}) async {
    final l = context.l10n;
    final text = _text;
    if (_busy) return;
    if (text.isEmpty) {
      Haptics.reject();
      _answer(_Problem(l.errCaptureEmpty));
      return;
    }
    // The button said "Etkinlik olarak aç": a suggestion opens the form.
    final saidEvent = !asTodo && guessQuickAddKind(text) == QuickAddKind.event;
    // Today's counts before the line, for a habit check-in's undo.
    final counts = {
      for (final h in _homeShown()?.todayHabits ?? const <HomeHabit>[])
        h.id: h.todayCount,
    };
    setState(() => _busy = true);
    try {
      final result = await _repo.quickCapture(text, asTodo: asTodo);
      if (result.saved) {
        switch (result.capturedType) {
          case 'todo' when result.todo != null:
            _noteCreated(DataScope.todos, result.todo!.id);
          case 'transaction' when result.transaction != null:
            _noteCreated(DataScope.transactions, result.transaction!.id);
        }
      }
      if (!mounted) {
        // Closed while it was on its way: what was saved is still said.
        if (result.saved) _done(_savedCapture(_l, result, counts));
        return;
      }
      if (!result.saved) {
        Haptics.tick();
        final suggestion = result.suggestion;
        if (suggestion == null) {
          _answer(_Problem(l.captureNotSaved));
          return;
        }
        _suggested = (text: text, suggestion: suggestion);
        _answer(_Suggestion(suggestion));
        final open = ref.read(createFlowsProvider).event;
        if (saidEvent && open != null) await _addAsEvent(open, suggestion);
        return;
      }
      Haptics.confirm();
      _done(_savedCapture(l, result, counts));
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      _answer(_problemFor(e, retry: () => _capture(asTodo: asTodo)));
    }
  }

  /// "Görev": `POST /todos`, due on the day quick add was opened for.
  Future<void> _addTask() async {
    final l = context.l10n;
    final text = _text;
    if (text.isEmpty) {
      Haptics.reject();
      _answer(_Problem(l.errCaptureEmpty));
      return;
    }
    setState(() => _busy = true);
    try {
      final todo = await _repo.createTodo(
        TodoInput(title: text, dueDate: _taskDay()),
      );
      _noteCreated(DataScope.todos, todo.id);
      if (mounted) Haptics.confirm();
      // Closed while it was on its way, it is still said on the screen.
      _done(_savedTodo(_l, todo));
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      _answer(_problemFor(e, retry: _addTask));
    }
  }

  /// "Harcama" / "Gelir": the sheet closes and the transaction form opens
  /// with the line's first number as the amount and the rest as the
  /// description — saved, and confirmed, there.
  ///
  /// The amount is in the minor units of the account the form starts on
  /// (gram gold has none), so that account is looked up first and handed
  /// to the form. Should the accounts not load, the amount is left out
  /// rather than read in the wrong currency.
  Future<void> _openMoneyForm({required bool income}) async {
    final text = _controller.text;
    setState(() {
      _busy = true;
      _inline = null;
    });
    final start = await _formAccount();
    if (!mounted) return;
    final line = splitQuickAmount(
      text,
      // With no account to start on, the form reads the amount as typed
      // until one is picked.
      subunitToUnit: start.account?.subunitToUnit ?? 100,
    );
    final opener = widget.opener;
    Navigator.of(context).pop();
    if (!opener.mounted) return;
    flows.openTransactionForm(
      opener,
      initialKind: income ? 'income' : 'expense',
      initialAmountCents: start.known ? line.minorUnits : null,
      initialDescription: line.description.isEmpty ? null : line.description,
      accountId: start.account?.id,
    );
  }

  /// The account the transaction form starts on, as it picks one: the
  /// last one a transaction was saved on while it is still active, else
  /// the only active one, else none ([known] true). [known] is false when
  /// the accounts could not be loaded.
  Future<({bool known, Account? account})> _formAccount() async {
    // Kept alive while it loads: nothing else may be listening.
    final sub = ref.listenManual(accountsProvider.future, (_, _) {});
    try {
      final all = (await sub.read()).data;
      if (!mounted) return (known: false, account: null);
      final offered = withoutDeleted(
        all.where((a) => !a.archived),
        ref.read(deferredDeletesProvider),
        DataScope.accounts,
        (a) => a.id,
      );
      // The user's default, else the last account used: the first of
      // them still offered.
      for (final id in preferredAccountIds(ref)) {
        for (final a in offered) {
          if (a.id == id) return (known: true, account: a);
        }
      }
      return (
        known: true,
        account: offered.length == 1 ? offered.single : null,
      );
    } catch (_) {
      return (known: false, account: null);
    } finally {
      sub.close();
    }
  }

  /// "Etkinlik": the event form, with the server's reading of the line when
  /// there is one (its day and time), else titled with the line on the day
  /// quick add was opened for. A line that names a day is read by the
  /// server first — `POST /quick_captures` saves nothing for one, and
  /// answers with its day, time and title. Once it is saved the sheet
  /// closes too.
  Future<void> _openEvent() async {
    final open = ref.read(createFlowsProvider).event;
    if (open == null) return;
    final suggested = _suggested;
    if (suggested != null && suggested.text == _text) {
      await _addAsEvent(open, suggested.suggestion);
      return;
    }
    if (guessQuickAddKind(_text) == QuickAddKind.event) {
      await _capture();
      return;
    }
    await _addAsEvent(
      open,
      EventSuggestion(title: _text, date: _eventDay(), allDay: false),
    );
  }

  /// Event suggestion: hand it to the event form; once saved, done.
  ///
  /// The form is opened from the screen quick add was opened on: its
  /// "eklendi" is said there, above the capture bar — the sheet's own
  /// context sees no bar (`snackMarginFor`), and is gone by then.
  Future<void> _addAsEvent(
    Future<bool> Function(BuildContext, EventSuggestion) open,
    EventSuggestion suggestion,
  ) async {
    final opener = widget.opener;
    final saved = await open(opener.mounted ? opener : context, suggestion);
    if (saved && mounted) Navigator.of(context).pop();
  }

  // --- Days ----------------------------------------------------------------------

  /// The server's today: `/home`'s when Today has it, else the account's.
  DateTime _today() => _homeShown()?.today ?? ref.read(currentDayProvider);

  /// A task's due day: today on Today, the held day heading's, or none
  /// from Agenda's upcoming list (it lands in the inbox).
  DateTime? _taskDay() => switch (widget.ctx) {
    flows.QuickAddContext.today => widget.day ?? _today(),
    flows.QuickAddContext.agenda => widget.day,
  };

  DateTime _eventDay() => widget.day ?? _today();

  HomeSummary? _homeShown() =>
      ref.exists(homeProvider) ? ref.read(homeProvider).value?.data : null;

  // --- Habits ----------------------------------------------------------------------

  void _showHabits() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _pickingHabit = true;
      _inline = null;
    });
  }

  void _backToLine() => setState(() {
    _pickingHabit = false;
    _inlineKey = GlobalKey();
  });

  /// The line without its `habit:` / `alışkanlık:` lead-in: the name to
  /// look for, or to give a new habit.
  String _habitName() {
    final text = _text;
    final colon = text.indexOf(':');
    if (colon < 0) return text;
    final lead = trFold(text.substring(0, colon).trim());
    const leads = {'habit', 'alişkanlik', 'aliskanlik'};
    return leads.contains(lead) ? text.substring(colon + 1).trim() : text;
  }

  /// One step on [habit] today — a daily one counts up by one, toward its
  /// target; a weekly or monthly one is done for the day — shown on every
  /// screen at once ([HabitActions.setToday]); the sheet closes at once.
  void _logHabit(HomeHabit habit, DateTime? day) {
    final l = context.l10n;
    final actions = ref.read(habitActionsProvider);
    final daily = actions.isDaily(habit.id) ?? true;
    final target = math.max(1, habit.targetCount);
    final count = daily ? math.min(habit.todayCount + 1, target) : target;
    final opener = widget.opener;
    final request = actions.setToday(habit.id, count, day: day);
    Haptics.check();
    _done((
      message: l.captureSavedHabit(
        habit.name,
        completed: habit.logFor(count, daily: daily).completed,
      ),
      undo: _undoHabit(habit.id, habit.todayCount, day),
      edit: _editHabit(habit.id, day),
    ));
    request.then(
      (_) {},
      onError: (Object e) {
        if (!opener.mounted) return;
        showAppSnack(
          opener,
          failureMessage(e, l, fallback: l.todayHabitUpdateFailed),
          isError: true,
        );
      },
    );
  }

  // --- What was saved ----------------------------------------------------------------

  _Saved _savedCapture(
    AppL10n l,
    QuickCaptureResult result,
    Map<int, int> countsBefore,
  ) {
    switch (result.capturedType) {
      case 'transaction':
        final tx = result.transaction;
        if (tx == null) break;
        final income = tx.kind == 'income';
        final amount = formatMoney(
          tx.amountCents,
          tx.account.currency,
          tx.account.subunitToUnit,
          sign: income ? MoneySign.always : MoneySign.negative,
          // "−₺85", as typed; the cents only when there are some.
          decimals: MoneyDecimals.auto,
        );
        final opener = widget.opener;
        return (
          message: income
              ? l.captureSavedIncome(amount, tx.account.name)
              : l.captureSavedExpense(amount, tx.account.name),
          undo: _undoDelete(l, (scope: DataScope.transactions, id: tx.id)),
          edit: () {
            if (opener.mounted) {
              tx_form.openTransactionForm(opener, existing: tx);
            }
          },
        );
      case 'habit_log':
        final log = result.habitLog;
        final habitId = readIntOrNull(result.record?['habit_id']);
        final before = habitId == null ? null : countsBefore[habitId];
        return (
          message: l.captureSavedHabit(
            result.summary,
            completed: log?.completed ?? false,
          ),
          undo: before == null || log == null
              ? null
              : _undoHabit(habitId!, before, log.date),
          edit: habitId == null ? null : _editHabit(habitId, log?.date),
        );
      case 'todo':
        final todo = result.todo;
        if (todo == null) return _plain(l.captureSavedTodo(result.summary));
        return _savedTodo(l, todo);
    }
    return _plain(l.captureSaved(result.summary));
  }

  static _Saved _plain(String message) =>
      (message: message, undo: null, edit: null);

  _Saved _savedTodo(AppL10n l, Todo todo) {
    final opener = widget.opener;
    return (
      message: l.captureSavedTodo(todo.title),
      undo: _undoDelete(l, (scope: DataScope.todos, id: todo.id)),
      edit: () {
        if (opener.mounted) flows.openTodoSheet(opener, existing: todo);
      },
    );
  }

  /// "Geri al" on a record the line created: it leaves every list at once
  /// and its delete is sent now. Should the server refuse, it comes back and
  /// the snackbar says so. Silent, like every undo.
  ///
  /// What it needs is read now: the sheet is gone by the time it runs.
  VoidCallback _undoDelete(AppL10n l, DeletedRecord record) {
    final deletes = _deletes;
    final repo = _repo;
    final opener = widget.opener;
    final deleteIt = record.scope == DataScope.todos
        ? () => repo.deleteTodo(record.id)
        : () => repo.deleteTransaction(record.id);
    return () {
      deletes.stage(
        record,
        send: deleteIt,
        onFailed: (_) {
          if (opener.mounted) {
            showAppSnack(opener, l.quickAddUndoFailed, isError: true);
          }
        },
      );
      deletes.commit(record);
    };
  }

  /// "Geri al" on a habit check-in: the day's count goes back to [before]
  /// (`PUT /habits/:id/logs/:date`), on every screen at once.
  VoidCallback _undoHabit(int habitId, int before, DateTime? day) {
    final l = _l;
    final actions = _habitActions;
    final opener = widget.opener;
    return () {
      actions.setToday(habitId, before, day: day).catchError((Object _) {
        if (opener.mounted) {
          showAppSnack(opener, l.quickAddUndoFailed, isError: true);
        }
        return false;
      });
    };
  }

  /// "Düzenle" on a habit check-in: that day's log.
  VoidCallback _editHabit(int habitId, DateTime? day) {
    final opener = widget.opener;
    return () {
      if (opener.mounted) {
        flows.openHabitLog(opener, habitId: habitId, date: day);
      }
    };
  }

  // --- Refusals ------------------------------------------------------------------

  /// What a failure says, and the next step: [retry] sends the line again
  /// the same way when nothing reached the server.
  _Problem _problemFor(Object error, {required VoidCallback retry}) {
    final l = context.l10n;
    if (error is! ApiException) return _Problem(l.quickAddFailed);
    if (error.isNetwork) {
      // The line went out, but no answer came back in time: the server may
      // have saved it — the refetch that follows then shows it behind the
      // sheet. A capture is not safe to repeat (each one creates a record),
      // so there is no retry here; the line stays, to send again once
      // checked.
      if (error.mayHaveArrived) return _Problem(l.captureMaybeSaved);
      // It never reached the server: sending it again is safe.
      return _Problem(
        l.errNoConnection,
        actionLabel: l.actionRetry,
        onAction: retry,
      );
    }
    final createFlows = ref.read(createFlowsProvider);
    switch (error.code) {
      case 'no_account':
        final account = createFlows.account;
        return _Problem(
          error.localized(l),
          actionLabel: account == null ? null : l.captureCreateAccount,
          onAction: account == null ? null : () => _createAccount(account),
        );
      case 'unknown_habit':
        final name = error.name ?? '';
        return _Problem(
          error.localized(l),
          actionLabel: l.captureCreateHabit(name),
          onAction: () => _createHabit(name),
        );
      case 'validation_failed':
        // A todo title over 200 characters is the one field a line can get
        // wrong.
        return _Problem(error.fieldMessage(l, 'title') ?? error.localized(l));
    }
    return _Problem(failureMessage(error, l, fallback: l.quickAddFailed));
  }

  /// `no_account`: open the new-account form (a cash account, ready), then
  /// send the line again — the money now has an account to go to.
  Future<void> _createAccount(Future<bool> Function(BuildContext) open) async {
    final created = await open(context);
    if (created && mounted) await _capture();
  }

  /// `unknown_habit`, or "Alışkanlık oluştur" with no habit for today: open
  /// the habit form with the typed name, then log the habit it created for
  /// today — what the line asked for — even if its name was changed in the
  /// form.
  Future<void> _createHabit(String name) async {
    final l = context.l10n;
    final habit = await ref
        .read(createFlowsProvider)
        .habit(context, name: name.isEmpty ? null : name);
    if (habit == null || !mounted) return;
    setState(() {
      _busy = true;
      _inline = null;
    });
    try {
      // One step, as the line would have: a daily habit counts up by one,
      // a weekly or monthly one is done for the day.
      await ref
          .read(habitActionsProvider)
          .setToday(habit.id, 1, day: habit.today.date);
      if (!mounted) return;
      Haptics.confirm();
      _done((
        message: l.captureSavedHabit(
          habit.name,
          completed: habit.logFor(1).completed,
        ),
        undo: _undoHabit(habit.id, 0, habit.today.date),
        edit: _editHabit(habit.id, habit.today.date),
      ));
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      _answer(
        _Problem(failureMessage(e, l, fallback: l.todayHabitUpdateFailed)),
      );
    }
  }

  // --- Layout --------------------------------------------------------------------

  void _pickKind(QuickAddKind? kind) {
    if (_busy) return;
    setState(() {
      _kind = kind;
      _inline = null;
    });
  }

  void _useExample(String example) {
    _controller.value = TextEditingValue(
      text: example,
      selection: TextSelection.collapsed(offset: example.length),
    );
    setState(() {
      _kind = null;
      _inline = null;
    });
  }

  static String _kindLabel(AppL10n l, QuickAddKind kind) => switch (kind) {
    QuickAddKind.task => l.quickAddKindTask,
    QuickAddKind.expense => l.quickAddKindExpense,
    QuickAddKind.income => l.quickAddKindIncome,
    QuickAddKind.event => l.quickAddKindEvent,
    QuickAddKind.habit => l.quickAddKindHabit,
  };

  static String _actionLabel(AppL10n l, QuickAddKind? kind) => switch (kind) {
    null => l.quickAddAction,
    QuickAddKind.task => l.quickAddActionTask,
    QuickAddKind.expense => l.quickAddActionExpense,
    QuickAddKind.income => l.quickAddActionIncome,
    QuickAddKind.event => l.quickAddActionEvent,
    QuickAddKind.habit => l.quickAddActionHabit,
  };

  @override
  Widget build(BuildContext context) {
    return SheetStepSwitcher(
      reverse: !_pickingHabit,
      child: _pickingHabit
          ? _HabitStep(
              key: const ValueKey('habits'),
              name: _habitName(),
              onBack: _backToLine,
              onPick: _logHabit,
              onCreate: () => _createHabit(_habitName()),
            )
          : KeyedSubtree(key: const ValueKey('line'), child: _line(context)),
    );
  }

  /// The line, its type, and the answer or the examples under it; the add
  /// button stays put, right above the keyboard, while the rest scrolls
  /// above it when it does not fit — a small phone with the keyboard up, an
  /// event suggestion or a refusal with its next step, large text.
  Widget _line(BuildContext context) {
    final l = context.l10n;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final guess = guessQuickAddKind(_controller.text);
    final hasEvent = ref.read(createFlowsProvider).event != null;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Insets.sheetH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _controller,
                      // The keyboard is up in the sheet's first frame.
                      autofocus: true,
                      // Read-only rather than disabled while sending: the
                      // keyboard and the cursor stay, so a refused line is
                      // fixed in place.
                      readOnly: _busy,
                      minLines: 1,
                      maxLines: 3,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _submit(),
                      // Every keystroke can change the guess, and with it
                      // the chip and the button.
                      onChanged: (_) => setState(() => _inline = null),
                      decoration: InputDecoration(hintText: l.quickAddHint),
                    ),
                    const SizedBox(height: Gap.sm),
                    ChoiceWrap<QuickAddKind?>(
                      choices: [
                        Choice(
                          null,
                          l.quickAddAuto(
                            guess == null ? null : _kindLabel(l, guess),
                          ),
                        ),
                        for (final kind in QuickAddKind.values)
                          if (kind != QuickAddKind.event || hasEvent)
                            Choice(kind, _kindLabel(l, kind)),
                      ],
                      selected: _kind,
                      onChanged: _pickKind,
                    ),
                    KeyedSubtree(key: _inlineKey, child: _under(context)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.sheetH,
                Gap.md,
                Insets.sheetH,
                Gap.lg,
              ),
              child: PrimaryButton(
                label: _actionLabel(l, _resolved),
                loading: _busy,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Under the chips: the answer to the line, or — while the field is
  /// empty — the examples. It grows into place in 200 ms and fades in.
  Widget _under(BuildContext context) {
    final inline = _inline;
    final Widget child;
    if (inline != null) {
      child = Padding(
        key: ObjectKey(inline),
        padding: const EdgeInsets.only(top: Gap.xs),
        child: switch (inline) {
          final _Problem problem => _ProblemView(problem: problem, busy: _busy),
          _Suggestion(:final suggestion) => _SuggestionView(
            suggestion: suggestion,
            busy: _busy,
            onSaveAsTodo: () => _capture(asTodo: true),
            onAddAsEvent: switch (ref.read(createFlowsProvider).event) {
              final open? => () => _addAsEvent(open, suggestion),
              null => null,
            },
          ),
        },
      );
    } else if (_controller.text.trim().isEmpty) {
      child = _Examples(
        key: const ValueKey('examples'),
        examples: context.l10n.quickAddExamples,
        onPick: _useExample,
      );
    } else {
      child = const SizedBox(key: ValueKey('nothing'), width: double.infinity);
    }

    final switcher = AnimatedSwitcher(
      duration: Motion.orInstant(context, Motion.filterIn),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: child,
    );
    // AnimatedSize cannot take zero time: under reduced motion the answer
    // just takes its place.
    if (Motion.reduced(context)) return switcher;
    return AnimatedSize(
      duration: Motion.quick,
      curve: Motion.surfaceIn,
      alignment: Alignment.topCenter,
      // Grown into place: bring its action into view again.
      onEnd: _revealAnswer,
      child: switcher,
    );
  }
}

/// Example lines, one tap writes one into the field: they teach what
/// "Otomatik" reads (a sign for money, `alışkanlık:`, a day word).
class _Examples extends StatelessWidget {
  final List<String> examples;
  final ValueChanged<String> onPick;

  const _Examples({super.key, required this.examples, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, example) in examples.indexed) ...[
            if (i > 0) const SizedBox(width: Gap.sm),
            NokChip(
              label: example,
              icon: Icons.north_west_rounded,
              onTap: () => onPick(example),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProblemView extends StatelessWidget {
  final _Problem problem;
  final bool busy;

  const _ProblemView({required this.problem, required this.busy});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final action = problem.actionLabel;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Gap.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_rounded, size: 18, color: c.error),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  problem.message,
                  style: text.bodyMedium!.copyWith(color: c.error),
                ),
              ),
            ],
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: TextButton(
                onPressed: busy ? null : problem.onAction,
                child: Text(action),
              ),
            ),
        ],
      ),
    );
  }
}

class _SuggestionView extends StatelessWidget {
  final EventSuggestion suggestion;
  final bool busy;
  final VoidCallback onSaveAsTodo;

  /// Null while there is no event form to open.
  final VoidCallback? onAddAsEvent;

  const _SuggestionView({
    required this.suggestion,
    required this.busy,
    required this.onSaveAsTodo,
    required this.onAddAsEvent,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final when = [
      l.relativeDay(suggestion.date),
      suggestion.time ?? l.dayAllDay,
    ].join(' · ');
    final title = suggestion.title.isEmpty ? null : suggestion.title;
    final addAsEvent = onAddAsEvent;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: Gap.sm),
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: Radii.mdAll,
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.event_outlined, size: 18, color: c.gold),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(l.captureLooksLikeEvent, style: text.bodyMedium),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                title == null ? when : '$title · $when',
                style: text.bodySmall!.copyWith(color: c.inkMid),
              ),
            ),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              children: [
                if (addAsEvent != null)
                  FilledButton(
                    onPressed: busy ? null : addAsEvent,
                    child: Text(l.captureAddAsEvent),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : onSaveAsTodo,
                  child: Text(l.captureSaveAsTodo),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The habit step (§7.3): today's habits from `/home`, 48 dp rows; a tap
/// logs one step and closes the sheet. Habits whose name has [name] in it
/// come first. A done one is shown, but not tapped again.
class _HabitStep extends ConsumerWidget {
  final String name;
  final VoidCallback onBack;
  final void Function(HomeHabit habit, DateTime? day) onPick;

  /// The habit form, for a day with no habits; null without one.
  final VoidCallback? onCreate;

  const _HabitStep({
    super.key,
    required this.name,
    required this.onBack,
    required this.onPick,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final home = ref.watch(homeProvider);
    final summary = home.value?.data;

    final Widget body;
    if (summary == null) {
      body = home.hasError
          ? Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.sheetH,
                vertical: Gap.md,
              ),
              child: Text(
                l.quickAddHabitsFailed,
                style: text.bodyMedium!.copyWith(color: c.error),
              ),
            )
          : const Padding(
              padding: EdgeInsets.all(Gap.xxl),
              child: Center(child: CircularProgressIndicator()),
            );
    } else if (summary.todayHabits.isEmpty) {
      final create = onCreate;
      body = Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.sheetH,
          Gap.sm,
          Insets.sheetH,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.quickAddNoHabits,
              style: text.bodyMedium!.copyWith(color: c.inkMid),
            ),
            if (create != null)
              TextButton(onPressed: create, child: Text(l.quickAddNewHabit)),
          ],
        ),
      );
    } else {
      final wanted = trFold(name.trim());
      bool matches(HomeHabit h) =>
          wanted.isNotEmpty && trFold(h.name).contains(wanted);
      final habits = [
        ...summary.todayHabits.where(matches),
        ...summary.todayHabits.where((h) => !matches(h)),
      ];
      body = ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final habit in habits)
            _HabitPickRow(
              habit: habit,
              onTap: habit.completedToday
                  ? null
                  : () => onPick(habit, summary.today),
            ),
        ],
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Gap.xs, right: Insets.sheetH),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  tooltip: l.actionBack,
                  icon: Icon(Icons.arrow_back_rounded, color: c.inkMid),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(l.quickAddPickHabit, style: text.titleMedium),
                  ),
                ),
              ],
            ),
          ),
          Flexible(child: body),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }
}

class _HabitPickRow extends StatelessWidget {
  final HomeHabit habit;

  /// Null for a habit already done today.
  final VoidCallback? onTap;

  const _HabitPickRow({required this.habit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(habit.color, c);
    final done = habit.completedToday;
    final counts = habit.targetCount > 1;
    return Semantics(
      button: !done,
      enabled: !done,
      label: habit.name,
      value: done
          ? l.quickAddHabitDone
          : counts
          ? '${habit.todayCount}/${habit.targetCount}'
          : null,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.sheetH,
              vertical: Gap.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: tone.fill,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    habit.name,
                    style: text.bodyLarge!.copyWith(
                      color: done ? c.inkMid : c.inkHi,
                    ),
                  ),
                ),
                if (done)
                  Icon(Icons.check_circle_rounded, size: 20, color: c.income)
                else if (counts)
                  Text(
                    '${habit.todayCount}/${habit.targetCount}',
                    style: text.bodySmall!.copyWith(color: c.inkMid),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
