import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api.dart';
import '../../../../core/formats.dart';
import '../../../../core/haptics.dart';
import '../../../../data/actions.dart';
import '../../../../data/providers.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/quick_capture.dart';
import '../../../../theme/app_colors.dart';
import '../../../../ui/widgets/primary_button.dart';
import '../../../flows/create_flows.dart';

/// Bolt quick-capture: one line → `POST /quick_captures`.
///
/// The line becomes a transaction (it starts with `-` or `+`), a habit
/// check-in (`alışkanlık: koşu`) or a todo; the repository reports which,
/// and every screen showing that data refreshes. The sheet closes only once
/// something was saved, and the snackbar then says what — a line that names
/// a day ("yarın 15:00 dişçi") saves nothing, and the sheet says so and
/// offers to save it as a task (or as an event, once the event form exists).
///
/// A refusal stays in the sheet, under the line, with the text kept so it
/// can be fixed, and with the next step where there is one: create the
/// account a money line needs, or the habit a `habit:` line names.
Future<void> showQuickCaptureSheet(BuildContext context) {
  final c = context.nok;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    // However tall it grows (a small phone with the keyboard up, large
    // text), the sheet stops below the status bar.
    useSafeArea: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    backgroundColor: c.surface3,
    builder: (_) => const _QuickCaptureSheet(),
  );
}

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

class _QuickCaptureSheet extends ConsumerStatefulWidget {
  const _QuickCaptureSheet();

  @override
  ConsumerState<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends ConsumerState<_QuickCaptureSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  _Inline? _inline;

