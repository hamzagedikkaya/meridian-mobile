import 'package:flutter/material.dart';

import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_row.dart';
import 'para_utils.dart';

/// Transaction row in Noktürn list style (design §4.4 İşlemler).
/// Category-color leading circle (transfer → swap_horiz on inkLow),
/// title = description ?? category name, meta = "Kategori · Hesap",
/// trailing = signed amount per the account's own subunit.
class TxRow extends StatelessWidget {
  final Transaction tx;
  final VoidCallback? onTap;

  const TxRow({super.key, required this.tx, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final isTransfer = tx.kind == 'transfer';
    final catColor =
        isTransfer ? c.inkLow : hexColor(tx.category?.color, fallback: c.inkLow);
    final title = (tx.description?.isNotEmpty ?? false)
        ? tx.description!
        : (tx.category?.name ?? (isTransfer ? 'Transfer' : 'İşlem'));

    final metaParts = <String>[
      if (tx.category != null) tx.category!.name,
      if (isTransfer && tx.relatedAccount != null)
        '${tx.account.name} → ${tx.relatedAccount!.name}'
      else
        tx.account.name,
    ];

    return NokturnRow(
      onTap: onTap,
      leading: LeadingCircle(
        color: catColor,
        icon: isTransfer
            ? Icons.swap_horiz
            : (tx.kind == 'income'
                ? Icons.south_west
                : Icons.north_east),
      ),
      title: title,
      meta: metaParts.join(' · '),
      trailing: _amount(context),
    );
  }

  Widget _amount(BuildContext context) {
    final currency = tx.account.currency;
    final subunit = tx.account.subunitToUnit;
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
