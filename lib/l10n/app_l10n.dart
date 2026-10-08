import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_l10n_en.dart';
import 'app_l10n_tr.dart';

/// Every piece of user-facing copy in the app, as a typed contract.
///
/// [AppL10n] is abstract on purpose: a new string has to be implemented in
/// [AppL10nTr] *and* [AppL10nEn] or the analyzer fails the build, so a locale
/// can never silently fall back to the other language. There is no codegen and
/// no `.arb` step — the same choice the rest of the app makes with Riverpod.
///
/// Read it the way colours are read (`context.nok`):
///
///     final l = context.l10n;
///     Text(l.titleFinance)
///
/// Pure number/date formatting lives in `core/formats.dart` and follows
/// [Intl.defaultLocale], which this file's delegate keeps in sync.
abstract class AppL10n {
  const AppL10n();

  static const supportedLocales = <Locale>[Locale('tr'), Locale('en')];

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  static AppL10n of(BuildContext context) =>
      Localizations.of<AppL10n>(context, AppL10n) ?? const AppL10nTr();

  static AppL10n forLocale(Locale locale) =>
      locale.languageCode == 'en' ? const AppL10nEn() : const AppL10nTr();

  /// `tr` or `en` — also the locale handed to `intl` for numbers and dates.
  String get localeCode;

  // --- Generic actions and words --------------------------------------------

  String get appName;
  String get tagline;
  String get actionSave;
  String get actionUpdate;
  String get actionCancel;
  String get actionConfirm;
  String get actionDelete;
  String get actionEdit;
  String get actionRetry;
  String get actionBack;
  String get actionSelect;
  String get actionSelectOptional;
  String get actionSeeAll;
  String get actionUndo;
  String get actionDismiss;
  String get labelAll;
  String get labelNone;
  String get labelSkip;
  String get labelChange;

  // --- Navigation and screen titles -----------------------------------------

  String get tabToday;
  String get tabFinance;
  String get tabHabits;
  String get tabGoals;
  String get tabJournal;
  String get titleToday;
  String get titleFinance;
  String get titleHabits;
  String get titleGoals;
  String get titleJournal;
  String get titleProfile;
  String get titleServer;
  String get titleTransactions;
  String get titleAccount;
  String get titleGoal;
  String get titleJournalEntry;

  // --- Errors, offline, session ---------------------------------------------

  String get errServerUnreachable;
  String get errCheckWifi;
  String get errServerSettings;
  String offlineLastUpdated(String time);

  /// Screen-reader label of the thin progress line shown while data already
  /// on screen is being refreshed.
  String get syncUpdating;
  String get errInvalidData;
  String get errInvalidCredentials;
  String get errSessionExpired;
  String get errNotFound;
  String errServer(int status);
  String get errNoConnection;
  String get noticeSessionExpired;

  /// Under the title of a detail screen whose record the server no longer
  /// has (a 404): it was deleted on the web or on another device.
  String get errRecordGoneBody;

  // --- Server refusals, by the error `code` the API sends -------------------
  //
  // Worded here rather than shown as the server wrote them, so a refusal
  // reads in the app's language whatever the account's language is.

  /// 429 `too_many_requests`: too many sign-in attempts.
  String get errTooManyRequests;

  /// `invalid_parameter`: the app sent a value the server cannot use.
  String errInvalidParameter(String param);

  /// `value_out_of_range`: a number does not fit (amounts top out at
  /// 21,474,836.47).
  String get errValueOutOfRange;
  String get errInvalidDate;
  String get errInvalidDatetime;

  /// `future_date`: a habit day after today.
  String get errFutureDate;

  /// `before_habit_start`: a habit day before the habit existed.
  String errBeforeHabitStart(DateTime? start);
  String get errHabitArchived;

  /// Quick capture `empty`: nothing was typed.
  String get errCaptureEmpty;

  /// Quick capture `no_account`: money needs an account to go to.
  String get errNoAccount;

  /// Quick capture `unknown_habit`: no habit is called [name].
  String errUnknownHabit(String name);

  /// Quick capture `invalid_amount`, by `reason`: `unreadable`, `zero`,
  /// `too_precise` or `too_large`.
  String errInvalidAmount(String? reason);

