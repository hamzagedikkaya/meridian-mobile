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
  String get actionSelect;
  String get actionSelectOptional;
  String get actionSeeAll;
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
  String get errInvalidData;
  String get errInvalidCredentials;
  String get errSessionExpired;
  String get errNotFound;
  String errServer(int status);
  String get errNoConnection;
  String get noticeSessionExpired;

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

  // --- Finance --------------------------------------------------------------

  String get financeScopeMonth;
  String get financeScopeYear;
  String get financeIncome;
  String get financeExpense;
  String get financeTransfer;
  String get financeTransaction;
  String get financeLast6Months;
  String get financeCategoriesThisMonth;
  String get financeNoSpendThisMonth;
  String get financeBudgets;
  String get financeExceeded;
  String financeRemaining(String amount);
  String financeMonthEndEstimate(String amount);
  String get financeUpcomingSubscriptions;
  String get financeRecentTransactions;
  String get financeNoTransactionsYet;
  String get financeAddFirstAccount;
  String get financeAddAccount;
  String get financeAddAccountSoon;
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
  String get txDeleteTitle;
  String get txDeleted;
  String get txDeleteFailed;
  String get txSaved;
  String get txUpdated;
  String get txSaveFailed;

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
  String get txFormSelectCategory;

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
  String get journalLoadFailed;
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
