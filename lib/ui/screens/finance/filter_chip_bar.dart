import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../l10n/app_l10n.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/pressable_scale.dart';

/// Sticky filter chip bar for the transactions feed (design §4.4): kind chips
/// (all / income / expense / transfer) + account, category and date pickers.
class FilterChipBar extends StatelessWidget {
  final String? kind; // null = every kind
  final ValueChanged<String?> onKind;
  final String? accountLabel;
  final String? categoryLabel;
  final String? dateLabel;
  final VoidCallback onAccountTap;
  final VoidCallback onCategoryTap;
  final VoidCallback onDateTap;

  const FilterChipBar({
    super.key,
    required this.kind,
    required this.onKind,
    required this.accountLabel,
    required this.categoryLabel,
    required this.dateLabel,
    required this.onAccountTap,
    required this.onCategoryTap,
    required this.onDateTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    return Container(
      color: c.bg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            _chip(context, label: l.labelAll, active: kind == null,
                onTap: () => onKind(null)),
            _chip(context, label: l.financeIncome, active: kind == 'income',
                onTap: () => onKind('income')),
            _chip(context, label: l.financeExpense, active: kind == 'expense',
                onTap: () => onKind('expense')),
            _chip(context, label: l.financeTransfer, active: kind == 'transfer',
                onTap: () => onKind('transfer')),
            _divider(c),
            _chip(context,
                label: accountLabel ?? l.txFilterAccount,
                active: accountLabel != null,
                dropdown: true,
                onTap: onAccountTap),
            _chip(context,
                label: categoryLabel ?? l.txFilterCategory,
                active: categoryLabel != null,
                dropdown: true,
                onTap: onCategoryTap),
            _chip(context,
                label: dateLabel ?? l.txFilterDate,
                active: dateLabel != null,
                dropdown: true,
                onTap: onDateTap),
          ],
        ),
      ),
    );
  }

  Widget _divider(NokturnColors c) => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: c.hairline,
      );

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool dropdown = false,
  }) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        onTap: () {
          Haptics.tick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? c.goldContainer : c.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? c.goldContainer : c.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: text.labelLarge!.copyWith(
                  color: active ? c.onGoldContainer : c.inkMid,
                ),
              ),
              if (dropdown) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: active ? c.onGoldContainer : c.inkMid,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
