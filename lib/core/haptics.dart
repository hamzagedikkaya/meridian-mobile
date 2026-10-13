import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What a haptic means, lowest priority first (design-analysis §5.8). When a
/// gesture asks for several, only the highest plays.
enum HapticKind {
  /// `selectionClick` · CLOCK_TICK: keypad key, counter step, segment,
  /// picker, mood, energy, swatch and chip selection, swipe threshold, chart
  /// scrub, goal stepper step.
  tick,

  /// `lightImpact` · VIRTUAL_KEY: one habit or todo checked off — only from
  /// a `CheckPop` or `CounterPill` tap.
  check,

  /// `mediumImpact` · KEYBOARD_TAP: pull-to-refresh armed.
  armed,

  /// `successNotification` · CONFIRM (API 30+, else `lightImpact`): every
  /// form save, a subscription paid, sign-in, the day done, a goal at 100 %,
  /// a milestone.
  confirm,

  /// `errorNotification` · REJECT (API 30+, else `vibrate()`): a write taken
  /// back, a 422 or validation error, a quick-capture failure, a refused
  /// delete or keypad digit, a wrong current password.
  reject,
}

/// Semantic haptics — the one way the app touches the vibrator (§5.8).
///
/// * **Meaning, not strength.** Call [tick], [check], [armed], [confirm] or
///   [reject]; the Android constant (and its fallback below API 30) is
///   chosen here.
/// * **One per gesture.** Requests made while one event is being handled
///   are queued and the highest-priority one plays once, in a microtask: the
///   tap that finishes the day plays [confirm] only, not [check] and then
///   [confirm]. A request within [quietWindow] of the last one played is
///   dropped unless it outranks it.
/// * **Only from a finger.** Never from data: a refresh, an undo, a
///   navigation, a scroll or a routine delete is silent. A widget that
///   animates when its data changes (`CheckPop.didUpdateWidget`) does not
///   buzz.
/// * Every haptic has a visual counterpart; it is never the only signal.
///   Long presses use `Feedback.forLongPress(context)` instead.
///
/// Silent on web. On Android the API level comes from [init] (the
/// `meridian/device` channel, `MainActivity.kt`).
abstract final class Haptics {
  /// The platform channel `MainActivity.kt` answers on.
  static const channel = MethodChannel('meridian/device');

  /// How long after a haptic an equal or lower one is dropped.
  static const quietWindow = Duration(milliseconds: 80);

  static int? _androidSdk;
  static HapticKind? _queued;
  static HapticKind? _lastKind;
  static Duration? _lastAt;
  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration Function() _now = () => _stopwatch.elapsed;

  /// Reads the Android API level once, at start-up. Elsewhere, and when the
  /// channel does not answer, the modern constants are used.
  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _androidSdk = await channel.invokeMethod<int>('sdkInt');
    } catch (_) {
      _androidSdk = null;
    }
  }

  /// The Android API level [init] read, or null.
  static int? get androidSdk => _androidSdk;

  /// Below API 30 Android has no CONFIRM or REJECT constant.
  static bool get _legacyAndroid =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      (_androidSdk ?? 30) < 30;

  // --- The semantic API --------------------------------------------------------

  static void tick() => request(HapticKind.tick);
  static void check() => request(HapticKind.check);
  static void armed() => request(HapticKind.armed);
  static void confirm() => request(HapticKind.confirm);
  static void reject() => request(HapticKind.reject);

  // --- The coalescer -----------------------------------------------------------

  /// Queues [kind]; the strongest request of this event plays once.
  static void request(HapticKind kind) {
    if (kIsWeb) return;
    final queued = _queued;
    if (queued == null) {
      _queued = kind;
      scheduleMicrotask(_flush);
    } else if (kind.index > queued.index) {
      _queued = kind;
    }
  }

  static void _flush() {
    final kind = _queued;
    _queued = null;
    if (kind == null) return;
    final now = _now();
    final last = _lastAt;
    final lastKind = _lastKind;
    if (last != null &&
        lastKind != null &&
        now - last < quietWindow &&
        kind.index <= lastKind.index) {
      return;
    }
    _lastAt = now;
    _lastKind = kind;
    unawaited(_play(kind));
  }

  static Future<void> _play(HapticKind kind) async {
    try {
      switch (kind) {
        case HapticKind.tick:
          await HapticFeedback.selectionClick();
        case HapticKind.check:
          await HapticFeedback.lightImpact();
        case HapticKind.armed:
          await HapticFeedback.mediumImpact();
        case HapticKind.confirm:
          await (_legacyAndroid
              ? HapticFeedback.lightImpact()
              : HapticFeedback.successNotification());
        case HapticKind.reject:
          await (_legacyAndroid
              ? HapticFeedback.vibrate()
              : HapticFeedback.errorNotification());
      }
    } catch (_) {
      // A platform without a vibrator: nothing to feel, nothing to report.
    }
  }

  /// Test hooks: a fake API level and clock, and a clean coalescer.
  @visibleForTesting
  static void debugReset({int? androidSdk, Duration Function()? now}) {
    _androidSdk = androidSdk;
    _queued = null;
    _lastKind = null;
    _lastAt = null;
    _now = now ?? () => _stopwatch.elapsed;
  }
}
