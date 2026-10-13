import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api.dart';
import '../../../../core/haptics.dart';
import '../../../../core/session.dart';
import '../../../../data/providers.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/account.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/entity_color.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/nok_chip.dart';
import '../../../widgets/nok_sheet.dart';
import '../../../widgets/nokturn_card.dart';
import '../../habits/habit_form.dart';
import '../../journal/journal_editor.dart';
import 'today_agenda.dart';

/// Whether the first-run card has been shown on this device (it then stays
/// until it is done or hidden), whether it was hidden for good, and the
/// steps it has shown done ([TodayStartProgress.stepNames]) — a step once
/// done stays done, though what it made is gone (the first task finished).
@immutable
class TodayStartFlags {
  const TodayStartFlags({
    this.active = false,
    this.dismissed = false,
    this.done = const {},
  });

  final bool active;
  final bool dismissed;
  final Set<String> done;

  static const activeKey = 'today.start.active';
  static const dismissedKey = 'today.start.dismissed';
  static const doneKey = 'today.start.done';
}

final todayStartFlagsProvider =
    NotifierProvider<TodayStartFlagsNotifier, TodayStartFlags>(
      TodayStartFlagsNotifier.new,
    );

class TodayStartFlagsNotifier extends Notifier<TodayStartFlags> {
  /// Read afresh for each session: signing out clears the device store, and
  /// the next account — a new one included — decides for itself.
  @override
  TodayStartFlags build() {
    ref.watch(sessionProvider.select((s) => s is SessionLoggedIn));
    try {
      final prefs = ref.read(sharedPrefsProvider);
      return TodayStartFlags(
        active: prefs.getBool(TodayStartFlags.activeKey) ?? false,
        dismissed: prefs.getBool(TodayStartFlags.dismissedKey) ?? false,
        done: {...?prefs.getStringList(TodayStartFlags.doneKey)},
      );
    } catch (_) {
      return const TodayStartFlags();
    }
  }

  void _write(String key) {
    try {
      ref.read(sharedPrefsProvider).setBool(key, true);
    } catch (_) {
      /* no device store: it lasts this run */
    }
  }

  /// The card showed: it stays until done or hidden, whatever is added.
  void activate() {
    if (state.active) return;
    state = TodayStartFlags(
      active: true,
      dismissed: state.dismissed,
      done: state.done,
    );
    _write(TodayStartFlags.activeKey);
  }

  /// "Gizle", or every step done: never again on this device.
  void dismiss() {
    if (state.dismissed) return;
    state = TodayStartFlags(
      active: state.active,
      dismissed: true,
      done: state.done,
    );
    _write(TodayStartFlags.dismissedKey);
  }

  /// The card showed [progress]: its steps done stay done.
  void remember(TodayStartProgress progress) {
    final done = {...state.done, ...progress.doneSteps};
    if (done.length == state.done.length) return;
    state = TodayStartFlags(
      active: state.active,
      dismissed: state.dismissed,
      done: done,
    );
    try {
      ref
          .read(sharedPrefsProvider)
          .setStringList(TodayStartFlags.doneKey, [...done]);
    } catch (_) {
      /* no device store: it lasts this run */
    }
  }
}

/// The four first steps (design-analysis §7.15) and which are done.
@immutable
class TodayStartProgress {
  const TodayStartProgress({
    required this.account,
    required this.habit,
    required this.todo,
    required this.journal,
  });

  final bool account;
  final bool habit;
  final bool todo;
  final bool journal;

  static const total = 4;

  /// The steps' names, in the card's order (what [TodayStartFlags.done]
  /// keeps).
  static const stepNames = ['account', 'habit', 'todo', 'journal'];

  /// The names of the steps done.
  Set<String> get doneSteps => {
    for (final (i, d) in [account, habit, todo, journal].indexed)
      if (d) stepNames[i],
  };

  int get done => [account, habit, todo, journal].where((d) => d).length;
  bool get complete => done == total;

  @override
  bool operator ==(Object other) =>
      other is TodayStartProgress &&
      other.account == account &&
      other.habit == habit &&
      other.todo == todo &&
      other.journal == journal;

  @override
  int get hashCode => Object.hash(account, habit, todo, journal);
}

