import 'package:flutter/material.dart';

import '../../../l10n/app_l10n.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_row.dart';
import 'finance_utils.dart';

/// Transaction row in Noktürn list style (design §4.4 İşlemler).
///
/// The title is the description, else the category ("Kategorisiz" for an
/// income or expense without one), else for a transfer its route
/// ("Cüzdan → Birikim"); the meta line adds what the title does not say,
/// without repeating it. The amount is signed by kind: + income, − expense,
/// and a transfer is neutral — except in one account's own history
/// ([perspectiveAccountId]), where money out is − and money in is +.
class TxRow extends StatelessWidget {
  final Transaction tx;
  final VoidCallback? onTap;

  /// The account whose history this row is in, if any.
  final int? perspectiveAccountId;

  const TxRow({
    super.key,
    required this.tx,
    this.onTap,
    this.perspectiveAccountId,
  });

  /// [tx]'s title and meta line, as the row shows them (the detail sheet
  /// uses the same).
  static ({String title, String meta}) describe(AppL10n l, Transaction tx) {
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
      meta: [if (described) category, tx.account.name].join(' · '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final isTransfer = tx.kind == 'transfer';
    final catColor = isTransfer || tx.category == null
        ? c.inkLow
        : hexColor(tx.category?.color, fallback: c.inkLow);
    final text = describe(l, tx);

    return NokturnRow(
      onTap: onTap,
      leading: LeadingCircle(
        color: catColor,
        icon: isTransfer
            ? Icons.swap_horiz
            : (tx.kind == 'income' ? Icons.south_west : Icons.north_east),
      ),
      title: text.title,
      meta: text.meta,
      trailing: _amount(context),
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
