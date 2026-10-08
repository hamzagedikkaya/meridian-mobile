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
  String get actionBack => 'Geri dön';
  @override
  String get actionSelect => 'Seç';
  @override
  String get actionSelectOptional => 'Seç (isteğe bağlı)';
  @override
  String get actionSeeAll => 'Tümü →';
  @override
  String get actionUndo => 'Geri al';
  @override
  String get actionDismiss => 'Kapat';
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
  String get syncUpdating => 'Güncelleniyor';
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
  @override
  String get errRecordGoneBody =>
      'Web\'de ya da başka bir cihazda silinmiş olabilir.';

  // --- Server refusals, by the error `code` the API sends -------------------

  @override
  String get errTooManyRequests =>
      'Çok fazla deneme yapıldı. Birkaç dakika sonra tekrar dene.';
  @override
  String errInvalidParameter(String param) =>
      'Sunucu bir değeri kabul etmedi ($param)';
  @override
  String get errValueOutOfRange => 'Bu sayı çok büyük';
  @override
  String get errInvalidDate => 'Geçersiz tarih';
  @override
  String get errInvalidDatetime => 'Geçersiz tarih ya da saat';
  @override
  String get errFutureDate => 'Gelecekteki bir gün işaretlenemez';
  @override
  String errBeforeHabitStart(DateTime? start) => start == null
      ? 'Bu alışkanlık o gün henüz yoktu'
      : 'Bu alışkanlık o gün henüz yoktu '
          '(${formatDate(start, withYear: true, locale: localeCode)} '
          'tarihinde başladı)';
  @override
  String get errHabitArchived => 'Arşivlenmiş alışkanlık işaretlenemez';
  @override
  String get errCaptureEmpty => 'Önce bir şey yaz';
  @override
  String get errNoAccount =>
      'Tutarı kaydetmek için önce bir hesap oluşturman gerek';
  @override
  String errUnknownHabit(String name) => '“$name” adında bir alışkanlık yok';
  @override
  String errInvalidAmount(String? reason) => switch (reason) {
        'zero' => 'Tutar sıfırdan büyük olmalı',
        'too_precise' =>
          'Bu hesabın para birimi bu kadar ondalık basamak almaz',
        'too_large' => 'Tutar çok büyük',
        _ => 'Tutar okunamadı. -250, -12,50 ya da +1.250,50 gibi yaz.',
      };
  @override
  String errHasTransactions(int transactions, int incomingTransfers) =>
      incomingTransfers > 0
          ? 'Bu hesabın $transactions işlemi ve $incomingTransfers gelen '
              'transferi var; silmek yerine arşivle'
          : 'Bu hesabın $transactions işlemi var; silmek yerine arşivle';
  @override
  String get errCurrencyLocked =>
      'İşlemi ya da aboneliği olan bir hesabın para birimi değiştirilemez';
  @override
  String get errKindLocked =>
      'Kullanımda olan bir kategorinin türü değiştirilemez';
  @override
  String get errAmountRequired =>
      'Hesabın para birimi farklı; tutarı da yeniden gir';
  @override
  String errNotChargeable(String? reason) => reason == 'inactive'
      ? 'Duraklatılmış bir abonelik ödendi olarak işaretlenemez'
      : 'Bu aboneliğin sıradaki ödeme tarihi yok';
  @override
  String get errTargetReached =>
      'Hedef değere zaten ulaşıldı; yeniden açmak için hedefi yükselt';
  @override
  String get errTargetNotReached => 'Hedef değere henüz ulaşılmadı';
  @override
  String get errProgressComputed =>
      'Bu hedefin ilerlemesi otomatik hesaplanıyor';
  @override
  String get errBodyHasFormatting =>
      'Bu kayıtta web\'de eklenmiş biçimlendirme var; düzenlersen kalkar';

  @override
  String? validationDetail(String error, {num? count}) => switch (error) {
        'blank' => 'Boş bırakılamaz',
        'taken' => 'Bu zaten kullanılıyor',
        'too_long' =>
          count == null ? 'Çok uzun' : 'En fazla ${_n(count)} karakter olabilir',
        'too_short' =>
          count == null ? 'Çok kısa' : 'En az ${_n(count)} karakter olmalı',
        'inclusion' => 'Geçerli bir seçenek değil',
        'exclusion' => 'Bu değer kullanılamaz',
        'invalid' => 'Geçersiz',
        'not_a_number' => 'Bir sayı olmalı',
        'not_an_integer' => 'Tam sayı olmalı',
        'greater_than' when count != null =>
          '${_n(count)} değerinden büyük olmalı',
        'greater_than_or_equal_to' when count != null =>
          'En az ${_n(count)} olmalı',
        'less_than' when count != null =>
          '${_n(count)} değerinden küçük olmalı',
        'less_than_or_equal_to' when count != null =>
          'En fazla ${_n(count)} olabilir',
        'must_belong_to_same_user' => 'Bu kayıt kullanılamaz',
        'must_be_after_start' => 'Başlangıçtan sonra olmalı',
        'before_start_date' => 'Başlangıç tarihinden sonra olmalı',
        'must_match_kind' => 'Üst kategoriyle aynı türde olmalı',
        'must_be_root' => 'Bir ana kategori olmalı',
        'cannot_have_children' =>
          'Alt kategorileri olan bir kategori başka birinin altına taşınamaz',
        'cannot_be_self' => 'Kendi altına taşınamaz',
        'has_budget' => 'Bütçesi olan bir kategori alt kategori yapılamaz',
        'must_be_expense' => 'Bir gider kategorisi olmalı',
        'kind_mismatch' => 'İşlemin türüyle uyuşmuyor',
        'same_account' => 'Kaynak ve hedef hesap farklı olmalı',
        'currency_mismatch' => 'Hedef hesap aynı para biriminde olmalı',
        'required_for_transfer' => 'Transfer için bir hedef hesap seç',
        'must_match_target_type' => 'Hedefin türüyle uyuşmuyor',
        'unsupported_frequency' =>
          'Günlük, haftalık, aylık ya da yıllık tekrarlanmalı',
        'unsupported_part' => 'Bu tekrar kuralı desteklenmiyor',
        'out_of_range' => 'İzin verilen aralığın dışında',
        'no_occurrences' => 'Bu tekrar hiçbir güne denk gelmiyor',
        _ => null,
      };

  @override
  String? fieldLabel(String field) => switch (field) {
        'name' => 'Ad',
        'title' => 'Başlık',
        'description' => 'Açıklama',
        'body' || 'body_text' || 'text' => 'Metin',
        'note' => 'Not',
        'amount_cents' || 'amount' => 'Tutar',
        'initial_balance_cents' || 'initial_balance' => 'Açılış bakiyesi',
        'limit_cents' => 'Limit',
        'monthly_limit_cents' || 'monthly_limit' => 'Aylık limit',
        'account_type' => 'Hesap türü',
        'next_charge_on' => 'Sonraki ödeme',
        'vendor' => 'Firma',
        'active' => 'Durum',
        'position' => 'Sıra',
        'date' => 'Tarih',
        'deadline' || 'end_date' => 'Bitiş tarihi',
        'start_date' => 'Başlangıç tarihi',
        'start_at' => 'Başlangıç',
        'end_at' => 'Bitiş',
        'due_at' || 'due_date' || 'due_time' => 'Son tarih',
        'account_id' || 'account' => 'Hesap',
        'related_account_id' => 'Hedef hesap',
        'finance_category_id' || 'finance_category' => 'Kategori',
        'parent_id' => 'Üst kategori',
        'currency' => 'Para birimi',
        'color' => 'Renk',
        'frequency' => 'Sıklık',
        'target_count' => 'Hedef sayı',
        'target_value' => 'Hedef değer',
        'current_value' => 'Güncel değer',
        'unit' => 'Birim',
        'related' => 'Bağlantı',
        'recurrence_rule' => 'Tekrar',
        'location' => 'Konum',
        'priority' => 'Öncelik',
        'status' => 'Durum',
        'kind' => 'Tür',
        'mood' => 'Ruh hali',
        'energy_level' => 'Enerji',
        'tags' => 'Etiketler',
        'gratitude' => 'Minnet',
        'email' => 'E-posta',
        'password' || 'current_password' => 'Şifre',
        'todo_list_id' => 'Liste',
        'goal_id' => 'Hedef',
        _ => null,
      };

  /// A limit as a plain number in Turkish notation.
  String _n(num value) => formatDecimal(
        value,
        decimals: value == value.roundToDouble() ? 0 : 2,
        locale: localeCode,
      );

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
      withYear: date.year != appToday().year,
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
      'Ne oldu? (-250 kahve, +1.500 maaş, alışkanlık: koşu, süt al)';
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
  @override
  String todayTodoDone(String title) => '“$title” tamamlandı';
  @override
  String todayZoneNotice(String zone, String offset) =>
      'Günler ve saatler hesabının saat dilimine göre: $zone (UTC$offset)';

  // --- Quick capture --------------------------------------------------------

  @override
  String captureSavedExpense(String amount, String description) =>
      'Harcama eklendi · $amount · $description';
  @override
  String captureSavedIncome(String amount, String description) =>
      'Gelir eklendi · $amount · $description';
  @override
  String captureSavedHabit(String name, {required bool completed}) =>
      completed ? '“$name” bugün tamamlandı ✓' : '“$name” işaretlendi';
  @override
  String captureSavedTodo(String title) => 'Görev eklendi: $title';
  @override
  String captureSaved(String summary) => 'Kaydedildi: $summary';
  @override
  String get captureLooksLikeEvent =>
      'Bir etkinlik gibi görünüyor — henüz kaydedilmedi.';
  @override
  String get captureNotSaved => 'Hiçbir şey kaydedilmedi';
  @override
  String get captureMaybeSaved =>
      'Sunucu zamanında yanıt vermedi — kaydedilmiş olabilir. '
      'Yeniden göndermeden önce kontrol et.';
  @override
  String get captureSaveAsTodo => 'Görev olarak kaydet';
  @override
  String get captureAddAsEvent => 'Etkinlik olarak ekle';
  @override
  String get captureCreateAccount => 'Hesap oluştur';
  @override
  String captureCreateHabit(String name) => '“$name” alışkanlığını oluştur';

  // --- Habit day log --------------------------------------------------------

  @override
  String get habitLogToday => 'Bugünün kaydı';
  @override
  String get habitLogDone => 'Bugün tamamlandı';
  @override
  String get habitLogNotDone => 'Bugün henüz yapılmadı';
  @override
  String get habitLogComplete => 'Tamamla';
  @override
  String get habitLogReset => 'Sıfırla';
  @override
  String get habitLogDecrease => 'Bir azalt';
  @override
  String get habitLogIncrease => 'Bir artır';
  @override
  String habitLogSemantics(
    String name, {
    required int count,
    required int target,
    required bool done,
  }) {
    if (done) return '$name, bugün tamamlandı';
    if (target > 1) return '$name, $count / $target';
    return '$name, henüz yapılmadı';
  }

  @override
  String get habitLogHint => 'Ayarlamak için basılı tut';

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
  String get financeLast6Months => 'Son 6 ay';
  @override
  String get financeCategoriesThisMonth => 'Kategoriler (bu ay)';
  @override
  String get financeNoSpendThisMonth => 'Bu ay harcama yok';
  @override
  String get financeBudgets => 'Bütçeler';
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
  String get financeAddAccount => 'Hesap ekle';
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
  String get txFormNote => 'Not';
  @override
  String get txFormAmount => 'Tutar';
  @override
  String get txFilterGroupExpense => 'GİDER';
  @override
  String get txFilterGroupIncome => 'GELİR';
  @override
  String get txFilterCustomRange => 'Özel aralık';
  @override
  String get txFormTransferSameCurrency =>
      'Transfer yalnızca aynı para birimindeki hesaplar arasında yapılır.';
  @override
  String get txFormNoTransferTarget =>
      'Aynı para biriminde başka bir hesap yok';
  @override
  String get txFormNeedAccount => 'Önce bir hesap oluştur';

  // --- Forms, keypad and undo -----------------------------------------------

  @override
  String get actionAdd => 'Ekle';
  @override
  String get actionDone => 'Tamam';
  @override
  String get actionArchive => 'Arşivle';
  @override
  String get actionRestore => 'Geri yükle';
  @override
  String get actionMoreOptions => 'Diğer seçenekler';
  @override
  String get labelOptional => 'isteğe bağlı';
  @override
  String get formDiscardTitle => 'Değişiklikler kaydedilmedi';
  @override
  String get formKeepEditing => 'Düzenlemeye devam';
  @override
  String get formDiscard => 'Değişiklikleri at';
  @override
  String amountTooLarge(String max) => 'En fazla $max girilebilir';
  @override
  String get keypadBackspace => 'Son rakamı sil';
  @override
  String get keypadDecimalMark => 'Ondalık virgül';
  @override
  String get keypadClearHint => 'Tümünü silmek için basılı tut';
  @override
  String get errDeleteFailed => 'Silinemedi; geri getirildi';
  @override
  String colorSwatch(int index) => 'Renk $index';

  // --- Finance: setup, accounts, menus --------------------------------------

  @override
  String get financeAccounts => 'Hesaplar';
  @override
  String get financeAddTransactionFab => 'İşlem';
  @override
  String get financeMenuCategories => 'Kategoriler';
  @override
  String get financeMenuSubscriptions => 'Abonelikler';
  @override
  String get financeMenuArchivedAccounts => 'Arşivlenmiş hesaplar';
  @override
  String get financeFirstRunTitle => 'İlk hesabını oluştur';
  @override
  String get financeFirstRunBody =>
      'Paran nerede duruyorsa onu ekle: nakit, banka ya da kredi kartı. '
      'Sonra ilk işlemini kaydedersin.';
  @override
  String get financeFirstRunCash => 'Nakit hesabıyla başla';
  @override
  String get financeFirstRunOther => 'Başka bir hesap ekle';
  @override
  String get financeCashAccountName => 'Nakit';
  @override
  String get financeFirstTxTitle => 'İlk işlemini ekle';
  @override
  String get financeFirstTxBody =>
      'Bir harcama ya da gelir kaydet; bakiyen ve bu ayın özeti buradan '
      'güncellenir.';
  @override
  String get financeFirstTxAction => 'İşlem ekle';
  @override
  String get financeNoActiveAccounts => 'Aktif hesabın yok';
  @override
  String get financeNoActiveAccountsBody =>
      'Bütün hesapların arşivde. Birini geri yükle ya da yeni bir hesap aç.';
  @override
  String get financeUncategorized => 'Kategorisiz';
  @override
  String get financeCategorize => 'Kategorize et';
  @override
  String get financeOtherCategories => 'Diğer';
  @override
  String get financeAddBudget => 'Bütçe ekle';
  @override
  String get financeBudgetsEmpty =>
      'Bir kategoriye aylık sınır koy, ay sonunu önceden gör.';
  @override
  String financeBudgetSpentOf(String spent, String limit) => '$spent / $limit';
  @override
  String financeOverBy(String amount) => '$amount fazla';
  @override
  String get financeNoUpcomingPayments => 'Önümüzdeki 30 günde ödeme yok';
  @override
  String get financeAddSubscription => 'Abonelik ekle';
  @override
  String get financeSubscriptionsEmpty =>
      'Düzenli ödemelerini ekle, sabit giderini tek bir sayıda gör.';

  // --- Account form, archive, delete ----------------------------------------

  @override
  String get accountFormNewTitle => 'Yeni hesap';
  @override
  String get accountFormEditTitle => 'Hesabı düzenle';
  @override
  String get accountFormType => 'Hesap türü';
  @override
  String get accountFormName => 'Hesap adı';
  @override
  String get accountFormNameRequired => 'Bir ad gir';
  @override
  String get accountFormCurrency => 'Para birimi';
  @override
  String get accountFormCurrencyLocked =>
      'Bu hesapta işlem ya da abonelik olduğu için para birimi değişmez.';
  @override
  String get accountFormOpeningBalance => 'Açılış bakiyesi';
  @override
  String get accountFormOpeningBalanceHint =>
      'Hesapta bugün duran tutar. Kredi kartı borcunu “Borç” ile gir.';
  @override
  String get accountFormDebt => 'Borç';
  @override
  String get accountFormColor => 'Renk';
  @override
  String get accountFormCreate => 'Hesabı oluştur';
  @override
  String get accountNew => 'Yeni hesap';
  @override
  String accountCreated(String name) => '“$name” hesabı açıldı ✓';
  @override
  String get accountUpdated => 'Hesap güncellendi ✓';
  @override
  String get accountSaveFailed => 'Hesap kaydedilemedi';
  @override
  String accountArchived(String name) => '“$name” arşivlendi';
  @override
  String accountRestored(String name) => '“$name” geri yüklendi';
  @override
  String get accountArchiveFailed => 'Hesap arşivlenemedi';
  @override
  String get accountRestoreFailed => 'Hesap geri yüklenemedi';
  @override
  String get accountArchivedBadge => 'Arşivde';
  @override
  String get accountArchivedNote =>
      'Bu hesap arşivde: listelerde ve seçicilerde görünmez, işlemleri '
      'toplamlarda sayılmaya devam eder.';
  @override
  String accountDeleted(String name) => '“$name” silindi';
  @override
  String get accountDeleteFailed => 'Hesap silinemedi';
  @override
  String get accountCantDeleteTitle => 'Bu hesap silinemez';
  @override
  String accountDeleteTitle(String name) => '“$name” silinsin mi?';
  @override
  String accountDeleteConsequences({
    required int subscriptions,
    required int goals,
  }) =>
      [
        if (subscriptions > 0)
          'Bu hesaptan ödenen $subscriptions abonelik de silinecek.',
        if (goals > 0)
          'Bu hesaba bağlı $goals hedefin bağlantısı kalkacak; bu hedefler '
              'bundan sonra tüm gelirini izler.',
      ].join(' ');
  @override
  String get accountGone => 'Bu hesap silinmiş';
  @override
  String get titleArchivedAccounts => 'Arşivlenmiş hesaplar';
  @override
  String get archivedAccountsEmpty => 'Arşivlenmiş hesap yok';
  @override
  String get archivedAccountsBody =>
      'Arşivlediğin hesaplar burada durur; istediğinde geri yükle.';

  // --- Finance categories ----------------------------------------------------

  @override
  String get titleCategories => 'Kategoriler';
  @override
  String get categoriesEmptyExpense => 'Henüz gider kategorisi yok';
  @override
  String get categoriesEmptyIncome => 'Henüz gelir kategorisi yok';
  @override
  String get categoriesEmptyBody =>
      'Kategoriler harcamalarını gruplar; bütçeler de onlara konur.';
  @override
  String get categoriesAddFab => 'Kategori';
  @override
  String get categoriesStarter => 'Hazır kategorileri ekle';
  @override
  String get categoriesStarterAdded => 'Hazır kategoriler eklendi ✓';
  @override
  String get categoriesStarterFailed =>
      'Kategorilerin bir kısmı eklenemedi, tekrar dene';
  @override
  List<String> starterCategories(String kind) => kind == 'income'
      ? const ['Maaş', 'Diğer gelir']
      : const [
          'Market',
          'Ulaşım',
          'Faturalar',
          'Kira',
          'Yemek',
          'Sağlık',
          'Eğlence',
          'Diğer',
        ];
  @override
  String get categoryNew => 'Yeni kategori';
  @override
  String get categoryFormNewTitle => 'Yeni kategori';
  @override
  String get categoryFormEditTitle => 'Kategoriyi düzenle';
  @override
  String get categoryFormName => 'Kategori adı';
  @override
  String get categoryFormNameRequired => 'Bir ad gir';
  @override
  String get categoryFormKind => 'Tür';
  @override
  String get categoryFormKindLocked =>
      'Kullanımda olduğu için türü değiştirilemez.';
  @override
  String get categoryFormParent => 'Üst kategori';
  @override
  String get categoryFormNoParent => 'Yok — ana kategori';
  @override
  String get categoryFormParentLocked =>
      'Alt kategorileri olduğu için başka bir kategorinin altına alınamaz.';
  @override
  String get categoryFormColor => 'Renk';
  @override
  String categoryCreated(String name) => '“$name” eklendi ✓';
  @override
  String get categoryUpdated => 'Kategori güncellendi ✓';
  @override
  String get categorySaveFailed => 'Kategori kaydedilemedi';
  @override
  String categoryDeleted(String name) => '“$name” silindi';
  @override
  String categoryDeleteTitle(String name) => '“$name” silinsin mi?';
  @override
  String categoryDeleteImpact({
    required int transactions,
    required int subscriptions,
    required int children,
    required int budgets,
  }) =>
      [
        if (transactions > 0) '$transactions işlem kategorisiz kalacak.',
        if (subscriptions > 0) '$subscriptions abonelik kategorisiz kalacak.',
        if (children > 0) '$children alt kategori de silinecek.',
        if (budgets > 0) '$budgets bütçe silinecek.',
      ].join(' ');
  @override
  String get categoryDeleteFailed => 'Kategori silinemedi';
  @override
  String categoryChildren(int count) => '$count alt kategori';
  @override
  String get categoryLoadFailed => 'Kategori yüklenemedi';

  // --- Budgets ---------------------------------------------------------------

  @override
  String get budgetNewTitle => 'Yeni bütçe';
  @override
  String budgetEditTitle(String category) => '$category bütçesi';
  @override
  String get budgetCategory => 'Kategori';
  @override
  String get budgetLimit => 'Aylık limit';
  @override
  String get budgetLimitRequired => 'Sıfırdan büyük bir limit gir';
  @override
  String get budgetPickCategory => 'Bir kategori seç';
  @override
  String get budgetNoCategories =>
      'Bütçe konabilecek bir gider kategorisi kalmadı. Önce bir tane ekle.';
  @override
  String budgetCurrencyNote(String currency) =>
      'Bütçeler profilindeki para biriminde ($currency) tutulur.';
  @override
  String get budgetCreated => 'Bütçe eklendi ✓';
  @override
  String get budgetUpdated => 'Bütçe güncellendi ✓';
  @override
  String get budgetSaveFailed => 'Bütçe kaydedilemedi';
  @override
  String get budgetRemove => 'Bütçeyi kaldır';
  @override
  String budgetRemoved(String category) => '“$category” bütçesi kaldırıldı';

  // --- Subscriptions ---------------------------------------------------------

  @override
  String get titleSubscriptions => 'Abonelikler';
  @override
  String subscriptionsMonthly(String amount) => 'Aylık sabit giderin $amount';
  @override
  String subscriptionsYearly(String amount) => 'yılda $amount';
  @override
  String get subscriptionsActive => 'Aktif';
  @override
  String get subscriptionsPaused => 'Duraklatılmış';
  @override
  String get subscriptionsEmpty => 'Henüz abonelik yok';
  @override
  String get subscriptionsAddFab => 'Abonelik';
  @override
  String get subscriptionFormNewTitle => 'Yeni abonelik';
  @override
  String get subscriptionFormEditTitle => 'Aboneliği düzenle';
  @override
  String get subscriptionFormName => 'Ad';
  @override
  String get subscriptionFormNameHint => 'ör. Netflix, kira, spor salonu';
  @override
  String get subscriptionFormNameRequired => 'Bir ad gir';
  @override
  String get subscriptionFormAmount => 'Tutar';
  @override
  String get subscriptionFormAmountRequired => 'Sıfırdan büyük bir tutar gir';
  @override
  String get subscriptionFormFrequency => 'Sıklık';
  @override
  String get subscriptionFormAccount => 'Hesap';
  @override
  String get subscriptionFormNextCharge => 'Sonraki ödeme';
  @override
  String get subscriptionFormNextChargeAuto => 'Bir dönem sonra';
  @override
  String get subscriptionFormCategory => 'Kategori';
  @override
  String get subscriptionFormVendor => 'Firma';
  @override
  String get subscriptionFormNote => 'Not';
  @override
  String get subscriptionFormColor => 'Renk';
  @override
  String get subscriptionFormMore => 'Daha fazla ayrıntı';
  @override
  String get subscriptionCreated => 'Abonelik eklendi ✓';
  @override
  String get subscriptionUpdated => 'Abonelik güncellendi ✓';
  @override
  String get subscriptionSaveFailed => 'Abonelik kaydedilemedi';
  @override
  String subscriptionAmountPer(String amount, String frequency) =>
      switch (frequency) {
        'weekly' => '$amount / hafta',
        'yearly' => '$amount / yıl',
        _ => '$amount / ay',
      };
  @override
  String subscriptionNextOn(String date) => 'Sonraki ödeme: $date';
  @override
  String get subscriptionNoDate => 'Ödeme tarihi yok';
  @override
  String get subscriptionOverdue => 'Gecikmiş';
  @override
  String get subscriptionPausedLabel => 'Duraklatıldı';
  @override
  String get subscriptionCharge => 'Ödendi olarak kaydet';
  @override
  String subscriptionCharged(String amount) => 'Ödeme kaydedildi · $amount';
  @override
  String get subscriptionChargeFailed => 'Ödeme kaydedilemedi';
  @override
  String get subscriptionChargeMaybe =>
      'Sunucu zamanında yanıt vermedi — ödeme kaydedilmiş olabilir. '
      'Tekrar denemeden önce işlemlere bak.';
  @override
  String get subscriptionPause => 'Durdur';
  @override
  String get subscriptionResume => 'Devam ettir';
  @override
  String subscriptionPausedDone(String name) => '“$name” durduruldu';
  @override
  String subscriptionResumedDone(String name) => '“$name” yeniden aktif';
  @override
  String get subscriptionToggleFailed => 'Abonelik güncellenemedi';
  @override
  String subscriptionDeleted(String name) => '“$name” silindi';

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
  String get goalsGone => 'Bu hedef silinmiş';
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
  String get journalDeleteFailed => 'Kayıt silinemedi';
  @override
  String get journalLoadFailed => 'Kayıt yüklenemedi';
  @override
  String get journalGone => 'Bu günlük kaydı silinmiş';
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
  String get profileTimeZone => 'Saat dilimi';
  @override
  String profileTimeZoneValue(String zone, String offset) =>
      '$zone (UTC$offset)';
  @override
  String profileTimeZoneDeviceDiffers(String deviceOffset) =>
      'Bu cihaz UTC$deviceOffset kullanıyor. Günler ve saatler hesabının '
      'saat dilimine göre gösterilir.';
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
