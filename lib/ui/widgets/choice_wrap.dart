import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';

/// One pill of a [ChoiceWrap].
class Choice<T> {
  final T value;
  final String label;

  /// A colour dot before the label (a category's colour).
  final Color? color;
  final IconData? icon;

  const Choice(this.value, this.label, {this.color, this.icon});
}

/// Selectable pills that wrap onto as many lines as they need — account
/// types, currencies, frequencies, a budget's category. The selected one is
/// gold; each is a 48 dp target. With [onChanged] null they show the
/// choice but cannot change it (a locked currency).
class ChoiceWrap<T> extends StatelessWidget {
  final List<Choice<T>> choices;
  final T? selected;
  final ValueChanged<T>? onChanged;

  const ChoiceWrap({
    super.key,
    required this.choices,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final enabled = onChanged != null;
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      children: [
        for (final choice in choices)
          Semantics(
            button: true,
            selected: choice.value == selected,
            enabled: enabled,
            label: choice.label,
            excludeSemantics: true,
            child: InkWell(
              onTap: !enabled || choice.value == selected
                  ? null
                  : () {
                      Haptics.tick();
                      onChanged!(choice.value);
                    },
              borderRadius: BorderRadius.circular(999),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  widthFactor: 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: choice.value == selected
                          ? c.goldContainer
                          : c.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: choice.value == selected
                            ? c.goldContainer
                            : c.hairline,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (choice.color != null) ...[
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: choice.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ] else if (choice.icon != null) ...[
                          Icon(
                            choice.icon,
                            size: 16,
                            color: choice.value == selected
                                ? c.onGoldContainer
                                : c.inkMid,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            choice.label,
                            style: text.labelLarge!.copyWith(
                              color: !enabled && choice.value != selected
                                  ? c.inkFaint
                                  : (choice.value == selected
                                      ? c.onGoldContainer
                                      : c.inkMid),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