  /// `has_transactions`: an account with history cannot be deleted.
  String errHasTransactions(int transactions, int incomingTransfers);
  String get errCurrencyLocked;
  String get errKindLocked;
  String get errAmountRequired;

  /// `not_chargeable`, by `reason`: `inactive` or `no_next_charge`.
  String errNotChargeable(String? reason);
  String get errTargetReached;
  String get errTargetNotReached;
  String get errProgressComputed;
  String get errBodyHasFormatting;

  /// What is wrong with a field, by the validation type the server reports
  /// for it (`blank`, `too_long` with [count], `taken`, …) — worded to sit
  /// under the field, so it names no field. Null for a type the app does
  /// not know; the server's own message is shown then.
  String? validationDetail(String error, {num? count});

  /// The name of a server field (`title`, `amount_cents`, …), to say which
  /// field an error is about when it is not shown under the field itself.
  /// Null for a field the app does not know.
  String? fieldLabel(String field);

  // --- Login and server address ---------------------------------------------

  String get loginEmail;
  String get loginPassword;
  String get loginSubmit;
  String get serverAddress;

  /// Shorter label for the Profile row, where the address sits beside it.
  String get serverAddressShort;
  String get serverAddressUnreachable;

  // --- Dates and relative days ----------------------------------------------

  String get dayToday;
  String get dayYesterday;
  String get dayTomorrow;
  String get dayAllDay;

  /// "Bugün" / "Dün" / "Yarın", otherwise the formatted date.
  String relativeDay(DateTime date);

  /// "bugün" / "3 gün sonra" / "2 gün önce".
  String relativeDays(DateTime date);

  /// Greeting by hour of day, for the Today app bar.
  String greeting(int hour);

  /// Locale-correct percentage: `%82` in Turkish, `82%` in English.
  String percent(num value);

  /// Compact chart-axis numbers: `75B` / `1,2Mn` in Turkish, `75K` / `1.2M`.
  String compactThousands(double major);
  String compactMillions(double major);

  // --- Today ----------------------------------------------------------------

  String get todayMonthNet;
  String get todayYearNet;
  String get todayStatStreak;
  String get todayStatOpenTodos;
  String get todayStatWeek;
  String get todayQuickCapture;
  String get todayQuickCaptureHint;
  String get todayQuickCaptureAdd;
  String get todayQuickCaptureFailed;
  String get todayEmptyDay;
  String get todayAllHabitsDone;
  String get todayNoHabitsYet;
  String get todayNoGoalsYet;
  String get todayOpenTodos;
  String get todayNoOpenTodos;
  String get todayTodosFailed;
  String get todayTodoUpdateFailed;
  String get todayHabitUpdateFailed;

  /// Snackbar after a todo is checked off on Today; it offers undo.
  String todayTodoDone(String title);

  /// Today's notice when this device's clock is in another time zone than
  /// the account: days and times follow the account ([zone], [offset] like
  /// `+03:00`), not the phone.
  String todayZoneNotice(String zone, String offset);

  // --- Quick capture --------------------------------------------------------

  /// What a capture saved, by what it turned into.
  String captureSavedExpense(String amount, String description);
  String captureSavedIncome(String amount, String description);
  String captureSavedHabit(String name, {required bool completed});
  String captureSavedTodo(String title);

  /// A capture of a kind this version of the app does not know.
  String captureSaved(String summary);

  /// The text names a day: nothing was saved, and the sheet says so.
  String get captureLooksLikeEvent;

  /// The server saved nothing, for a reason this app does not know.
  String get captureNotSaved;

  /// The line went out but no answer came back in time: it may have been
  /// saved, so it is not sent again on its own (that could save it twice).
  String get captureMaybeSaved;
  String get captureSaveAsTodo;
  String get captureAddAsEvent;
  String get captureCreateAccount;
  String captureCreateHabit(String name);

  // --- Habit day log --------------------------------------------------------

  /// Sheet title for setting today's count of a habit.
  String get habitLogToday;
  String get habitLogDone;
  String get habitLogNotDone;
  String get habitLogComplete;
  String get habitLogReset;

  /// The counter's − and + buttons, for screen readers and tooltips.
  String get habitLogDecrease;
  String get habitLogIncrease;

  /// What a screen reader says for a habit's ring or counter.
  String habitLogSemantics(
    String name, {
    required int count,
    required int target,
    required bool done,
  });

