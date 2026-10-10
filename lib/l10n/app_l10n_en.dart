import '../core/formats.dart';
import '../models/event.dart';
import '../theme/entity_color.dart' show RecordSwatch;
import 'app_l10n.dart';

/// English copy. Keep this file and [AppL10nTr] member-for-member identical —
/// the abstract base enforces it.
class AppL10nEn extends AppL10n {
  const AppL10nEn();

  @override
  String get localeCode => 'en';

  // --- Generic actions and words --------------------------------------------
  // region common (WP-1)

  @override
  String get appName => 'Meridian';
  @override
  String get tagline => 'Your personal life hub';
  @override
  String get actionSave => 'Save';
  @override
  String get actionUpdate => 'Update';
  @override
  String get actionCancel => 'Cancel';
  @override
  String get actionDelete => 'Delete';
  @override
  String get actionEdit => 'Edit';
  @override
  String get actionRetry => 'Try again';
  @override
  String get actionBack => 'Go back';
  @override
  String get actionSelect => 'Select';
  @override
  String get actionSelectOptional => 'Select (optional)';
  @override
  String get actionSeeAll => 'See all →';
  @override
  String get actionUndo => 'Undo';
  @override
  String get actionDismiss => 'Dismiss';
  @override
  String get labelAll => 'All';
  @override
  String get labelNone => 'None';
  @override
  String get labelSkip => 'Skip';
  @override
  String get labelChange => 'Change';
  @override
  String get actionClose => 'Close';
  @override
  String get actionSearch => 'Search';
  @override
  String get labelAllDone => 'All done';
  @override
  String streakDays(int days) => '$days-day streak';
  @override
  String streakNewRecord(int record) => 'New streak · Best $record';
  @override
  String get semProfileAndSettings => 'Profile and settings';
  @override
  String get semDragToReorder => 'Drag to reorder';
  @override
  String colorName(RecordSwatch swatch) => switch (swatch) {
        RecordSwatch.gold => 'Gold',
        RecordSwatch.sage => 'Sage',
        RecordSwatch.dustyBlue => 'Dusty blue',
        RecordSwatch.clay => 'Clay',
        RecordSwatch.tan => 'Tan',
        RecordSwatch.mauve => 'Mauve',
        RecordSwatch.teal => 'Teal',
        RecordSwatch.amber => 'Amber',
      };
  // endregion

  // --- Navigation and screen titles -----------------------------------------
  // region shell (WP-4)

  @override
  String get tabToday => 'Today';
  @override
  String get tabAgenda => 'Agenda';
  @override
  String get tabFinance => 'Finance';
  @override
  String get tabHabits => 'Habits';
  @override
  String get tabGoals => 'Goals';
  @override
  String get tabJournal => 'Journal';
  @override
  String get titleToday => 'Today';
  @override
  String get titleFinance => 'Finance';
  @override
  String get titleHabits => 'Habits';
  @override
  String get titleGoals => 'Goals';
  @override
  String get titleJournal => 'Journal';
  @override
  String get titleProfile => 'Profile';
  @override
  String get titleServer => 'Server';
  @override
  String get titleTransactions => 'Transactions';
  @override
  String get titleAccount => 'Account';
  @override
  String get titleGoal => 'Goal';
  @override
  String get titleJournalEntry => 'Entry';
  @override
  String semAgendaOverdue(int count) =>
      '$count overdue ${count == 1 ? 'task' : 'tasks'}';
  @override
  String get titleEvents => 'Events';
  @override
  String get titleSearch => 'Search';
  @override
  String get searchComingSoon => 'Search across everything is coming here';
  @override
  String get subscriptionUndoFailed =>
      "Couldn't undo the payment. You can delete it under Transactions.";
  // endregion

  // --- Search ----------------------------------------------------------------
  // region search (WP-16)
  // endregion

  // --- Errors, offline, session ---------------------------------------------
  // region errors (WP-1)

  @override
  String get errServerUnreachable => 'Can\'t reach the server';
  @override
  String get errCheckWifi => 'Check your Wi-Fi or Tailscale connection';
  @override
  String get errServerSettings => 'Server settings';
  @override
  String offlineLastUpdated(String time) => 'Offline · last updated $time';
  @override
  String get syncUpdating => 'Updating';
  @override
  String get errInvalidData => 'Invalid data';
  @override
  String get errInvalidCredentials => 'Wrong email or password';
  @override
  String get errSessionExpired => 'Your session expired';
  @override
  String get errNotFound => 'Not found';
  @override
  String errServer(int status) => 'Server error ($status)';
  @override
  String get errNoConnection =>
      'Can\'t reach the server — check your Wi-Fi or Tailscale connection';
  @override
  String get noticeSessionExpired => 'Your session expired, sign in again';
  @override
  String get errRecordGoneBody =>
      'It may have been deleted on the web or on another device.';
  // endregion

  // --- Server refusals, by the error `code` the API sends -------------------
  // region server refusals (WP-1)

  @override
  String get errTooManyRequests =>
      'Too many attempts. Try again in a few minutes.';
  @override
  String get errCurrentPasswordRequired => 'Enter your current password';
  @override
  String get errInvalidCurrentPassword => 'Your current password is wrong';
  @override
  String errInvalidParameter(String param) =>
      'The server didn\'t accept a value ($param)';
  @override
  String get errValueOutOfRange => 'That number is too large';
  @override
  String get errInvalidDate => 'That date isn\'t valid';
  @override
  String get errInvalidDatetime => 'That date or time isn\'t valid';
  @override
  String get errFutureDate => 'You can\'t log a day in the future';
  @override
  String errBeforeHabitStart(DateTime? start) => start == null
      ? 'This habit didn\'t exist yet on that day'
      : 'This habit didn\'t exist yet on that day (it started on '
          '${formatDate(start, withYear: true, locale: localeCode)})';
  @override
  String get errHabitArchived => 'An archived habit can\'t be logged';
  @override
  String get errCaptureEmpty => 'Type something first';
  @override
  String get errNoAccount => 'To record an amount, create an account first';
  @override
  String errUnknownHabit(String name) => 'There\'s no habit called “$name”';
  @override
  String errInvalidAmount(String? reason) => switch (reason) {
        'zero' => 'The amount must be greater than zero',
        'too_precise' =>
          'This account\'s currency can\'t have that many decimal places',
        'too_large' => 'That amount is too large',
        _ => 'Couldn\'t read the amount. Write it like -250, -12.50 or '
            '+1,250.50.',
      };
  @override
  String errHasTransactions(int transactions, int incomingTransfers) {
    final count = transactions == 1 ? '1 transaction' : '$transactions transactions';
    if (incomingTransfers <= 0) {
      return 'This account has $count; archive it instead of deleting it';
    }
    final transfers = incomingTransfers == 1
        ? '1 incoming transfer'
        : '$incomingTransfers incoming transfers';
    return 'This account has $count and $transfers; archive it instead of '
        'deleting it';
  }

  @override
  String get errCurrencyLocked =>
      'An account with transactions or subscriptions can\'t change its '
      'currency';
  @override
  String get errKindLocked => 'A category in use can\'t change its type';
  @override
  String get errAmountRequired =>
      'That account uses another currency; enter the amount again';
  @override
  String errNotChargeable(String? reason) => reason == 'inactive'
      ? 'A paused subscription can\'t be marked paid'
      : 'This subscription has no upcoming charge';
  @override
  String get errTargetReached =>
      'The target is already reached; raise it to reopen the goal';
  @override
  String get errTargetNotReached => 'The target isn\'t reached yet';
  @override
  String get errProgressComputed =>
      'This goal\'s progress is calculated automatically';
  @override
  String get errBodyHasFormatting =>
      'This entry has formatting added on the web; editing it here removes it';

  @override
  String? validationDetail(String error, {num? count}) => switch (error) {
        'blank' => 'Can\'t be blank',
        'taken' => 'Already taken',
        'too_long' => count == null
            ? 'Too long'
            : 'At most ${_n(count)} characters',
        'too_short' => count == null
            ? 'Too short'
            : 'At least ${_n(count)} characters',
        'wrong_length' => count == null
            ? 'Wrong length'
            : 'Must be exactly ${_n(count)} characters',
        'confirmation' => 'Doesn\'t match the new password',
        'inclusion' => 'Not a valid option',
        'exclusion' => 'This value can\'t be used',
        'invalid' => 'Isn\'t valid',
        'not_a_number' => 'Must be a number',
        'not_an_integer' => 'Must be a whole number',
        'greater_than' when count != null =>
          'Must be greater than ${_n(count)}',
        'greater_than_or_equal_to' when count != null =>
          'Must be at least ${_n(count)}',
        'less_than' when count != null => 'Must be less than ${_n(count)}',
        'less_than_or_equal_to' when count != null =>
          'Must be at most ${_n(count)}',
        'must_belong_to_same_user' => 'That record can\'t be used',
        'must_be_after_start' => 'Must be after the start',
        'before_start_date' => 'Must be after the start date',
        'must_match_kind' => 'Must be the same type as its parent',
        'must_be_root' => 'Must be a top-level category',
        'cannot_have_children' =>
          'A category with subcategories can\'t move under another one',
        'cannot_be_self' => 'Can\'t be placed under itself',
        'has_budget' => 'A category with a budget can\'t become a subcategory',
        'must_be_expense' => 'Must be an expense category',
        'kind_mismatch' => 'Doesn\'t match the transaction type',
        'same_account' => 'The source and target accounts must differ',
        'currency_mismatch' => 'The target account must use the same currency',
        'required_for_transfer' => 'Pick a target account for the transfer',
        'must_match_target_type' => 'Doesn\'t match the goal\'s type',
        'unsupported_frequency' =>
          'Must repeat daily, weekly, monthly or yearly',
        'unsupported_part' => 'This repeat rule isn\'t supported',
        'out_of_range' => 'Outside the allowed range',
        'no_occurrences' => 'This repeat never falls on any day',
        _ => null,
      };

