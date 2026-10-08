import 'package:flutter/material.dart';
import '../../core/haptics.dart';
import '../../theme/app_colors.dart';

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

/// Generic modal bottom-sheet list picker on surface3 (design §3).
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
  String? note,
}) {
  final c = context.nok;
  final text = Theme.of(context).textTheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: text.titleLarge),
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  note,
                  style: text.bodySmall!.copyWith(color: c.inkMid),
                ),
              ),
            ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final option = options[i];
                final isSelected = option.value == selected;
                final check = isSelected
                    ? Icon(Icons.check, color: c.gold, size: 20)
                    : null;
                final trailing = option.trailing;
                return ListTile(
                  selected: isSelected,
                  contentPadding: EdgeInsetsDirectional.only(
                    start: option.indent ? 40 : 16,
                    end: 16,
                  ),
                  leading: option.icon == null
                      ? (option.color == null
                          ? null
                          : Container(
                              width: option.indent ? 16 : 24,
                              height: option.indent ? 16 : 24,
                              decoration: BoxDecoration(
                                color: option.color,
                                shape: BoxShape.circle,
                              ),
                            ))
                      : Icon(option.icon, color: option.color ?? c.inkMid),
                  title: Text(
                    option.label,
                    style: option.indent ? text.bodyLarge : text.titleMedium,
                  ),
                  subtitle: option.subtitle == null
                      ? null
                      : Text(
                          option.subtitle!,
                          style: text.bodySmall!.copyWith(color: c.inkMid),
                        ),
                  trailing: trailing == null
                      ? check
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              trailing,
                              style:
                                  text.bodySmall!.copyWith(color: c.inkMid),
                            ),
                            if (check != null) ...[
                              const SizedBox(width: 8),
                              check,
                            ],
                          ],
                        ),
                  onTap: () {
                    Haptics.tick();
                    Navigator.of(context).pop(option.value);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
