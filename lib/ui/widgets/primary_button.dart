import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// 52dp gold filled button with an inline spinner while loading —
/// size stays fixed, label swaps (design §4.2).
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.onGold),
            )
          : Text(label),
    );
  }
}