  /// Screen-reader hint: a long-press opens the day's log.
  String get habitLogHint;

  // --- Finance --------------------------------------------------------------

  String get financeScopeMonth;
  String get financeScopeYear;
  String get financeIncome;
  String get financeExpense;
  String get financeTransfer;
  String get financeLast6Months;
  String get financeCategoriesThisMonth;
  String get financeNoSpendThisMonth;
  String get financeBudgets;
  String financeRemaining(String amount);
  String financeMonthEndEstimate(String amount);
  String get financeUpcomingSubscriptions;
  String get financeRecentTransactions;
  String get financeNoTransactionsYet;
  String get financeAddAccount;
  String get financeNoTransactionsInAccount;

  /// Cash / bank / credit card / savings / crypto, by API `account_type`.
  String accountType(String type);

  /// Subscription cadence, by API `frequency`.
  String subscriptionFrequency(String frequency);

  // --- Transactions feed ----------------------------------------------------

  String get txFilterAccount;
  String get txFilterAllAccounts;
  String get txFilterCategory;
  String get txFilterAllCategories;
  String get txFilterDate;
  String get txFilterDateRange;
  String get txFilterThisMonth;
  String get txFilterLast30Days;
  String get txFilterThisYear;
  String get txFilterClear;
  String get txNoneForFilter;
  String get txAllLoaded;
  String txSummary(String income, String expense);
  String get txDeleted;
  String get txDeleteFailed;
  String get txSaved;
  String get txUpdated;
  String get txSaveFailed;

  /// A transaction's sheet: the other row of its linked pair (the web saves
  /// an expense on one account with an income on another), and what
  /// deleting this one does to it.
  String get txLinkedTitle;
  String get txLinkedDeletedAlong;
  String get txLinkedStays;

  /// Deleting a transaction that takes its linked one along asks first;
  /// [linked] names that one (its account, amount and date).
  String txDeleteLinkedTitle(String name);
  String txDeleteLinkedBody(String linked);
  String get txDeleteBoth;
  String get txDeletedWithLinked;

  /// The sheet of a transaction deleted on the web or another device.
  String get txGone;

  // --- Transaction form ------------------------------------------------------

  String get txFormNewTitle;
  String get txFormEditTitle;
  String get txFormAccount;
  String get txFormTargetAccount;
  String get txFormCategory;
  String get txFormDate;
  String get txFormDescription;
  String get txFormEnterAmount;
  String get txFormSelectAccount;
  String get txFormSelectTargetAccount;
  String get txFormAccountsMustDiffer;
  String get txFormNote;
  String get txFormAmount;

  /// The category filter's headings (pre-cased overlines).
  String get txFilterGroupExpense;
  String get txFilterGroupIncome;
  String get txFilterCustomRange;

  /// The transfer target list holds same-currency accounts only.
  String get txFormTransferSameCurrency;
  String get txFormNoTransferTarget;
  String get txFormNeedAccount;

  /// An account row while the account list loads, and when it could not be
  /// loaded (a tap tries again) — never "make your first account" then.
  String get txFormAccountsLoading;
  String get txFormAccountsFailed;

  // --- Forms, keypad and undo -----------------------------------------------

  String get actionAdd;
  String get actionDone;
  String get actionArchive;
  String get actionRestore;
  String get actionMoreOptions;
  String get labelOptional;

  /// The sheet a form with unsaved changes asks from when it is closed.
  String get formDiscardTitle;
  String get formKeepEditing;
  String get formDiscard;

  /// Under an amount that would pass what the server can store.
  String amountTooLarge(String max);

  /// Screen-reader labels of the keypad's icon and mark keys.
  String get keypadBackspace;
  String get keypadDecimalMark;
  String get keypadClearHint;

  /// A delete sent after its undo window that the server refused: the
  /// record is back.
  String get errDeleteFailed;

  /// A colour swatch, for screen readers ("Renk 3").
  String colorSwatch(int index);

  // --- Finance: setup, accounts, menus --------------------------------------

  String get financeAccounts;

  /// A page dot of the accounts carousel, for screen readers ("Sayfa 2 / 4").
  String accountsCarouselPage(int page, int count);

  /// The label of the Finance FAB (it adds a transaction).
  String get financeAddTransactionFab;
  String get financeMenuCategories;
  String get financeMenuSubscriptions;
  String get financeMenuArchivedAccounts;

