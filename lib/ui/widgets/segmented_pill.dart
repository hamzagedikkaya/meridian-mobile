import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_motion.dart';

/// A single choice among two to four short options — a transaction's kind,
/// a habit's frequency, a goal's type (design-analysis §4.13, D17).
///
/// * **Rail**: 40 dp, surface2 with a hairline, fully rounded, 4 dp inside;
///   centred in a 48 dp target.
/// * **Segments**: all as wide as the widest label (measured) + 32 dp —
///   "Gider/Gelir/Transfer" is 282 dp. With [expand] they share the full
///   width instead, never narrower than that.
/// * **Thumb**: 32 dp, goldContainer with a goldDim edge, slides to the
///   choice in 250 ms `easeOutCubic` (at once under reduced motion) and
///   carries on from where it is when retargeted mid-flight. Selection is
///   told by fill **and** edge, and the label weight.
/// * **Labels**: selected onGoldContainer w600, others inkMid w500, the
///   change in 150 ms.
/// * **Drag**: a horizontal drag along the rail carries the thumb under the
///   finger and picks the segment it is let go over.
/// * **Too wide** for the screen: the rail scrolls sideways and fades its
///   last 24 dp.
///
/// Each segment is a screen-reader button that says whether it is selected,
/// as one of a mutually exclusive group. A change plays the selection tick.
///
/// It sizes itself to the width it is given (a `LayoutBuilder`), so it
/// cannot sit inside a parent that asks for intrinsic sizes — an
/// `AlertDialog`'s content, an `IntrinsicWidth`; give it a bounded width
/// there instead.
class SegmentedPill<T> extends StatefulWidget {
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Share the available width (forms) rather than hug the labels.
  final bool expand;

  const SegmentedPill({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.expand = false,
  });

  static const railHeight = 40.0;
  static const thumbHeight = 32.0;
  static const _inset = 4.0;
  static const _labelPadding = 32.0;

  @override
  State<SegmentedPill<T>> createState() => _SegmentedPillState<T>();
}

class _SegmentedPillState<T> extends State<SegmentedPill<T>> {
  /// The thumb's left edge while a finger drags it; null otherwise.
  double? _dragLeft;

  int get _index {
    final i = widget.options.indexWhere((o) => o.$1 == widget.selected);
    return i < 0 ? 0 : i;
  }

  void _pick(int i) {
    final value = widget.options[i].$1;
    if (value == widget.selected) return;
    Haptics.tick();
    widget.onChanged(value);
  }

  /// The widest label's width, and the tallest line.
  (double, double) _measure(BuildContext context, TextStyle style) {
    var widest = 0.0;
    var tallest = 0.0;
    for (final (_, label) in widget.options) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      if (painter.height > tallest) tallest = painter.height;
      painter.dispose();
    }
    return (widest, tallest);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final selectedStyle = text.labelLarge!.copyWith(
      color: c.onGoldContainer,
      fontWeight: FontWeight.w600,
    );
    final restStyle = text.labelLarge!.copyWith(
      color: c.inkMid,
      fontWeight: FontWeight.w500,
    );
    final (widest, line) = _measure(context, selectedStyle);
    final natural = widest.ceilToDouble() + SegmentedPill._labelPadding;
    // 32 / 40 / 48 dp at normal size; larger text grows all three together,
    // so a label is never clipped (§8.3).
    final thumbH = line + 12 > SegmentedPill.thumbHeight
        ? (line + 12).ceilToDouble()
        : SegmentedPill.thumbHeight;
    final railH = thumbH + 2 * SegmentedPill._inset;
    final hitH = railH + 8 > Hit.min ? railH + 8 : Hit.min;
    final n = widget.options.length;
    final reduced = Motion.reduced(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - 2 * SegmentedPill._inset;
        var w = natural;
        if (widget.expand && constraints.hasBoundedWidth) {
          w = natural > available / n ? natural : available / n;
        }
        final overflows =
            constraints.hasBoundedWidth && w * n > available + 0.5;
        final index = _index;
        final thumbLeft = _dragLeft ?? index * w;

        // The drawn rail; screen readers get the segments' targets below.
        final drawn = ExcludeSemantics(
          child: Container(
            height: railH,
            width: w * n + 2 * SegmentedPill._inset,
            // The 1 dp edge counts towards the 4 dp inset.
            padding: const EdgeInsets.all(SegmentedPill._inset - 1),
            decoration: ShapeDecoration(
              color: c.surface2,
              shape: StadiumBorder(side: BorderSide(color: c.hairline)),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedPositioned(
                  duration: reduced || _dragLeft != null
                      ? Duration.zero
                      : Motion.collapse,
                  curve: Motion.enter,
                  left: thumbLeft,
                  width: w,
                  top: 0,
                  height: thumbH,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: c.goldContainer,
                      shape: StadiumBorder(side: BorderSide(color: c.goldDim)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        // The 48 dp targets, one per segment, over the 40 dp rail; each
        // holds its label, centred on the rail, so a tap on a label lands
        // on its own segment.
        Widget rail = SizedBox(
          height: hitH,
          width: w * n + 2 * SegmentedPill._inset,
          child: Stack(
            alignment: Alignment.center,
            children: [
              drawn,
              Positioned.fill(
                left: SegmentedPill._inset,
                right: SegmentedPill._inset,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: overflows
                      ? null
                      : (d) => setState(
                          () => _dragLeft = (d.localPosition.dx - w / 2).clamp(
                            0,
                            w * (n - 1),
                          ),
                        ),
                  onHorizontalDragUpdate: overflows
                      ? null
                      : (d) => setState(
                          () => _dragLeft = (d.localPosition.dx - w / 2).clamp(
                            0,
                            w * (n - 1),
                          ),
                        ),
                  onHorizontalDragEnd: overflows
                      ? null
                      : (_) {
                          final at = ((_dragLeft ?? 0) / w).round();
                          setState(() => _dragLeft = null);
                          _pick(at.clamp(0, n - 1));
                        },
                  onHorizontalDragCancel: () =>
                      setState(() => _dragLeft = null),
                  child: Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Semantics(
                          button: true,
                          selected: i == index,
                          inMutuallyExclusiveGroup: true,
                          label: widget.options[i].$2,
                          onTap: () => _pick(i),
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _pick(i),
                            child: SizedBox(
                              width: w,
                              height: hitH,
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: reduced
                                      ? Duration.zero
                                      : Motion.pressOut,
                                  style: i == index ? selectedStyle : restStyle,
                                  child: Text(
                                    widget.options[i].$2,
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        if (!overflows) {
          // Hugging its labels, it sits at the start of a wider parent.
          return Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            heightFactor: 1,
            child: rail,
          );
        }
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: const [Colors.white, Colors.white, Colors.transparent],
            stops: [0, 1 - Gap.xxl / bounds.width, 1],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: Gap.xxl),
            child: rail,
          ),
        );
      },
    );
  }
}
