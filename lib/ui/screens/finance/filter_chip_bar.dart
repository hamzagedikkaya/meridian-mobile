import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../l10n/app_l10n.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/pressable_scale.dart';

/// İşlemler's filter row (design-analysis §4.12, §7.7): four dropdown chips
/// — [Tür ▾] [Hesap ▾] [Kategori ▾] [Tarih ▾] — and, while any filter is
/// on, a 48 dp × that clears them all, after a hairline.
///
/// A chip whose filter is on turns gold and says its value ("Tür: Gider ▾",
/// "Cüzdan ▾", "Bu ay ▾"). The four fit a 360 dp phone at rest; when they
/// and the × no longer fit one line (a filter on, longer English labels,
/// larger text) the row wraps onto a second one, so every chip and the ×
/// always stay in sight — never scrolled away or hidden behind the ×.
///
/// The kind chip opens its own picker (Tümü · Gelir · Gider · Transfer);
/// the others call back. Each chip is one screen-reader button that says
/// its value and whether its filter is on.
class FilterChipBar extends StatefulWidget {
  final String? kind; // null = every kind
  final ValueChanged<String?> onKind;
  final String? accountLabel;
  final String? categoryLabel;
  final String? dateLabel;
  final VoidCallback onAccountTap;
  final VoidCallback onCategoryTap;
  final VoidCallback onDateTap;

  /// Clears every filter; the × is shown while any is set.
  final VoidCallback? onClear;

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
    this.onClear,
  });

  @override
  State<FilterChipBar> createState() => _FilterChipBarState();
}

class _FilterChipBarState extends State<FilterChipBar> {
  String _kindName(AppL10n l, String kind) => switch (kind) {
        'income' => l.financeIncome,
        'expense' => l.financeExpense,
        _ => l.financeTransfer,
      };

  Future<void> _pickKind() async {
    final l = context.l10n;
    final picked = await showPickerSheet<String>(
      context,
      title: l.txFilterKind,
      selected: widget.kind ?? 'all',
      options: [
        PickerOption(value: 'all', label: l.labelAll, icon: Icons.all_inclusive),
        PickerOption(
            value: 'income',
            label: l.financeIncome,
            icon: Icons.south_west_rounded),
        PickerOption(
            value: 'expense',
            label: l.financeExpense,
            icon: Icons.north_east_rounded),
        PickerOption(
            value: 'transfer',
            label: l.financeTransfer,
            icon: Icons.swap_horiz_rounded),
      ],
    );
    if (picked == null || !mounted) return;
    widget.onKind(picked == 'all' ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final kind = widget.kind;
    final clear = widget.onClear;
    return ColoredBox(
      color: c.bg,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: Gap.lg,
          end: Gap.xs,
        ),
        // From the leading edge, whatever the column around it centres.
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FilterChip(
                label: kind == null
                    ? l.txFilterKind
                    : l.txFilterKindValue(_kindName(l, kind)),
                active: kind != null,
                onTap: _pickKind,
              ),
              _FilterChip(
                label: widget.accountLabel ?? l.txFilterAccount,
                active: widget.accountLabel != null,
                onTap: widget.onAccountTap,
              ),
              _FilterChip(
                label: widget.categoryLabel ?? l.txFilterCategory,
                active: widget.categoryLabel != null,
                onTap: widget.onCategoryTap,
              ),
              _FilterChip(
                label: widget.dateLabel ?? l.txFilterDate,
                active: widget.dateLabel != null,
                onTap: widget.onDateTap,
              ),
              if (clear != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 1, height: 24, color: c.hairline),
                    IconButton(
                      onPressed: () {
                        Haptics.tick();
                        clear();
                      },
                      tooltip: l.txFilterClear,
                      icon: Icon(Icons.close_rounded, color: c.inkMid),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dropdown filter chip, drawn as `NokChip` draws one but a little
/// tighter (9 / 7 dp inside, the arrow 2 dp after the label), so the four fit
/// a 360 dp row: 36 dp tall in a 48 dp target, a 1 dp hairline on surface2
/// at rest; goldContainer with a goldDim edge and an onGoldContainer w600
/// label when its filter is on. Colours change in 200 ms; it presses to
/// 0.95.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final duration = Motion.orInstant(context, Motion.quick);
    final fg = active ? c.onGoldContainer : c.inkMid;
    void tap() {
      Haptics.tick();
      onTap();
    }

    final pill = AnimatedContainer(
      duration: duration,
      curve: Motion.enter,
      // 9 / 7 dp inside, the 1 dp edge included: 36 dp tall.
      padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
      decoration: ShapeDecoration(
        color: active ? c.goldContainer : c.surface2,
        shape: StadiumBorder(
          side: BorderSide(color: active ? c.goldDim : c.hairline),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A long name (larger text) ends in "…" rather than running
          // past a line of its own.
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: duration,
              style: text.labelLarge!.copyWith(
                color: fg,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: Gap.xxs),
          Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: fg),
        ],
      ),
    );
    // One node per chip for screen readers, saying its value and whether
    // its filter is on; it answers the double-tap itself.
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: tap,
      excludeSemantics: true,
      child: PressableScale.small(
        onTap: tap,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Center(widthFactor: 1, heightFactor: 1, child: pill),
        ),
      ),
    );
  }
}