  /// First run, no account yet.
  String get financeFirstRunTitle;
  String get financeFirstRunBody;
  String get financeFirstRunCash;
  String get financeFirstRunOther;

  /// The name of the cash account the first-run button opens.
  String get financeCashAccountName;

  /// First run, an account but no transaction yet.
  String get financeFirstTxTitle;
  String get financeFirstTxBody;
  String get financeFirstTxAction;

  /// Every account is archived.
  String get financeNoActiveAccounts;
  String get financeNoActiveAccountsBody;

  /// Expenses without a category, as a slice of the month's spending.
  String get financeUncategorized;
  String get financeCategorize;
  String get financeOtherCategories;

  /// A slice's breakdown sheet: its whole spending, subcategories included,
  /// and the part filed under the category itself (the web's "(genel)").
  String get financeSliceAll;
  String get financeSliceAllMeta;
  String financeSliceDirect(String name);
  String get financeBudgetsEmpty;

  /// A budget's spend against its limit.
  String financeBudgetSpentOf(String spent, String limit);

  /// How far a budget is over its limit.
  String financeOverBy(String amount);
  String get financeNoUpcomingPayments;
  String get financeAddSubscription;
  String get financeSubscriptionsEmpty;

  // --- Account form, archive, delete ----------------------------------------

  String get accountFormNewTitle;
  String get accountFormEditTitle;
  String get accountFormType;
  String get accountFormName;
  String get accountFormNameRequired;
  String get accountFormCurrency;
  String get accountFormCurrencyLocked;
  String get accountFormOpeningBalance;
  String get accountFormOpeningBalanceHint;

  /// The toggle that makes an opening balance negative (a card's debt).
  String get accountFormDebt;
  String get accountFormColor;
  String get accountFormCreate;

  /// The picker row that opens the account form.
  String get accountNew;
  String accountCreated(String name);
  String get accountUpdated;
  String get accountSaveFailed;
  String accountArchived(String name);
  String accountRestored(String name);
  String get accountArchiveFailed;
  String get accountRestoreFailed;
  String get accountArchivedBadge;
  String get accountArchivedNote;
  String accountDeleted(String name);
  String get accountDeleteFailed;
  String get accountCantDeleteTitle;

  /// An archived account with history cannot be deleted, and archiving is
  /// no way out for it: said, with nothing offered instead.
  String accountCantDeleteArchived(int transactions, int incomingTransfers);
  String accountDeleteTitle(String name);

  /// What else an account's delete takes or unlinks.
  String accountDeleteConsequences({
    required int subscriptions,
    required int goals,
  });
  String get accountGone;
  String get titleArchivedAccounts;
  String get archivedAccountsEmpty;
  String get archivedAccountsBody;

  // --- Finance categories ----------------------------------------------------

  String get titleCategories;
  String get categoriesEmptyExpense;
  String get categoriesEmptyIncome;
  String get categoriesEmptyBody;
  String get categoriesAddFab;
  String get categoriesStarter;
  String get categoriesStarterAdded;
  String get categoriesStarterFailed;

  /// The starter set "Hazır kategorileri ekle" creates, in this language.
  List<String> starterCategories(String kind);
  String get categoryNew;
  String get categoryFormNewTitle;
  String get categoryFormEditTitle;
  String get categoryFormName;
  String get categoryFormNameRequired;
  String get categoryFormKind;
  String get categoryFormKindLocked;
  String get categoryFormParent;
  String get categoryFormNoParent;
  String get categoryFormParentLocked;
  String get categoryFormColor;
  String categoryCreated(String name);
  String get categoryUpdated;
  String get categorySaveFailed;
  String categoryDeleted(String name);
  String categoryDeleteTitle(String name);

  /// What a category's delete touches, counts from GET /finance_categories/:id.
  String categoryDeleteImpact({
    required int transactions,
    required int subscriptions,
    required int children,
    required int budgets,
  });
  String get categoryDeleteFailed;
  String categoryChildren(int count);
  String get categoryLoadFailed;

  // --- Budgets ---------------------------------------------------------------