  @override
  String? fieldLabel(String field) => switch (field) {
        'name' => 'Name',
        'title' => 'Title',
        'description' => 'Description',
        'body' || 'body_text' || 'text' => 'Text',
        'note' => 'Note',
        'amount_cents' || 'amount' => 'Amount',
        'initial_balance_cents' || 'initial_balance' => 'Opening balance',
        'limit_cents' => 'Limit',
        'monthly_limit_cents' || 'monthly_limit' => 'Monthly limit',
        'account_type' => 'Account type',
        'next_charge_on' => 'Next payment',
        'vendor' => 'Vendor',
        'active' => 'Status',
        'position' => 'Order',
        'date' => 'Date',
        'deadline' || 'end_date' => 'End date',
        'start_date' => 'Start date',
        'start_at' => 'Start',
        'end_at' => 'End',
        'due_at' || 'due_date' || 'due_time' => 'Due date',
        'account_id' || 'account' => 'Account',
        'related_account_id' => 'Target account',
        'finance_category_id' || 'finance_category' => 'Category',
        'parent_id' => 'Parent category',
        'currency' => 'Currency',
        'color' => 'Color',
        'frequency' => 'Frequency',
        'target_count' => 'Target count',
        'target_value' => 'Target value',
        'current_value' => 'Current value',
        'unit' => 'Unit',
        'related' => 'Link',
        'recurrence_rule' => 'Repeat',
        'location' => 'Location',
        'priority' => 'Priority',
        'status' => 'Status',
        'kind' => 'Type',
        'mood' => 'Mood',
        'energy_level' => 'Energy',
        'tags' => 'Tags',
        'gratitude' => 'Gratitude',
        'email' => 'Email',
        'password' => 'Password',
        'current_password' => 'Current password',
        'password_confirmation' => 'Password confirmation',
        'timezone' => 'Time zone',
        'weekly_review_day' => 'Weekly review day',
        'locale' => 'Language',
        'theme_preference' => 'Theme',
        'todo_list_id' => 'List',
        'goal_id' => 'Goal',
        'list_id' => 'List',
        'todos' => 'Tasks',
        'done' => 'Status',
        'all_day' => 'All day',
        'event_type' => 'Event type',
        _ => null,
      };

  /// A limit as a plain number in English notation.
  String _n(num value) => formatDecimal(
        value,
        decimals: value == value.roundToDouble() ? 0 : 2,
        locale: localeCode,
      );
  // endregion

  // --- Login and server address ---------------------------------------------
  // region login (WP-14)

  @override
  String get loginEmail => 'Email';
  @override
  String get loginPassword => 'Password';
  @override
  String get loginSubmit => 'Sign In';
  @override
  String get serverAddress => 'Server address';
  @override
  String get serverAddressShort => 'Address';
  @override
  String get serverAddressUnreachable =>
      'Couldn\'t reach the server — check the address and your Wi-Fi or Tailscale connection';
  // endregion

  // --- Dates and relative days ----------------------------------------------
  // region dates (WP-1)

  @override
  String get dayToday => 'Today';
  @override
  String get dayYesterday => 'Yesterday';
  @override
  String get dayTomorrow => 'Tomorrow';
  @override
  String get dayAllDay => 'All day';

  @override
  String relativeDay(DateTime date) {
    final diff = dayDelta(date);
    if (diff == 0) return dayToday;
    if (diff == -1) return dayYesterday;
    if (diff == 1) return dayTomorrow;
    return formatDate(
      date,
      withYear: date.year != appToday().year,
      locale: localeCode,
    );
  }

  @override
  String relativeDays(DateTime date) {
    final diff = dayDelta(date);
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    if (diff == -1) return 'yesterday';
    if (diff > 0) return 'in $diff days';
    return '${-diff} days ago';
  }

