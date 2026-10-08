import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import 'primary_button.dart';

/// The full-screen create/edit form (design-research §4.4): close (X) and
/// the title at the top, the fields scrolling, and the save button pinned
/// at the bottom of what the keyboard leaves — always above it, never
/// behind it (a `bottomNavigationBar` stays under the keyboard).
///
/// While [dirty], leaving — the X, the back gesture, the system back —
/// first asks in a sheet whether to keep editing or discard the changes. A
/// clean form closes at once, with the full predictive-back animation.
class FormScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool busy;
  final bool dirty;

  /// Under the save button: a quieter way out (a delete, an archive).
  final Widget? footer;
  final List<Widget>? actions;

  const FormScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.actionLabel,
    required this.onAction,
    this.busy = false,
    this.dirty = false,
    this.footer,
    this.actions,
  });

  Future<void> _close(BuildContext context) async {
    if (!dirty || await confirmDiscard(context)) {
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The Scaffold resizes for the keyboard, so the button column at the
    // bottom of its body sits right on top of it.
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => _close(context),
          ),
          title: Text(title),
          actions: actions,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: children,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrimaryButton(
                      label: actionLabel,
                      loading: busy,
                      onPressed: onAction,
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: 8),
                      footer!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks, in a sheet, whether to drop a form's unsaved changes: "Düzenlemeye
/// devam" (the primary, and what dismissing the sheet means) or "Değişiklikleri
/// at". True to discard.
Future<bool> confirmDiscard(BuildContext context) async {
  final l = context.l10n;
  final text = Theme.of(context).textTheme;
  final discard = await showModalBottomSheet<bool>(
    context: context,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.formDiscardTitle, style: text.titleLarge),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(sheet).pop(false),
              child: Text(l.formKeepEditing),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(sheet).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: sheet.nok.error,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(l.formDiscard),
            ),
          ],
        ),
      ),
    ),
  );
  return discard ?? false;
}

/// A form section's overline label.
class FormLabel extends StatelessWidget {
  final String text;
  const FormLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall!
            .copyWith(color: c.inkMid),
      ),
    );
  }
}

/// A tappable row of a form that opens a picker: an icon or colour dot, the
/// label, and the chosen value (or "Seç") — the value wraps rather than
/// overflowing, whatever its length.
class FormPickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Color? color;
  final VoidCallback? onTap;
  final String? errorText;

  /// What the picker offers is still loading: a small spinner stands in
  /// for the chevron.
  final bool busy;

  const FormPickerRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.color,
    this.onTap,
    this.errorText,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final error = errorText;
    final row = Material(
      color: c.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: error == null ? c.hairline : c.error),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (color != null)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 12),
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(icon, size: 20, color: c.inkMid),
                  ),
                Text(label, style: text.bodyMedium!.copyWith(color: c.inkMid)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value ?? l.actionSelect,
                    textAlign: TextAlign.end,
                    style: text.titleSmall!.copyWith(
                      color: value == null ? c.inkLow : c.inkHi,
                    ),
                  ),
                ),
                if (busy) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ] else if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 20, color: c.inkLow),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One node for screen readers: what the row is and what it holds.
        MergeSemantics(
          child: Semantics(button: onTap != null, child: row),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(error, style: text.bodySmall!.copyWith(color: c.error)),
          ),
      ],
    );
  }
}
