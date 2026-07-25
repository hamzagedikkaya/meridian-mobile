import 'package:flutter/material.dart';
import '../../core/haptics.dart';
import '../../theme/app_colors.dart';

class PickerOption<T> {
  final T value;
  final String label;
  final Color? color;
  final IconData? icon;
  final String? trailing;

  const PickerOption({
    required this.value,
    required this.label,
    this.color,
    this.icon,
    this.trailing,
  });
}

/// Generic modal bottom-sheet list picker on surface3 (design §3).
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
}) {
  final c = context.nok;
  final text = Theme.of(context).textTheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: text.titleLarge),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final option = options[i];
                final isSelected = option.value == selected;
                return ListTile(
                  leading: option.icon == null
                      ? (option.color == null
                          ? null
                          : Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: option.color,
                                shape: BoxShape.circle,
                              ),
                            ))
                      : Icon(option.icon, color: option.color ?? c.inkMid),
                  title: Text(option.label, style: text.titleMedium),
                  trailing: option.trailing != null
                      ? Text(option.trailing!,
                          style: text.bodySmall!.copyWith(color: c.inkMid))
                      : (isSelected
                          ? Icon(Icons.check, color: c.gold, size: 20)
                          : null),
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
