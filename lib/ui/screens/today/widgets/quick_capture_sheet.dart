import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api.dart';
import '../../../../data/providers.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../theme/app_colors.dart';
import '../../../../ui/widgets/app_snackbar.dart';
import '../../../../ui/widgets/primary_button.dart';

/// Bolt quick-capture: one field → repository.quickCapture(text).
Future<void> showQuickCaptureSheet(BuildContext context, WidgetRef ref) {
  final c = context.nok;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    backgroundColor: c.surface3,
    builder: (_) => _QuickCaptureSheet(parentRef: ref),
  );
}

class _QuickCaptureSheet extends StatefulWidget {
  final WidgetRef parentRef;

  const _QuickCaptureSheet({required this.parentRef});

  @override
  State<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends State<_QuickCaptureSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result =
          await widget.parentRef.read(repositoryProvider).quickCapture(text);
      widget.parentRef.invalidate(homeProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${result.summary} ✓')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppSnack(context, e.localized(l), isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppSnack(context, l.todayQuickCaptureFailed, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.inkFaint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(l.todayQuickCapture, style: text.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_submitting,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: l.todayQuickCaptureHint,
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: l.todayQuickCaptureAdd,
                loading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
