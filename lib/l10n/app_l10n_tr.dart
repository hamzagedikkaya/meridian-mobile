import '../core/formats.dart';
import '../models/event.dart';
import '../theme/entity_color.dart' show RecordSwatch;
import 'app_l10n.dart';

/// Turkish copy. Keep this file and [AppL10nEn] member-for-member identical —
/// the abstract base enforces it.
class AppL10nTr extends AppL10n {
  const AppL10nTr();

  @override
  String get localeCode => 'tr';

  // --- Generic actions and words --------------------------------------------
  // region common (WP-1)

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
  @override
  String get actionClose => 'Kapat';
  @override
  String get actionSearch => 'Ara';
  @override
  String get labelAllDone => 'Hepsi tamam';
  @override
  String streakDays(int days) => '$days günlük seri';
  @override
  String streakNewRecord(int record) => 'Yeni seri · Rekor $record';
  @override
  String get semProfileAndSettings => 'Profil ve ayarlar';
  @override
  String get semDragToReorder => 'Sıralamak için sürükle';
  @override
  String colorName(RecordSwatch swatch) => switch (swatch) {
        RecordSwatch.gold => 'Altın',
        RecordSwatch.sage => 'Adaçayı',
        RecordSwatch.dustyBlue => 'Toz mavisi',
        RecordSwatch.clay => 'Kil',
        RecordSwatch.tan => 'Ten',
        RecordSwatch.mauve => 'Mor',
        RecordSwatch.teal => 'Deniz',
        RecordSwatch.amber => 'Amber',
      };
  // endregion

  // --- Navigation and screen titles -----------------------------------------
  // region shell (WP-4)

  @override
  String get tabToday => 'Bugün';
  @override
  String get tabAgenda => 'Ajanda';
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
  @override
  String semAgendaOverdue(int count) => '$count gecikmiş görev';
  @override
  String get titleEvents => 'Etkinlikler';
  @override
  String get titleSearch => 'Ara';
  @override
  String get searchComingSoon => 'Her yerde arama yakında burada';
  @override
  String get subscriptionUndoFailed =>
      'Ödeme geri alınamadı. İşlemler sayfasından silebilirsin.';
  // endregion

  // --- Search ----------------------------------------------------------------
  // region search (WP-16)
  // endregion

  // --- Errors, offline, session ---------------------------------------------
  // region errors (WP-1)

  @override
  String get errServerUnreachable => 'Sunucuya ulaşılamıyor';
  @override
  String get errCheckWifi => 'Wi-Fi veya Tailscale bağlantını kontrol et';
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
      'Sunucuya ulaşılamıyor — Wi-Fi veya Tailscale bağlantını kontrol et';
  @override
  String get noticeSessionExpired => 'Oturum süresi doldu, tekrar giriş yap';
  @override
  String get errRecordGoneBody =>
      'Web\'de ya da başka bir cihazda silinmiş olabilir.';
  // endregion

  // --- Server refusals, by the error `code` the API sends -------------------
  // region server refusals (WP-1)

