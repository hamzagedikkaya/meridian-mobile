import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// 6dp progress bar with an optional vertical pace tick (design §4.4 budgets).
/// Fills from 0 over 600ms on first build, then animates previous→new over
/// 350ms, never re-zeroing (§5).
class PacedProgressBar extends StatefulWidget {
  final double value;
  final Color color;
  final double? paceTick;
  final double height;

  const PacedProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.paceTick,
    this.height = 6,
  });

  @override
  State<PacedProgressBar> createState() => _PacedProgressBarState();
}

class _PacedProgressBarState extends State<PacedProgressBar> {
  bool _first = true;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final target = widget.value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height / 2),
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              children: [
                Container(color: c.surface2),
                TweenAnimationBuilder<double>(
                  tween:
                      _first ? Tween(begin: 0, end: target) : Tween(end: target),
                  duration: Duration(milliseconds: _first ? 600 : 350),
                  curve: Curves.easeOutCubic,
                  onEnd: () {
                    if (mounted && _first) setState(() => _first = false);
                  },
                  builder: (context, v, _) =>
                      Container(width: width * v, color: widget.color),
                ),
                if (widget.paceTick != null)
                  Positioned(
                    left: (width * widget.paceTick!.clamp(0.0, 1.0)) - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: c.inkLow),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
