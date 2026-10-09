import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';

/// The app's own "Reduce motion" switch (Profil › Uygulama), next to the
/// system's "Remove animations" (design-analysis §5.9).
///
/// Nothing reads this directly to decide whether to animate: `MeridianApp`
/// folds it into `MediaQuery.disableAnimations` together with the system
/// flag, so every widget asks one question — `Motion.reduced(context)`.
///
/// Stored on this device only (SharedPreferences `reduce_motion`), off by
/// default, and kept across a sign-out like the theme and language.
class ReduceMotionController extends Notifier<bool> {
  static const _key = PrefKeys.reduceMotion;

  @override
  bool build() => ref.watch(sharedPrefsProvider).getString(_key) == 'true';

  Future<void> set(bool reduce) async {
    state = reduce;
    await ref.read(sharedPrefsProvider).setString(_key, reduce.toString());
  }
}

final reduceMotionProvider =
    NotifierProvider<ReduceMotionController, bool>(ReduceMotionController.new);

/// Folds the app's "Reduce motion" switch into the one signal every widget
/// reads: `MediaQuery.disableAnimations` is true when the system's "Remove
/// animations" **or** [reduce] is on. `MeridianApp` puts it in
/// `MaterialApp.builder`, above every route, sheet and dialog.
class MotionPreference extends StatelessWidget {
  const MotionPreference({super.key, required this.reduce, required this.child});

  final bool reduce;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!reduce || MediaQuery.disableAnimationsOf(context)) return child;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child,
    );
  }
}