  @override
  String get errTooManyRequests =>
      'Çok fazla deneme yapıldı. Birkaç dakika sonra tekrar dene.';
  @override
  String get errCurrentPasswordRequired => 'Mevcut şifreni gir';
  @override
  String get errInvalidCurrentPassword => 'Mevcut şifre yanlış';
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
        'wrong_length' => count == null
            ? 'Uzunluğu geçersiz'
            : 'Tam ${_n(count)} karakter olmalı',
        'confirmation' => 'Yeni şifreyle eşleşmiyor',
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
        'password' => 'Şifre',
        'current_password' => 'Mevcut şifre',
        'password_confirmation' => 'Şifre tekrarı',
        'timezone' => 'Saat dilimi',
        'weekly_review_day' => 'Haftalık değerlendirme günü',
        'locale' => 'Dil',
        'theme_preference' => 'Tema',
        'todo_list_id' => 'Liste',
        'goal_id' => 'Hedef',
        'list_id' => 'Liste',
        'todos' => 'Görevler',
        'done' => 'Durum',
        'all_day' => 'Tüm gün',
        'event_type' => 'Etkinlik türü',
        _ => null,
      };

  /// A limit as a plain number in Turkish notation.
  String _n(num value) => formatDecimal(
        value,
        decimals: value == value.roundToDouble() ? 0 : 2,
        locale: localeCode,
      );
  // endregion

  // --- Login and server address ---------------------------------------------
  // region login (WP-14)

  @override
  String get loginEmail => 'E-posta';
  @override
  String get loginPassword => 'Şifre';
  @override
  String get loginSubmit => 'Giriş yap';
  @override
  String get serverAddress => 'Sunucu adresi';
  @override
  String get serverAddressShort => 'Sunucu adresi';
  @override
  String get serverAddressUnreachable =>
      'Sunucuya ulaşılamadı — adresi, Wi-Fi veya Tailscale bağlantını kontrol et';
  @override
  String get loginEmailRequired => 'E-posta gir';
  @override
  String get loginPasswordRequired => 'Şifre gir';
  @override
  String get loginRateLimited =>
      'Çok fazla deneme — biraz bekleyip tekrar dene';
  @override
  String get serverAddressHint =>
      'http://192.168.1.20:3000 ya da http://mac.tailnet.ts.net:3000';
  @override
  String get serverHelpAction => 'Adresi nereden bulurum?';
  @override
  String get serverHelpTitle => 'Sunucu adresini bul';
  @override
  String get serverHelpLanTitle => 'Aynı ağdaysan: yerel IP';
  @override
  String get serverHelpLanBody =>
      'Meridian\'ın çalıştığı bilgisayarda Wi-Fi ayrıntılarına bak: '
      '192.168.1.20 gibi bir adres.';
  @override
  String get serverHelpTailscaleTitle => 'Başka yerdeysen: Tailscale adı';
  @override
  String get serverHelpTailscaleBody =>
      'Tailscale uygulamasında bilgisayarın MagicDNS adını kopyala, '
      'mac.tailnet.ts.net gibi. Bu telefonda da Tailscale açık olmalı.';
  @override
  String get serverHelpPortTitle => 'Sonuna port: 3000';
  @override
  String get serverHelpPortBody =>
      'Adresi http:// ile başlat, :3000 ile bitir: http://192.168.1.20:3000';
  // endregion

  // --- Dates and relative days ----------------------------------------------
  // region dates (WP-1)

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
  // endregion

  // --- Today ----------------------------------------------------------------
  // region today (WP-5)

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
  String get todayEmptyDay => 'Bugün plan yok — sakin bir gün';
  @override
  String get todayAllHabitsDone => 'Hepsi tamam';
  @override
  String get todayNoHabitsYet => 'Henüz alışkanlık yok — küçük başla';
  @override
  String get todayNoGoalsYet => 'Henüz hedef yok — ilk hedefini koy';
  @override
  String get todayOpenTodos => 'Açık görevler';
  @override
  String get todayNoOpenTodos => 'Açık görev yok — hepsi tamam';
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

  @override
  String todayDateLine(DateTime day) =>
      '${formatWeekday(day, locale: 'tr')}, ${formatDate(day, locale: 'tr')}';
  @override
  String todayGreeting(String greeting, String firstName) =>
      firstName.isEmpty ? greeting : '$greeting, $firstName';
  @override
  String get todayCaptureLabel => 'Ekle: görev, harcama, etkinlik…';
  @override
  String get todayCaptureTransaction => 'İşlem ekle';
  @override
  String todayNextUpNow(String title) => 'Şimdi · $title';
  @override
  String todayNextUpSoon(String time, String title, int minutes) =>
      '$time · $title · $minutes dk';
  @override
  String get todayAddForToday => 'Bugün için görev ekle';
  @override
  String todayEventsPassed(int count) => '+$count geçti';
  @override
  String todayMoreRows(int count) => '+$count daha';
  @override
  String get todayShowFinished => 'Tamamlananları göster';
  @override
  String get todayHideFinished => 'Tamamlananları gizle';
  @override
  String get todaySetGoal => 'Bir hedef koy';
  @override
  String get todayJournalWrite => 'Yaz';
  @override
  String get todayJournalWritten => 'Bugün yazdın';
  @override
  String todayNudgeYesterday(String habit) =>
      'Dünü işaretlemeyi unuttun mu? · $habit';
  @override
  String todayNudgeLate(String name, String amount) =>
      '$name ödemesi gecikti · $amount';
  @override
  String get todayNudgePaid => 'Ödendi';
  @override
  String todayStartTitle(int done, int total) => 'Başlayalım · $done/$total';
  @override
  String get todayStartCash => 'Nakit hesabı aç';
  @override
  String get todayStartHabit => 'Bir alışkanlık seç';
  @override
  String get todayStartTodo => 'İlk görevini ekle';
  @override
  String get todayStartJournal => 'Bugünü yaz';
  @override
  String get todayStartHabitTitle => 'Bir alışkanlıkla başla';
  @override
  String get todayStartHabitOwn => 'Kendin yaz';
  @override
  List<String> get todayHabitStarters => const [
        'Su iç',
        'Yürüyüş',
        'Kitap oku',
        'Meditasyon',
        'Erken kalk',
        'Esneme',
      ];
  // endregion

  // --- Quick capture --------------------------------------------------------
  // region quick capture (WP-6)

  @override
  String captureSavedExpense(String amount, String account) =>
      'Harcama eklendi · $amount · $account';
  @override
  String captureSavedIncome(String amount, String account) =>
      'Gelir eklendi · $amount · $account';
  @override
  String captureSavedHabit(String name, {required bool completed}) =>
      completed ? '“$name” bugün tamamlandı' : '“$name” işaretlendi';
  @override
  String captureSavedTodo(String title) => 'Görev eklendi · $title';
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
  String get captureCreateAccount => 'Nakit hesabı aç';
  @override
  String captureCreateHabit(String name) => '“$name” alışkanlığını oluştur';
  @override
  String get quickAddTitle => 'Hızlı ekle';
  @override
  String get quickAddHint => 'Ne eklemek istersin?';
  @override
  String quickAddAuto(String? guess) =>
      guess == null ? 'Otomatik' : 'Otomatik · $guess';
  @override
  String get quickAddKindTask => 'Görev';
  @override
  String get quickAddKindExpense => 'Harcama';
  @override
  String get quickAddKindIncome => 'Gelir';
  @override
  String get quickAddKindEvent => 'Etkinlik';
  @override
  String get quickAddKindHabit => 'Alışkanlık';
  @override
  String get quickAddAction => 'Ekle';
  @override
  String get quickAddActionTask => 'Görev ekle';
  @override
  String get quickAddActionExpense => 'Harcama ekle';
  @override
  String get quickAddActionIncome => 'Gelir ekle';
  @override
  String get quickAddActionEvent => 'Etkinlik olarak aç';
  @override
  String get quickAddActionHabit => 'Alışkanlığı işaretle';
  @override
  List<String> get quickAddExamples => const [
        '−85 kahve',
        '+1.500 maaş',
        'yarın 15:00 dişçi',
        'alışkanlık: su',
        'süt al',
      ];
  @override
  String get quickAddPickHabit => 'Hangi alışkanlık?';
  @override
  String get quickAddNoHabits => 'Bugün için alışkanlık yok';
  @override
  String get quickAddNewHabit => 'Alışkanlık oluştur';
  @override
  String get quickAddHabitsFailed => 'Alışkanlıklar yüklenemedi';
  @override
  String get quickAddHabitDone => 'Bugün tamamlandı';
  @override
  String get quickAddFailed => 'Eklenemedi';
  @override
  String get quickAddUndoFailed => 'Geri alınamadı';
  // endregion

  // --- Todos and todo lists -------------------------------------------------
  // region todos (WP-7)

  @override
  String get titleTodos => 'Görevler';
  @override
  String todoFilter(String filter) => switch (filter) {
        'today' => 'Bugün',
        'upcoming' => 'Yaklaşan',
        'week' => 'Bu hafta',
        'overdue' => 'Gecikmiş',
        'undated' => 'Tarihsiz',
        'done' => 'Tamamlanan',
        'cancelled' => 'İptal edilen',
        'all' => 'Tümü',
        _ => 'Açık',
      };
  @override
  String todoFilterEmpty(String filter) => switch (filter) {
        'today' => 'Bugün için görev yok',
        'upcoming' => 'Önümüzdeki 7 günde görev yok',
        'week' => 'Bu hafta görev yok',
        'overdue' => 'Gecikmiş görev yok — harika',
        'undated' => 'Tarihsiz görev yok',
        'done' => 'Henüz tamamlanan görev yok',
        'cancelled' => 'İptal edilen görev yok',
        _ => 'Açık görev yok — hepsi tamam',
      };
  @override
  String get todoAllLists => 'Tüm listeler';
  @override
  String get todoNoList => 'Listesiz';
  @override
  String get todoGroupOverdue => 'Gecikmiş';
  @override
  String get todoGroupUndated => 'Tarihsiz';
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
        if (overdue && !done) 'gecikmiş',
        if (done) 'tamamlandı',
      ].join(', ');
  @override
  String get todoAdd => 'Görev';
  @override
  String get todoAddInline => 'Görev ekle';
  @override
  String get todoNewTitle => 'Yeni görev';
  @override
  String get todoEditTitle => 'Görevi düzenle';
  @override
  String get todoFieldTitle => 'Başlık';
  @override
  String get todoFieldNotes => 'Notlar';
  @override
  String get todoFieldDue => 'Tarih';
  @override
  String get todoDuePick => 'Tarih seç';
  @override
  String get todoAddTime => 'Saat ekle';
  @override
  String get todoRemoveTime => 'Saati kaldır';
  @override
  String get todoFieldPriority => 'Öncelik';
  @override
  String todoPriority(String priority) => switch (priority) {
        'low' => 'Düşük',
        'high' => 'Yüksek',
        'urgent' => 'Acil',
        _ => 'Orta',
      };
  @override
  String get todoFieldList => 'Liste';
  @override
  String get todoFieldGoal => 'Hedef';
  @override
  String get todoGoalLinked => 'Bağlı hedef';
  @override
  String get todoTitleRequired => 'Bir başlık yaz';
  @override
  String get todoSaveAndNew => 'Kaydet ve yeni';
  @override
  String todoCreated(String title) => 'Görev eklendi: $title';
  @override
  String get todoUpdated => 'Görev güncellendi';
  @override
  String get todoSaveFailed => 'Görev kaydedilemedi';
  @override
  String todoDeleted(String title) => '“$title” silindi';
  @override
  String get todoDeleteFailed => 'Görev silinemedi';
  @override
  String get todoComplete => 'Tamamla';
  @override
  String get todoReopen => 'Yeniden aç';
  @override
  String get todoPostpone => 'Yarına ertele';
  @override
  String todoPostponed(String title) => '“$title” yarına ertelendi';
  @override
  String todoAllOpen(int count) => 'Tüm açık görevler ($count)';
  @override
  String get todoNoneUpcoming => 'Önümüzdeki 7 günde görev yok';

  @override
  String get todoListsTitle => 'Listeler';
  @override
  String get todoListsManage => 'Listeleri yönet';
  @override
  String get todoListNew => 'Yeni liste';
  @override
  String get todoListEdit => 'Listeyi düzenle';
  @override
  String get todoListName => 'Ad';
  @override
  String get todoListNameRequired => 'Listeye bir ad ver';
  @override
  String get todoListColor => 'Renk';
  @override
  String todoListCounts(int open, int total) => '$open açık · $total görev';
  @override
  String get todoListsEmpty =>
      'Henüz liste yok — görevlerini Ev, İş gibi listelere ayır';
  @override
  String todoListCreated(String name) => '“$name” listesi oluşturuldu';
  @override
  String get todoListUpdated => 'Liste güncellendi';
  @override
  String get todoListSaveFailed => 'Liste kaydedilemedi';
  @override
  String todoListDeleteTitle(String name) => '“$name” listesi silinsin mi?';
  @override
  String todoListDeleteBody(int total) => total == 0
      ? 'Bu liste boş.'
      : 'Bu listede $total görev var (tamamlananlar dahil).';
  @override
  String get todoListDeleteKeep => 'Görevleri listesiz bırak';
  @override
  String get todoListDeleteAll => 'Görevlerle birlikte sil';
  @override
  String todoListDeleted(String name) => '“$name” listesi silindi';
  @override
  String get todoListDeleteFailed => 'Liste silinemedi';

  @override
  String get todoMoreFields => 'Daha fazla';
  @override
  String todoMovedToday(String title) => '“$title” bugüne alındı';
  @override
  String todoMovedOn(String title, String day) => '“$title” taşındı · $day';
  @override
  String todosMovedToday(int count) => '$count görev bugüne alındı';
  @override
  String todoReopened(String title) => '“$title” yeniden açıldı';
  @override
  String get todoListsArchived => 'Arşivlenmiş';
  @override
  String todoListArchived(String name) => '“$name” listesi arşivlendi';
  @override
  String todoListRestored(String name) => '“$name” listesi geri yüklendi';
  // endregion

  // --- Events and agenda ----------------------------------------------------
  // region agenda (WP-7)

  @override
  String get titleAgenda => 'Ajanda';
  @override
  String get agendaThisWeek => 'Bu hafta';
  @override
  String get agendaEmptyWeek => 'Bu hafta etkinlik yok';
  @override
  String get agendaEmpty => 'Önümüzdeki günlerde etkinlik yok';
  @override
  String get agendaShowMore => 'Daha fazla göster';
  @override
  String get agendaLoadFailed => 'Etkinlikler yüklenemedi';
  @override
  String agendaMore(int count) => '+$count etkinlik daha';
  @override
  String get eventAdd => 'Etkinlik';
  @override
  String get eventNewTitle => 'Yeni etkinlik';
  @override
  String get eventEditTitle => 'Etkinliği düzenle';
  @override
  String get eventFieldTitle => 'Başlık';
  @override
  String get eventStarts => 'Başlangıç';
  @override
  String get eventEnds => 'Bitiş';
  @override
  String get eventNoEnd => 'Bitiş yok';
  @override
  String get eventAddEnd => 'Bitiş ekle';
  @override
  String get eventRemoveEnd => 'Bitişi kaldır';
  @override
  String get eventLocation => 'Konum';
  @override
  String get eventDescription => 'Açıklama';
  @override
  String get eventFieldType => 'Tür';
  @override
  String eventType(String type) => switch (type) {
        'work' => 'İş',
        'health' => 'Sağlık',
        'finance' => 'Finans',
        'other' => 'Diğer',
        _ => 'Kişisel',
      };
  @override
  String get eventColor => 'Renk';
  @override
  String get eventRepeat => 'Tekrar';
  @override
  String recurrence(RecurrencePreset preset) => switch (preset) {
        RecurrencePreset.none => 'Tekrarlanmaz',
        RecurrencePreset.daily => 'Her gün',
        RecurrencePreset.weekdays => 'Hafta içi her gün',
        RecurrencePreset.weekly => 'Her hafta',
        RecurrencePreset.monthly => 'Her ay',
        RecurrencePreset.yearly => 'Her yıl',
        RecurrencePreset.custom => 'Özel tekrar (webde ayarlandı)',
      };
  @override
  String get eventRepeatEnds => 'Tekrar bitişi';
  @override
  String get eventRepeatForever => 'Hiç';
  @override
  String recurrenceUntil(DateTime day) =>
      '${formatDate(day, withYear: day.year != appToday().year, locale: localeCode)} '
      'tarihine kadar';
  @override
  String recurrenceCount(int count) => '$count kez';
  @override
  String get eventTitleRequired => 'Bir başlık yaz';
  @override
  String get eventEndBeforeStart => 'Bitiş başlangıçtan sonra olmalı';
  @override
  String get eventSeriesFormNote =>
      'Bu değişiklik serideki tüm etkinlikleri etkiler';
  @override
  String get eventSeriesNote =>
      'Tekrarlayan etkinlik: düzenlemek ya da silmek serideki tüm etkinlikleri '
      'etkiler.';
  @override
  String eventCreated(String title) => '“$title” eklendi';
  @override
  String get eventUpdated => 'Etkinlik güncellendi';
  @override
  String get eventSaveFailed => 'Etkinlik kaydedilemedi';
  @override
  String eventDeleted(String title) => '“$title” silindi';
  @override
  String get eventDeleteFailed => 'Etkinlik silinemedi';
  @override
  String get eventDeleteSeriesTitle => 'Tekrarlayan etkinlik';
  @override
  String eventDeleteFollowing(DateTime day) => 'Bu ve sonrakileri sil';
  @override
  String eventDeleteFollowingHint(DateTime day) =>
      '${formatDate(day, withYear: day.year != appToday().year, locale: localeCode)} '
      'öncesindeki etkinlikler kalır.';
  @override
  String get eventDeleteAll => 'Tüm seriyi sil';
  @override
  String get eventDeleteAllHint => 'Serideki bütün etkinlikler silinir.';
  @override
  String eventSeriesEnded(String title) =>
      '“$title” serisi bu tarihten itibaren kaldırıldı';
  @override
  String get eventLoadFailed => 'Etkinlik yüklenemedi';
  @override
  String eventSemantics(String title, {required String when, String? where}) =>
      [title, when, ?where].join(', ');

  @override
  String get agendaViewUpcoming => 'Yaklaşan';
  @override
  String get agendaViewInbox => 'Gelen kutusu';
  @override
  String get agendaViewOverdue => 'Gecikmiş';
  @override
  String get agendaViewDone => 'Tamamlanan';
  @override
  String agendaChipCount(String label, int count) => '$label · $count';
  @override
  String agendaListChip(String? name) => 'Liste: ${name ?? 'Tümü'}';
  @override
  String get agendaLater => 'Sonra';
  @override
  String get agendaUpcomingEmpty => 'Önümüzdeki günler sakin';
  @override
  String get agendaUpcomingEmptyBody =>
      'Eklediğin görevler ve etkinlikler burada gün gün sıralanır.';
  @override
  String get agendaTodayEmpty => 'Bugün için plan yok';
  @override
  String get agendaInboxEmpty =>
      'Gelen kutun boş — tarihsiz görevler burada toplanır';
  @override
  String get agendaCaptureLabel => 'Ekle: görev, etkinlik…';
  @override
  String get agendaAddEvent => 'Etkinlik ekle';
  @override
  String get agendaShowDone => 'Tamamlananlar';
  @override
  String get agendaDayAddHint => 'bu güne ekle';
  @override
  String get eventDate => 'Tarih';
  @override
  String get eventEndDay => 'Bitiş günü';
  @override
  String get eventSameDay => 'Aynı gün';
  @override
  String get eventTime => 'Saat';
  @override
  String get eventMoreFields => 'Daha fazla';
  @override
  String recurrenceWeeklyOn(String weekday) => 'Her hafta $weekday';
  // endregion

  // --- Habit day log --------------------------------------------------------
  // region habit log (WP-11)

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
  @override
  String get habitLogAdd => 'Ekle';
  @override
  String get habitLogSet => 'Ayarla';
  @override
  String habitLogPlus(int n) => '+$n';
  @override
  String get habitLogToTarget => 'Hedefe tamamla';
  @override
  String habitLogNow(int count) => 'Şu an $count';
  @override
  String habitLogNowPlus(int count, int add) => 'Şu an $count · +$add';
  // endregion

  // --- Finance --------------------------------------------------------------
  // region finance (WP-8)

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
  String get financeUpcomingSubscriptions => 'Yaklaşan ödemeler';
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
        'credit_card' => 'Kredi kartı',
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
  @override
  String get financeMonthNet => 'BU AY NET';
  @override
  String financeYearNet(String amount) => 'Bu yıl $amount';
  @override
  String financeInsightVsLastMonth(String amount, {required bool less}) =>
      'Geçen ayın aynı gününe göre $amount daha ${less ? 'az' : 'fazla'} '
      'harcadın';
  @override
  String financeInsightProjection(
    String amount,
    int percent, {
    required bool below,
  }) =>
      percent == 0
          ? 'Bu tempoyla ay sonu gider $amount, 5 aylık ortalamayla aynı'
          : 'Bu tempoyla ay sonu gider $amount, 5 aylık ortalamanın '
              '%$percent ${below ? 'altında' : 'üstünde'}';
  @override
  String financeInsightSpent(String amount, String perDay) =>
      'Bu ay $amount harcadın · günde ortalama $perDay';
  @override
  String get financeCurrencyNoteMixed =>
      'Bu toplam farklı para birimlerini dönüştürmeden içerir';
  @override
  String get financeCurrencyNoteExcluded =>
      'Diğer para birimleri bu toplama dahil değil';
  @override
  String financeSixMonthInsight(int percent, {required bool below}) =>
      percent == 0
          ? 'Bu ay gider 6 ay ortalamasında'
          : 'Bu ay gider 6 ay ortalamasının %$percent '
              '${below ? 'altında' : 'üstünde'}';
  @override
  String financeCategoriesInsight(String name, String amount) =>
      'En büyük kalem $name · $amount';
  @override
  String get financeSearch => 'İşlemlerde ara';
  @override
  String get financeMenuAddBudget => 'Bütçe ekle';
  @override
  String financeSetupTitle(int done, int total) => 'Kurulum $done/$total';
  @override
  String get financeSetupAccount => 'Hesap aç';
  @override
  String get financeSetupBudget => 'Bütçe koy';
  @override
  String get financeSetupSubscription => 'Düzenli ödemeni ekle';
  @override
  String get financePaid => 'Ödendi';
  @override
  String financeSubscriptionsMonthly(String amount) => 'aylık $amount';
  @override
  String financeBudgetPerDay(String amount, int daysLeft) => daysLeft <= 1
      ? 'Bugün $amount · son gün'
      : 'Günde $amount · $daysLeft gün kaldı';
  @override
  String get financeBudgetEditLimit => 'Limiti düzenle';
  // endregion

  // --- Transactions feed ----------------------------------------------------
  // region transactions (WP-9)

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
  String get txSaved => 'İşlem kaydedildi';
  @override
  String get txUpdated => 'İşlem güncellendi';
  @override
  String get txSaveFailed => 'Kaydedilemedi, tekrar dene';
  @override
  String get txLinkedTitle => 'Bağlı işlem';
  @override
  String get txLinkedDeletedAlong =>
      'Bu işlem silinirse bağlı işlem de silinir.';
  @override
  String get txLinkedStays => 'Bu işlem silinirse bağlı işlem silinmez.';
  @override
  String txDeleteLinkedTitle(String name) => '“$name” silinsin mi?';
  @override
  String txDeleteLinkedBody(String linked) =>
      'Bağlı işlem de silinecek: $linked. Bu geri alınamaz.';
  @override
  String get txDeleteBoth => 'İkisini de sil';
  @override
  String get txDeletedWithLinked => 'İşlem ve bağlı işlem silindi';
  @override
  String get txGone => 'Bu işlem silinmiş';
  @override
  String get txFilterKind => 'Tür';
  @override
  String txFilterKindValue(String kind) => 'Tür: $kind';
  @override
  String get txSearchHint => 'Açıklama ya da notta ara';
  @override
  String get txSearchClose => 'Aramayı kapat';
  @override
  String txSearchEmpty(String query) => 'Sonuç yok · “$query”';
  @override
  String get txSearchClear => 'Aramayı temizle';
  @override
  String get txSearchEverywhere => 'Her yerde ara';
  @override
  String get txCopyToToday => 'Bugüne kopyala';
  @override
  String get txCopiedToToday => 'Bugüne kopyalandı';
  @override
  String get txCopyFailed => 'Kopyalanamadı';
  @override
  String txDaySpent(String amount) => 'Gider $amount';
  // endregion

  // --- Transaction form ------------------------------------------------------
  // region transaction form (WP-9)

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
  @override
  String get txFormAccountsLoading => 'Hesaplar yükleniyor…';
  @override
  String get txFormAccountsFailed =>
      'Hesaplar yüklenemedi. Tekrar denemek için dokun.';
  @override
  String txFormAccountChip(String name) => 'Hesap: $name';
  @override
  String get txFormAddDescription => 'Açıklama';
  @override
  String get txFormMore => 'Daha fazla';
  @override
  String get txFormAllCategories => 'Tümü…';
  @override
  String get txFormPickDate => 'Tarih seç';
  @override
  String get txFormSource => 'Kaynak';
  @override
  String get txFormTarget => 'Hedef';
  @override
  String get txFormSwap => 'Hesapları değiştir';
  @override
  String txFormBalanceAfter(String amount) => 'sonra: $amount';
  @override
  String get txFormEditAmount => 'Tutarı düzenle';
  // endregion

  // --- Forms, keypad and undo -----------------------------------------------
  // region forms and controls (WP-2)

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
  @override
  String get actionSeeAllShort => 'Tümü';
  @override
  String get actionHide => 'Gizle';
  @override
  String get captureBarSemantics => 'Hızlı ekle';
  @override
  String get moneyGlanceThisMonth => 'Bu ay';
  @override
  String moneyGlanceSemantics(String amount) =>
      "Bu ay net $amount, Finans'ı aç";
  @override
  String get moneyGlanceStart => 'Nakit hesabıyla başla';
  // endregion

  // --- Numbers, progress, motion and celebrations ----------------------------
  // region numbers and motion (WP-3)
  @override
  String get dayHeaderMoveAllToToday => 'Hepsini bugüne al';
  @override
  String chartAverage(String amount) => 'ort. $amount';
  @override
  String chartPaceTooltip(String date, String amount, String? previous) =>
      previous == null
          ? '$date · $amount'
          : '$date · $amount / geçen ay $previous';
  @override
  String lingeringFinished(int count) => '$count tamamlandı';
  @override
  String milestoneStreak(int days, String habit) => '$days gün · $habit';
  @override
  String get milestonePerfectWeek => 'İlk mükemmel hafta';
  @override
  String milestoneGoal(String goal) => 'Hedefe ulaştın · $goal';
  @override
  String get milestoneDismissHint => 'Kapatmak için dokun';
  // endregion

  // --- Finance: setup, accounts, menus --------------------------------------
  // region accounts (WP-8)

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
  String get financeSliceAll => 'Tümü';
  @override
  String get financeSliceAllMeta => 'Alt kategoriler dahil';
  @override
  String financeSliceDirect(String name) => '$name (genel)';
  @override
  String get financeBudgetsEmpty =>
      'Bir kategoriye aylık sınır koy — ay sonunu önceden gör';
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
  @override
  String get financeSubscriptionsGhost => 'Düzenli ödemelerini ekle';
  @override
  String accountsTotal(String totals) => 'Toplam $totals';
  @override
  String get accountsTotalsTitle => 'Para birimine göre toplam';
  @override
  String get accountFab => 'Hesap';
  @override
  String accountTileSemantics(String name, String type, String balance) =>
      '$name, $type, $balance';
  @override
  String accountTypeOverline(String type) => switch (type) {
        'cash' => 'NAKİT',
        'bank' => 'BANKA',
        'credit_card' => 'KREDİ KARTI',
        'savings' => 'BİRİKİM',
        'crypto' => 'KRİPTO',
        _ => 'HESAP',
      };
  @override
  String accountMonthSummary(String? income, String? expense) => 'Bu ay ${[
        if (income != null) '$income gelir',
        if (expense != null) '$expense gider',
      ].join(' · ')}';
  @override
  String get accountReconcile => 'Bakiyeyi eşitle';
  @override
  String accountLinkedGoals(int count) => 'Bağlı hedefler ($count)';
  @override
  String get reconcileTitle => 'Gerçek bakiye';
  @override
  String reconcileNowAndDifference(String now, String? difference) =>
      difference == null
          ? 'Şu anki: $now'
          : 'Şu anki: $now · Fark: $difference';
  @override
  String get reconcileDone => 'Bakiye eşitlendi';
  @override
  String get reconcileFailed => 'Bakiye eşitlenemedi';
  @override
  String get reconcileUndoFailed => 'Eski bakiyeye dönülemedi';
  @override
  String get accountDefaultBadge => 'Varsayılan';
  // endregion

  // --- Account form, archive, delete ----------------------------------------
  // region account form (WP-8)

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
  String accountCreated(String name) => '“$name” hesabı açıldı';
  @override
  String get accountUpdated => 'Hesap güncellendi';
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
  String accountCantDeleteArchived(int transactions, int incomingTransfers) {
    final history = [
      if (transactions > 0) '$transactions işlemi',
      if (incomingTransfers > 0) '$incomingTransfers gelen transferi',
    ];
    final has =
        history.isEmpty ? '' : 'Bu hesabın ${history.join(' ve ')} var. ';
    return '${has}Geçmişi olan bir hesap silinemez; arşivde kalır ve '
        'işlemleri toplamlarda sayılmaya devam eder.';
  }
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
  @override
  String get accountFormDefault => 'Varsayılan hesap';
  @override
  String get accountFormDefaultHint =>
      'Yeni işlemler bu hesapla başlar · bu cihazda';
  // endregion

  // --- Finance categories ----------------------------------------------------
  // region categories (WP-10)

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
  String get categoriesStarterAdded => 'Hazır kategoriler eklendi';
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
  String categoryCreated(String name) => '“$name” eklendi';
  @override
  String get categoryUpdated => 'Kategori güncellendi';
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
    String? movedTo,
  }) =>
      [
        if (transactions > 0)
          movedTo == null
              ? '$transactions işlem kategorisiz kalacak.'
              : '$transactions işlem “$movedTo” kategorisine taşınacak.',
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
  @override
  String get categoriesEmpty => 'Henüz kategori yok';
  @override
  String categoryMonthSpend(String amount) => 'Bu ay $amount';
  @override
  String get categoryMoveTo => 'İşlemler şuraya taşınsın';
  @override
  String get categoryDeleteAndMove => 'Sil ve taşı';
  @override
  String categoryDeletedMoved(String name, int count) =>
      '“$name” silindi · $count işlem taşındı';
  @override
  String categoryMoving(int count) => '$count işlem taşınıyor…';
  @override
  String categoryMovePartial(int moved, int total) =>
      'Kategori silinemedi · $total işlemin $moved tanesi taşındı';
  // endregion

  // --- Budgets ---------------------------------------------------------------
  // region budgets (WP-10)

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
  String get budgetCreated => 'Bütçe eklendi';
  @override
  String get budgetUpdated => 'Bütçe güncellendi';
  @override
  String get budgetSaveFailed => 'Bütçe kaydedilemedi';
  @override
  String get budgetRemove => 'Bütçeyi kaldır';
  @override
  String budgetRemoved(String category) => '“$category” bütçesi kaldırıldı';
  // endregion

  // --- Subscriptions ---------------------------------------------------------
  // region subscriptions (WP-10)

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
  String get subscriptionCreated => 'Abonelik eklendi';
  @override
  String get subscriptionUpdated => 'Abonelik güncellendi';
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
  @override
  String get subscriptionsMonthlyLabel => 'Aylık sabit giderin';
  @override
  String subscriptionsActiveCount(int count) => '$count aktif';
  @override
  String subscriptionsPausedCount(int count) => '$count duraklatılmış';
  @override
  String get subscriptionsThisWeek => 'Bu hafta';
  @override
  String get subscriptionsThisMonth => 'Bu ay';
  @override
  String get subscriptionsLater => 'Sonra';
  @override
  String get subscriptionPaid => 'Ödendi';
  @override
  String subscriptionPaidFor(String name) => '$name ödendi olarak kaydet';
  @override
  String get subscriptionSkip => 'Atla';
  @override
  String subscriptionSkipped(String name, String date) =>
      '“$name” atlandı · sonraki $date';
  @override
  String get subscriptionSkipFailed => 'Ödeme atlanamadı';
  @override
  String get subscriptionMoreActions => 'Diğer seçenekler';
  @override
  String get subscriptionFormInWeek => '1 hafta';
  @override
  String get subscriptionFormInMonth => '1 ay';
  @override
  String get subscriptionFormStart => 'Başlangıç';
  @override
  String get subscriptionFormEnd => 'Bitiş';
  @override
  String get subscriptionFormNotSet => 'Yok';
  @override
  String get subscriptionFormClearDate => 'Tarihi kaldır';
  @override
  String get subscriptionFormOtherCurrency =>
      'Bu hesap başka bir para birimi kullanıyor. Tutarı o para biriminde gir.';
  // endregion

  // --- Habits ---------------------------------------------------------------
  // region habits (WP-11)

  @override
  String habitsDoneOfTotal(int done, int total) =>
      '$done / $total tamamlandı';
  @override
  String get habitsAllDone => 'Hepsi tamam';
  @override
  String get habitsPerfectChain => 'Mükemmel gün zinciri';
  @override
  String get habitsPerfectHistory => 'Mükemmel gün geçmişi';
  @override
  String habitsPerfectStreak(int streak, int record) =>
      'Mükemmel seri: $streak gün · Rekor: $record';
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
  String habitsMeta(int streak, int rate) => 'Seri $streak · %$rate (30g)';
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
  String habitsArchiveBody(String name) =>
      '$name Bugün\'den ve listeden kalkar, artık işaretlenemez. Geçmişi '
      'saklanır; Arşiv\'den geri alabilirsin.';
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
  String get habitsAdded => 'Alışkanlık eklendi';
  @override
  String get habitsSaveFailed => 'Kaydedilemedi, tekrar dene';
  @override
  String get habitsFormEditTitle => 'Alışkanlığı düzenle';
  @override
  String get habitsFormDescription => 'Açıklama (isteğe bağlı)';
  @override
  String get habitsFormDescriptionHint => 'ör. Kahvaltıdan önce, 2 bardak';
  @override
  String get habitsFormHistoryNote =>
      'Geçmiş günler kaydedildikleri gibi kalır; değişiklik bugünden itibaren geçerli.';
  @override
  String get habitsUpdated => 'Alışkanlık güncellendi';
  @override
  String habitsArchiveFreezes(String goals) =>
      'Şu hedefler bu alışkanlığın tamamlanan günlerini sayıyor: $goals. '
      'Arşivlersen ilerlemeleri durur, yeni gün eklenmez.';
  @override
  String habitsArchivedNamed(String name) => '“$name” arşivlendi';
  @override
  String get habitsUnarchive => 'Arşivden çıkar';
  @override
  String habitsUnarchived(String name) => '“$name” yeniden aktif';
  @override
  String get habitsUnarchiveFailed => 'Arşivden çıkarılamadı';
  @override
  String get habitsDelete => 'Alışkanlığı sil';
  @override
  String habitsDeleteTitle(String name) => '“$name” silinsin mi?';
  @override
  String habitsDeleteBody({required int days, required String goals}) {
    final logs = days == 0
        ? 'Henüz işaretlenmiş günü yok.'
        : 'İşaretlenmiş $days günün kaydı, serileri ve oranları kalıcı olarak silinir.';
    final linked = goals.isEmpty
        ? ''
        : ' Bu alışkanlığı sayan hedefler ($goals) bağlantısız kalır ve '
            'son değerini korur; ilerlemeyi bundan sonra elle girersin.';
    return '$logs$linked Bu geri alınamaz.';
  }

  @override
  String habitsDeleted(String name) => '“$name” silindi';
  @override
  String get habitsDeleteFailed => 'Alışkanlık silinemedi';
  @override
  String get habitsArchivedTitle => 'Arşivlenmiş alışkanlıklar';
  @override
  String get habitsArchivedEmpty => 'Arşivde alışkanlık yok';
  @override
  String get habitsArchivedEmptyBody =>
      'Arşivlediğin alışkanlıklar geçmişleriyle burada durur.';
  @override
  String habitsArchivedOn(String date) => 'Arşivlendi: $date';
  @override
  String get habitsArchivedNote =>
      'Arşivde: işaretlenemez ve Bugün\'de görünmez. Geçmişi saklanır.';
  @override
  String habitsTrackedBy(String goals) => 'Bu alışkanlığı sayan hedefler: $goals';
  @override
  String habitsServesGoal(String goal) => 'Hedef: $goal';
  @override
  String get habitsCalendar => 'Takvim';
  @override
  String get habitsCalendarHint => 'Kaydını düzeltmek için bir güne dokun.';
  @override
  String get habitsPrevMonth => 'Önceki ay';
  @override
  String get habitsNextMonth => 'Sonraki ay';
  @override
  String get habitsDayFuture => 'Gelecek günler işaretlenemez.';
  @override
  String habitsDayBeforeStart(String date) =>
      'Bu alışkanlık o gün henüz yoktu ($date tarihinde başladı).';
  @override
  String get habitsDayDone => 'Yapıldı';
  @override
  String get habitsDayNotDone => 'Yapılmadı';
  @override
  String habitsDaySemantics(
    String date, {
    required int count,
    required int target,
    required bool done,
    required bool loggable,
  }) {
    final state = done
        ? 'yapıldı'
        : count > 0
            ? '$count / $target'
            : 'yapılmadı';
    return loggable ? '$date, $state' : '$date, $state, kaydedilemez';
  }
  @override
  String get habitsNew => 'Yeni';
  @override
  String get habitsMenuArchive => 'Arşiv';
  @override
  String habitsAddedNamed(String name) => '“$name” eklendi';
  @override
  String get habitsPickFirst => 'İlk alışkanlığını seç';
  @override
  String get habitsStarterBody =>
      'Birine dokun, hemen eklensin; sonra düzenleyebilirsin.';
  @override
  String get habitsStarterWater => 'Su';
  @override
  String get habitsStarterWaterChip => 'Su · günde 8';
  @override
  String get habitsStarterWalk => 'Yürüyüş';
  @override
  String get habitsStarterRead => 'Kitap';
  @override
  String get habitsStarterReadChip => 'Kitap · 10 sayfa';
  @override
  String get habitsStarterSleep => 'Erken yat';
  @override
  String get habitsStarterMeditate => 'Meditasyon';
  @override
  String get habitsStarterCustom => 'Özel…';
  @override
  String habitsDoneOfTotalRest(int total) => ' / $total tamamlandı';
  @override
  String habitsPerfectMeta(int streak, int record) =>
      'Mükemmel seri $streak · Rekor $record';
  @override
  String habitsRate30d(int rate) => '%$rate (30g)';
  @override
  String get habitsDayStateDone => 'tamamlandı';
  @override
  String get habitsDayStatePartial => 'kısmi';
  @override
  String get habitsDayStateMissed => 'eksik';
  @override
  String get habitsDayStatePending => 'bekliyor';
  @override
  String get habitsDayStateNone => 'kayıt yok';
  @override
  String get habitsLegendToday => 'Bugün';
  @override
  String get habitsDayCannotLog => 'Kaydedilemez';
  @override
  String habitsStartedOn(String date) => 'Başlangıç $date';
  @override
  String habitsCadenceDaily(int target) =>
      target == 1 ? 'Günlük' : 'Günlük · $target/gün';
  @override
  String habitsCadenceWeekly(int target) => 'Haftalık · $target gün';
  @override
  String habitsCadenceMonthly(int target) => 'Aylık · $target gün';
  @override
  String get habitsTrackingGoals => 'İzleyen hedefler';
  @override
  String get habitsSetGoal => 'Bu alışkanlık için hedef koy';
  @override
  String get habitsDeleteForever => 'Kalıcı olarak sil';
  @override
  String habitsTargetDaily(int target) => 'günde $target kez';
  @override
  String habitsTargetWeekly(int target) => 'haftada $target gün';
  @override
  String habitsTargetMonthly(int target) => 'ayda $target gün';
  @override
  String get habitsTargetTypeHint => 'Hedefi yazmak için dokun';
  @override
  String get habitsFormMore => 'Daha fazla';
  @override
  String habitsFormStarted(String date) => 'Başlangıç: $date';
  // endregion

  // --- Goals ----------------------------------------------------------------
  // region goals (WP-12)

  @override
  String get goalsTypeFinancial => 'BİRİKİM';
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
  String get goalsFormColor => 'Renk';
  @override
  String get goalsFormTargetValue => 'Hedef değer';
  @override
  String get goalsFormTargetRequired => 'Geçerli bir hedef değer gir';
  @override
  String goalsNumberAmbiguous(String mark) =>
      'Belirsiz sayı: ondalık için “$mark” kullan, binlik ayırıcı koyma';
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
  String get goalsCreated => 'Hedef oluşturuldu';
  @override
  String get goalsCreateFailed => 'Hedef oluşturulamadı';
  @override
  String get goalsFormEditTitle => 'Hedefi düzenle';
  @override
  String get goalsUpdated => 'Hedef güncellendi';
  @override
  String get goalsSaveFailed => 'Hedef kaydedilemedi';
  @override
  String get goalsFormCurrentValue => 'Mevcut ilerleme';
  @override
  String get goalsFormNoDeadline => 'Yok';
  @override
  String get goalsFormTypeChangeNote =>
      'Tür değişince eski bağlantı kalkar; hedef o anki değerini korur.';
  @override
  String get goalsReopen => 'Yeniden aç';
  @override
  String get goalsReopened => 'Hedef yeniden açıldı';
  @override
  String get goalsReopenTitle => 'Hedefi yeniden aç';
  @override
  String goalsReopenNeedsHigherTarget(String current) =>
      'İlerleme hedefe zaten ulaştı ($current). Yeniden açmak için daha '
      'yüksek bir hedef gir.';
  @override
  String goalsReopenTargetTooLow(String current) =>
      'Hedef, mevcut ilerlemeden ($current) büyük olmalı';
  @override
  String get goalsMarkAchieved => 'Tamamlandı olarak işaretle';
  @override
  String get goalsMarkedAchieved => 'Hedef tamamlandı';
  @override
  String get goalsAbandonedSnack => 'Hedef bırakıldı';
  @override
  String get goalsDelete => 'Hedefi sil';
  @override
  String goalsDeleted(String name) => '“$name” silindi';
  @override
  String get goalsDeleteFailed => 'Hedef silinemedi';
  @override
  String get goalsLinkAccount => 'Hesap bağla';
  @override
  String get goalsLinkHabit => 'Alışkanlık bağla';
  @override
  String get goalsChangeLink => 'Bağlantıyı değiştir';
  @override
  String get goalsNoHabitLinked =>
      'Bağlı alışkanlık yok: ilerlemeyi elle girersin. Bir alışkanlık '
      'bağlarsan tamamlanan günleri sayılır.';
  @override
  String get goalsNoAccountLinked =>
      'Bağlı hesap yok: ilerleme tüm gelirlerinden hesaplanıyor. Bir hesap '
      'bağlarsan bakiyesi izlenir.';
  @override
  String goalsLinked(String name) => '“$name” bağlandı';
  @override
  String get goalsUnlinked => 'Bağlantı kaldırıldı';
  @override
  String get goalsTotalIncome => 'Toplam gelir';
  @override
  String goalsDaysOverdue(int days) => '$days gün geçti';
  @override
  String get goalsMore => 'Diğer işlemler';
  @override
  String get goalsNew => 'Yeni';
  @override
  String get goalsKindSavings => 'Birikim hedefi';
  @override
  String get goalsKindSavingsBody => 'Bir hesabın bakiyesi ya da gelirlerin';
  @override
  String get goalsKindHabit => 'Alışkanlık hedefi';
  @override
  String get goalsKindHabitBody => 'Bir alışkanlığın tamamlanan günleri';
  @override
  String get goalsKindCustom => 'Özel hedef';
  @override
  String get goalsKindCustomBody => 'İlerlemeyi sen girersin';
  @override
  String get goalsProgressNotSaved => 'İlerleme kaydedilemedi';
  @override
  String goalsStepAdd(String amount) => '$amount ekle';
  @override
  String goalsStepRemove(String amount) => '$amount çıkar';
  @override
  String get goalsMarkToday => 'Bugünü işaretle';
  @override
  String get goalsTodayDone => 'Bugün tamam';
  @override
  String get goalsOpenHabit => 'Alışkanlığa git';
  @override
  String get goalsOpenAccount => 'Hesaba git';
  @override
  String get goalsIncomeCounts => 'Tüm gelirlerin sayılır';
  @override
  String get goalsAddProgress => 'İlerleme ekle';
  @override
  String goalsDeadlineMonths(int months) => '$months ay';
  @override
  String get goalsDeadlinePick => 'Tarih';
  @override
  String get goalsFormMore => 'Daha fazla';
  // endregion

  // --- Journal --------------------------------------------------------------
  // region journal (WP-13)

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
  String get journalUpdated => 'Güncellendi';
  @override
  String get journalAdded => 'Kayıt eklendi';
  @override
  String get journalSaveFailed => 'Kayıt kaydedilemedi';
  @override
  String journalRichNotice(String formatting) =>
      'Bu kayıt web\'de biçimlendirilmiş ($formatting). Başlığı, ruh halini '
      've etiketleri güvenle düzenleyebilirsin; metni değiştirirsen '
      'biçimlendirme kalkar.';
  @override
  String get journalRichConfirmTitle => 'Biçimlendirme kaldırılsın mı?';
  @override
  String journalRichConfirmBody(String formatting) =>
      'Metni değiştirdin. Kaydedersen web\'de eklenen biçimlendirme '
      '($formatting) kalkar, yazın düz metin olarak saklanır.';
  @override
  String get journalRichConfirmAction => 'Yine de kaydet';
  @override
  String journalFormatting(String kind) => switch (kind) {
        'bold' => 'kalın yazı',
        'italic' => 'italik',
        'strikethrough' => 'üstü çizili',
        'link' => 'bağlantı',
        'heading' => 'başlık',
        'quote' => 'alıntı',
        'code' => 'kod',
        'list' => 'liste',
        'attachment' => 'ek',
        _ => 'diğer',
      };
  @override
  String get journalDraftRestored => 'Kaydedilmemiş taslak geri yüklendi';
  @override
  String get journalDraftDiscard => 'Taslağı at';
  @override
  String get journalDraftRestoredStale =>
      'Taslak geri yüklendi. Bu kayıt o zamandan beri başka yerde değişti; kaydetmeden önce kontrol et';
  @override
  String get journalEditorEntryGone =>
      'Bu kayıt başka yerde silindi. Yazdıkların burada duruyor; yeni kayıt olarak kaydedebilirsin';
  @override
  String get journalEditorSaveAsNew => 'Yeni kayıt olarak kaydet';
  @override
  String get journalDeleted => 'Kayıt silindi';
  @override
  String get journalEditorMood => 'Ruh hali';
  @override
  String get journalEditorMoodClear => 'Ruh halini kaldır';

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
  @override
  String journalRangeLong(String range) => switch (range) {
        '7d' => 'Son 7 gün',
        '30d' => 'Son 30 gün',
        '6mo' => 'Son 6 ay',
        '1y' => 'Son 1 yıl',
        _ => 'Tümü',
      };
  @override
  String get journalRangeTitle => 'Aralık';
  @override
  String journalStreakWeeks(int weeks) => '$weeks haftadır yazıyorsun';
  @override
  String get journalTodayOverline => 'BUGÜN';
  @override
  String get journalEmptyRange => 'Bu aralıkta kayıt yok';
  @override
  String get journalAllEntries => 'Tüm kayıtlar';
  @override
  String journalTagFilter(String tag) => 'Etiket: $tag';
  @override
  String get journalNoEntryForFilter => 'Bu filtreyle kayıt yok';
  @override
  String get journalClearFilters => 'Filtreleri temizle';
  @override
  String get journalFabWrite => 'Yaz';
  @override
  String journalEnergyValue(int level) => 'Enerji $level / 5';
  @override
  String journalDraftSavedAt(String time) => 'Taslak $time';
  @override
  String get journalChipTags => 'Etiket';
  @override
  String get journalChipGratitude => 'Minnet';
  @override
  String get journalChipWeather => 'Hava';
  @override
  String journalEditorDateLabel(String date) => 'Tarih: $date. Değiştir';
  @override
  String get journalEditorWeatherClear => 'Havayı kaldır';
  // endregion

  // --- Profile and server settings ------------------------------------------
  // region profile (WP-14)

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
      '$zone, UTC$offset';
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
  String get profileApiOnline => 'Bağlı';
  @override
  String get profileApiUnreachable => 'Ulaşılamıyor';
  @override
  String get profileSignOut => 'Çıkış yap';
  @override
  String get profileSignOutTitle => 'Çıkış yapılsın mı?';
  @override
  String get profileSignOutBody =>
      'Bu cihazdaki oturum kapanır ve sunucudaki oturumun iptal edilir '
      '(tüm cihazlarda).';
  @override
  String get profileFallbackName => 'Kullanıcı';
  @override
  String get profileLanguageSaveFailed =>
      'Dil sunucuya kaydedilemedi — bu cihazda geçerli';
  @override
  String get profileThemeSaveFailed =>
      'Tema sunucuya kaydedilemedi — bu cihazda geçerli';
  @override
  String get profileSignOutEverywhere => 'Tüm cihazlarda oturumu kapatır';
  @override
  String get profileSignOutDraft =>
      'Kaydedilmemiş günlük taslağın da silinir.';
  @override
  String get noticeSignOutNotRevoked =>
      'Bu telefonda çıkış yapıldı, ancak sunucuya ulaşılamadı: oturum '
      'sunucuda kapatılamadı, diğer cihazlar açık kalabilir.';
  @override
  String get profileSectionAccount => 'Hesap';
  @override
  String get profileName => 'Ad';
  @override
  String get profileEmail => 'E-posta';
  @override
  String get profilePassword => 'Şifre';
  @override
  String get profilePasswordAction => 'Değiştir';
  @override
  String get profileEditName => 'Adını düzenle';
  @override
  String get profileNameHint => 'Uygulamada ve web\'de böyle görünür.';
  @override
  String get profileNameSaved => 'Adın güncellendi';
  @override
  String get profileEmailTitle => 'E-posta adresi';
  @override
  String get profileEmailNew => 'Yeni e-posta';
  @override
  String get profileEmailNote =>
      'E-posta giriş adın olduğu için değiştirmek mevcut şifreni ister.';
  @override
  String get profileEmailSaved => 'E-posta adresin güncellendi';
  @override
  String get profileCurrentPassword => 'Mevcut şifre';
  @override
  String get profileNewPassword => 'Yeni şifre';
  @override
  String get profileConfirmPassword => 'Yeni şifre (tekrar)';
  @override
  String get profilePasswordTitle => 'Şifreyi değiştir';
  @override
  String get profilePasswordNote =>
      'Şifre değişince diğer tüm cihazlarda oturum kapanır; bu telefonda '
      'açık kalır.';
  @override
  String get profilePasswordSaved =>
      'Şifren değişti. Diğer cihazlarda yeniden giriş yapman gerekecek.';
  @override
  String get profileShowPassword => 'Şifreyi göster';
  @override
  String get profileHidePassword => 'Şifreyi gizle';
  @override
  String get profileRateLimited =>
      'Çok fazla şifre denemesi. Birkaç dakika bekleyip tekrar dene.';
  @override
  String get profileSaveFailed => 'Kaydedilemedi · Tekrar dene';
  @override
  String get profileOptionsFailed => 'Seçenekler yüklenemedi';
  @override
  String get profileCurrencyNote => 'Mevcut tutarlar dönüştürülmez.';
  @override
  String profileCurrencyConfirmTitle(String code) => '$code kullanılsın mı?';
  @override
  String profileCurrencyConfirmBody(String before, String after) =>
      'Hiçbir tutar dönüştürülmez: bütçe limitleri ve toplamlar aynı rakamla '
      'yeni para biriminde okunur — $before, $after olur. Hesaplar kendi '
      'para birimlerini korur.';
  @override
  String get profileCurrencyConfirm => 'Değiştir';
  @override
  String profileCurrencySaved(String code) => 'Para birimi: $code';
  @override
  String get profileTimeZoneNote =>
      '“Bugün”, gün sınırları ve saatler bu dilime göre hesaplanır.';
  @override
  String get profileTimeZoneSearch => 'Şehir ya da UTC+03 ara';
  @override
  String profileTimeZoneDeviceGroup(String offset) =>
      'Bu cihazın saati (UTC$offset)';
  @override
  String get profileTimeZoneAllGroup => 'Tüm saat dilimleri';
  @override
  String get profileTimeZoneNoMatch => 'Eşleşen saat dilimi yok';
  @override
  String profileTimeZoneSaved(String zone) => 'Saat dilimi: $zone';
  @override
  String get profileWeeklyReview => 'Haftalık değerlendirme';
  @override
  String get profileWeeklyReviewNote =>
      'Web\'deki haftalık değerlendirme hatırlatıcısının günü.';
  @override
  String profileWeeklyReviewSaved(String day) =>
      'Haftalık değerlendirme günü: $day';
  @override
  String get serverBlurb =>
      'Meridian sunucusunun yerel ağ ya da Tailscale adresi. Bağlanamazsan Wi-Fi veya Tailscale bağlantını kontrol et.';
  @override
  String get serverTest => 'Bağlantıyı test et';
  @override
  String get serverConnected => 'Bağlandı';
  @override
  String serverVersion(String version) => 'Meridian v$version';
  @override
  String serverLatency(int ms) => '$ms\u00A0ms';
  @override
  String get serverCantConnect =>
      'Bağlanılamadı — adresi, Wi-Fi veya Tailscale bağlantını kontrol et';
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
  @override
  String get profileSectionData => 'Veri';
  @override
  String get profileDataAccounts => 'Hesaplar';
  @override
  String get profileDataCategories => 'Kategoriler';
  @override
  String get profileDataSubscriptions => 'Abonelikler';
  @override
  String get profileDataLists => 'Görev listeleri';
  @override
  String get profileDataArchivedHabits => 'Arşivlenmiş alışkanlıklar';
  @override
  String get profileDataGoals => 'Hedefler';
  @override
  String get profileReduceMotion => 'Hareketi azalt';
  @override
  String get profileReduceMotionNote => 'Geçişler ve sayılar anında değişir';
  @override
  String get profileServerChecking => 'Kontrol ediliyor';
  // endregion
}
