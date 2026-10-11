import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../../core/turkish_case.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_row.dart';

/// A transaction in a list (design-analysis §4.5): Finance's recent ones,
/// İşlemler, an account's history.
///
/// * **Leading circle**: the category's initial (Turkish upper case) on its
///   tint; `swap_horiz_rounded` for a transfer, `category_outlined` without
///   a category. No direction arrows — the amount carries the sign.
/// * **Title**: the description, else the category ("Kategorisiz" for an
///   income or expense without one), else for a transfer its route
///   ("Cüzdan → Birikim").
/// * **Meta**: only what the title does not say. The account is left out in
///   its own history ([perspectiveAccountId]) and when the list is filtered
///   to it ([hideAccount]); a title that fell back to the category leaves the
///   account alone in the meta; a transfer says "Transfer".
/// * **Amount** (`numRow`): + income in income green, − expense in inkHi, a
///   transfer unsigned — except in one account's own history, where money
///   out is − and money in is +.
///
/// [onLongPress] opens the row's actions (Düzenle · Bugüne kopyala · Sil);
/// give a screen reader the same in [semanticActions].
class TxRow extends StatelessWidget {
  final Transaction tx;
  final VoidCallback? onTap;

  /// The account whose history this row is in, if any.
  final int? perspectiveAccountId;

  /// The list is filtered to [tx]'s account: its name would repeat on
  /// every row.
  final bool hideAccount;

  final VoidCallback? onLongPress;
  final Map<CustomSemanticsAction, VoidCallback>? semanticActions;

  const TxRow({
    super.key,
    required this.tx,
    this.onTap,
    this.perspectiveAccountId,
    this.hideAccount = false,
    this.onLongPress,
    this.semanticActions,
  });

  /// [tx]'s title and meta line, as the row shows them (the detail sheet
  /// uses the title too). [hideAccount] leaves the account's name out of
  /// the meta; the meta is empty when nothing is left to say.
  static ({String title, String meta}) describe(
    AppL10n l,
    Transaction tx, {
    bool hideAccount = false,
  }) {
    final isTransfer = tx.kind == 'transfer';
    final description = tx.description?.trim() ?? '';
    final described = description.isNotEmpty;
    final route = tx.relatedAccount == null
        ? null
        : '${tx.account.name} → ${tx.relatedAccount!.name}';
    if (isTransfer) {
      return (
        title: described ? description : (route ?? l.financeTransfer),
        meta: [
          l.financeTransfer,
          if (described && route != null) route,
        ].join(' · '),
      );
    }
    final category = tx.category?.name ?? l.financeUncategorized;
    return (
      title: described ? description : category,
      meta: [
        if (described) category,
        if (!hideAccount) tx.account.name,
      ].join(' · '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ownHistory =
        perspectiveAccountId != null && perspectiveAccountId == tx.account.id;
    final text = describe(l, tx, hideAccount: hideAccount || ownHistory);
    return NokturnRow(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticActions: semanticActions,
      leading: _leading(context.nok),
      title: text.title,
      meta: text.meta.isEmpty ? null : text.meta,
      trailing: _amount(context),
    );
  }

  Widget _leading(NokturnColors c) {
    if (tx.kind == 'transfer') return const LeadingCircle.transfer();
    final category = tx.category;
    final name = category?.name.trim() ?? '';
    if (category == null || name.isEmpty) {
      return const LeadingCircle.uncategorized();
    }
    return LeadingCircle.tone(
      entityTone(category.color, c),
      initial: trUpper(String.fromCharCode(name.runes.first)),
    );
  }

  Widget _amount(BuildContext context) {
    final currency = tx.account.currency;
    final subunit = tx.account.subunitToUnit;
    final perspective = perspectiveAccountId;
    switch (tx.kind) {
      case 'income':
        return MoneyText(
          tx.amountCents,
          currency: currency,
          subunitToUnit: subunit,
          signed: true,
          positiveGreen: true,
        );
      case 'transfer':
        if (perspective != null && tx.relatedAccount?.id == perspective) {
          // Money in, from another account.
          return MoneyText(
            tx.amountCents,
            currency: currency,
            subunitToUnit: subunit,
            signed: true,
            positiveGreen: true,
          );
        }
        if (perspective != null && tx.account.id == perspective) {
          return MoneyText(
            tx.amountCents,
            currency: currency,
            subunitToUnit: subunit,
            negative: true,
          );
        }
        return MoneyText(
          tx.amountCents,
          currency: currency,
          subunitToUnit: subunit,
        );
      default:
        return MoneyText(
          tx.amountCents,
          currency: currency,
          subunitToUnit: subunit,
          negative: true,
        );
    }
  }
}
