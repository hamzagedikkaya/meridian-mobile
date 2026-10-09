import 'package:flutter/material.dart';

import '../../theme/app_metrics.dart';
import 'nok_chip.dart';

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
/// types, currencies, frequencies, a budget's category: a single-choice
/// group of [NokChip]s, 8 dp apart (design-analysis §4.12). The selected one
/// is gold with a tick and a goldDim edge; each is a 48 dp target. With
/// [onChanged] null they show the choice but cannot change it (a locked
/// currency).
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
    return Wrap(
      spacing: Gap.sm,
      runSpacing: 0,
      children: [
        for (final choice in choices) _pill(context, choice),
      ],
    );
  }

  Widget _pill(BuildContext context, Choice<T> choice) {
    final enabled = onChanged != null;
    final isSelected = choice.value == selected;
    // The selected pill, and every pill of a locked choice, does nothing.
    return NokChip(
      label: choice.label,
      selected: isSelected,
      enabled: enabled,
      exclusive: true,
      dot: choice.color,
      icon: choice.icon,
      onTap: !enabled || isSelected ? null : () => onChanged!(choice.value),
    );
  }
}
