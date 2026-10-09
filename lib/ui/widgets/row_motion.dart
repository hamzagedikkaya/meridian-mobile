import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/deferred_deletes.dart';
import '../../data/recent_changes.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

// Row motion (design-analysis §4.29, §5.4): only rows the user just
// changed on this device move — never a refetch, a page or a filter.

/// A new or restored row growing in: its height opens in [Motion.standard]
/// (`easeOutCubic`, from the top) and it fades in from 80 ms. Plays once,
/// when mounted with [play]; reduced motion shows it at once.
class RowEnter extends StatefulWidget {
  const RowEnter({super.key, required this.play, required this.child});

  final bool play;
  final Widget child;

  @override
  State<RowEnter> createState() => _RowEnterState();
}

class _RowEnterState extends State<RowEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.standard,
    value: 1,
  );
  late final CurvedAnimation _size = CurvedAnimation(
    parent: _c,
    curve: Motion.enter,
  );
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _c,
    curve: Interval(
      Motion.pressIn.inMicroseconds / Motion.standard.inMicroseconds,
      1,
      curve: Motion.enter,
    ),
  );
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (widget.play && !Motion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _size.dispose();
    _fade.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _size,
    alignment: AlignmentDirectional.topStart,
    child: FadeTransition(opacity: _fade, child: widget.child),
  );
}

/// A row leaving: its ghost shrinks in [Motion.collapse] (`easeInCubic`)
/// and fades in 150 ms, then [onDone]. Reduced motion: gone at once.
class RowExit extends StatefulWidget {
  const RowExit({super.key, required this.onDone, required this.child});

  final VoidCallback onDone;
  final Widget child;

  @override
  State<RowExit> createState() => _RowExitState();
}

class _RowExitState extends State<RowExit> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.collapse,
    value: 1,
  );
  late final CurvedAnimation _size = CurvedAnimation(
    parent: _c,
    curve: Motion.exit,
  );
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _c,
    // Fully faded in the first 150 of the 250 ms.
    curve: Interval(
      1 - Motion.pressOut.inMicroseconds / Motion.collapse.inMicroseconds,
      1,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
      return;
    }
    _c.reverse().whenCompleteOrCancel(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _size.dispose();
    _fade.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: SizeTransition(
        sizeFactor: _size,
        alignment: AlignmentDirectional.topStart,
        child: FadeTransition(opacity: _fade, child: widget.child),
      ),
    ),
  );
}

/// "What changed": goldContainer at 55 % behind the row, fading out over
/// [Motion.highlight] (`easeOutCubic`). Paint only — no layout. Plays when
/// mounted with [play], and again whenever [trigger] changes. Reduced
/// motion: no wash (the row itself shows the change).
class HighlightWash extends StatefulWidget {
  const HighlightWash({
    super.key,
    required this.play,
    this.trigger,
    required this.child,
  });

  final bool play;
  final Object? trigger;
  final Widget child;

  @override
  State<HighlightWash> createState() => _HighlightWashState();
}

class _HighlightWashState extends State<HighlightWash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.highlight,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: Motion.enter,
  );
  bool _decided = false;

  void _play() {
    if (Motion.reduced(context)) return;
    _c.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (widget.play) _play();
  }

  @override
  void didUpdateWidget(HighlightWash old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger != null) _play();
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _WashPainter(_t, context.nok.goldContainer),
    child: widget.child,
  );
}

class _WashPainter extends CustomPainter {
  _WashPainter(this.t, this.color) : super(repaint: t);

  final Animation<double> t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 1 → 0 as the animation runs; nothing once it is done (or never ran).
    final status = t.status;
    if (status == AnimationStatus.dismissed ||
        status == AnimationStatus.completed) {
      return;
    }
    final alpha = 0.55 * (1 - t.value);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: color.a * alpha),
    );
  }

  @override
  bool shouldRepaint(_WashPainter old) => old.t != t || old.color != color;
}

/// A list row that moves only if this device just changed it
/// ([RecentChanges]): created or restored → [RowEnter] and the wash;
/// edited → the wash (again on each new edit while mounted). Rows a
/// refetch brings, pages and filters stay still.
class RowMotion extends ConsumerStatefulWidget {
  const RowMotion({super.key, required this.record, required this.child});

  final RecordKey record;
  final Widget child;

  @override
  ConsumerState<RowMotion> createState() => _RowMotionState();
}

class _RowMotionState extends ConsumerState<RowMotion> {
  late final ChangeKind? _atMount = ref
      .read(recentChangesProvider.notifier)
      .of(widget.record.scope, widget.record.id);
  Object? _washTrigger;

