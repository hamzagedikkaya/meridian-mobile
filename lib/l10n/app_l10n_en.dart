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
  String get actionSelect => 'Select';
  @override
  String get actionSelectOptional => 'Select (optional)';
  @override
  String get actionSeeAll => 'See all →';
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
      withYear: date.year != DateTime.now().year,
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
      'What happened? (−250 coffee, habit: run, buy milk…)';
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
  String get financeTransaction => 'Transaction';
  @override
  String get financeLast6Months => 'Last 6 months';
  @override
  String get financeCategoriesThisMonth => 'Categories (this month)';
  @override
  String get financeNoSpendThisMonth => 'No spending this month';
  @override
  String get financeBudgets => 'Budgets';
  @override
  String get financeExceeded => 'over';
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
  String get financeAddFirstAccount => 'Add your first account';
  @override
  String get financeAddAccount => 'Add account';
  @override
  String get financeAddAccountSoon => 'Adding accounts is coming soon';
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
  String get txDeleteTitle => 'Delete this transaction?';
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
  String get txFormSelectCategory => 'Pick a category';

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
  String get journalLoadFailed => 'Couldn\'t load the entry';
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