  @override
  String greeting(int hour) {
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 18) return 'Good afternoon';
    if (hour >= 18 && hour < 23) return 'Good evening';
    return 'Good night';
  }

  @override
  String percent(num value) => '${formatPercentNumber(value)}%';
  @override
  String compactThousands(double major) =>
      '${formatDecimal(major / 1000, decimals: 0, locale: localeCode)}K';
  @override
  String compactMillions(double major) =>
      '${formatDecimal(major / 1000000, locale: localeCode)}M';
  // endregion

  // --- Today ----------------------------------------------------------------
  // region today (WP-5)

  @override
  String get todayMonthNet => 'NET THIS MONTH';
  @override
  String get todayYearNet => 'NET THIS YEAR';
  @override
  String get todayStatStreak => 'streaks';
  @override
  String get todayStatOpenTodos => 'open todos';
  @override
  String get todayStatWeek => 'this week';
  @override
  String get todayQuickCapture => 'Quick capture';
  @override
  String get todayQuickCaptureHint =>
      'What happened? (-250 coffee, +1,500 salary, habit: run, buy milk)';
  @override
  String get todayQuickCaptureAdd => 'Add';
  @override
  String get todayQuickCaptureFailed => 'Couldn\'t capture that';
  @override
  String get todayEmptyDay => 'Nothing planned — a quiet day';
  @override
  String get todayAllHabitsDone => 'All done';
  @override
  String get todayNoHabitsYet => 'No habits yet — start small';
  @override
  String get todayNoGoalsYet => 'No goals yet — set your first one';
  @override
  String get todayOpenTodos => 'Open todos';
  @override
  String get todayNoOpenTodos => 'Nothing open — all clear';
  @override
  String get todayTodosFailed => 'Couldn\'t load todos';
  @override
  String get todayTodoUpdateFailed => 'Couldn\'t update the todo';
  @override
  String get todayHabitUpdateFailed => 'Couldn\'t update the habit';
  @override
  String todayTodoDone(String title) => '“$title” done';
  @override
  String todayZoneNotice(String zone, String offset) =>
      'Days and times follow your account\'s time zone: $zone (UTC$offset)';

  @override
  String todayDateLine(DateTime day) =>
      '${formatWeekday(day, locale: 'en')}, ${formatDate(day, locale: 'en')}';
  @override
  String todayGreeting(String greeting, String firstName) =>
      firstName.isEmpty ? greeting : '$greeting, $firstName';
  @override
  String get todayCaptureLabel => 'Add a task, expense, event…';
  @override
  String get todayCaptureTransaction => 'Add transaction';
  @override
  String todayNextUpNow(String title) => 'Now · $title';
  @override
  String todayNextUpSoon(String time, String title, int minutes) =>
      '$time · $title · $minutes min';
  @override
  String get todayAddForToday => 'Add a task for today';
  @override
  String todayEventsPassed(int count) => '+$count earlier';
  @override
  String todayMoreRows(int count) => '+$count more';
  @override
  String get todayShowFinished => 'Show finished';
  @override
  String get todayHideFinished => 'Hide finished';
  @override
  String get todaySetGoal => 'Set a goal';
  @override
  String get todayJournalWrite => 'Write';
  @override
  String get todayJournalWritten => 'You wrote today';
  @override
  String todayNudgeYesterday(String habit) =>
      'Forgot to mark yesterday? · $habit';
  @override
  String todayNudgeLate(String name, String amount) =>
      '$name payment is overdue · $amount';
  @override
  String get todayNudgePaid => 'Paid';
  @override
  String todayStartTitle(int done, int total) => 'Let\'s begin · $done/$total';
  @override
  String get todayStartCash => 'Open a cash account';
  @override
  String get todayStartHabit => 'Pick a habit';
  @override
  String get todayStartTodo => 'Add your first task';
  @override
  String get todayStartJournal => 'Write about today';
  @override
  String get todayStartHabitTitle => 'Start with a habit';
  @override
  String get todayStartHabitOwn => 'Your own';
  @override
  List<String> get todayHabitStarters => const [
        'Drink water',
        'Walk',
        'Read',
        'Meditate',
        'Wake up early',
        'Stretch',
      ];
  // endregion

  // --- Quick capture --------------------------------------------------------
  // region quick capture (WP-6)

  @override
  String captureSavedExpense(String amount, String account) =>
      'Expense added · $amount · $account';
  @override
  String captureSavedIncome(String amount, String account) =>
      'Income added · $amount · $account';
  @override
  String captureSavedHabit(String name, {required bool completed}) =>
      completed ? '“$name” done for today' : '“$name” logged';
  @override
  String captureSavedTodo(String title) => 'Task added · $title';
  @override
  String captureSaved(String summary) => 'Saved: $summary';
  @override
  String get captureLooksLikeEvent =>
      'This looks like an event — nothing was saved yet.';
  @override
  String get captureNotSaved => 'Nothing was saved';
  @override
  String get captureMaybeSaved =>
      'The server didn\'t answer in time — it may have been saved. '
      'Check before sending it again.';
  @override
  String get captureSaveAsTodo => 'Save as a task';
  @override
  String get captureAddAsEvent => 'Add as an event';
  @override
  String get captureCreateAccount => 'Open a cash account';
  @override
  String captureCreateHabit(String name) => 'Create the habit “$name”';
  @override
  String get quickAddTitle => 'Quick add';
  @override
  String get quickAddHint => 'What do you want to add?';
  @override
  String quickAddAuto(String? guess) =>
      guess == null ? 'Auto' : 'Auto · $guess';
  @override
  String get quickAddKindTask => 'Task';
  @override
  String get quickAddKindExpense => 'Expense';
  @override
  String get quickAddKindIncome => 'Income';
  @override
  String get quickAddKindEvent => 'Event';
  @override
  String get quickAddKindHabit => 'Habit';
  @override
  String get quickAddAction => 'Add';
  @override
  String get quickAddActionTask => 'Add task';
  @override
  String get quickAddActionExpense => 'Add expense';
  @override
  String get quickAddActionIncome => 'Add income';
  @override
  String get quickAddActionEvent => 'Open as event';
  @override
  String get quickAddActionHabit => 'Check off habit';
  @override
  List<String> get quickAddExamples => const [
        '−85 coffee',
        '+1,500 salary',
        'tomorrow 15:00 dentist',
        'habit: water',
        'buy milk',
      ];
  @override
  String get quickAddPickHabit => 'Which habit?';
  @override
  String get quickAddNoHabits => 'No habits for today';
  @override
  String get quickAddNewHabit => 'Create a habit';
  @override
  String get quickAddHabitsFailed => 'Couldn\'t load your habits';
  @override
  String get quickAddHabitDone => 'Done today';
  @override
  String get quickAddFailed => 'Couldn\'t add that';
  @override
  String get quickAddUndoFailed => 'Couldn\'t undo that';
  // endregion

  // --- Todos and todo lists -------------------------------------------------
  // region todos (WP-7)

  @override
  String get titleTodos => 'Tasks';
  @override
  String todoFilter(String filter) => switch (filter) {
        'today' => 'Today',
        'upcoming' => 'Upcoming',
        'week' => 'This week',
        'overdue' => 'Overdue',
        'undated' => 'No date',
        'done' => 'Done',
        'cancelled' => 'Cancelled',
        'all' => 'All',
        _ => 'Open',
      };
  @override
  String todoFilterEmpty(String filter) => switch (filter) {
        'today' => 'Nothing due today',
        'upcoming' => 'Nothing due in the next 7 days',
        'week' => 'Nothing due this week',
        'overdue' => 'Nothing overdue — nice',
        'undated' => 'No tasks without a date',
        'done' => 'No finished tasks yet',
        'cancelled' => 'No cancelled tasks',
        _ => 'No open tasks — all done',
      };
  @override
  String get todoAllLists => 'All lists';
  @override
  String get todoNoList => 'No list';
  @override
  String get todoGroupOverdue => 'Overdue';
  @override
  String get todoGroupUndated => 'No date';
  @override
  String todoDue(DateTime day, String? time) =>
      time == null ? relativeDay(day) : '${relativeDay(day)} · $time';
  @override
  String todoSemantics(
    String title, {
    String? due,
    required bool overdue,
    required bool done,
  }) =>
      [
        title,
        ?due,
        if (overdue && !done) 'overdue',
        if (done) 'done',
      ].join(', ');
  @override
  String get todoAdd => 'Task';
  @override
  String get todoAddInline => 'Add a task';
  @override
  String get todoNewTitle => 'New task';
  @override
  String get todoEditTitle => 'Edit task';
  @override
  String get todoFieldTitle => 'Title';
  @override
  String get todoFieldNotes => 'Notes';
  @override
  String get todoFieldDue => 'Due';
  @override
  String get todoDuePick => 'Pick a date';
  @override
  String get todoAddTime => 'Add a time';
  @override
  String get todoRemoveTime => 'Remove the time';
  @override
  String get todoFieldPriority => 'Priority';
  @override
  String todoPriority(String priority) => switch (priority) {
        'low' => 'Low',
        'high' => 'High',
        'urgent' => 'Urgent',
        _ => 'Medium',
      };
  @override
  String get todoFieldList => 'List';
  @override
  String get todoFieldGoal => 'Goal';
  @override
  String get todoGoalLinked => 'Linked goal';
  @override
  String get todoTitleRequired => 'Write a title';
  @override
  String get todoSaveAndNew => 'Save and add another';
  @override
  String todoCreated(String title) => 'Task added: $title';
  @override
  String get todoUpdated => 'Task updated';
  @override
  String get todoSaveFailed => 'Couldn’t save the task';
  @override
  String todoDeleted(String title) => '“$title” deleted';
  @override
  String get todoDeleteFailed => 'Couldn’t delete the task';
  @override
  String get todoComplete => 'Complete';
  @override
  String get todoReopen => 'Reopen';
  @override
  String get todoPostpone => 'Move to tomorrow';
  @override
  String todoPostponed(String title) => '“$title” moved to tomorrow';
  @override
  String todoAllOpen(int count) => 'All open tasks ($count)';
  @override
  String get todoNoneUpcoming => 'Nothing due in the next 7 days';

  @override
  String get todoListsTitle => 'Lists';
  @override
  String get todoListsManage => 'Manage lists';
  @override
  String get todoListNew => 'New list';
  @override
  String get todoListEdit => 'Edit list';
  @override
  String get todoListName => 'Name';
  @override
  String get todoListNameRequired => 'Give the list a name';
  @override
  String get todoListColor => 'Colour';
  @override
  String todoListCounts(int open, int total) =>
      '$open open · $total ${total == 1 ? 'task' : 'tasks'}';
  @override
  String get todoListsEmpty =>
      'No lists yet — sort your tasks into lists like Home or Work';
  @override
  String todoListCreated(String name) => 'List “$name” created';
  @override
  String get todoListUpdated => 'List updated';
  @override
  String get todoListSaveFailed => 'Couldn’t save the list';
  @override
  String todoListDeleteTitle(String name) => 'Delete the list “$name”?';
  @override
  String todoListDeleteBody(int total) => total == 0
      ? 'This list is empty.'
      : 'This list has $total ${total == 1 ? 'task' : 'tasks'} (finished ones '
          'included).';
  @override
  String get todoListDeleteKeep => 'Keep the tasks, unlisted';
  @override
  String get todoListDeleteAll => 'Delete with its tasks';
  @override
  String todoListDeleted(String name) => 'List “$name” deleted';
  @override
  String get todoListDeleteFailed => 'Couldn’t delete the list';

  @override
  String get todoMoreFields => 'More';
  @override
  String todoMovedToday(String title) => '“$title” moved to today';
  @override
  String todoMovedOn(String title, String day) => '“$title” moved · $day';
  @override
  String todosMovedToday(int count) =>
      '$count ${count == 1 ? 'task' : 'tasks'} moved to today';
  @override
  String todoReopened(String title) => '“$title” reopened';
  @override
  String get todoListsArchived => 'Archived';
  @override
  String todoListArchived(String name) => 'List “$name” archived';
  @override
  String todoListRestored(String name) => 'List “$name” restored';
  // endregion

  // --- Events and agenda ----------------------------------------------------
  // region agenda (WP-7)

  @override
  String get titleAgenda => 'Agenda';
  @override
  String get agendaThisWeek => 'This week';
  @override
  String get agendaEmptyWeek => 'No events this week';
  @override
  String get agendaEmpty => 'No events in the coming days';
  @override
  String get agendaShowMore => 'Show more';
  @override
  String get agendaLoadFailed => 'Couldn’t load the events';
  @override
  String agendaMore(int count) =>
      '+$count more ${count == 1 ? 'event' : 'events'}';
  @override
  String get eventAdd => 'Event';
  @override
  String get eventNewTitle => 'New event';
  @override
  String get eventEditTitle => 'Edit event';
  @override
  String get eventFieldTitle => 'Title';
  @override
  String get eventStarts => 'Starts';
  @override
  String get eventEnds => 'Ends';
  @override
  String get eventNoEnd => 'No end';
  @override
  String get eventAddEnd => 'Add an end';
  @override
  String get eventRemoveEnd => 'Remove the end';
  @override
  String get eventLocation => 'Location';
  @override
  String get eventDescription => 'Description';
  @override
  String get eventFieldType => 'Type';
  @override
  String eventType(String type) => switch (type) {
        'work' => 'Work',
        'health' => 'Health',
        'finance' => 'Finance',
        'other' => 'Other',
        _ => 'Personal',
      };
  @override
  String get eventColor => 'Colour';
  @override
  String get eventRepeat => 'Repeat';
  @override
  String recurrence(RecurrencePreset preset) => switch (preset) {
        RecurrencePreset.none => 'Doesn’t repeat',
        RecurrencePreset.daily => 'Every day',
        RecurrencePreset.weekdays => 'Every weekday',
        RecurrencePreset.weekly => 'Every week',
        RecurrencePreset.monthly => 'Every month',
        RecurrencePreset.yearly => 'Every year',
        RecurrencePreset.custom => 'Custom repeat (set on the web)',
      };
  @override
  String get eventRepeatEnds => 'Repeat ends';
  @override
  String get eventRepeatForever => 'Never';
  @override
  String recurrenceUntil(DateTime day) =>
      'until ${formatDate(day, withYear: day.year != appToday().year, locale: localeCode)}';
  @override
  String recurrenceCount(int count) =>
      '$count ${count == 1 ? 'time' : 'times'}';
  @override
  String get eventTitleRequired => 'Write a title';
  @override
  String get eventEndBeforeStart => 'The end must be after the start';
  @override
  String get eventSeriesFormNote =>
      'This change affects every event in the series';
  @override
  String get eventSeriesNote =>
      'Recurring event: editing or deleting it changes every event in the '
      'series.';
  @override
  String eventCreated(String title) => '“$title” added';
  @override
  String get eventUpdated => 'Event updated';
  @override
  String get eventSaveFailed => 'Couldn’t save the event';
  @override
  String eventDeleted(String title) => '“$title” deleted';
  @override
  String get eventDeleteFailed => 'Couldn’t delete the event';
  @override
  String get eventDeleteSeriesTitle => 'Recurring event';
  @override
  String eventDeleteFollowing(DateTime day) => 'Delete this and later ones';
  @override
  String eventDeleteFollowingHint(DateTime day) =>
      'The events before '
      '${formatDate(day, withYear: day.year != appToday().year, locale: localeCode)} '
      'stay.';
  @override
  String get eventDeleteAll => 'Delete the whole series';
  @override
  String get eventDeleteAllHint => 'Every event in the series is deleted.';
  @override
  String eventSeriesEnded(String title) =>
      '“$title” removed from this date on';
  @override
  String get eventLoadFailed => 'Couldn’t load the event';
  @override
  String eventSemantics(String title, {required String when, String? where}) =>
      [title, when, ?where].join(', ');

  @override
  String get agendaViewUpcoming => 'Upcoming';
  @override
  String get agendaViewInbox => 'Inbox';
  @override
  String get agendaViewOverdue => 'Overdue';
  @override
  String get agendaViewDone => 'Done';
  @override
  String agendaChipCount(String label, int count) => '$label · $count';
  @override
  String agendaListChip(String? name) => 'List: ${name ?? 'All'}';
  @override
  String get agendaLater => 'Later';
  @override
  String get agendaUpcomingEmpty => 'The days ahead are calm';
  @override
  String get agendaUpcomingEmptyBody =>
      'The tasks and events you add line up here, day by day.';
  @override
  String get agendaTodayEmpty => 'Nothing planned for today';
  @override
  String get agendaInboxEmpty =>
      'Your inbox is empty — tasks without a date gather here';
  @override
  String get agendaCaptureLabel => 'Add a task, event…';
  @override
  String get agendaAddEvent => 'Add event';
  @override
  String get agendaShowDone => 'Completed';
  @override
  String get agendaDayAddHint => 'add to this day';
  @override
  String get eventDate => 'Date';
  @override
  String get eventEndDay => 'Ends on';
  @override
  String get eventSameDay => 'Same day';
  @override
  String get eventTime => 'Time';
  @override
  String get eventMoreFields => 'More';
  @override
  String recurrenceWeeklyOn(String weekday) => 'Every week on $weekday';
  // endregion

  // --- Habit day log --------------------------------------------------------
  // region habit log (WP-11)

  @override
  String get habitLogToday => 'Today\'s log';
  @override
  String get habitLogDone => 'Done today';
  @override
  String get habitLogNotDone => 'Not done yet today';
  @override
  String get habitLogComplete => 'Complete';
  @override
  String get habitLogReset => 'Reset';
  @override
  String get habitLogDecrease => 'One less';
  @override
  String get habitLogIncrease => 'One more';
  @override
  String habitLogSemantics(
    String name, {
    required int count,
    required int target,
    required bool done,
  }) {
    if (done) return '$name, done today';
    if (target > 1) return '$name, $count of $target';
    return '$name, not done yet';
  }

  @override
  String get habitLogHint => 'Long-press to adjust';
  @override
  String get habitLogAdd => 'Add';
  @override
  String get habitLogSet => 'Set';
  @override
  String habitLogPlus(int n) => '+$n';
  @override
  String get habitLogToTarget => 'Fill to target';
  @override
  String habitLogNow(int count) => 'Now $count';
  @override
  String habitLogNowPlus(int count, int add) => 'Now $count · +$add';
  // endregion

  // --- Finance --------------------------------------------------------------
  // region finance (WP-8)

  @override
  String get financeIncome => 'Income';
  @override
  String get financeExpense => 'Expense';
  @override
  String get financeTransfer => 'Transfer';
  @override
  String get financeLast6Months => 'Last 6 months';
  @override
  String get financeCategoriesThisMonth => 'Categories (this month)';
  @override
  String get financeNoSpendThisMonth => 'No spending this month';
  @override
  String get financeBudgets => 'Budgets';
  @override
  String financeRemaining(String amount) => '$amount left';
  @override
  String financeMonthEndEstimate(String amount) => 'Month-end estimate: $amount';
  @override
  String get financeUpcomingSubscriptions => 'Upcoming payments';
  @override
  String get financeRecentTransactions => 'Recent transactions';
  @override
  String get financeNoTransactionsYet => 'No transactions yet';
  @override
  String get financeAddAccount => 'Add account';
  @override
  String get financeNoTransactionsInAccount => 'No transactions in this account';

  @override
  String accountType(String type) => switch (type) {
        'cash' => 'Cash',
        'bank' => 'Bank',
        'credit_card' => 'Credit Card',
        'savings' => 'Savings',
        'crypto' => 'Crypto',
        _ => 'Account',
      };

  @override
  String subscriptionFrequency(String frequency) => switch (frequency) {
        'daily' => 'Daily',
        'weekly' => 'Weekly',
        'monthly' => 'Monthly',
        'yearly' => 'Yearly',
        _ => frequency,
      };
  @override
  String get financeMonthNet => 'THIS MONTH NET';
  @override
  String financeYearNet(String amount) => 'This year $amount';
  @override
  String financeInsightVsLastMonth(String amount, {required bool less}) =>
      'You have spent $amount ${less ? 'less' : 'more'} than by this day '
      'last month';
  @override
  String financeInsightProjection(
    String amount,
    int percent, {
    required bool below,
  }) =>
      percent == 0
          ? 'At this pace the month ends at $amount spent, level with your '
              '5-month average'
          : 'At this pace the month ends at $amount spent, $percent% '
              '${below ? 'below' : 'above'} your 5-month average';
  @override
  String financeInsightSpent(String amount, String perDay) =>
      'You have spent $amount this month · $perDay a day on average';
  @override
  String get financeCurrencyNoteMixed =>
      'This total adds other currencies without converting them';
  @override
  String get financeCurrencyNoteExcluded =>
      'Other currencies are not in this total';
  @override
  String financeSixMonthInsight(int percent, {required bool below}) =>
      percent == 0
          ? 'This month\'s spending is level with the 6-month average'
          : 'This month\'s spending is $percent% '
              '${below ? 'below' : 'above'} the 6-month average';
  @override
  String financeCategoriesInsight(String name, String amount) =>
      'Biggest: $name · $amount';
  @override
  String get financeSearch => 'Search transactions';
  @override
  String get financeMenuAddBudget => 'Add budget';
  @override
  String financeSetupTitle(int done, int total) => 'Setup $done/$total';
  @override
  String get financeSetupAccount => 'Open an account';
  @override
  String get financeSetupBudget => 'Set a budget';
  @override
  String get financeSetupSubscription => 'Add a regular payment';
  @override
  String get financePaid => 'Paid';
  @override
  String financeSubscriptionsMonthly(String amount) => '$amount a month';
  @override
  String financeBudgetPerDay(String amount, int daysLeft) => daysLeft <= 1
      ? '$amount today · last day'
      : '$amount a day · $daysLeft days left';
  @override
  String get financeBudgetEditLimit => 'Edit limit';
  // endregion

  // --- Transactions feed ----------------------------------------------------
  // region transactions (WP-9)

  @override
  String get txFilterAccount => 'Account';
  @override
  String get txFilterAllAccounts => 'All accounts';
  @override
  String get txFilterCategory => 'Category';
  @override
  String get txFilterAllCategories => 'All categories';
  @override
  String get txFilterDate => 'Date';
  @override
  String get txFilterDateRange => 'Date range';
  @override
  String get txFilterThisMonth => 'This month';
  @override
  String get txFilterLast30Days => 'Last 30 days';
  @override
  String get txFilterThisYear => 'This year';
  @override
  String get txFilterClear => 'Clear filters';
  @override
  String get txNoneForFilter => 'No transactions match this filter';
  @override
  String get txAllLoaded => 'That\'s everything';
  @override
  String txSummary(String income, String expense) =>
      '$income in · $expense out';
  @override
  String get txDeleted => 'Transaction deleted';
  @override
  String get txDeleteFailed => 'Couldn\'t delete it';
  @override
  String get txSaved => 'Transaction saved';
  @override
  String get txUpdated => 'Transaction updated';
  @override
  String get txLinkedTitle => 'Linked transaction';
  @override
  String get txLinkedDeletedAlong =>
      'Deleting this transaction deletes the linked one too.';
  @override
  String get txLinkedStays =>
      'Deleting this transaction leaves the linked one.';
  @override
  String txDeleteLinkedTitle(String name) => 'Delete “$name”?';
  @override
  String txDeleteLinkedBody(String linked) =>
      'Its linked transaction will be deleted too: $linked. This can\'t be '
      'undone.';
  @override
  String get txDeleteBoth => 'Delete both';
  @override
  String get txDeletedWithLinked => 'Transaction and its linked one deleted';
  @override
  String get txGone => 'This transaction was deleted';
  @override
  String get txSaveFailed => 'Couldn\'t save, try again';
  // endregion

  // --- Transaction form ------------------------------------------------------
  // region transaction form (WP-9)

  @override
  String get txFormNewTitle => 'New Transaction';
  @override
  String get txFormEditTitle => 'Edit Transaction';
  @override
  String get txFormAccount => 'Account';
  @override
  String get txFormTargetAccount => 'To account';
  @override
  String get txFormCategory => 'Category';
  @override
  String get txFormDate => 'Date';
  @override
  String get txFormDescription => 'Description';
  @override
  String get txFormEnterAmount => 'Enter an amount';
  @override
  String get txFormSelectAccount => 'Pick an account';
  @override
  String get txFormSelectTargetAccount => 'Pick a target account';
  @override
  String get txFormAccountsMustDiffer =>
      'The two accounts have to be different';
  @override
  String get txFormNote => 'Note';
  @override
  String get txFormAmount => 'Amount';
  @override
  String get txFilterGroupExpense => 'EXPENSE';
  @override
  String get txFilterGroupIncome => 'INCOME';
  @override
  String get txFilterCustomRange => 'Custom range';
  @override
  String get txFormTransferSameCurrency =>
      'Transfers go between accounts in the same currency.';
  @override
  String get txFormNoTransferTarget => 'No other account uses this currency';
  @override
  String get txFormNeedAccount => 'Create an account first';
  @override
  String get txFormAccountsLoading => 'Loading accounts…';
  @override
  String get txFormAccountsFailed =>
      'Couldn\'t load your accounts. Tap to try again.';
  // endregion

  // --- Forms, keypad and undo -----------------------------------------------
  // region forms and controls (WP-2)

  @override
  String get actionAdd => 'Add';
  @override
  String get actionDone => 'Done';
  @override
  String get actionArchive => 'Archive';
  @override
  String get actionRestore => 'Restore';
  @override
  String get actionMoreOptions => 'More options';
  @override
  String get labelOptional => 'optional';
  @override
  String get formDiscardTitle => 'Your changes aren\'t saved';
  @override
  String get formKeepEditing => 'Keep editing';
  @override
  String get formDiscard => 'Discard changes';
  @override
  String amountTooLarge(String max) => 'The most you can enter is $max';
  @override
  String get keypadBackspace => 'Delete last digit';
  @override
  String get keypadDecimalMark => 'Decimal point';
  @override
  String get keypadClearHint => 'Long-press to clear';
  @override
  String get errDeleteFailed => 'Couldn\'t delete it; it\'s back';
  @override
  String colorSwatch(int index) => 'Color $index';
  @override
  String get actionSeeAllShort => 'See all';
  @override
  String get actionHide => 'Hide';
  @override
  String get captureBarSemantics => 'Quick add';
  @override
  String get moneyGlanceThisMonth => 'This month';
  @override
  String moneyGlanceSemantics(String amount) =>
      'Net this month $amount, open Finance';
  @override
  String get moneyGlanceStart => 'Start with a cash account';
  // endregion

  // --- Numbers, progress, motion and celebrations ----------------------------
  // region numbers and motion (WP-3)
  @override
  String get dayHeaderMoveAllToToday => 'Move all to today';
  @override
  String chartAverage(String amount) => 'avg $amount';
  @override
  String chartPaceTooltip(String date, String amount, String? previous) =>
      previous == null
          ? '$date · $amount'
          : '$date · $amount / last month $previous';
  @override
  String lingeringFinished(int count) => '$count done';
  @override
  String milestoneStreak(int days, String habit) =>
      '${days == 1 ? '1 day' : '$days days'} · $habit';
  @override
  String get milestonePerfectWeek => 'First perfect week';
  @override
  String milestoneGoal(String goal) => 'Goal reached · $goal';
  @override
  String get milestoneDismissHint => 'Tap to dismiss';
  // endregion

  // --- Finance: setup, accounts, menus --------------------------------------
  // region accounts (WP-8)

  @override
  String get financeAccounts => 'Accounts';
  @override
  String get financeAddTransactionFab => 'Transaction';
  @override
  String get financeMenuCategories => 'Categories';
  @override
  String get financeMenuSubscriptions => 'Subscriptions';
  @override
  String get financeMenuArchivedAccounts => 'Archived accounts';
  @override
  String get financeFirstRunTitle => 'Create your first account';
  @override
  String get financeFirstRunBody =>
      'Add wherever your money lives: cash, a bank account or a credit '
      'card. Then record your first transaction.';
  @override
  String get financeFirstRunCash => 'Start with a cash account';
  @override
  String get financeFirstRunOther => 'Add another kind of account';
  @override
  String get financeCashAccountName => 'Cash';
  @override
  String get financeFirstTxTitle => 'Add your first transaction';
  @override
  String get financeFirstTxBody =>
      'Record an expense or an income; your balance and this month\'s '
      'summary update from here.';
  @override
  String get financeFirstTxAction => 'Add a transaction';
  @override
  String get financeNoActiveAccounts => 'You have no active accounts';
  @override
  String get financeNoActiveAccountsBody =>
      'All your accounts are archived. Restore one or open a new account.';
  @override
  String get financeUncategorized => 'Uncategorized';
  @override
  String get financeCategorize => 'Categorize';
  @override
  String get financeOtherCategories => 'Other';
  @override
  String get financeSliceAll => 'All';
  @override
  String get financeSliceAllMeta => 'Subcategories included';
  @override
  String financeSliceDirect(String name) => '$name (direct)';
  @override
  String get financeBudgetsEmpty =>
      'Set a monthly limit on a category — see the month\'s end coming';
  @override
  String financeBudgetSpentOf(String spent, String limit) => '$spent of $limit';
  @override
  String financeOverBy(String amount) => '$amount over';
  @override
  String get financeNoUpcomingPayments => 'Nothing due in the next 30 days';
  @override
  String get financeAddSubscription => 'Add subscription';
  @override
  String get financeSubscriptionsEmpty =>
      'Add your regular payments and see your fixed costs as one number.';
  @override
  String get financeSubscriptionsGhost => 'Add your regular payments';
  @override
  String accountsTotal(String totals) => 'Total $totals';
  @override
  String get accountsTotalsTitle => 'Totals by currency';
  @override
  String get accountFab => 'Account';
  @override
  String accountTileSemantics(String name, String type, String balance) =>
      '$name, $type, $balance';
  @override
  String accountTypeOverline(String type) => switch (type) {
        'cash' => 'CASH',
        'bank' => 'BANK',
        'credit_card' => 'CREDIT CARD',
        'savings' => 'SAVINGS',
        'crypto' => 'CRYPTO',
        _ => 'ACCOUNT',
      };
  @override
  String accountMonthSummary(String? income, String? expense) =>
      'This month ${[
        if (income != null) '$income in',
        if (expense != null) '$expense out',
      ].join(' · ')}';
  @override
  String get accountReconcile => 'Reconcile balance';
  @override
  String accountLinkedGoals(int count) => 'Linked goals ($count)';
  @override
  String get reconcileTitle => 'Actual balance';
  @override
  String reconcileNowAndDifference(String now, String? difference) =>
      difference == null
          ? 'Now: $now'
          : 'Now: $now · Difference: $difference';
  @override
  String get reconcileDone => 'Balance reconciled';
  @override
  String get reconcileFailed => 'Could not reconcile the balance';
  @override
  String get reconcileUndoFailed => 'Could not go back to the old balance';
  @override
  String get accountDefaultBadge => 'Default';
  // endregion

  // --- Account form, archive, delete ----------------------------------------
  // region account form (WP-8)

  @override
  String get accountFormNewTitle => 'New account';
  @override
  String get accountFormEditTitle => 'Edit account';
  @override
  String get accountFormType => 'Account type';
  @override
  String get accountFormName => 'Account name';
  @override
  String get accountFormNameRequired => 'Enter a name';
  @override
  String get accountFormCurrency => 'Currency';
  @override
  String get accountFormCurrencyLocked =>
      'This account has transactions or subscriptions, so its currency '
      'can\'t change.';
  @override
  String get accountFormOpeningBalance => 'Opening balance';
  @override
  String get accountFormOpeningBalanceHint =>
      'What the account holds today. Enter a credit card\'s debt as “Debt”.';
  @override
  String get accountFormDebt => 'Debt';
  @override
  String get accountFormColor => 'Color';
  @override
  String get accountFormCreate => 'Create account';
  @override
  String get accountNew => 'New account';
  @override
  String accountCreated(String name) => 'Account “$name” is ready';
  @override
  String get accountUpdated => 'Account updated';
  @override
  String get accountSaveFailed => 'Couldn\'t save the account';
  @override
  String accountArchived(String name) => '“$name” archived';
  @override
  String accountRestored(String name) => '“$name” restored';
  @override
  String get accountArchiveFailed => 'Couldn\'t archive the account';
  @override
  String get accountRestoreFailed => 'Couldn\'t restore the account';
  @override
  String get accountArchivedBadge => 'Archived';
  @override
  String get accountArchivedNote =>
      'This account is archived: it\'s hidden from lists and pickers, and '
      'its transactions still count in every total.';
  @override
  String accountDeleted(String name) => '“$name” deleted';
  @override
  String get accountDeleteFailed => 'Couldn\'t delete the account';
  @override
  String get accountCantDeleteTitle => 'This account can\'t be deleted';
  @override
  String accountCantDeleteArchived(int transactions, int incomingTransfers) {
    final history = [
      if (transactions > 0)
        transactions == 1 ? '1 transaction' : '$transactions transactions',
      if (incomingTransfers > 0)
        incomingTransfers == 1
            ? '1 incoming transfer'
            : '$incomingTransfers incoming transfers',
    ];
    final has = history.isEmpty
        ? ''
        : 'This account has ${history.join(' and ')}. ';
    return '${has}An account with history can\'t be deleted; it stays '
        'archived, and its transactions keep counting in your totals.';
  }
  @override
  String accountDeleteTitle(String name) => 'Delete “$name”?';
  @override
  String accountDeleteConsequences({
    required int subscriptions,
    required int goals,
  }) =>
      [
        if (subscriptions == 1)
          'The subscription paid from it is deleted too.'
        else if (subscriptions > 1)
          'The $subscriptions subscriptions paid from it are deleted too.',
        if (goals == 1)
          'The goal linked to it is unlinked and tracks all your income '
              'from then on.'
        else if (goals > 1)
          'The $goals goals linked to it are unlinked and track all your '
              'income from then on.',
      ].join(' ');
  @override
  String get accountGone => 'This account was deleted';
  @override
  String get titleArchivedAccounts => 'Archived accounts';
  @override
  String get archivedAccountsEmpty => 'No archived accounts';
  @override
  String get archivedAccountsBody =>
      'Accounts you archive wait here; restore one whenever you like.';
  @override
  String get accountFormDefault => 'Default account';
  @override
  String get accountFormDefaultHint =>
      'New transactions start on it · on this device';
  // endregion

  // --- Finance categories ----------------------------------------------------
  // region categories (WP-10)

  @override
  String get titleCategories => 'Categories';
  @override
  String get categoriesEmptyExpense => 'No expense categories yet';
  @override
  String get categoriesEmptyIncome => 'No income categories yet';
  @override
  String get categoriesEmptyBody =>
      'Categories group your spending, and budgets go on them.';
  @override
  String get categoriesAddFab => 'Category';
  @override
  String get categoriesStarter => 'Add starter categories';
  @override
  String get categoriesStarterAdded => 'Starter categories added';
  @override
  String get categoriesStarterFailed =>
      'Some categories couldn\'t be added, try again';
  @override
  List<String> starterCategories(String kind) => kind == 'income'
      ? const ['Salary', 'Other income']
      : const [
          'Groceries',
          'Transport',
          'Bills',
          'Rent',
          'Food',
          'Health',
          'Entertainment',
          'Other',
        ];
  @override
  String get categoryNew => 'New category';
  @override
  String get categoryFormNewTitle => 'New category';
  @override
  String get categoryFormEditTitle => 'Edit category';
  @override
  String get categoryFormName => 'Category name';
  @override
  String get categoryFormNameRequired => 'Enter a name';
  @override
  String get categoryFormKind => 'Type';
  @override
  String get categoryFormKindLocked =>
      'It\'s in use, so its type can\'t change.';
  @override
  String get categoryFormParent => 'Parent category';
  @override
  String get categoryFormNoParent => 'None — top level';
  @override
  String get categoryFormParentLocked =>
      'It has subcategories, so it can\'t move under another category.';
  @override
  String get categoryFormColor => 'Color';
  @override
  String categoryCreated(String name) => '“$name” added';
  @override
  String get categoryUpdated => 'Category updated';
  @override
  String get categorySaveFailed => 'Couldn\'t save the category';
  @override
  String categoryDeleted(String name) => '“$name” deleted';
  @override
  String categoryDeleteTitle(String name) => 'Delete “$name”?';
  @override
  String categoryDeleteImpact({
    required int transactions,
    required int subscriptions,
    required int children,
    required int budgets,
  }) {
    String count(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';
    return [
      if (transactions > 0)
        '${count(transactions, 'transaction', 'transactions')} will be '
            'left uncategorized.',
      if (subscriptions > 0)
        '${count(subscriptions, 'subscription', 'subscriptions')} will be '
            'left uncategorized.',
      if (children > 0)
        '${count(children, 'subcategory', 'subcategories')} will be deleted '
            'with it.',
      if (budgets > 0)
        '${count(budgets, 'budget', 'budgets')} will be deleted.',
    ].join(' ');
  }

  @override
  String get categoryDeleteFailed => 'Couldn\'t delete the category';
  @override
  String categoryChildren(int count) =>
      count == 1 ? '1 subcategory' : '$count subcategories';
  @override
  String get categoryLoadFailed => 'Couldn\'t load the category';
  // endregion

  // --- Budgets ---------------------------------------------------------------
  // region budgets (WP-10)

  @override
  String get budgetNewTitle => 'New budget';
  @override
  String budgetEditTitle(String category) => '$category budget';
  @override
  String get budgetCategory => 'Category';
  @override
  String get budgetLimit => 'Monthly limit';
  @override
  String get budgetLimitRequired => 'Enter a limit above zero';
  @override
  String get budgetPickCategory => 'Pick a category';
  @override
  String get budgetNoCategories =>
      'There\'s no expense category left to budget. Add one first.';
  @override
  String budgetCurrencyNote(String currency) =>
      'Budgets are kept in your profile currency ($currency).';
  @override
  String get budgetCreated => 'Budget added';
  @override
  String get budgetUpdated => 'Budget updated';
  @override
  String get budgetSaveFailed => 'Couldn\'t save the budget';
  @override
  String get budgetRemove => 'Remove budget';
  @override
  String budgetRemoved(String category) => '“$category” budget removed';
  // endregion

  // --- Subscriptions ---------------------------------------------------------
  // region subscriptions (WP-10)

  @override
  String get titleSubscriptions => 'Subscriptions';
  @override
  String subscriptionsMonthly(String amount) =>
      'Your fixed costs: $amount a month';
  @override
  String subscriptionsYearly(String amount) => '$amount a year';
  @override
  String get subscriptionsActive => 'Active';
  @override
  String get subscriptionsPaused => 'Paused';
  @override
  String get subscriptionsEmpty => 'No subscriptions yet';
  @override
  String get subscriptionsAddFab => 'Subscription';
  @override
  String get subscriptionFormNewTitle => 'New subscription';
  @override
  String get subscriptionFormEditTitle => 'Edit subscription';
  @override
  String get subscriptionFormName => 'Name';
  @override
  String get subscriptionFormNameHint => 'e.g. Netflix, rent, gym';
  @override
  String get subscriptionFormNameRequired => 'Enter a name';
  @override
  String get subscriptionFormAmount => 'Amount';
  @override
  String get subscriptionFormAmountRequired => 'Enter an amount above zero';
  @override
  String get subscriptionFormFrequency => 'Repeats';
  @override
  String get subscriptionFormAccount => 'Account';
  @override
  String get subscriptionFormNextCharge => 'Next payment';
  @override
  String get subscriptionFormNextChargeAuto => 'One period from now';
  @override
  String get subscriptionFormCategory => 'Category';
  @override
  String get subscriptionFormVendor => 'Vendor';
  @override
  String get subscriptionFormNote => 'Note';
  @override
  String get subscriptionFormColor => 'Color';
  @override
  String get subscriptionFormMore => 'More details';
  @override
  String get subscriptionCreated => 'Subscription added';
  @override
  String get subscriptionUpdated => 'Subscription updated';
  @override
  String get subscriptionSaveFailed => 'Couldn\'t save the subscription';
  @override
  String subscriptionAmountPer(String amount, String frequency) =>
      switch (frequency) {
        'weekly' => '$amount / week',
        'yearly' => '$amount / year',
        _ => '$amount / month',
      };
  @override
  String subscriptionNextOn(String date) => 'Next payment: $date';
  @override
  String get subscriptionNoDate => 'No payment date';
  @override
  String get subscriptionOverdue => 'Overdue';
  @override
  String get subscriptionPausedLabel => 'Paused';
  @override
  String get subscriptionCharge => 'Record payment';
  @override
  String subscriptionCharged(String amount) => 'Payment recorded · $amount';
  @override
  String get subscriptionChargeFailed => 'Couldn\'t record the payment';
  @override
  String get subscriptionChargeMaybe =>
      'The server didn\'t answer in time — the payment may have been '
      'recorded. Check your transactions before trying again.';
  @override
  String get subscriptionPause => 'Pause';
  @override
  String get subscriptionResume => 'Resume';
  @override
  String subscriptionPausedDone(String name) => '“$name” paused';
  @override
  String subscriptionResumedDone(String name) => '“$name” is active again';
  @override
  String get subscriptionToggleFailed => 'Couldn\'t update the subscription';
  @override
  String subscriptionDeleted(String name) => '“$name” deleted';
  // endregion

  // --- Habits ---------------------------------------------------------------
  // region habits (WP-11)

  @override
  String habitsDoneOfTotal(int done, int total) => '$done / $total done';
  @override
  String get habitsAllDone => 'All done';
  @override
  String get habitsPerfectChain => 'Perfect-day chain';
  @override
  String get habitsPerfectHistory => 'Perfect-day history';
  @override
  String habitsPerfectStreak(int streak, int record) =>
      'Perfect streak: $streak ${streak == 1 ? 'day' : 'days'} · Best: $record';
  @override
  String get habitsHistory => 'History';
  @override
  String get habitsCreateFirst => 'Create your first habit';
  @override
  String get habitsStartSmall => 'Start small';
  @override
  String get habitsAdd => 'Add habit';
  @override
  String get habitsToggleFailed => 'Couldn\'t check it off, try again';
  @override
  String habitsMeta(int streak, int rate) => 'Streak $streak · $rate% (30d)';
  @override
  String get habitsThisWeek => 'This week';
  @override
  String get habitsThisMonth => 'This month';
  @override
  String habitsPeriodProgress(String period, int done, int target) =>
      '$period $done/$target';
  @override
  String get habitsStatStreak => 'Streak';
  @override
  String get habitsStatRecord => 'Best';
  @override
  String get habitsStatRate30d => '30d rate';
  @override
  String get habitsLast30Days => 'Last 30 days';
  @override
  String get habitsLast84Days => 'Last 84 days';
  @override
  String get habitsLegendDone => 'Done';
  @override
  String get habitsLegendPartial => 'Partial';
  @override
  String get habitsLegendMissed => 'Missed';
  @override
  String get habitsArchive => 'Archive';
  @override
  String habitsArchiveBody(String name) =>
      '$name leaves Today and the list and can no longer be logged. Its '
      'history is kept; you can restore it from the Archive.';
  @override
  String get habitsArchiveTitle => 'Archive this habit?';
  @override
  String get habitsArchived => 'Archived';
  @override
  String get habitsArchiveFailed => 'Couldn\'t archive it, try again';
  @override
  String get habitsFormNewTitle => 'New habit';
  @override
  String get habitsFormName => 'Habit name';
  @override
  String get habitsFormNameHint => 'e.g. Drink water, run, read';
  @override
  String get habitsFormNameRequired => 'Give it a name';
  @override
  String get habitsFormFrequency => 'Frequency';
  @override
  String get habitsFormDaily => 'Daily';
  @override
  String get habitsFormWeekly => 'Weekly';
  @override
  String get habitsFormMonthly => 'Monthly';
  @override
  String get habitsFormColor => 'Colour';
  @override
  String get habitsFormDailyTarget => 'Daily target';
  @override
  String get habitsFormPeriodTarget => 'Period target';
  @override
  String get habitsFormGoalLink => 'Linked goal (optional)';
  @override
  String get habitsFormLinkGoal => 'Link to a goal';
  @override
  String get habitsAdded => 'Habit added';
  @override
  String get habitsSaveFailed => 'Couldn\'t save, try again';
  @override
  String get habitsFormEditTitle => 'Edit habit';
  @override
  String get habitsFormDescription => 'Description (optional)';
  @override
  String get habitsFormDescriptionHint => 'e.g. Before breakfast, 2 glasses';
  @override
  String get habitsFormHistoryNote =>
      'Past days stay as they were logged; the change applies from today.';
  @override
  String get habitsUpdated => 'Habit updated';
  @override
  String habitsArchiveFreezes(String goals) =>
      'These goals count this habit\'s completed days: $goals. '
      'Archiving it stops their progress: no new days are added.';
  @override
  String habitsArchivedNamed(String name) => '“$name” archived';
  @override
  String get habitsUnarchive => 'Restore';
  @override
  String habitsUnarchived(String name) => '“$name” is active again';
  @override
  String get habitsUnarchiveFailed => 'Couldn\'t restore the habit';
  @override
  String get habitsDelete => 'Delete habit';
  @override
  String habitsDeleteTitle(String name) => 'Delete “$name”?';
  @override
  String habitsDeleteBody({required int days, required String goals}) {
    final logs = days == 0
        ? 'No days have been logged yet.'
        : 'The log of $days ${days == 1 ? 'day' : 'days'}, its streaks and '
            'rates are deleted for good.';
    final linked = goals.isEmpty
        ? ''
        : ' Goals that count this habit ($goals) are unlinked and keep their '
            'last value; you log their progress by hand from then on.';
    return '$logs$linked This can\'t be undone.';
  }

  @override
  String habitsDeleted(String name) => '“$name” deleted';
  @override
  String get habitsDeleteFailed => 'Couldn\'t delete the habit';
  @override
  String get habitsArchivedTitle => 'Archived habits';
  @override
  String get habitsArchivedEmpty => 'No archived habits';
  @override
  String get habitsArchivedEmptyBody =>
      'Habits you archive stay here with their history.';
  @override
  String habitsArchivedOn(String date) => 'Archived $date';
  @override
  String get habitsArchivedNote =>
      'Archived: it can\'t be logged and stays off Today. Its history is kept.';
  @override
  String habitsTrackedBy(String goals) => 'Counted by goals: $goals';
  @override
  String habitsServesGoal(String goal) => 'Goal: $goal';
  @override
  String get habitsCalendar => 'Calendar';
  @override
  String get habitsCalendarHint => 'Tap a day to fix its log.';
  @override
  String get habitsPrevMonth => 'Previous month';
  @override
  String get habitsNextMonth => 'Next month';
  @override
  String get habitsDayFuture => 'Future days can\'t be logged.';
  @override
  String habitsDayBeforeStart(String date) =>
      'This habit didn\'t exist yet on that day (it starts on $date).';
  @override
  String get habitsDayDone => 'Done';
  @override
  String get habitsDayNotDone => 'Not done';
  @override
  String habitsDaySemantics(
    String date, {
    required int count,
    required int target,
    required bool done,
    required bool loggable,
  }) {
    final state = done
        ? 'done'
        : count > 0
            ? '$count of $target'
            : 'not done';
    return loggable ? '$date, $state' : '$date, $state, can\'t be logged';
  }
  @override
  String get habitsNew => 'New';
  @override
  String get habitsMenuArchive => 'Archive';
  @override
  String habitsAddedNamed(String name) => '“$name” added';
  @override
  String get habitsPickFirst => 'Pick your first habit';
  @override
  String get habitsStarterBody =>
      'Tap one to add it now — you can edit it later.';
  @override
  String get habitsStarterWater => 'Water';
  @override
  String get habitsStarterWaterChip => 'Water · 8 a day';
  @override
  String get habitsStarterWalk => 'Walk';
  @override
  String get habitsStarterRead => 'Reading';
  @override
  String get habitsStarterReadChip => 'Reading · 10 pages';
  @override
  String get habitsStarterSleep => 'Early bedtime';
  @override
  String get habitsStarterMeditate => 'Meditation';
  @override
  String get habitsStarterCustom => 'Custom…';
  @override
  String habitsDoneOfTotalRest(int total) => ' / $total done';
  @override
  String habitsPerfectMeta(int streak, int record) =>
      'Perfect streak $streak · Best $record';
  @override
  String habitsRate30d(int rate) => '$rate% (30d)';
  @override
  String get habitsDayStateDone => 'done';
  @override
  String get habitsDayStatePartial => 'partial';
  @override
  String get habitsDayStateMissed => 'missed';
  @override
  String get habitsDayStatePending => 'pending';
  @override
  String get habitsDayStateNone => 'no log';
  @override
  String get habitsLegendToday => 'Today';
  @override
  String get habitsDayCannotLog => 'Can\'t be logged';
  @override
  String habitsStartedOn(String date) => 'Started $date';
  @override
  String habitsCadenceDaily(int target) =>
      target == 1 ? 'Daily' : 'Daily · $target/day';
  @override
  String habitsCadenceWeekly(int target) =>
      'Weekly · $target ${target == 1 ? 'day' : 'days'}';
  @override
  String habitsCadenceMonthly(int target) =>
      'Monthly · $target ${target == 1 ? 'day' : 'days'}';
  @override
  String get habitsTrackingGoals => 'Goals tracking it';
  @override
  String get habitsSetGoal => 'Set a goal for this habit';
  @override
  String get habitsDeleteForever => 'Delete for good';
  @override
  String habitsTargetDaily(int target) =>
      target == 1 ? 'once a day' : '$target times a day';
  @override
  String habitsTargetWeekly(int target) =>
      '$target ${target == 1 ? 'day' : 'days'} a week';
  @override
  String habitsTargetMonthly(int target) =>
      '$target ${target == 1 ? 'day' : 'days'} a month';
  @override
  String get habitsTargetTypeHint => 'Tap to type the target';
  @override
  String get habitsFormMore => 'More';
  @override
  String habitsFormStarted(String date) => 'Started: $date';
  // endregion

  // --- Goals ----------------------------------------------------------------
  // region goals (WP-12)

  @override
  String get goalsTypeFinancial => 'FINANCIAL';
  @override
  String get goalsTypeHabit => 'HABIT';
  @override
  String get goalsTypeCustom => 'CUSTOM';
  @override
  String get goalsStatusAchieved => 'Achieved';
  @override
  String get goalsStatusAbandoned => 'Abandoned';
  @override
  String get goalsStatusActive => 'Active';
  @override
  String get goalsSectionActive => 'Active';
  @override
  String get goalsSectionAchieved => 'Achieved';
  @override
  String get goalsSectionAbandoned => 'Abandoned';
  @override
  String get goalsSetFirst => 'Set your first goal';
  @override
  String get goalsSetFirstBody => 'Pick a target and track it from here.';
  @override
  String get goalsAdd => 'Add goal';
  @override
  String goalsOverdueBadge(int days) => '${days}d late';
  @override
  String get goalsDueTodayBadge => 'today';
  @override
  String goalsDaysLeftBadge(int days) => '${days}d left';
  @override
  String get goalsDetailStatus => 'Status';
  @override
  String get goalsDetailDeadline => 'Deadline';
  @override
  String get goalsDetailDaysLeft => 'Days left';
  @override
  String get goalsDetailProgress => 'Progress';
  @override
  String get goalsHabitProgress => 'Habit progress';
  @override
  String goalsStreakDays(int days) => '$days-day streak';
  @override
  String get goalsLinkedAccount => 'Linked account';
  @override
  String get goalsCurrentBalance => 'Current balance';
  @override
  String get goalsRefresh => 'Refresh';
  @override
  String get goalsEnterValue => 'Enter a value';
  @override
  String get goalsMarkAbandoned => 'Mark as abandoned';
  @override
  String get goalsAbandonAction => 'Abandon';
  @override
  String get goalsActionFailed => 'That didn\'t work';
  @override
  String get goalsLoadFailed => 'Couldn\'t load the goal';
  @override
  String get goalsGone => 'This goal was deleted';
  @override
  String goalsProgressDays(String current, String target) =>
      '$current / $target days';
  @override
  String get goalsFormNewTitle => 'New goal';
  @override
  String get goalsFormName => 'Goal name';
  @override
  String get goalsFormNameRequired => 'A name is required';
  @override
  String get goalsFormDescription => 'Description (optional)';
  @override
  String get goalsFormType => 'Type';
  @override
  String get goalsFormTypeCustom => 'Custom';
  @override
  String get goalsFormTypeHabit => 'Habit';
  @override
  String get goalsFormTypeFinancial => 'Financial';
  @override
  String get goalsFormColor => 'Colour';
  @override
  String get goalsFormTargetValue => 'Target value';
  @override
  String get goalsFormTargetRequired => 'Enter a valid target value';
  @override
  String goalsNumberAmbiguous(String mark) =>
      'Ambiguous number: use “$mark” for decimals and no thousands separator';
  @override
  String get goalsFormUnit => 'Unit';
  @override
  String get goalsFormUnitHint => 'kg · days · TRY';
  @override
  String get goalsFormEndDate => 'Deadline';
  @override
  String get goalsFormLinkedAccount => 'Linked account';
  @override
  String get goalsFormLinkedHabit => 'Linked habit';
  @override
  String get goalsFormSubmit => 'Create goal';
  @override
  String get goalsCreated => 'Goal created';
  @override
  String get goalsCreateFailed => 'Couldn\'t create the goal';
  @override
  String get goalsFormEditTitle => 'Edit goal';
  @override
  String get goalsUpdated => 'Goal updated';
  @override
  String get goalsSaveFailed => 'Couldn\'t save the goal';
  @override
  String get goalsFormCurrentValue => 'Progress so far';
  @override
  String get goalsFormNoDeadline => 'None';
  @override
  String get goalsFormClearDeadline => 'Remove end date';
  @override
  String get goalsFormTypeChangeNote =>
      'Changing the type removes the old link; the goal keeps its current value.';
  @override
  String get goalsReopen => 'Reopen';
  @override
  String get goalsReopened => 'Goal reopened';
  @override
  String get goalsReopenTitle => 'Reopen goal';
  @override
  String goalsReopenNeedsHigherTarget(String current) =>
      'Its progress already reaches the target ($current). Enter a higher '
      'target to reopen it.';
  @override
  String get goalsReopenNewTarget => 'New target';
  @override
  String goalsReopenTargetTooLow(String current) =>
      'The target must be above the current progress ($current)';
  @override
  String get goalsMarkAchieved => 'Mark as achieved';
  @override
  String get goalsMarkedAchieved => 'Goal achieved';
  @override
  String get goalsAbandonedSnack => 'Goal abandoned';
  @override
  String get goalsDelete => 'Delete goal';
  @override
  String goalsDeleted(String name) => '“$name” deleted';
  @override
  String get goalsDeleteFailed => 'Couldn\'t delete the goal';
  @override
  String get goalsLinkAccount => 'Link an account';
  @override
  String get goalsLinkHabit => 'Link a habit';
  @override
  String get goalsChangeLink => 'Change link';
  @override
  String get goalsNoHabitLinked =>
      'No habit linked: you log progress by hand. Link a habit and its '
      'completed days are counted.';
  @override
  String get goalsNoAccountLinked =>
      'No account linked: progress counts all your income. Link an account '
      'to track its balance.';
  @override
  String goalsLinked(String name) => '“$name” linked';
  @override
  String get goalsUnlinked => 'Link removed';
  @override
  String get goalsTotalIncome => 'Total income';
  @override
  String goalsDaysOverdue(int days) =>
      '$days ${days == 1 ? 'day' : 'days'} past';
  @override
  String get goalsMore => 'More actions';
  // endregion

  // --- Journal --------------------------------------------------------------
  // region journal (WP-13)

  @override
  String journalEntriesCount(int count) =>
      count == 1 ? '1 entry' : '$count entries';
  @override
  String get journalNoEntryForMood => 'No entries with this mood';
  @override
  String get journalHowWasToday => 'How was today?';
  @override
  String get journalWriteFirst => 'Write your first entry';
  @override
  String get journalCreateEntry => 'New entry';
  @override
  String get journalUntitled => 'Untitled';
  @override
  String get journalEnergy => 'Energy';
  @override
  String get journalGratitude => 'GRATITUDE';
  @override
  String get journalDeleteFailed => 'Couldn\'t delete the entry';
  @override
  String get journalLoadFailed => 'Couldn\'t load the entry';
  @override
  String get journalGone => 'This journal entry was deleted';
  @override
  String get journalEditorNewTitle => 'New entry';
  @override
  String get journalEditorEditTitle => 'Edit';
  @override
  String get journalEditorTitleHint => 'Title';
  @override
  String get journalEditorBodyHint => 'What happened today?';
  @override
  String get journalEditorTags => 'TAGS';
  @override
  String get journalEditorTagsHint => 'comma separated: walk, family';
  @override
  String get journalEditorGratitudeHint => 'What are you grateful for today?';
  @override
  String get journalEditorMoodPrompt => 'How are you feeling today?';
  @override
  String get journalEditorWeather => 'Weather';
  @override
  String get journalEditorNeedsContent => 'Write a title or a few lines';
  @override
  String get journalUpdated => 'Updated';
  @override
  String get journalAdded => 'Entry added';
  @override
  String get journalSaveFailed => 'Couldn\'t save the entry';
  @override
  String journalRichNotice(String formatting) =>
      'This entry has formatting from the web ($formatting). You can safely '
      'edit its title, mood and tags; changing the text removes the '
      'formatting.';
  @override
  String get journalRichConfirmTitle => 'Remove the formatting?';
  @override
  String journalRichConfirmBody(String formatting) =>
      'You changed the text. Saving removes the formatting added on the web '
      '($formatting) and keeps your writing as plain text.';
  @override
  String get journalRichConfirmAction => 'Save anyway';
  @override
  String journalFormatting(String kind) => switch (kind) {
        'bold' => 'bold',
        'italic' => 'italic',
        'strikethrough' => 'strikethrough',
        'link' => 'links',
        'heading' => 'headings',
        'quote' => 'quotes',
        'code' => 'code',
        'list' => 'lists',
        'attachment' => 'attachments',
        _ => 'other',
      };
  @override
  String get journalDraftRestored => 'Unsaved draft restored';
  @override
  String get journalDraftDiscard => 'Discard draft';
  @override
  String get journalDraftRestoredStale =>
      'Draft restored. This entry has changed elsewhere since; check it before saving';
  @override
  String get journalEditorEntryGone =>
      'This entry was deleted elsewhere. Your text is still here; you can save it as a new entry';
  @override
  String get journalEditorSaveAsNew => 'Save as new entry';
  @override
  String get journalDeleted => 'Entry deleted';
  @override
  String get journalEditorMood => 'Mood';
  @override
  String get journalEditorMoodClear => 'Clear mood';

  @override
  String moodLabel(String mood) => switch (mood) {
        'great' => 'Great',
        'good' => 'Good',
        'neutral' => 'Okay',
        'bad' => 'Bad',
        'awful' => 'Awful',
        _ => mood,
      };

  @override
  String weatherLabel(String weather) => switch (weather) {
        'sunny' => 'Sunny',
        'partly_cloudy' => 'Partly cloudy',
        'cloudy' => 'Cloudy',
        'rainy' => 'Rainy',
        'snowy' => 'Snowy',
        _ => weather,
      };

  @override
  String journalRange(String range) => switch (range) {
        '7d' => '7d',
        '30d' => '30d',
        '6mo' => '6mo',
        '1y' => '1y',
        _ => 'All',
      };
  // endregion

  // --- Profile and server settings ------------------------------------------
  // region profile (WP-14)

  @override
  String get profileSectionApp => 'App';
  @override
  String get profileTheme => 'Theme';
  @override
  String get profileThemeDark => 'Dark';
  @override
  String get profileThemeLight => 'Light';
  @override
  String get profileThemeSystem => 'System';
  @override
  String get profileLanguage => 'Language';
  @override
  String get profileLanguageTr => 'Türkçe';
  @override
  String get profileLanguageEn => 'English';
  @override
  String get profileCurrency => 'Currency';
  @override
  String get profileTimeZone => 'Time zone';
  @override
  String profileTimeZoneValue(String zone, String offset) =>
      '$zone (UTC$offset)';
  @override
  String profileTimeZoneDeviceDiffers(String deviceOffset) =>
      'This device is on UTC$deviceOffset. Days and times follow your '
      'account\'s time zone.';
  @override
  String get profileSectionServer => 'Server';
  @override
  String get profileSectionAbout => 'About';
  @override
  String get profileVersion => 'Version';
  @override
  String get profileApiStatus => 'API status';
  @override
  String get profileApiOnline => 'Online';
  @override
  String get profileApiUnreachable => 'Unreachable';
  @override
  String get profileSignOut => 'Sign Out';
  @override
  String get profileSignOutTitle => 'Sign out?';
  @override
  String get profileSignOutBody =>
      'This signs out every device signed in to this account: each account '
      'has a single session key. The server address stays on this phone.';
  @override
  String get profileFallbackName => 'User';
  @override
  String get profileLanguageSaveFailed =>
      'Couldn\'t save the language to the server — it applies on this device';
  @override
  String get profileThemeSaveFailed =>
      'Couldn\'t save the theme to the server — it applies on this device';
  @override
  String get profileSignOutEverywhere => 'Signs out on every device';
  @override
  String get profileSignOutDraft =>
      'Your unsaved journal draft will be deleted from this phone.';
  @override
  String get noticeSignOutNotRevoked =>
      'Signed out on this phone, but the server couldn\'t be reached: the '
      'session couldn\'t be ended there, so other devices may stay signed in.';
  @override
  String get profileSectionAccount => 'Account';
  @override
  String get profileName => 'Name';
  @override
  String get profileEmail => 'Email';
  @override
  String get profilePassword => 'Password';
  @override
  String get profilePasswordAction => 'Change';
  @override
  String get profileEditName => 'Edit your name';
  @override
  String get profileNameHint => 'How you appear in the app and on the web.';
  @override
  String get profileNameSaved => 'Name updated';
  @override
  String get profileEmailTitle => 'Email address';
  @override
  String get profileEmailNew => 'New email';
  @override
  String get profileEmailNote =>
      'Your email is how you sign in, so changing it needs your current '
      'password.';
  @override
  String get profileEmailSaved => 'Email updated';
  @override
  String get profileCurrentPassword => 'Current password';
  @override
  String get profileNewPassword => 'New password';
  @override
  String get profileConfirmPassword => 'Confirm new password';
  @override
  String get profilePasswordTitle => 'Change password';
  @override
  String get profilePasswordNote =>
      'Changing it signs out every other device; this phone stays signed in.';
  @override
  String get profilePasswordSaved =>
      'Password changed. You\'ll need to sign in again on your other devices.';
  @override
  String get profileShowPassword => 'Show password';
  @override
  String get profileHidePassword => 'Hide password';
  @override
  String get profileRateLimited =>
      'Too many password attempts. Wait a few minutes and try again.';
  @override
  String get profileSaveFailed => 'Couldn\'t save · Try again';
  @override
  String get profileOptionsFailed => 'Couldn\'t load the options';
  @override
  String get profileCurrencyNote => 'Existing amounts aren\'t converted.';
  @override
  String profileCurrencyConfirmTitle(String code) => 'Switch to $code?';
  @override
  String profileCurrencyConfirmBody(String before, String after) =>
      'Nothing is converted: budget limits and totals keep their numbers and '
      'are read in the new currency — $before becomes $after. Accounts keep '
      'their own currencies.';
  @override
  String get profileCurrencyConfirm => 'Switch';
  @override
  String profileCurrencySaved(String code) => 'Currency: $code';
  @override
  String get profileTimeZoneNote =>
      '“Today”, day boundaries and times follow this zone.';
  @override
  String get profileTimeZoneSearch => 'Search a city or UTC+03';
  @override
  String profileTimeZoneDeviceGroup(String offset) =>
      'This device\'s time (UTC$offset)';
  @override
  String get profileTimeZoneAllGroup => 'All time zones';
  @override
  String get profileTimeZoneNoMatch => 'No matching time zone';
  @override
  String profileTimeZoneSaved(String zone) => 'Time zone: $zone';
  @override
  String get profileWeeklyReview => 'Weekly review';
  @override
  String get profileWeeklyReviewNote =>
      'The day of the web\'s weekly review reminder.';
  @override
  String profileWeeklyReviewSaved(String day) => 'Weekly review day: $day';
  @override
  String get serverBlurb =>
      'Your Meridian server\'s local network or Tailscale address. Can\'t connect? Check your Wi-Fi or Tailscale connection.';
  @override
  String get serverTest => 'Test connection';
  @override
  String get serverConnected => 'Connected';
  @override
  String serverVersion(String version) => 'Meridian v$version';
  @override
  String serverLatency(int ms) => '$ms ms';
  @override
  String get serverCantConnect =>
      'Couldn\'t connect — check the address and your Wi-Fi or Tailscale connection';
  @override
  String get serverEmpty => 'The server address can\'t be empty';
  @override
  String get serverUnverifiedTitle => 'Connection not verified';
  @override
  String get serverUnverifiedBody =>
      'This address didn\'t respond, or hasn\'t been tested yet. Save it anyway?';
  @override
  String get serverSaveAnyway => 'Save anyway';
  @override
  String get serverSaved => 'Server address saved';
  // endregion
}