  @override
  Widget build(BuildContext context) {
    ref.listen(
      recentChangesProvider.select((changes) => changes[widget.record]),
      (_, next) {
        if (next == null || next.kind == ChangeKind.removed) return;
        setState(() => _washTrigger = next.at);
      },
    );
    final kind = _atMount;
    final enters = kind == ChangeKind.inserted || kind == ChangeKind.restored;
    return RowEnter(
      play: enters,
      child: HighlightWash(
        play: kind != null && kind != ChangeKind.removed,
        trigger: _washTrigger,
        child: widget.child,
      ),
    );
  }
}

/// A column of rows that keeps the ghost of a row deleted from a sheet or
/// a menu for [Motion.collapse] (it shrinks and fades in place), and grows
/// a row back in, washed, when "Geri al" brings it back.
///
/// A row counts as deleted by the user when its record ([recordOf]) is
/// hidden by a pending delete (`DeferredDeletes`) or noted as removed in
/// [RecentChanges]. Any other row that leaves — a refetch, a filter —
/// leaves without motion. A swipe delete animates itself (`Dismissible`)
/// and is hidden before it leaves: pass [animateRemoval] to skip it.
class RemovalAwareList<T> extends ConsumerStatefulWidget {
  const RemovalAwareList({
    super.key,
    required this.items,
    required this.recordOf,
    required this.itemBuilder,
    this.animateRemoval,
  });

  final List<T> items;
  final RecordKey Function(T item) recordOf;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Whether a row that just left should leave a ghost; null asks the
  /// pending deletes and [RecentChanges].
  final bool Function(T item)? animateRemoval;

  @override
  ConsumerState<RemovalAwareList<T>> createState() =>
      _RemovalAwareListState<T>();
}

class _RemovalAwareListState<T> extends ConsumerState<RemovalAwareList<T>> {
  /// Rows on their way out, by record, with the place they had.
  final _ghosts = <RecordKey, ({T item, int index})>{};

  /// Records whose ghost was shown: if they come back, it is an undo.
  final _removed = <RecordKey>{};
  final _restored = <RecordKey>{};

  bool _userRemoved(T item) {
    final custom = widget.animateRemoval;
    if (custom != null) return custom(item);
    final record = widget.recordOf(item);
    final hidden = ref.read(deferredDeletesProvider).contains(record);
    final noted =
        ref.read(recentChangesProvider.notifier).of(record.scope, record.id) ==
        ChangeKind.removed;
    return hidden || noted;
  }

  @override
  void didUpdateWidget(RemovalAwareList<T> old) {
    super.didUpdateWidget(old);
    final now = {for (final item in widget.items) widget.recordOf(item)};
    for (var i = 0; i < old.items.length; i++) {
      final item = old.items[i];
      final record = widget.recordOf(item);
      if (now.contains(record) || _ghosts.containsKey(record)) continue;
      if (Motion.reduced(context) || !_userRemoved(item)) continue;
      _ghosts[record] = (item: item, index: i);
      _removed.add(record);
    }
    for (final record in now) {
      _ghosts.remove(record);
      if (_removed.remove(record)) _restored.add(record);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      for (final item in widget.items)
        KeyedSubtree(
          key: ValueKey(widget.recordOf(item)),
          child: _restored.contains(widget.recordOf(item))
              ? RowEnter(
                  play: true,
                  child: HighlightWash(
                    play: true,
                    child: widget.itemBuilder(context, item),
                  ),
                )
              : widget.itemBuilder(context, item),
        ),
    ];
    final ghosts = _ghosts.entries.toList()
      ..sort((a, b) => a.value.index.compareTo(b.value.index));
    for (final ghost in ghosts) {
      final record = ghost.key;
      rows.insert(
        ghost.value.index.clamp(0, rows.length),
        KeyedSubtree(
          key: ValueKey(('ghost', record)),
          child: RowExit(
            onDone: () {
              if (mounted) setState(() => _ghosts.remove(record));
            },
            child: widget.itemBuilder(context, ghost.value.item),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// The row checked-off todos collapse into once they stop lingering
/// (`LingeringTodos`): a check and "3 tamamlandı", fading in over
/// [Motion.quick]; a tap shows the finished ones.
class FinishedSummaryRow extends StatelessWidget {
  const FinishedSummaryRow({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.orInstant(context, Motion.quick),
      curve: Motion.enter,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.check_rounded, size: 16, color: c.inkMid),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.lingeringFinished(count),
                    style: text.bodyMedium!.copyWith(color: c.inkMid),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
