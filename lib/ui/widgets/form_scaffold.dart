import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../core/haptics.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_motion.dart';
import 'nok_sheet.dart';
import 'primary_button.dart';

/// The full-screen create/edit form (design-analysis §4.31, §6.3) — open it
/// with `SlideUpPageRoute` (`slideUpModalRoute`).
///
/// * **Top**: an X that closes it and the [title] (headlineSmall 20 sp).
/// * **Body**: [children], scrolling; dragging the list puts the keyboard
///   away. Order fields as IA-21 does: the deciding choice (a kind) → the
///   name, autofocused only when creating → the essentials → "Daha fazla".
/// * **Save**: the [actionLabel] `PrimaryButton`, pinned right above the
///   keyboard — never behind it. While content scrolls under it a hairline
///   fades in over the button. [busy] shows its delayed spinner;
///   [errorText] shows under it.
/// * **Leaving** while [dirty] — the X, the back gesture, the system back —
///   first asks in a sheet whether to keep editing or discard. A clean form
///   closes at once, with the full predictive-back animation.
///
/// On a failed save, [FormScaffold.revealInvalid] brings the first invalid
/// field into view and focuses it. When editing, send only what changed.
class FormScaffold extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool busy;
  final bool dirty;

  /// Under the save button: a quieter way out (a delete, an archive).
  final Widget? footer;
  final List<Widget>? actions;

  /// A form-level error under the save button.
  final String? errorText;

  /// A quiet line right above the save button — what saving will reach
  /// ("Bu değişiklik serideki tüm etkinlikleri etkiler").
  final Widget? notice;

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
    this.errorText,
    this.notice,
  });

  /// After a failed save: the REJECT haptic, then the field under
  /// [fieldKey] scrolls into view (250 ms, 15 % from the top; a jump under
  /// reduced motion) and — when it holds a text field — takes the focus.
  static Future<void> revealInvalid(GlobalKey fieldKey) async {
    Haptics.reject();
    final context = fieldKey.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: Motion.orInstant(context, Motion.collapse),
      curve: Motion.enter,
      alignment: 0.15,
    );
    if (!context.mounted) return;
    // Focus the first text field inside, if it has one; a picker row is
    // only shown.
    FocusNode? field;
    void visit(Element element) {
      if (field != null) return;
      final widget = element.widget;
      if (widget is EditableText) {
        field = widget.focusNode;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    field?.requestFocus();
  }

  @override
  State<FormScaffold> createState() => _FormScaffoldState();
}

class _FormScaffoldState extends State<FormScaffold> {
  /// Content runs on under the save bar.
  bool _underBar = false;