  String get budgetNewTitle;
  String budgetEditTitle(String category);
  String get budgetCategory;
  String get budgetLimit;
  String get budgetLimitRequired;
  String get budgetPickCategory;
  String get budgetNoCategories;
  String budgetCurrencyNote(String currency);
  String get budgetCreated;
  String get budgetUpdated;
  String get budgetSaveFailed;
  String get budgetRemove;
  String budgetRemoved(String category);

  // --- Subscriptions ---------------------------------------------------------

  String get titleSubscriptions;

  /// The Subscriptions page's hero: what the active ones cost a month, then
  /// a year.
  String subscriptionsMonthly(String amount);
  String subscriptionsYearly(String amount);
  String get subscriptionsActive;
  String get subscriptionsPaused;
  String get subscriptionsEmpty;
  String get subscriptionsAddFab;
  String get subscriptionFormNewTitle;
  String get subscriptionFormEditTitle;
  String get subscriptionFormName;
  String get subscriptionFormNameHint;
  String get subscriptionFormNameRequired;
  String get subscriptionFormAmount;
  String get subscriptionFormAmountRequired;
  String get subscriptionFormFrequency;
  String get subscriptionFormAccount;
  String get subscriptionFormNextCharge;
  String get subscriptionFormNextChargeAuto;
  String get subscriptionFormCategory;
  String get subscriptionFormVendor;
  String get subscriptionFormNote;
  String get subscriptionFormColor;
  String get subscriptionFormMore;
  String get subscriptionCreated;
  String get subscriptionUpdated;
  String get subscriptionSaveFailed;

  /// "₺99,99 / ay": an amount per period, by API `frequency`.
  String subscriptionAmountPer(String amount, String frequency);
  String subscriptionNextOn(String date);
  String get subscriptionNoDate;
  String get subscriptionOverdue;
  String get subscriptionPausedLabel;
  String get subscriptionCharge;
  String subscriptionCharged(String amount);
  String get subscriptionChargeFailed;
  String get subscriptionChargeMaybe;
  String get subscriptionPause;
  String get subscriptionResume;
  String subscriptionPausedDone(String name);
  String subscriptionResumedDone(String name);
  String get subscriptionToggleFailed;
  String subscriptionDeleted(String name);

  // --- Habits ---------------------------------------------------------------

  String habitsDoneOfTotal(int done, int total);
  String get habitsAllDone;
  String get habitsPerfectChain;
  String get habitsPerfectHistory;
  String habitsPerfectStreak(int streak, int record);
  String get habitsHistory;
  String get habitsCreateFirst;
  String get habitsStartSmall;
  String get habitsAdd;
  String get habitsToggleFailed;
  String habitsMeta(int streak, int rate);
  String get habitsThisWeek;
  String get habitsThisMonth;
  String habitsPeriodProgress(String period, int done, int target);
  String get habitsStatStreak;
  String get habitsStatRecord;
  String get habitsStatRate30d;
  String get habitsLast30Days;
  String get habitsLast84Days;
  String get habitsLegendDone;
  String get habitsLegendPartial;
  String get habitsLegendMissed;
  String get habitsArchive;
  String habitsArchiveBody(String name);
  String get habitsArchiveTitle;
  String get habitsArchived;
  String get habitsArchiveFailed;
  String get habitsFormNewTitle;
  String get habitsFormName;
  String get habitsFormNameHint;
  String get habitsFormNameRequired;
  String get habitsFormFrequency;
  String get habitsFormDaily;
  String get habitsFormWeekly;
  String get habitsFormMonthly;
  String get habitsFormColor;
  String get habitsFormDailyTarget;
  String get habitsFormPeriodTarget;
  String get habitsFormGoalLink;
  String get habitsFormLinkGoal;
  String get habitsAdded;
  String get habitsSaveFailed;

  // --- Goals ----------------------------------------------------------------

