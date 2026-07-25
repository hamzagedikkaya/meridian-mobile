import 'package:flutter/material.dart';

/// Full-screen modal route that slides up from the bottom (design §5, §3):
/// 400ms easeOutCubic in / 300ms easeInCubic out, opaque, fullscreenDialog
/// semantics. Use for every create/edit form.
Route<T> slideUpModalRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    fullscreenDialog: true,
    opaque: true,
    transitionDuration: const Duration(milliseconds: 400),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}
