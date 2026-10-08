import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';

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

/// A 2 dp line that says "updating" without hiding anything.
///
/// Shown at the top of a screen while data that is already on screen is
/// refetched in the background (after a write, on app resume, on a tab
/// re-tap, at midnight). It waits ~300 ms before it appears, so a quick
/// refresh never flashes it, and it takes no layout space.
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

class _SyncHintState extends State<SyncHint>
    with SingleTickerProviderStateMixin {
  // The first half of the fade-in shows nothing: that is the delay.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: widget.active ? 1 : 0,
  );
  late final CurvedAnimation _opacity = CurvedAnimation(
    parent: _fade,
    curve: const Interval(0.5, 1, curve: Curves.easeOut),
  );

  @override
  void didUpdateWidget(SyncHint old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      widget.active ? _fade.forward() : _fade.reverse();
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) {
        // Not even mounted while idle: an indeterminate indicator ticks for
        // as long as it exists.
        if (_fade.value == 0) return const SizedBox(height: 2);
        return Opacity(
          opacity: _opacity.value,
          child: LinearProgressIndicator(
            minHeight: 2,
            color: c.gold,
            backgroundColor: Colors.transparent,
            semanticsLabel: context.l10n.syncUpdating,
          ),
        );
      },
    );
  }
}
