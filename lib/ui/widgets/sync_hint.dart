import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// The three things a screen can show for a read model, decided the same way
/// on every screen so that no refresh or retry flashes a skeleton:
///
/// * a value → the data (plus the offline banner when [refreshFailed]),
///   never replaced while newer data loads;
/// * [isFirstLoad] → a skeleton, only before anything was ever shown;
/// * [hasFailed] → the error view, which stays put while a retry runs.
///
/// [isRefetching] is when the [SyncHint] line shows.
///
/// A read model's quick retry runs inside its fetch (see `retried`), so the
/// state only ever holds a fetch's outcome: a blip the retry heals never
/// shows a failure, and a failure once shown stays up — through every
/// refresh and retry that fails again — until a fetch lands.
extension AsyncScreenState on AsyncValue<Object?> {
  /// Data is on screen but the last refresh of it failed: the offline
  /// banner's case. It stays up, under the hint, while the next refresh runs.
  bool get refreshFailed => hasValue && hasError;

  /// Nothing to show yet and the first load is still running — its quick
  /// retry included. The only state for a skeleton.
  bool get isFirstLoad => !hasValue && !hasError && isLoading;

  /// The load failed and there is nothing to show: the error view. A retry
  /// keeps it up (under the hint) instead of swapping it for a skeleton and
  /// back.
  bool get hasFailed => !hasValue && hasError;

  /// Newer data is loading behind what is on screen — the data itself (a
  /// background refetch, a reload after midnight) or the error view (a
  /// retry).
  bool get isRefetching => isLoading && !isFirstLoad;

  /// The record this read model shows no longer exists: the server answered
  /// 404 — it was deleted on the web or on another device. Asking again
  /// would only answer 404 again, so a detail screen says so instead of
  /// blaming the connection.
  bool get isGone => switch (error) {
        ApiException(kind: ApiErrorKind.notFound) => true,
        _ => false,
      };
}

/// A 2 dp gold line that says "updating" without hiding anything
/// (design-analysis §4.27).
///
/// Shown at the top of a screen while data that is already on screen is
/// refetched in the background (after a write, on app resume, on a tab
/// re-tap, at midnight). It takes no layout space and appears only after
/// [Motion.syncHintDelay] — a real timer, so a quick refresh never flashes
/// it, reduced motion included — then fades in over 150 ms and out over
/// 200 ms. Under reduced motion it is a still line at 60 %.
///
/// Hide it while a pull-to-refresh spinner shows
/// (`active: isRefetching && !pulling`).
class SyncHint extends StatefulWidget {
  final bool active;

  const SyncHint({super.key, required this.active});

  /// [child] with the hint laid over its top edge (taps pass through it).
  static Widget over({required bool active, required Widget child}) => Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(child: SyncHint(active: active)),
          ),
        ],
      );

  @override
  State<SyncHint> createState() => _SyncHintState();
}

class _SyncHintState extends State<SyncHint> {
  /// The hint's fade in.
  static const _hintIn = Motion.hintIn;

  Timer? _delay;

  /// Past the delay and still active.
  bool _shown = false;

  /// Still on screen: shown, or fading out.
  bool _mounted = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _wait();
  }

  @override
  void didUpdateWidget(SyncHint old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _wait();
    } else {
      _delay?.cancel();
      _delay = null;
      if (_shown) setState(() => _shown = false);
    }
  }

  void _wait() {
    _delay?.cancel();
    _delay = Timer(Motion.syncHintDelay, () {
      _delay = null;
      if (!mounted) return;
      setState(() {
        _shown = true;
        _mounted = true;
      });
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    // Not even built while idle: an indeterminate indicator ticks for as
    // long as it exists.
    if (!_mounted) return const SizedBox(height: 2);
    final reduced = Motion.reduced(context);
    if (reduced && !_shown) return const SizedBox(height: 2);
    final Widget line = reduced
        ? Semantics(
            label: context.l10n.syncUpdating,
            child: SizedBox(
              height: 2,
              width: double.infinity,
              child: ColoredBox(color: c.gold.withValues(alpha: 0.6)),
            ),
          )
        : LinearProgressIndicator(
            minHeight: 2,
            color: c.gold,
            backgroundColor: Colors.transparent,
            semanticsLabel: context.l10n.syncUpdating,
          );
    return RepaintBoundary(
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        // In 150 ms, out in 200 ms.
        duration: reduced
            ? Duration.zero
            : _shown
                ? _hintIn
                : Motion.quick,
        curve: _shown ? Motion.enter : Motion.exit,
        onEnd: () {
          if (!_shown && mounted) setState(() => _mounted = false);
        },
        child: line,
      ),
    );
  }
}
