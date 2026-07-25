import 'package:flutter/material.dart';

/// Press feedback for tappable cards/chips: scale to 0.98 over 100ms,
/// back over 150ms. Curve-based, no springs (design §2.5).
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) {
      return widget.child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: Duration(milliseconds: _pressed ? 100 : 150),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
