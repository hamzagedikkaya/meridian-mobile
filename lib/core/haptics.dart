import 'package:flutter/services.dart';

/// Haptics map — docs/design.md §5. All calls are silent no-ops on web.
class Haptics {
  /// Habit check complete, todo done, transaction saved, login success.
  static void success() => HapticFeedback.lightImpact();

  /// Counter ±, keypad key, segmented/mood/tab select, picker tick, card snap.
  static void tick() => HapticFeedback.selectionClick();

  /// Pull-to-refresh armed, all-habits-done, goal reaches 100%.
  static void celebrate() => HapticFeedback.mediumImpact();

  /// Delete confirm, over-budget crossing, error snackbar.
  static void danger() => HapticFeedback.heavyImpact();
}