  String get goalsTypeFinancial;
  String get goalsTypeHabit;
  String get goalsTypeCustom;
  String get goalsStatusAchieved;
  String get goalsStatusAbandoned;
  String get goalsStatusActive;
  String get goalsSectionActive;
  String get goalsSectionAchieved;
  String get goalsSectionAbandoned;
  String get goalsSetFirst;
  String get goalsSetFirstBody;
  String get goalsAdd;
  String goalsOverdueBadge(int days);
  String get goalsDueTodayBadge;
  String goalsDaysLeftBadge(int days);
  String get goalsDetailStatus;
  String get goalsDetailDeadline;
  String get goalsDetailDaysLeft;
  String get goalsDetailProgress;
  String get goalsHabitProgress;
  String goalsStreakDays(int days);
  String get goalsLinkedAccount;
  String get goalsCurrentBalance;
  String get goalsRefresh;
  String get goalsEnterValue;
  String get goalsMarkAbandoned;
  String get goalsAbandonTitle;
  String get goalsAbandonBody;
  String get goalsAbandonAction;
  String get goalsActionFailed;
  String get goalsLoadFailed;
  String get goalsGone;
  String goalsProgressDays(String current, String target);
  String get goalsFormNewTitle;
  String get goalsFormName;
  String get goalsFormNameRequired;
  String get goalsFormDescription;
  String get goalsFormType;
  String get goalsFormTypeCustom;
  String get goalsFormTypeHabit;
  String get goalsFormTypeFinancial;
  String get goalsFormColor;
  String get goalsFormTargetValue;
  String get goalsFormTargetRequired;
  String get goalsFormUnit;
  String get goalsFormUnitHint;
  String get goalsFormEndDate;
  String get goalsFormLinkedAccount;
  String get goalsFormLinkedHabit;
  String get goalsFormSubmit;
  String get goalsCreated;
  String get goalsCreateFailed;

  // --- Journal --------------------------------------------------------------

  String journalEntriesCount(int count);
  String get journalNoEntryForMood;
  String get journalHowWasToday;
  String get journalWriteFirst;
  String get journalCreateEntry;
  String get journalUntitled;
  String get journalEnergy;
  String get journalGratitude;
  String get journalDeleteTitle;
  String get journalDeleteBody;
  String get journalDeleteFailed;
  String get journalLoadFailed;
  String get journalGone;
  String get journalEditorNewTitle;
  String get journalEditorEditTitle;
  String get journalEditorTitleHint;
  String get journalEditorBodyHint;
  String get journalEditorTags;
  String get journalEditorTagsHint;
  String get journalEditorGratitudeHint;
  String get journalEditorMoodPrompt;
  String get journalEditorWeather;
  String get journalEditorNeedsContent;
  String get journalUpdated;
  String get journalAdded;
  String get journalSaveFailed;

  /// Mood label by API `mood` value.
  String moodLabel(String mood);

  /// Weather label by API `weather` value.
  String weatherLabel(String weather);

  /// Range pill label for `7d` / `30d` / `6mo` / `1y` / `all`.
  String journalRange(String range);

  // --- Profile and server settings ------------------------------------------

  String get profileSectionApp;
  String get profileTheme;
  String get profileThemeDark;
  String get profileThemeLight;
  String get profileThemeSystem;
  String get profileLanguage;
  String get profileLanguageTr;
  String get profileLanguageEn;
  String get profileCurrency;

  /// The account's time zone row; [zone] is its IANA name, [offset] `+03:00`.
  String get profileTimeZone;
  String profileTimeZoneValue(String zone, String offset);

  /// Under the time zone row when this device is in another zone.
  String profileTimeZoneDeviceDiffers(String deviceOffset);
  String get profileSectionServer;
  String get profileSectionAbout;
  String get profileVersion;
  String get profileApiStatus;
  String get profileApiOnline;
  String get profileApiUnreachable;
  String get profileSignOut;
  String get profileSignOutTitle;
  String get profileSignOutBody;
  String get profileFallbackName;
  String get profileLanguageSaveFailed;
  String get serverBlurb;
  String get serverTest;
  String get serverConnected;
  String serverVersion(String version);
  String serverLatency(int ms);
  String get serverCantConnect;
  String get serverEmpty;
  String get serverUnverifiedTitle;
  String get serverUnverifiedBody;
  String get serverSaveAnyway;
  String get serverSaved;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppL10n.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppL10n> load(Locale locale) {
    final strings = AppL10n.forLocale(locale);
    // Keep `intl` in step with the UI language, so every NumberFormat and
    // DateFormat in core/formats.dart follows without being passed a locale.
    Intl.defaultLocale = strings.localeCode;
    return SynchronousFuture<AppL10n>(strings);
  }

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

extension AppL10nContext on BuildContext {
  /// The active language's copy — mirrors `context.nok` for colours.
  AppL10n get l10n => AppL10n.of(this);
}
