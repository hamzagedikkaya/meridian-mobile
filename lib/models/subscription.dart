import 'account.dart';
import 'date_utils.dart';
import 'form_text.dart';
import 'json_read.dart';
import 'transaction.dart';

/// How often a subscription charges, in the order the form offers them.
const subscriptionFrequencies = ['weekly', 'monthly', 'yearly'];

/// A recurring charge on an account (the subscription object). Amounts are
/// in the account currency's minor units.
///
/// Nothing charges it on its own: [nextChargeOn] moves only when a payment
/// is recorded (`POST /subscriptions/:id/charge`) or the date is edited.
class Subscription {
  final int id;
  final String name;
  final String? vendor;
  final int amountCents;
  final String frequency;

  /// The next payment's due date; null: never due, cannot be charged.
  final DateTime? nextChargeOn;
  final DateTime? startDate;
  final DateTime? endDate;

  /// False while paused: never due, cannot be charged.
  final bool active;
  final String color;
  final String? note;

  /// What it costs a month (a yearly one's twelfth) and a year.
  final int monthlyAmountCents;
  final int yearlyAmountCents;
  final AccountRef account;
  final TxCategory? category;

  const Subscription({
    required this.id,
    required this.name,
    this.vendor,
    required this.amountCents,
    required this.frequency,
    this.nextChargeOn,
    this.startDate,
    this.endDate,
    required this.active,
    required this.color,
    this.note,
    required this.monthlyAmountCents,
    required this.yearlyAmountCents,
    required this.account,
    this.category,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;
    final amount = readInt(json['amount_cents']);
    return Subscription(
      id: readId(json['id']),
      name: (json['name'] as String?) ?? '',
      vendor: text(json['vendor']),
      amountCents: amount,
      frequency: (json['frequency'] as String?) ?? 'monthly',
      nextChargeOn: parseDateTime(json['next_charge_on']),
      startDate: parseDateTime(json['start_date']),
      endDate: parseDateTime(json['end_date']),
      active: readBool(json['active'], fallback: true),
      color: (json['color'] as String?) ?? '#B8860B',
      note: text(json['note']),
      monthlyAmountCents: readIntOrNull(json['monthly_amount_cents']) ?? amount,
      yearlyAmountCents: readInt(json['yearly_amount_cents']),
      account: AccountRef.fromJson(
          (json['account'] as Map<String, dynamic>?) ?? const {'id': 0}),
      category: json['category'] is Map<String, dynamic>
          ? TxCategory.fromJson(json['category'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// One currency's share of the active subscriptions' cost. Amounts in
/// different currencies are never added together.
class SubscriptionTotal {
  final String currency;
  final int subunitToUnit;
  final int monthlyCents;
  final int yearlyCents;

  const SubscriptionTotal({
    required this.currency,
    required this.subunitToUnit,
    required this.monthlyCents,
    required this.yearlyCents,
  });

  factory SubscriptionTotal.fromJson(Map<String, dynamic> json) =>
      SubscriptionTotal(
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: readInt(json['subunit_to_unit'], fallback: 100),
        monthlyCents: readInt(json['monthly_cents']),
        yearlyCents: readInt(json['yearly_cents']),
      );
}

/// GET /subscriptions: the active ones by next charge date, the paused ones
/// by name, and what the active ones cost per currency (the user's first).
class SubscriptionsBundle {
  final List<Subscription> active;
  final List<Subscription> inactive;
  final List<SubscriptionTotal> totals;

  const SubscriptionsBundle({
    required this.active,
    required this.inactive,
    required this.totals,
  });

  factory SubscriptionsBundle.fromJson(Map<String, dynamic> json) {
    List<Subscription> list(Object? raw) => [
          for (final item in (raw as List?) ?? const [])
            if (item is Map<String, dynamic>) Subscription.fromJson(item),
        ];
    return SubscriptionsBundle(
      active: list(json['active']),
      inactive: list(json['inactive']),
      totals: [
        for (final item in (json['totals'] as List?) ?? const [])
          if (item is Map<String, dynamic>) SubscriptionTotal.fromJson(item),
      ],
    );
  }

  /// Every subscription, active ones first.
  List<Subscription> get all => [...active, ...inactive];
}

/// What the subscription form sends (`POST /subscriptions`,
/// `PATCH /subscriptions/:id`).
class SubscriptionInput {
  final String name;
  final int accountId;
  final int amountCents;
  final String frequency;

  /// The next payment's date; null leaves it to the server on a create (the
  /// first date of the series after today) and clears it on an edit.
  final DateTime? nextChargeOn;
  final int? categoryId;
  final String? vendor;
  final String? note;
  final String color;

  /// When the series starts and ends; null leaves both as they are (the
  /// server starts a new one today and never ends it). A null [start] or
  /// [end] inside it clears that date on an edit.
  final ({DateTime? start, DateTime? end})? period;

  const SubscriptionInput({
    required this.name,
    required this.accountId,
    required this.amountCents,
    required this.frequency,
    this.nextChargeOn,
    this.categoryId,
    this.vendor,
    this.note,
    required this.color,
    this.period,
  });

  /// The body of a create. Without a date the server proposes the first
  /// charge itself, as the web form does.
  Map<String, dynamic> toJson() => {
        'name': name,
        'account_id': accountId,
        'amount_cents': amountCents,
        'frequency': frequency,
        if (nextChargeOn != null) 'next_charge_on': isoDate(nextChargeOn!),
        if (categoryId != null) 'finance_category_id': categoryId,
        if (vendor != null) 'vendor': vendor,
        if (note != null) 'note': note,
        'color': color,
        if (period?.start != null) 'start_date': isoDate(period!.start!),
        if (period?.end != null) 'end_date': isoDate(period!.end!),
      };

  /// The body of an edit of [before]: only what changed. Moving it to an
  /// account in another currency carries the amount with it, re-read in
  /// that currency (the server asks for both in one request). Text is
  /// compared as the form sends it ([formTextChanged]), so a vendor or note
  /// saved with trailing spaces on the web is not rewritten untouched.
  Map<String, dynamic> changesFrom(
    Subscription before, {
    required String accountCurrency,
  }) {
    final next = nextChargeOn == null ? null : isoDate(nextChargeOn!);
    final wasNext =
        before.nextChargeOn == null ? null : isoDate(before.nextChargeOn!);
    final movedCurrency =
        accountCurrency.toUpperCase() != before.account.currency.toUpperCase();
    String? day(DateTime? d) => d == null ? null : isoDate(d);
    final period = this.period;
    return {
      if (formTextChanged(name, before.name)) 'name': name.trim(),
      if (accountId != before.account.id) 'account_id': accountId,
      if (amountCents != before.amountCents || movedCurrency)
        'amount_cents': amountCents,
      if (frequency != before.frequency) 'frequency': frequency,
      if (next != wasNext) 'next_charge_on': next,
      if (categoryId != before.category?.id) 'finance_category_id': categoryId,
      if (formTextChanged(vendor, before.vendor)) 'vendor': asFormText(vendor),
      if (formTextChanged(note, before.note)) 'note': asFormText(note),
      if (color.toUpperCase() != before.color.toUpperCase()) 'color': color,
      if (period != null && day(period.start) != day(before.startDate))
        'start_date': day(period.start),
      if (period != null && day(period.end) != day(before.endDate))
        'end_date': day(period.end),
    };
  }
}

/// A payment recorded for a subscription: the subscription with its next
/// date moved one period on, and the expense it recorded.
class SubscriptionCharge {
  final Subscription subscription;
  final Transaction? transaction;

  const SubscriptionCharge({required this.subscription, this.transaction});

  factory SubscriptionCharge.fromJson(Map<String, dynamic> json) =>
      SubscriptionCharge(
        subscription: Subscription.fromJson(
            (json['subscription'] as Map<String, dynamic>?) ?? json),
        transaction: json['transaction'] is Map<String, dynamic>
            ? Transaction.fromJson(json['transaction'] as Map<String, dynamic>)
            : null,
      );
}