/// The first-run card's steps, or null when it is not shown. It shows on a
/// new account — no account, no habit and no journal entry, once all three
/// are known — and from then on until every step is done or it is hidden
/// ([TodayStartFlags]). Unknown data (still loading, failed) never shows it.
final todayStartProvider = Provider.autoDispose<TodayStartProgress?>((ref) {
  final flags = ref.watch(todayStartFlagsProvider);
  if (flags.dismissed) return null;
  final account = ref.watch(
    accountsProvider.select(
      (a) => a.value?.data.any((account) => !account.archived),
    ),
  );
  final habit = ref.watch(
    homeProvider.select((a) => a.value?.data.todayHabits.isNotEmpty),
  );
  final todo = ref.watch(
    homeProvider.select((a) {
      final home = a.value?.data;
      return home == null
          ? null
          : home.openTodos > 0 || home.upcomingTodos.isNotEmpty;
    }),
  );
  final journal = ref.watch(
    journalProvider(todayJournalRange).select((a) {
      final bundle = a.value?.data;
      return bundle == null
          ? null
          : bundle.entriesCount > 0 || bundle.entries.isNotEmpty;
    }),
  );
  if (!flags.active &&
      (account != false || habit != false || journal != false)) {
    return null;
  }
  // A step the card has shown done stays done: finishing the first task
  // must not take its step back.
  bool seen(bool? live, String step) =>
      (live ?? false) || flags.done.contains(step);
  return TodayStartProgress(
    account: seen(account, 'account'),
    habit: seen(habit, 'habit'),
    todo: seen(todo, 'todo'),
    journal: seen(journal, 'journal'),
  );
});

/// Whether [todayStartProvider] has made up its mind — what it says will not
/// flip once the reads still loading land. Until then Today holds back what
/// the first-run card would replace (the habits' empty card, the money
/// chip's "start"), so a new account never paints a "₺0" or an empty
/// state that the card then pushes away. A failed read counts as decided:
/// unknown data never shows the card.
final todayStartDecidedProvider = Provider.autoDispose<bool>((ref) {
  final flags = ref.watch(todayStartFlagsProvider);
  if (flags.dismissed || flags.active) return true;
  // Each read: true (not new), false (new), null (still loading).
  final account = ref.watch(
    accountsProvider.select(
      (a) => a.hasValue
          ? a.value!.data.any((account) => !account.archived)
          : a.hasError
          ? true
          : null,
    ),
  );
  final habit = ref.watch(
    homeProvider.select(
      (a) => a.hasValue
          ? a.value!.data.todayHabits.isNotEmpty
          : a.hasError
          ? true
          : null,
    ),
  );
  final journal = ref.watch(
    journalProvider(todayJournalRange).select((a) {
      if (a.hasError && !a.hasValue) return true;
      final bundle = a.value?.data;
      return bundle == null
          ? null
          : bundle.entriesCount > 0 || bundle.entries.isNotEmpty;
    }),
  );
  final reads = [account, habit, journal];
  return reads.contains(true) || !reads.contains(null);
});

/// The journal range Today reads (its journal card, the first-run card).
const todayJournalRange = '7d';

/// A cash account in the user's currency, in one tap — the same call as
/// Finance's first-run card. Shared by the money chip and the first-run
/// card; a second tap while one is on its way does nothing.
Future<void> openTodayCashAccount(BuildContext context, WidgetRef ref) async {
  if (_openingCash) return;
  _openingCash = true;
  final l = context.l10n;
  try {
    final account = await ref
        .read(repositoryProvider)
        .createAccount(
          AccountInput(
            name: l.financeCashAccountName,
            accountType: 'cash',
            color: recordSwatches.first,
          ),
        );
    Haptics.confirm();
    if (context.mounted) showAppSnack(context, l.accountCreated(account.name));
  } catch (e) {
    if (context.mounted) {
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.accountSaveFailed),
        isError: true,
      );
    }
  } finally {
    _openingCash = false;
  }
}

bool _openingCash = false;

/// The first-run card, "Başlayalım · 1/4" (design-analysis §7.15): four
/// 48 dp steps, each led by a 24 dp ring that fills income-green once done —
/// open a cash account (one tap), pick a habit (starter chips), add the
/// first task (focuses the Today card's add row), write about today. "Gizle"
/// hides it for good. With every step done it says "Hepsi tamam" for 2 s,
/// then folds away.
class StartCard extends ConsumerStatefulWidget {
  const StartCard({super.key, required this.progress});

