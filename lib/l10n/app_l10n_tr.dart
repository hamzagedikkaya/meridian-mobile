import '../core/formats.dart';
import 'app_l10n.dart';

/// Turkish copy. Keep this file and [AppL10nEn] member-for-member identical —
/// the abstract base enforces it.
class AppL10nTr extends AppL10n {
  const AppL10nTr();

  @override
  String get localeCode => 'tr';

  // --- Generic actions and words --------------------------------------------

  @override
  String get appName => 'Meridian';
  @override
  String get tagline => 'Kişisel yaşam merkezin';
  @override
  String get actionSave => 'Kaydet';
  @override
  String get actionUpdate => 'Güncelle';
  @override
  String get actionCancel => 'Vazgeç';
  @override
  String get actionConfirm => 'Onayla';
  @override
  String get actionDelete => 'Sil';
  @override
  String get actionEdit => 'Düzenle';
  @override
  String get actionRetry => 'Tekrar dene';
  @override
  String get actionSelect => 'Seç';
  @override
  String get actionSelectOptional => 'Seç (isteğe bağlı)';
  @override
  String get actionSeeAll => 'Tümü →';
  @override
  String get labelAll => 'Tümü';
  @override
  String get labelNone => 'Yok';
  @override
  String get labelSkip => 'Geç';
  @override
  String get labelChange => 'Değiştir';

  // --- Navigation and screen titles -----------------------------------------

  @override
  String get tabToday => 'Bugün';
  @override
  String get tabFinance => 'Finans';
  @override
  String get tabHabits => 'Alışkanlık';
  @override
  String get tabGoals => 'Hedefler';
  @override
  String get tabJournal => 'Günlük';
  @override
  String get titleToday => 'Bugün';
  @override
  String get titleFinance => 'Finans';
  @override
  String get titleHabits => 'Alışkanlıklar';
  @override
  String get titleGoals => 'Hedefler';
  @override
  String get titleJournal => 'Günlük';
  @override
  String get titleProfile => 'Profil';
  @override
  String get titleServer => 'Sunucu';
  @override
  String get titleTransactions => 'İşlemler';
  @override
  String get titleAccount => 'Hesap';
  @override
  String get titleGoal => 'Hedef';
  @override
  String get titleJournalEntry => 'Günlük';

  // --- Errors, offline, session ---------------------------------------------

  @override
  String get errServerUnreachable => 'Sunucuya ulaşılamıyor';
  @override
  String get errCheckWifi => 'Aynı Wi-Fi ağında olduğundan emin ol';
  @override
  String get errServerSettings => 'Sunucu ayarları';
  @override
  String offlineLastUpdated(String time) => 'Çevrimdışı · son güncelleme $time';
  @override
  String get errInvalidData => 'Geçersiz veri';
  @override
  String get errInvalidCredentials => 'E-posta veya şifre hatalı';
  @override
  String get errSessionExpired => 'Oturum süresi doldu';
  @override
  String get errNotFound => 'Kayıt bulunamadı';
  @override
  String errServer(int status) => 'Sunucu hatası ($status)';
  @override
  String get errNoConnection =>
      'Sunucuya ulaşılamıyor — aynı Wi-Fi ağında olduğundan emin ol';
  @override
  String get noticeSessionExpired => 'Oturum süresi doldu, tekrar giriş yap';

  // --- Login and server address ---------------------------------------------

  @override
  String get loginEmail => 'E-posta';
  @override
  String get loginPassword => 'Şifre';
  @override
  String get loginSubmit => 'Giriş Yap';
  @override
  String get serverAddress => 'Sunucu adresi';
  @override
  String get serverAddressShort => 'Sunucu adresi';
  @override
  String get serverAddressUnreachable =>
      'Sunucuya ulaşılamadı — adresi ve Wi-Fi\'yi kontrol et';

  // --- Dates and relative days ----------------------------------------------