  Future<void> _close() async {
    if (!widget.dirty || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  // Only the form's own list counts (depth 0): a multi-line text field
  // scrolls in a Scrollable of its own.
  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth == 0) _track(n.metrics);
    return false;
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0) _track(n.metrics);
    return false;
  }

  void _track(ScrollMetrics m) {
    if (m.axis != Axis.vertical) return;
    final under = m.extentAfter > 0.5;
    if (under != _underBar) setState(() => _underBar = under);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    // The Scaffold resizes for the keyboard, so the button column at the
    // bottom of its body sits right on top of it.
    return PopScope<Object?>(
      canPop: !widget.dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: l.actionClose,
            onPressed: _close,
          ),
          title: Text(widget.title),
          actions: widget.actions,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: _onMetrics,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: ListView(
                      // A form is short: build every field, so a failed save
                      // can reach the first invalid one wherever it is.
                      scrollCacheExtent: const ScrollCacheExtent.pixels(10000),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(
                        Insets.formH,
                        Gap.sm,
                        Insets.formH,
                        Gap.xxl,
                      ),
                      children: widget.children,
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: Motion.orInstant(context, Motion.pressOut),
                height: 1,
                color: _underBar ? c.hairline : c.hairline.withValues(alpha: 0),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.formH,
                  Gap.sm,
                  Insets.formH,
                  Gap.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.notice != null) ...[
                      widget.notice!,
                      const SizedBox(height: Gap.sm),
                    ],
                    PrimaryButton(
                      label: widget.actionLabel,
                      loading: widget.busy,
                      onPressed: widget.onAction,
                      errorText: widget.errorText,
                    ),
                    if (widget.footer != null) ...[
                      const SizedBox(height: Gap.sm),
                      widget.footer!,
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
/// at" (an error text button 24 dp below it). True to discard.
Future<bool> confirmDiscard(BuildContext context) async {
  final l = context.l10n;
  final discard = await showNokSheet<bool>(
    context,
    title: l.formDiscardTitle,
    builder: (sheet) => SheetActions(
      primary: PrimaryButton(
        label: l.formKeepEditing,
        onPressed: () => Navigator.of(sheet).pop(false),
      ),
      destructive: TextButton(
        onPressed: () => Navigator.of(sheet).pop(true),
        style: TextButton.styleFrom(
          foregroundColor: sheet.nok.error,
          minimumSize: const Size.fromHeight(Hit.min),
        ),
        child: Text(l.formDiscard),
      ),
    ),
  );
  return discard ?? false;
}

/// An inline form error that grows into place (150 ms) and fades in, and
/// is announced by a screen reader; nothing when [text] is null.
class FormInlineError extends StatelessWidget {
  final String? text;

  /// Space above the message.
  final double gap;

  const FormInlineError(this.text, {super.key, this.gap = 6});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final message = text;
    final duration = Motion.orInstant(context, Motion.pressOut);
    final switcher = AnimatedSwitcher(
      duration: duration,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              key: ValueKey(message),
              padding: EdgeInsets.fromLTRB(16, gap, 16, 0),
              child: Semantics(
                liveRegion: true,
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall!
                        .copyWith(color: c.error),
                  ),
                ),
              ),
            ),
    );
    // AnimatedSize cannot take zero time (it would re-lay itself out
    // mid-layout): under reduced motion the message just takes its place.
    if (Motion.reduced(context)) return switcher;
    return AnimatedSize(
      duration: duration,
      alignment: Alignment.topCenter,
      child: switcher,
    );
  }
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
/// overflowing, whatever its length. Above 1.3× text the value goes under
/// the label at the row's full width, as in the `AmountField`: beside a
/// long label it would be squeezed to a letter a line.
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
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final labelText =
        Text(label, style: text.bodyMedium!.copyWith(color: c.inkMid));
    final valueText = Text(
      value ?? l.actionSelect,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: text.titleSmall!.copyWith(
        color: value == null ? c.inkLow : c.inkHi,
      ),
    );
    final row = FormFieldBox(
      onTap: onTap,
      hasError: error != null,
      child: Row(
        children: [
          if (color != null)
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(right: Gap.md),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: Icon(icon, size: 20, color: c.inkMid),
            ),
          if (stacked)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 2), valueText],
              ),
            )
          else ...[
            labelText,
            const SizedBox(width: Gap.md),
            Expanded(child: valueText),
          ],
          if (busy) ...[
            const SizedBox(width: Gap.sm),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ] else if (onTap != null) ...[
            const SizedBox(width: Gap.xs),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.inkLow),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One node for screen readers: what the row is and what it holds.
        MergeSemantics(
          child: Semantics(button: onTap != null, child: row),
        ),
        FormInlineError(error),
      ],
    );
  }
}

/// The box every tappable form field shares — [FormPickerRow], the
/// `AmountField`, a habit's goal row (design-analysis §4.11): surface2,
/// 12 dp corners, a 1 dp inkDisabled edge (error when [hasError]), at least
/// 52 dp tall — level with a text field and the primary button — with
/// 16 / 12 dp inside, and the gold ripple when tapped.
class FormFieldBox extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool hasError;

  const FormFieldBox({
    super.key,
    required this.child,
    this.onTap,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Material(
      color: c.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.mdAll,
        side: BorderSide(color: hasError ? c.error : c.inkDisabled),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: Gap.md,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
