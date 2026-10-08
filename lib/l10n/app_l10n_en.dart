import '../core/formats.dart';
import 'app_l10n.dart';

/// English copy. Keep this file and [AppL10nTr] member-for-member identical —
/// the abstract base enforces it.
class AppL10nEn extends AppL10n {
  const AppL10nEn();

  @override
  String get localeCode => 'en';

  // --- Generic actions and words --------------------------------------------

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
  String get actionConfirm => 'Confirm';
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

  // --- Navigation and screen titles -----------------------------------------

  @override
  String get tabToday => 'Today';
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

  // --- Errors, offline, session ---------------------------------------------

  @override
  String get errServerUnreachable => 'Can\'t reach the server';
  @override
  String get errCheckWifi => 'Make sure you\'re on the same Wi-Fi network';
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
      'Can\'t reach the server — make sure you\'re on the same Wi-Fi network';
  @override
  String get noticeSessionExpired => 'Your session expired, sign in again';
  @override
  String get errRecordGoneBody =>
      'It may have been deleted on the web or on another device.';

  // --- Server refusals, by the error `code` the API sends -------------------

  @override
  String get errTooManyRequests =>
      'Too many attempts. Try again in a few minutes.';
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
        'password' || 'current_password' => 'Password',
        'todo_list_id' => 'List',
        'goal_id' => 'Goal',
        _ => null,
      };

  /// A limit as a plain number in English notation.
  String _n(num value) => formatDecimal(
        value,
        decimals: value == value.roundToDouble() ? 0 : 2,
        locale: localeCode,
      );

  // --- Login and server address ---------------------------------------------

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
      'Couldn\'t reach the server — check the address and your Wi-Fi';

  // --- Dates and relative days ----------------------------------------------

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

  // --- Today ----------------------------------------------------------------

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
  String get todayEmptyDay => 'Nothing planned — a quiet day ☁';
  @override
  String get todayAllHabitsDone => '✦ All done';
  @override
  String get todayNoHabitsYet => 'No habits yet — start small';
  @override
  String get todayNoGoalsYet => 'No goals yet — set your first one';
  @override
  String get todayOpenTodos => 'Open todos';
  @override
  String get todayNoOpenTodos => 'Nothing open — all clear ✦';
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

  // --- Quick capture --------------------------------------------------------

  @override
  String captureSavedExpense(String amount, String description) =>
      'Expense added · $amount · $description';
  @override
  String captureSavedIncome(String amount, String description) =>
      'Income added · $amount · $description';
  @override
  String captureSavedHabit(String name, {required bool completed}) =>
      completed ? '“$name” done for today ✓' : '“$name” logged';
  @override
  String captureSavedTodo(String title) => 'Task added: $title';
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
  String get captureCreateAccount => 'Create an account';
  @override
  String captureCreateHabit(String name) => 'Create the habit “$name”';

  // --- Habit day log --------------------------------------------------------

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

  // --- Finance --------------------------------------------------------------

  @override
  String get financeScopeMonth => 'Month';
  @override
  String get financeScopeYear => 'Year';
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
  String get financeUpcomingSubscriptions => 'Upcoming subscriptions';
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

  // --- Transactions feed ----------------------------------------------------

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
  String get txSaved => 'Transaction saved ✓';
  @override
  String get txUpdated => 'Transaction updated ✓';
  @override
  String get txSaveFailed => 'Couldn\'t save, try again';

  // --- Transaction form ------------------------------------------------------

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

  // --- Forms, keypad and undo -----------------------------------------------

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

  // --- Finance: setup, accounts, menus --------------------------------------

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
  String get financeAddBudget => 'Add budget';
  @override
  String get financeBudgetsEmpty =>
      'Set a monthly limit on a category and see the month\'s end coming.';
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

  // --- Account form, archive, delete ----------------------------------------

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
  String accountCreated(String name) => 'Account “$name” is ready ✓';
  @override
  String get accountUpdated => 'Account updated ✓';
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

  // --- Finance categories ----------------------------------------------------

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
  String get categoriesStarterAdded => 'Starter categories added ✓';
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
  String categoryCreated(String name) => '“$name” added ✓';
  @override
  String get categoryUpdated => 'Category updated ✓';
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

  // --- Budgets ---------------------------------------------------------------

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
  String get budgetCreated => 'Budget added ✓';
  @override
  String get budgetUpdated => 'Budget updated ✓';
  @override
  String get budgetSaveFailed => 'Couldn\'t save the budget';
  @override
  String get budgetRemove => 'Remove budget';
  @override
  String budgetRemoved(String category) => '“$category” budget removed';

  // --- Subscriptions ---------------------------------------------------------

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
  String get subscriptionCreated => 'Subscription added ✓';
  @override
  String get subscriptionUpdated => 'Subscription updated ✓';
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

  // --- Habits ---------------------------------------------------------------

  @override
  String habitsDoneOfTotal(int done, int total) => '$done / $total done';
  @override
  String get habitsAllDone => '✦ All done';
  @override
  String get habitsPerfectChain => 'Perfect-day chain';
  @override
  String get habitsPerfectHistory => 'Perfect-day history';
  @override
  String habitsPerfectStreak(int streak, int record) =>
      'Perfect streak: 🔥 $streak · Best: $record';
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
  String habitsMeta(int streak, int rate) => '🔥 $streak · $rate% (30d)';
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
      '$name will be removed from the list.';
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
  String get habitsAdded => 'Habit added ✓';
  @override
  String get habitsSaveFailed => 'Couldn\'t save, try again';

  // --- Goals ----------------------------------------------------------------

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
  String get goalsAbandonTitle => 'Abandon this goal?';
  @override
  String get goalsAbandonBody => 'It will be marked as abandoned.';
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
  String get goalsCreated => 'Goal created ✓';
  @override
  String get goalsCreateFailed => 'Couldn\'t create the goal';

  // --- Journal --------------------------------------------------------------

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
  String get journalDeleteTitle => 'Delete this entry?';
  @override
  String get journalDeleteBody => 'This journal entry will be gone for good.';
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
  String get journalUpdated => 'Updated ✓';
  @override
  String get journalAdded => 'Entry added ✓';
  @override
  String get journalSaveFailed => 'Couldn\'t save the entry';

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

  // --- Profile and server settings ------------------------------------------

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
      'You\'ll be signed out. The server address is kept.';
  @override
  String get profileFallbackName => 'User';
  @override
  String get profileLanguageSaveFailed =>
      'Couldn\'t save the language to the server — it applies on this device';
  @override
  String get serverBlurb =>
      'Your Meridian server\'s LAN address. The phone has to be on the same Wi-Fi network.';
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
      'Couldn\'t connect — check the address and your Wi-Fi';
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
}
