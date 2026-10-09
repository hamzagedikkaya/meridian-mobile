import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_motion.dart';

/// The screen's one primary action (design-analysis §4.8, D34): a gold,
/// stadium-shaped `FilledButton`, 52 dp tall and — by default — as wide as
/// it may be.
///
/// **Loading is not disabled.** While [loading] the button keeps its gold
/// and ignores taps; only if the work takes longer than
/// [Motion.spinnerDelay] (150 ms) does a 20 dp spinner fade in over the
/// label — a quick save never flashes. The height never changes. Disabled
/// ([onPressed] null) is the theme's surface3 + inkDisabled.
///
/// [errorText] appears under the button, growing into place, and says
/// itself to a screen reader.
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  /// A 20 dp icon before the label.
  final IconData? icon;

  /// As wide as the parent allows (true), or as wide as the label.
  final bool expand;

  /// A destructive action (a dialog's "Sil"): error fill, onError label.
  final bool destructive;

  /// An inline error under the button.
  final String? errorText;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = true,
    this.destructive = false,
    this.errorText,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  Timer? _spinnerTimer;
  bool _spinner = false;

  /// The spinner is built: from the moment it is due to show until it has
  /// faded back out. Never while it is not needed — it would tick forever.
  bool _spinnerMounted = false;

  @override
  void initState() {
    super.initState();
    if (widget.loading) _arm();
  }

  @override
  void didUpdateWidget(PrimaryButton old) {
    super.didUpdateWidget(old);
    if (widget.loading && !old.loading) _arm();
    if (!widget.loading && old.loading) {
      _spinnerTimer?.cancel();
      // A spinner on screen fades out first; one never shown just goes, as
      // does any under reduced motion (no fade to wait for).
      if (!_spinner || Motion.reduced(context)) _spinnerMounted = false;
      _spinner = false;
    }
  }

  void _spinnerFaded() {
    if (!_spinner && _spinnerMounted && mounted) {
      setState(() => _spinnerMounted = false);
    }
  }

  @override
  void dispose() {
    _spinnerTimer?.cancel();
    super.dispose();
  }

  void _arm() {
    _spinnerTimer?.cancel();
    _spinnerTimer = Timer(Motion.spinnerDelay, () {
      if (mounted && widget.loading) {
        setState(() => _spinner = _spinnerMounted = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final fade = Motion.orInstant(context, Motion.pressOut);
    final loading = widget.loading;
    final onColor = widget.destructive ? c.onError : c.onGold;

    final label = widget.icon == null
        ? Text(widget.label, textAlign: TextAlign.center)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 20),
              const SizedBox(width: Gap.sm),
              Flexible(child: Text(widget.label)),
            ],
          );

    Widget button = FilledButton(
      // Loading keeps the enabled colours: a no-op handler, taps ignored
      // below.
      onPressed: loading ? () {} : widget.onPressed,
      style: widget.destructive
          ? FilledButton.styleFrom(
              backgroundColor: c.error,
              foregroundColor: c.onError,
            )
          : null,
      // The label keeps its place while the spinner shows, so the button
      // keeps its height at any text size.
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            opacity: _spinner ? 0 : 1,
            duration: fade,
            child: label,
          ),
          // Always in the tree, so the spinner fades back out on an error
          // rather than vanishing.
          AnimatedOpacity(
            opacity: _spinner ? 1 : 0,
            duration: fade,
            onEnd: _spinnerFaded,
            child: SizedBox.square(
              dimension: 20,
              child: _spinnerMounted
                  ? CircularProgressIndicator(strokeWidth: 2, color: onColor)
                  : null,
            ),
          ),
        ],
      ),
    );
    // Always the same wrappers around the same FilledButton: starting or
    // ending a save never rebuilds it, so the tap's ripple plays on and a
    // screen reader keeps its focus on the same node — one button with the
    // label, which reads disabled while loading.
    final enabled = !loading && widget.onPressed != null;
    button = Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.label,
      onTap: enabled ? widget.onPressed : null,
      excludeSemantics: true,
      child: IgnorePointer(ignoring: loading, child: button),
    );
    if (widget.expand) {
      button = SizedBox(width: double.infinity, child: button);
    }

    final error = widget.errorText;
    final errorLine = error == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: text.bodySmall!.copyWith(color: c.error),
              ),
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          widget.expand ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
      children: [
        button,
        // AnimatedSize cannot take zero time (it would re-lay itself out
        // mid-layout): under reduced motion the error just takes its place.
        if (Motion.reduced(context))
          errorLine
        else
          AnimatedSize(
            duration: fade,
            alignment: Alignment.topCenter,
            child: errorLine,
          ),
      ],
    );
  }
}