  /// What [_inline] shows, to scroll it into view.
  final _inlineKey = GlobalKey();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Shows [inline] under the line, with the sheet ready for the next step,
  /// and scrolls it into view: on a small phone with the keyboard up, the
  /// answer — and the action it offers — can fall below what the sheet has
  /// room for.
  void _answer(_Inline inline) {
    setState(() {
      _busy = false;
      _inline = inline;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shown = _inlineKey.currentContext;
      if (!mounted || shown == null || !shown.mounted) return;
      Scrollable.ensureVisible(
        shown,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Sends the line; [asTodo] saves it as it is, as a task.
  Future<void> _submit({bool asTodo = false}) async {
    final l = context.l10n;
    final text = _controller.text.trim();
    if (_busy) return;
    if (text.isEmpty) {
      _answer(_Problem(l.errCaptureEmpty));
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(repositoryProvider)
          .quickCapture(text, asTodo: asTodo);
      if (!mounted) return;
      if (!result.saved) {
        Haptics.tick();
        final suggestion = result.suggestion;
        _answer(
          suggestion != null
              ? _Suggestion(suggestion)
              : _Problem(l.captureNotSaved),
        );
        return;
      }
      Haptics.success();
      _close(_savedMessage(l, result));
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      _answer(_problemFor(e, asTodo: asTodo));
    }
  }

  /// Closes the sheet and says what was saved.
  ///
  /// Deferred: design-research §4.4/§4.7 also want "Geri al" and "Düzenle"
  /// on this confirmation. They wait for the quick-add rework (the preview
  /// and the confirmed structure of §4.7) and the todo edit form (part
  /// 2.4); a habit's undo also needs the count it had before the capture,
  /// which the answer does not carry.
  void _close(String message) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// What the snackbar says a capture saved, by what it turned into.
  static String _savedMessage(AppL10n l, QuickCaptureResult result) {
    switch (result.capturedType) {
      case 'transaction':
        final tx = result.transaction;
        if (tx == null) break;
        final income = tx.kind == 'income';
        final amount = formatMoney(
          tx.amountCents,
          tx.account.currency,
          tx.account.subunitToUnit,
          signed: income,
          negative: !income,
        );
        final what = tx.description ?? result.summary;
        return income
            ? l.captureSavedIncome(amount, what)
            : l.captureSavedExpense(amount, what);
      case 'habit_log':
        return l.captureSavedHabit(
          result.summary,
          completed: result.habitLog?.completed ?? false,
        );
      case 'todo':
        return l.captureSavedTodo(result.todo?.title ?? result.summary);
    }
    return l.captureSaved(result.summary);
  }

  /// [asTodo]: the line was being saved as a task, and a retry does that
  /// again.
  _Problem _problemFor(Object error, {required bool asTodo}) {
    final l = context.l10n;
    if (error is! ApiException) return _Problem(l.todayQuickCaptureFailed);
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
        onAction: () => _submit(asTodo: asTodo),
      );
    }
    final flows = ref.read(createFlowsProvider);
    switch (error.code) {
      case 'no_account':
        final account = flows.account;
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
    return _Problem(
      failureMessage(error, l, fallback: l.todayQuickCaptureFailed),
    );
  }

  /// `no_account`: open the new-account form, then send the line again —
  /// the money now has an account to go to.
  Future<void> _createAccount(Future<bool> Function(BuildContext) open) async {
    final created = await open(context);
    if (created && mounted) await _submit();
  }

  /// `unknown_habit`: open the habit form with the typed name, then log the
  /// habit it created for today — what the line asked for — even if its name
  /// was changed in the form.
  Future<void> _createHabit(String name) async {
    final l = context.l10n;
    final habit = await ref
        .read(createFlowsProvider)
        .habit(context, name: name);
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
      Haptics.success();
      _close(
        l.captureSavedHabit(habit.name, completed: habit.logFor(1).completed),
      );
    } catch (e) {
      if (!mounted) return;
      _answer(
        _Problem(failureMessage(e, l, fallback: l.todayHabitUpdateFailed)),
      );
    }
  }

  /// Event suggestion: hand it to the event form; once saved, done.
  Future<void> _addAsEvent(
    Future<bool> Function(BuildContext, EventSuggestion) open,
    EventSuggestion suggestion,
  ) async {
    final saved = await open(context, suggestion);
    if (saved && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final inline = _inline;

    // Laid out in what the keyboard leaves, under the drag handle every
    // sheet gets from the theme. The "Ekle" button stays put, right above
    // the keyboard; the line and what the server said about it scroll above
    // it when they do not fit — a small phone with the keyboard up, an
    // event suggestion or a refusal with its next step, large text.
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.todayQuickCapture, style: text.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      // Read-only rather than disabled while sending: the
                      // keyboard and the cursor stay, so a refused line is
                      // fixed in place.
                      readOnly: _busy,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _submit(),
                      onChanged: (_) {
                        if (_inline != null) setState(() => _inline = null);
                      },
                      decoration: InputDecoration(
                        hintText: l.todayQuickCaptureHint,
                        // The examples teach the syntax; let them wrap
                        // rather than be cut off on a narrow phone.
                        hintMaxLines: 2,
                      ),
                    ),
                    if (inline != null) ...[
                      const SizedBox(height: 12),
                      KeyedSubtree(
                        key: _inlineKey,
                        child: switch (inline) {
                          final _Problem problem => _ProblemView(
                            problem: problem,
                            busy: _busy,
                          ),
                          _Suggestion(:final suggestion) => _SuggestionView(
                            suggestion: suggestion,
                            busy: _busy,
                            onSaveAsTodo: () => _submit(asTodo: true),
                            onAddAsEvent:
                                switch (ref.read(createFlowsProvider).event) {
                              final open? =>
                                () => _addAsEvent(open, suggestion),
                              null => null,
                            },
                          ),
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: PrimaryButton(
                label: l.todayQuickCaptureAdd,
                loading: _busy,
                onPressed: _submit,
              ),
            ),
          ],
        ),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 18, color: c.error),
              const SizedBox(width: 8),
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
              padding: const EdgeInsets.only(left: 18),
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.event_outlined, size: 18, color: c.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.captureLooksLikeEvent, style: text.bodyMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                title == null ? when : '$title · $when',
                style: text.bodySmall!.copyWith(color: c.inkMid),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
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