  final TodayStartProgress progress;

  /// How long "Hepsi tamam" stays before the card folds away.
  static const doneHold = Motion.doneHold;

  @override
  ConsumerState<StartCard> createState() => _StartCardState();
}

class _StartCardState extends ConsumerState<StartCard> {
  Timer? _fold;

  @override
  void initState() {
    super.initState();
    // Once shown, it stays through the steps that make the account "not
    // new" any more.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(todayStartFlagsProvider.notifier)
        ..activate()
        ..remember(widget.progress);
    });
    _maybeFold();
  }

  @override
  void didUpdateWidget(StartCard old) {
    super.didUpdateWidget(old);
    if (widget.progress != old.progress) {
      // Not while building: the flags are another provider.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(todayStartFlagsProvider.notifier).remember(widget.progress);
        }
      });
    }
    _maybeFold();
  }

  void _maybeFold() {
    if (!widget.progress.complete || _fold != null) return;
    _fold = Timer(StartCard.doneHold, () {
      if (mounted) ref.read(todayStartFlagsProvider.notifier).dismiss();
    });
  }

  @override
  void dispose() {
    _fold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final p = widget.progress;

    if (p.complete) {
      return NokturnCard(
        child: Align(
          alignment: Alignment.centerLeft,
          child: EmptyState.allDone(label: l.labelAllDone),
        ),
      );
    }

    // A step not done yet does it; a done one leads to what it made.
    final steps = [
      (
        p.account,
        l.todayStartCash,
        p.account
            ? () => context.go('/finance')
            : () => openTodayCashAccount(context, ref),
      ),
      (
        p.habit,
        l.todayStartHabit,
        p.habit
            ? () => context.go('/habits')
            : () => showHabitStarterSheet(context),
      ),
      (
        p.todo,
        l.todayStartTodo,
        p.todo
            ? () => context.go('/agenda')
            : () => ref.read(todayInlineAddProvider.notifier).request(),
      ),
      (
        p.journal,
        l.todayStartJournal,
        p.journal
            ? () => context.go('/journal')
            : () => openJournalEditor(context),
      ),
    ];

    return NokturnCard(
      variant: NokCardVariant.list,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.rowH, 0, Gap.xs, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Hit.min),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l.todayStartTitle(p.done, TodayStartProgress.total),
                        style: text.titleMedium,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(todayStartFlagsProvider.notifier).dismiss(),
                    style: TextButton.styleFrom(foregroundColor: c.inkMid),
                    child: Text(l.actionHide),
                  ),
                ],
              ),
            ),
          ),
          for (final (done, label, onTap) in steps)
            _StartStep(done: done, label: label, onTap: onTap),
        ],
      ),
    );
  }
}

class _StartStep extends StatelessWidget {
  const _StartStep({
    required this.done,
    required this.label,
    required this.onTap,
  });

  final bool done;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Semantics(
        checked: done,
        button: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Hit.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.rowH,
                vertical: Gap.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 24,
                    color: done ? c.income : c.inkDisabled,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      label,
                      style: text.bodyLarge!.copyWith(
                        color: done ? c.inkMid : c.inkHi,
                      ),
                    ),
                  ),
                  if (!done)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: c.inkLow,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The first-run card's "Bir alışkanlık seç": starter chips; a chip opens the
/// habit form with that name, "Kendin yaz" an empty one.
Future<void> showHabitStarterSheet(BuildContext context) async {
  final l = context.l10n;
  final picked = await showNokSheet<String>(
    context,
    title: l.todayStartHabitTitle,
    showClose: true,
    builder: (sheet) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.sheetH,
          Gap.sm,
          Insets.sheetH,
          Gap.xxl,
        ),
        child: Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final name in l.todayHabitStarters)
              NokChip(label: name, onTap: () => Navigator.of(sheet).pop(name)),
            NokChip(
              label: l.todayStartHabitOwn,
              icon: Icons.edit_outlined,
              onTap: () => Navigator.of(sheet).pop(''),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  await openHabitForm(context, initialName: picked.isEmpty ? null : picked);
}
