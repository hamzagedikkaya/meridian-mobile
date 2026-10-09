import 'package:flutter/material.dart';
import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import 'nok_sheet.dart';

class PickerOption<T> {
  final T value;
  final String label;
  final Color? color;
  final IconData? icon;

  /// A value shown at the end of the row (an account's balance); the
  /// selected row keeps its check beside it.
  final String? trailing;

  /// A second line under the label.
  final String? subtitle;

  /// Drawn one step in, under the option above it (a subcategory).
  final bool indent;

  const PickerOption({
    required this.value,
    required this.label,
    this.color,
    this.icon,
    this.trailing,
    this.subtitle,
    this.indent = false,
  });
}

/// A list picker in a sheet (design-analysis §4.15): [title], an optional
/// [note], and one row per option; the [selected] row turns gold with a
/// gold check. A tap plays the selection tick and returns the option's
/// value; dismissing returns null.
///
/// Rows start 20 dp in (44 dp for an [PickerOption.indent]ed one).
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
  String? note,
}) {
  return showNokSheet<T>(
    context,
    title: title,
    builder: (context) {
      final c = context.nok;
      final text = Theme.of(context).textTheme;
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(note, style: text.bodySmall),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) => _PickerRow(
                  option: options[i],
                  selected: options[i].value == selected,
                  colors: c,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({
    required this.option,
    required this.selected,
    required this.colors,
  });

  final PickerOption<T> option;
  final bool selected;
  final NokturnColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final text = Theme.of(context).textTheme;
    final check =
        selected ? Icon(Icons.check_rounded, color: c.gold, size: 20) : null;
    final trailing = option.trailing;
    final dot = option.indent ? 16.0 : 24.0;
    return ListTile(
      selected: selected,
      selectedColor: c.gold,
      contentPadding: EdgeInsetsDirectional.only(
        start: option.indent ? 44 : 20,
        end: 20,
      ),
      leading: option.icon == null
          ? (option.color == null
              ? null
              : Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: option.color,
                    shape: BoxShape.circle,
                  ),
                ))
          : Icon(option.icon, color: option.color ?? c.inkMid),
      title: Text(
        option.label,
        style: (option.indent ? text.bodyLarge : text.titleMedium)!
            .copyWith(color: selected ? c.gold : null),
      ),
      subtitle: option.subtitle == null
          ? null
          : Text(option.subtitle!, style: text.bodySmall),
      trailing: trailing == null
          ? check
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(trailing, style: text.bodySmall),
                if (check != null) ...[const SizedBox(width: 8), check],
              ],
            ),
      onTap: () {
        Haptics.tick();
        Navigator.of(context).pop(option.value);
      },
    );
  }
}
