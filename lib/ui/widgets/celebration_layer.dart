import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/haptics.dart';
import '../../core/session.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// Celebrations (design-analysis §4.30, §5.7), drawn above every tab, route
/// and sheet: `MeridianApp` puts this layer over the router's output.
///
/// * **Tier 1** — one check-off — is the `CheckPop` alone; nothing here.
/// * **Tier 2** — today's habits all done, by the user's own tap, at most
///   once a day ([allDone]): 14 particles burst from the control that
///   finished the day, then a "Hepsi tamam" pill, with [Haptics.confirm].
/// * **Tier 3** — a 7/30/100/365-day streak, the first perfect week, a goal
///   past 100 % by a local write ([milestone]): a goldContainer card slides
///   down from under the status bar, holds 2.5 s and leaves; a tap
///   dismisses it. It is not modal.
///
/// Never for a refresh, an undo, a past day's log or a change from the
/// server — the callers only ask from a tap. One gesture plays its highest
/// tier only. Repeats are kept away in SharedPreferences
/// (`celebrated.day.<yyyy-MM-dd>`, `milestone.<key>`): unchecking and
/// checking again does not celebrate twice.
///
/// Reduced motion: no particles; the pill and the card appear and go
/// without moving; the haptic stays.
class CelebrationLayer extends ConsumerStatefulWidget {
  const CelebrationLayer({super.key, required this.child});

  final Widget child;

  /// The layer above [context], if the app has one.
  static CelebrationController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_CelebrationScope>()?.controller;

  @override
  ConsumerState<CelebrationLayer> createState() => _CelebrationLayerState();
}

/// What screens call to celebrate. Every call must come from the user's
/// own tap.
abstract interface class CelebrationController {
  /// Tier 2: today's habits are all done. [origin] is the global centre of
  /// the control that finished the day (`RenderBox.localToGlobal(
  /// size.center(Offset.zero))`); [day] the account's today.
  ///
  /// Returns whether this call claimed the day: false when the day was
  /// already celebrated, so the caller has nothing to give back.
  bool allDone({required Offset origin, required DateTime day});

  /// Gives [day]'s tier-2 celebration back: the write that earned it was
  /// refused or taken back, so the day's real completion later may still
  /// celebrate. What already played stays played. Only for a day this
  /// caller's [allDone] claimed — a day an earlier, accepted write
  /// celebrated stays celebrated (once a day, §5.7).
  void forget(DateTime day);

  /// Tier 3: a milestone, shown once per [key] ever (`habit.<id>.<n>`,
  /// `goal.<id>`, `perfect-week`). [text] is the card's line
  /// ("30 gün · Koşu").
  void milestone({required String key, required String text});
}

class _CelebrationScope extends InheritedWidget {
  const _CelebrationScope({required this.controller, required super.child});

  final CelebrationController controller;

  @override
  bool updateShouldNotify(_CelebrationScope old) => false;
}

/// The day key: `celebrated.day.2026-10-04`.
String celebratedDayKey(DateTime day) =>
    'celebrated.day.'
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