  @override
  String get dayToday => 'Bugün';
  @override
  String get dayYesterday => 'Dün';
  @override
  String get dayTomorrow => 'Yarın';
  @override
  String get dayAllDay => 'Tüm gün';

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
    if (diff == 0) return 'bugün';
    if (diff > 0) return '$diff gün sonra';
    return '${-diff} gün önce';
  }

  @override
  String greeting(int hour) {
    if (hour >= 5 && hour < 12) return 'İyi sabahlar';
    if (hour >= 12 && hour < 18) return 'İyi günler';
    if (hour >= 18 && hour < 23) return 'İyi akşamlar';
    return 'İyi geceler';
  }

  @override
  String percent(num value) => '%${formatPercentNumber(value)}';
  @override
  String compactThousands(double major) =>
      '${formatDecimal(major / 1000, decimals: 0, locale: localeCode)}B';
  @override
  String compactMillions(double major) =>
      '${formatDecimal(major / 1000000, locale: localeCode)}Mn';

  // --- Today ----------------------------------------------------------------

  @override
  String get todayMonthNet => 'BU AY NET';
  @override
  String get todayYearNet => 'BU YIL NET';
  @override
  String get todayStatStreak => 'seri';
  @override
  String get todayStatOpenTodos => 'açık görev';
  @override
  String get todayStatWeek => 'hafta';
  @override
  String get todayQuickCapture => 'Hızlı kayıt';
  @override
  String get todayQuickCaptureHint =>
      'Ne oldu? (−250 kahve, habit: koşu, süt al…)';
  @override
  String get todayQuickCaptureAdd => 'Ekle';
  @override
  String get todayQuickCaptureFailed => 'Kayıt eklenemedi';
  @override
  String get todayEmptyDay => 'Bugün plan yok — sakin bir gün ☁';
  @override
  String get todayAllHabitsDone => '✦ Hepsi tamam';
  @override
  String get todayNoHabitsYet => 'Henüz alışkanlık yok — küçük başla';
  @override
  String get todayNoGoalsYet => 'Henüz hedef yok — ilk hedefini koy';
  @override
  String get todayOpenTodos => 'Açık görevler';
  @override
  String get todayNoOpenTodos => 'Açık görev yok — hepsi tamam ✦';
  @override
  String get todayTodosFailed => 'Görevler yüklenemedi';
  @override
  String get todayTodoUpdateFailed => 'Görev güncellenemedi';
  @override
  String get todayHabitUpdateFailed => 'Alışkanlık güncellenemedi';

  // --- Finance --------------------------------------------------------------

  @override
  String get financeScopeMonth => 'Ay';
  @override
  String get financeScopeYear => 'Yıl';
  @override
  String get financeIncome => 'Gelir';
  @override
  String get financeExpense => 'Gider';
  @override
  String get financeTransfer => 'Transfer';
  @override
  String get financeTransaction => 'İşlem';
  @override
  String get financeLast6Months => 'Son 6 ay';
  @override
  String get financeCategoriesThisMonth => 'Kategoriler (bu ay)';
  @override
  String get financeNoSpendThisMonth => 'Bu ay harcama yok';
  @override
  String get financeBudgets => 'Bütçeler';
  @override
  String get financeExceeded => 'aşıldı';
  @override
  String financeRemaining(String amount) => 'kalan $amount';
  @override
  String financeMonthEndEstimate(String amount) => 'Ay sonu tahmini: $amount';
  @override
  String get financeUpcomingSubscriptions => 'Yaklaşan abonelikler';
  @override
  String get financeRecentTransactions => 'Son işlemler';
  @override
  String get financeNoTransactionsYet => 'Henüz işlem yok';
  @override
  String get financeAddFirstAccount => 'İlk hesabını ekle';
  @override
  String get financeAddAccount => 'Hesap ekle';
  @override
  String get financeAddAccountSoon => 'Hesap ekleme yakında';
  @override
  String get financeNoTransactionsInAccount => 'Bu hesapta işlem yok';

  @override
  String accountType(String type) => switch (type) {
        'cash' => 'Nakit',
        'bank' => 'Banka',
        'credit_card' => 'Kredi Kartı',
        'savings' => 'Birikim',
        'crypto' => 'Kripto',
        _ => 'Hesap',
      };

  @override
  String subscriptionFrequency(String frequency) => switch (frequency) {
        'daily' => 'Günlük',
        'weekly' => 'Haftalık',
        'monthly' => 'Aylık',
        'yearly' => 'Yıllık',
        _ => frequency,
      };

  // --- Transactions feed ----------------------------------------------------

  @override
  String get txFilterAccount => 'Hesap';
  @override
  String get txFilterAllAccounts => 'Tüm hesaplar';
  @override
  String get txFilterCategory => 'Kategori';
  @override
  String get txFilterAllCategories => 'Tüm kategoriler';
  @override
  String get txFilterDate => 'Tarih';
  @override
  String get txFilterDateRange => 'Tarih aralığı';
  @override
  String get txFilterThisMonth => 'Bu ay';
  @override
  String get txFilterLast30Days => 'Son 30 gün';
  @override
  String get txFilterThisYear => 'Bu yıl';
  @override
  String get txFilterClear => 'Filtreleri temizle';
  @override
  String get txNoneForFilter => 'Bu filtreyle işlem yok';
  @override
  String get txAllLoaded => 'Tümü yüklendi';
  @override
  String txSummary(String income, String expense) =>
      '$income gelir · $expense gider';
  @override
  String get txDeleteTitle => 'İşlem silinsin mi?';
  @override
  String get txDeleted => 'İşlem silindi';
  @override
  String get txDeleteFailed => 'Silinemedi';
  @override
  String get txSaved => 'İşlem kaydedildi ✓';
  @override
  String get txUpdated => 'İşlem güncellendi ✓';
  @override
  String get txSaveFailed => 'Kaydedilemedi, tekrar dene';

  // --- Transaction form ------------------------------------------------------

  @override
  String get txFormNewTitle => 'İşlem Ekle';
  @override
  String get txFormEditTitle => 'İşlemi Düzenle';
  @override
  String get txFormAccount => 'Hesap';
  @override
  String get txFormTargetAccount => 'Hedef hesap';
  @override
  String get txFormCategory => 'Kategori';
  @override
  String get txFormDate => 'Tarih';
  @override
  String get txFormDescription => 'Açıklama';
  @override
  String get txFormEnterAmount => 'Tutar gir';
  @override
  String get txFormSelectAccount => 'Hesap seç';
  @override
  String get txFormSelectTargetAccount => 'Hedef hesap seç';
  @override
  String get txFormAccountsMustDiffer =>
      'Kaynak ve hedef hesap farklı olmalı';
  @override
  String get txFormSelectCategory => 'Kategori seç';

  // --- Habits ---------------------------------------------------------------

  @override
  String habitsDoneOfTotal(int done, int total) =>
      '$done / $total tamamlandı';
  @override
  String get habitsAllDone => '✦ Hepsi tamam';
  @override
  String get habitsPerfectChain => 'Mükemmel gün zinciri';
  @override
  String get habitsPerfectHistory => 'Mükemmel gün geçmişi';
  @override
  String habitsPerfectStreak(int streak, int record) =>
      'Mükemmel seri: 🔥 $streak · Rekor: $record';
  @override
  String get habitsHistory => 'Geçmiş';
  @override
  String get habitsCreateFirst => 'İlk alışkanlığını oluştur';
  @override
  String get habitsStartSmall => 'Küçük başla';
  @override
  String get habitsAdd => 'Alışkanlık ekle';
  @override
  String get habitsToggleFailed => 'İşaretlenemedi, tekrar dene';
  @override
  String habitsMeta(int streak, int rate) => '🔥 $streak · %$rate (30g)';
  @override
  String get habitsThisWeek => 'Bu hafta';
  @override
  String get habitsThisMonth => 'Bu ay';
  @override
  String habitsPeriodProgress(String period, int done, int target) =>
      '$period $done/$target';
  @override
  String get habitsStatStreak => 'Seri';
  @override
  String get habitsStatRecord => 'Rekor';
  @override
  String get habitsStatRate30d => '30g oranı';
  @override
  String get habitsLast30Days => 'Son 30 gün';
  @override
  String get habitsLast84Days => 'Son 84 gün';
  @override
  String get habitsLegendDone => 'Tamam';
  @override
  String get habitsLegendPartial => 'Kısmi';
  @override
  String get habitsLegendMissed => 'Eksik';
  @override
  String get habitsArchive => 'Arşivle';
  @override
  String habitsArchiveBody(String name) => '$name listeden kaldırılacak.';
  @override
  String get habitsArchiveTitle => 'Alışkanlık arşivlensin mi?';
  @override
  String get habitsArchived => 'Arşivlendi';
  @override
  String get habitsArchiveFailed => 'Arşivlenemedi, tekrar dene';
  @override
  String get habitsFormNewTitle => 'Yeni alışkanlık';
  @override
  String get habitsFormName => 'Alışkanlık adı';
  @override
  String get habitsFormNameHint => 'ör. Su iç, koşu, kitap oku';
  @override
  String get habitsFormNameRequired => 'Bir ad gir';
  @override
  String get habitsFormFrequency => 'Sıklık';
  @override
  String get habitsFormDaily => 'Günlük';
  @override
  String get habitsFormWeekly => 'Haftalık';
  @override
  String get habitsFormMonthly => 'Aylık';
  @override
  String get habitsFormColor => 'Renk';
  @override
  String get habitsFormDailyTarget => 'Günlük hedef';
  @override
  String get habitsFormPeriodTarget => 'Dönem hedefi';
  @override
  String get habitsFormGoalLink => 'Hedef bağlantısı (opsiyonel)';
  @override
  String get habitsFormLinkGoal => 'Hedefe bağla';
  @override
  String get habitsAdded => 'Alışkanlık eklendi ✓';
  @override
  String get habitsSaveFailed => 'Kaydedilemedi, tekrar dene';

  // --- Goals ----------------------------------------------------------------

  @override
  String get goalsTypeFinancial => 'FİNANSAL';
  @override
  String get goalsTypeHabit => 'ALIŞKANLIK';
  @override
  String get goalsTypeCustom => 'ÖZEL';
  @override
  String get goalsStatusAchieved => 'Başarıldı';
  @override
  String get goalsStatusAbandoned => 'Bırakıldı';
  @override
  String get goalsStatusActive => 'Aktif';
  @override
  String get goalsSectionActive => 'Aktif';
  @override
  String get goalsSectionAchieved => 'Başarılanlar';
  @override
  String get goalsSectionAbandoned => 'Bırakılanlar';
  @override
  String get goalsSetFirst => 'İlk hedefini koy';
  @override
  String get goalsSetFirstBody =>
      'Bir hedef belirle, ilerlemeni buradan izle.';
  @override
  String get goalsAdd => 'Hedef ekle';
  @override
  String goalsOverdueBadge(int days) => '${days}g gecikti';
  @override
  String get goalsDueTodayBadge => 'bugün';
  @override
  String goalsDaysLeftBadge(int days) => '${days}g kaldı';
  @override
  String get goalsDetailStatus => 'Durum';
  @override
  String get goalsDetailDeadline => 'Bitiş';
  @override
  String get goalsDetailDaysLeft => 'Kalan gün';
  @override
  String get goalsDetailProgress => 'İlerleme';
  @override
  String get goalsHabitProgress => 'Alışkanlık ilerlemesi';
  @override
  String goalsStreakDays(int days) => '$days günlük seri';
  @override
  String get goalsLinkedAccount => 'Bağlı hesap';
  @override
  String get goalsCurrentBalance => 'Güncel bakiye';
  @override
  String get goalsRefresh => 'Yenile';
  @override
  String get goalsEnterValue => 'Değer gir';
  @override
  String get goalsMarkAbandoned => 'Bırakıldı olarak işaretle';
  @override
  String get goalsAbandonTitle => 'Hedef bırakılsın mı?';
  @override
  String get goalsAbandonBody =>
      'Bu hedefi bırakıldı olarak işaretleyeceksin.';
  @override
  String get goalsAbandonAction => 'Bırak';
  @override
  String get goalsActionFailed => 'İşlem başarısız';
  @override
  String get goalsLoadFailed => 'Hedef yüklenemedi';
  @override
  String goalsProgressDays(String current, String target) =>
      '$current / $target gün';
  @override
  String get goalsFormNewTitle => 'Yeni hedef';
  @override
  String get goalsFormName => 'Hedef adı';
  @override
  String get goalsFormNameRequired => 'Hedef adı gerekli';
  @override
  String get goalsFormDescription => 'Açıklama (isteğe bağlı)';
  @override
  String get goalsFormType => 'Tür';
  @override
  String get goalsFormTypeCustom => 'Özel';
  @override
  String get goalsFormTypeHabit => 'Alışkanlık';
  @override
  String get goalsFormTypeFinancial => 'Finansal';
  @override
  String get goalsFormColor => 'Renk';
  @override
  String get goalsFormTargetValue => 'Hedef değer';
  @override
  String get goalsFormTargetRequired => 'Geçerli bir hedef değer gir';
  @override
  String get goalsFormUnit => 'Birim';
  @override
  String get goalsFormUnitHint => 'kg · gün · TRY';
  @override
  String get goalsFormEndDate => 'Bitiş tarihi';
  @override
  String get goalsFormLinkedAccount => 'Bağlı hesap';
  @override
  String get goalsFormLinkedHabit => 'Bağlı alışkanlık';
  @override
  String get goalsFormSubmit => 'Hedef oluştur';
  @override
  String get goalsCreated => 'Hedef oluşturuldu ✓';
  @override
  String get goalsCreateFailed => 'Hedef oluşturulamadı';

  // --- Journal --------------------------------------------------------------

  @override
  String journalEntriesCount(int count) => '$count kayıt';
  @override
  String get journalNoEntryForMood => 'Bu ruh haliyle kayıt yok';
  @override
  String get journalHowWasToday => 'Bugün nasıldı?';
  @override
  String get journalWriteFirst => 'İlk kaydını yaz';
  @override
  String get journalCreateEntry => 'Kayıt oluştur';
  @override
  String get journalUntitled => 'Adsız';
  @override
  String get journalEnergy => 'Enerji';
  @override
  String get journalGratitude => 'MİNNET';
  @override
  String get journalDeleteTitle => 'Kayıt silinsin mi?';
  @override
  String get journalDeleteBody =>
      'Bu günlük kaydı kalıcı olarak silinecek.';
  @override
  String get journalLoadFailed => 'Kayıt yüklenemedi';
  @override
  String get journalEditorNewTitle => 'Yeni kayıt';
  @override
  String get journalEditorEditTitle => 'Düzenle';
  @override
  String get journalEditorTitleHint => 'Başlık';
  @override
  String get journalEditorBodyHint => 'Bugün neler oldu?';
  @override
  String get journalEditorTags => 'ETİKETLER';
  @override
  String get journalEditorTagsHint => 'virgülle ayır: yürüyüş, aile';
  @override
  String get journalEditorGratitudeHint => 'Bugün ne için minnettarsın?';
  @override
  String get journalEditorMoodPrompt => 'Bugün nasıl hissediyorsun?';
  @override
  String get journalEditorWeather => 'Hava durumu';
  @override
  String get journalEditorNeedsContent =>
      'Bir başlık ya da birkaç satır yaz';
  @override
  String get journalUpdated => 'Güncellendi ✓';
  @override
  String get journalAdded => 'Kayıt eklendi ✓';
  @override
  String get journalSaveFailed => 'Kayıt kaydedilemedi';

  @override
  String moodLabel(String mood) => switch (mood) {
        'great' => 'Harika',
        'good' => 'İyi',
        'neutral' => 'Normal',
        'bad' => 'Kötü',
        'awful' => 'Berbat',
        _ => mood,
      };

  @override
  String weatherLabel(String weather) => switch (weather) {
        'sunny' => 'Güneşli',
        'partly_cloudy' => 'Parçalı bulutlu',
        'cloudy' => 'Bulutlu',
        'rainy' => 'Yağmurlu',
        'snowy' => 'Karlı',
        _ => weather,
      };

  @override
  String journalRange(String range) => switch (range) {
        '7d' => '7g',
        '30d' => '30g',
        '6mo' => '6ay',
        '1y' => '1y',
        _ => 'Tümü',
      };

  // --- Profile and server settings ------------------------------------------

  @override
  String get profileSectionApp => 'Uygulama';
  @override
  String get profileTheme => 'Tema';
  @override
  String get profileThemeDark => 'Koyu';
  @override
  String get profileThemeLight => 'Açık';
  @override
  String get profileThemeSystem => 'Sistem';
  @override
  String get profileLanguage => 'Dil';
  @override
  String get profileLanguageTr => 'Türkçe';
  @override
  String get profileLanguageEn => 'English';
  @override
  String get profileCurrency => 'Para birimi';
  @override
  String get profileSectionServer => 'Sunucu';
  @override
  String get profileSectionAbout => 'Hakkında';
  @override
  String get profileVersion => 'Sürüm';
  @override
  String get profileApiStatus => 'API durumu';
  @override
  String get profileApiOnline => 'Çevrimiçi';
  @override
  String get profileApiUnreachable => 'Ulaşılamıyor';
  @override
  String get profileSignOut => 'Çıkış Yap';
  @override
  String get profileSignOutTitle => 'Çıkış yapılsın mı?';
  @override
  String get profileSignOutBody =>
      'Oturumun kapatılacak. Sunucu adresi kayıtlı kalır.';
  @override
  String get profileFallbackName => 'Kullanıcı';
  @override
  String get profileLanguageSaveFailed =>
      'Dil sunucuya kaydedilemedi — bu cihazda geçerli';
  @override
  String get serverBlurb =>
      'Meridian sunucusunun LAN adresi. Telefonun aynı Wi-Fi ağında olmalı.';
  @override
  String get serverTest => 'Bağlantıyı test et';
  @override
  String get serverConnected => 'Bağlandı';
  @override
  String serverVersion(String version) => 'Meridian v$version';
  @override
  String serverLatency(int ms) => '$ms ms';
  @override
  String get serverCantConnect =>
      'Bağlanılamadı — adresi ve Wi-Fi\'yi kontrol et';
  @override
  String get serverEmpty => 'Sunucu adresi boş olamaz';
  @override
  String get serverUnverifiedTitle => 'Bağlantı doğrulanmadı';
  @override
  String get serverUnverifiedBody =>
      'Bu adrese ulaşılamadı ya da henüz test edilmedi. Yine de kaydedilsin mi?';
  @override
  String get serverSaveAnyway => 'Yine de kaydet';
  @override
  String get serverSaved => 'Sunucu adresi kaydedildi';
}