class _CelebrationLayerState extends ConsumerState<CelebrationLayer>
    implements CelebrationController {
  /// Keys celebrated in this run when the device store is not there.
  final _seen = <String>{};

  ({Offset origin, String key})? _pendingDay;
  ({String key, String text})? _pendingMilestone;
  bool _flushQueued = false;

  /// The bursts and pills on screen, each with its own id.
  final _bursts = <int, Offset>{};
  final _pills = <int, Offset>{};
  var _nextId = 0;

  String? _card;
  int _cardRun = 0;

  SharedPreferences? get _prefs {
    try {
      return ref.read(sharedPrefsProvider);
    } catch (_) {
      return null;
    }
  }

  bool _celebrated(String key) =>
      _seen.contains(key) || (_prefs?.getBool(key) ?? false);

  void _remember(String key) {
    _seen.add(key);
    unawaited(_prefs?.setBool(key, true));
  }

  @override
  bool allDone({required Offset origin, required DateTime day}) {
    final key = celebratedDayKey(day);
    if (_celebrated(key) || _pendingDay?.key == key) return false;
    // In this event, so it merges with the CheckPop's [Haptics.check]: the
    // tap that finishes the day plays confirm only (§5.8).
    Haptics.confirm();
    _pendingDay = (origin: origin, key: key);
    _queue();
    return true;
  }

  @override
  void forget(DateTime day) {
    final key = celebratedDayKey(day);
    if (_pendingDay?.key == key) _pendingDay = null;
    _seen.remove(key);
    unawaited(_prefs?.remove(key));
  }

  @override
  void milestone({required String key, required String text}) {
    final full = 'milestone.$key';
    if (_celebrated(full)) return;
    Haptics.confirm();
    _pendingMilestone = (key: full, text: text);
    _queue();
  }

  /// One gesture, one tier: whatever it asked for during this event plays
  /// once, the highest.
  void _queue() {
    if (_flushQueued) return;
    _flushQueued = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushQueued = false;
    final day = _pendingDay;
    final milestone = _pendingMilestone;
    _pendingDay = null;
    _pendingMilestone = null;
    if (!mounted) return;
    if (milestone != null) {
      _remember(milestone.key);
      // The day still counts as celebrated: the higher tier stood for it.
      if (day != null) _remember(day.key);
      _showCard(milestone.text);
    } else if (day != null) {
      _remember(day.key);
      _burst(day.origin);
    }
  }

  void _burst(Offset origin) {
    final id = _nextId++;
    setState(() {
      if (!Motion.reduced(context)) _bursts[id] = origin;
      _pills[id] = origin;
    });
  }

  void _showCard(String text) {
    setState(() {
      _card = text;
      _cardRun++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    return _CelebrationScope(
      controller: this,
      child: Stack(
        children: [
          widget.child,
          for (final MapEntry(key: id, value: origin) in _bursts.entries)
            Positioned.fill(
              key: ValueKey(('burst', id)),
              child: RepaintBoundary(
                child: ConfettiBurst(
                  origin: origin,
                  onDone: () {
                    if (mounted) setState(() => _bursts.remove(id));
                  },
                ),
              ),
            ),
          for (final MapEntry(key: id, value: origin) in _pills.entries)
            _AllDonePill(
              key: ValueKey(('pill', id)),
              origin: origin,
              onDone: () {
                if (mounted) setState(() => _pills.remove(id));
              },
            ),
          if (card != null)
            _MilestoneCard(
              key: ValueKey(('card', _cardRun)),
              text: card,
              onDone: () {
                if (mounted) setState(() => _card = null);
              },
            ),
        ],
      ),
    );
  }
}

/// "Hepsi tamam" over the control that finished the day: in 120 ms after
/// the burst, 250 ms ease-out from 0.85 scale and transparent; it stays for
/// [Motion.milestoneHold] and fades out in [Motion.milestoneOut].
class _AllDonePill extends StatefulWidget {
  const _AllDonePill({super.key, required this.origin, required this.onDone});

  final Offset origin;
  final VoidCallback onDone;

  @override
  State<_AllDonePill> createState() => _AllDonePillState();
}

class _AllDonePillState extends State<_AllDonePill>
    with SingleTickerProviderStateMixin {
  // Delay (120 ms) + in (250 ms) in one controller.
  static const _delay = Motion.pillDelay;

  /// The pill's way in.
  static const _pillIn = Motion.pillIn;
  static final _total = _delay + _pillIn;

  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: _total,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _in,
    curve: Interval(
      _delay.inMicroseconds / _total.inMicroseconds,
      1,
      curve: Motion.enter,
    ),
    reverseCurve: Motion.exit,
  );
  Timer? _hold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_in.isAnimating || _in.value > 0 || _hold != null) return;
    if (Motion.reduced(context)) {
      _in.value = 1;
      _holdThenLeave();
    } else {
      _in.forward().whenCompleteOrCancel(_holdThenLeave);
    }
  }

  void _holdThenLeave() {
    if (!mounted) return;
    _hold = Timer(Motion.milestoneHold, () async {
      if (!mounted) return;
      if (Motion.reduced(context)) {
        widget.onDone();
        return;
      }
      _in.duration = Motion.milestoneOut;
      await _in.reverse().orCancel.catchError((_) {});
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    _t.dispose();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Positioned(
      left: 0,
      right: 0,
      top: math.max(0, widget.origin.dy - 72),
      child: IgnorePointer(
        child: Align(
          alignment: Alignment(
            (widget.origin.dx / MediaQuery.sizeOf(context).width) * 2 - 1,
            0,
          ),
          child: FadeTransition(
            opacity: _t,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1).animate(_t),
              child: Semantics(
                liveRegion: true,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: c.surface3,
                    shape: StadiumBorder(
                      side: BorderSide(color: c.overlayBorder),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: c.gold,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.labelAllDone,
                          style: text.titleSmall!.copyWith(color: c.gold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tier-3 card: goldContainer, radius 16, 20 dp from the sides, 8 dp
/// under the status bar; Fraunces line. Slides down in [Motion.milestoneIn]
/// ([Motion.surfaceIn]), holds [Motion.milestoneHold], slides up in
/// [Motion.milestoneOut]; a tap sends it away.
class _MilestoneCard extends StatefulWidget {
  const _MilestoneCard({super.key, required this.text, required this.onDone});

  final String text;
  final VoidCallback onDone;

  @override
  State<_MilestoneCard> createState() => _MilestoneCardState();
}

class _MilestoneCardState extends State<_MilestoneCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.milestoneIn,
    reverseDuration: Motion.milestoneOut,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: Motion.surfaceIn,
    reverseCurve: Motion.exit,
  );
  Timer? _hold;
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.value > 0 || _c.isAnimating || _hold != null) return;
    if (Motion.reduced(context)) {
      _c.value = 1;
      _hold = Timer(Motion.milestoneHold, _leave);
    } else {
      _c.forward().whenCompleteOrCancel(() {
        if (mounted && !_leaving) _hold = Timer(Motion.milestoneHold, _leave);
      });
    }
  }

  Future<void> _leave() async {
    if (!mounted || _leaving) return;
    _leaving = true;
    _hold?.cancel();
    if (!Motion.reduced(context)) {
      await _c.reverse().orCancel.catchError((_) {});
    }
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      left: 20,
      right: 20,
      top: top,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.6),
          end: Offset.zero,
        ).animate(_t),
        child: Semantics(
          liveRegion: true,
          button: true,
          hint: context.l10n.milestoneDismissHint,
          child: Material(
            color: c.goldContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _leave,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 20,
                        color: c.onGoldContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.text,
                          style: text.headlineSmall!.copyWith(
                            color: c.onGoldContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's one confetti (tier 2): 14 particles in the palette's gold and
/// income-chart green, bursting from [origin] (local to the area it fills;
/// null is the old spot, a third of the way down the middle) over
/// [Motion.confetti] under 520 dp/s² of gravity. Pointer events pass
/// through; reduced motion draws nothing.
class ConfettiBurst extends StatefulWidget {
  final VoidCallback? onDone;
  final Offset? origin;

  const ConfettiBurst({super.key, this.onDone, this.origin});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Motion.confetti,
  );
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _particles = List.generate(14, (i) {
      final angle = -math.pi * 0.85 + rnd.nextDouble() * (math.pi * 0.7);
      return _Particle(
        angle: angle,
        speed: 120 + rnd.nextDouble() * 150,
        gold: i.isEven,
        size: 5 + rnd.nextDouble() * 4,
        spin: (rnd.nextDouble() - 0.5) * 8,
      );
    });
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone?.call();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrl.isAnimating || _ctrl.isCompleted) return;
    if (Motion.reduced(context)) {
      // Nothing to draw: done as soon as this frame is.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone?.call();
      });
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return IgnorePointer(
      child: CustomPaint(
        painter: _ConfettiPainter(
          _ctrl,
          _particles,
          origin: widget.origin,
          gold: c.gold,
          green: c.chartIncome,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final bool gold;
  final double size;
  final double spin;

  const _Particle({
    required this.angle,
    required this.speed,
    required this.gold,
    required this.size,
    required this.spin,
  });
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(
    this.t,
    this.particles, {
    required this.origin,
    required this.gold,
    required this.green,
  }) : super(repaint: t);

  final Animation<double> t;
  final List<_Particle> particles;
  final Offset? origin;
  final Color gold;
  final Color green;

  static const _gravity = 520.0;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    if (v <= 0 || v >= 1) return;
    final from = origin ?? Offset(size.width / 2, size.height * 0.28);
    final seconds = v * Motion.confetti.inMicroseconds / 1e6;
    for (final p in particles) {
      final dx = math.cos(p.angle) * p.speed * v;
      final dy =
          math.sin(p.angle) * p.speed * v + 0.5 * _gravity * seconds * seconds;
      final pos = from + Offset(dx, dy);
      final opacity = (1 - ((v - 0.6) / 0.4)).clamp(0.0, 1.0);
      final color = p.gold ? gold : green;
      final paint = Paint()..color = color.withValues(alpha: color.a * opacity);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * v);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 1.6,
          ),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.t != t ||
      old.origin != origin ||
      old.gold != gold ||
      old.green != green;
}
