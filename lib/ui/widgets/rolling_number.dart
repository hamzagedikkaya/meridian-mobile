import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../../core/formats.dart';
import '../../theme/app_motion.dart';
import 'entrance.dart';

/// Why a number on screen changed — which decides how it moves
/// (design-analysis §4.19).
enum NumberCause {
  /// The first visible frame of a tab's data, with the [EntranceGate] open:
  /// a 500 ms count-up inside the digit slots.
  firstLoad,

  /// The user changed it on this device (within 5 s of their last write):
  /// only the digits that changed roll, 250 ms.
  user,

  /// A refresh: a 200 ms cross-fade, nothing moves.
  background,

  /// The transaction form's amount being typed: a new digit rises 0.35 em
  /// in 120 ms, ⌫ drops the last one in 90 ms, a long ⌫ all of them in
  /// 150 ms.
  typing,
}

/// Fixed digit slots for Fraunces numbers (§3.7 "DigitSlots").
///
/// Fraunces has no tabular figures — its digits are 937–1350/2000 em wide —
/// so a changing number jitters. Every digit gets a slot as wide as the
/// widest digit ('0': 27.0 dp at 40 sp) and is centred in it; signs, ₺ and
/// separators keep their own width. The slot is measured once per (style,
/// text scale) with a `TextPainter` and cached.
///
/// At rest the number is one `Text.rich`. The engine puts a span's letter
/// spacing after its glyph, so a digit's padding ([padFor]) is split: half
/// goes on the glyph before it (or, for a leading digit, on the left of the
/// paragraph) and half on the digit itself, which then sits in the middle
/// of its slot. The engine also moves a whole line right by half of its
/// first glyph's letter spacing; [unshiftLine] takes that back. One
/// paragraph, findable by its text, laid out exactly like the moving
/// cells.
abstract final class DigitSlots {
  static final _cache = <String, ({double slot, List<double> advances})>{};

  static String _key(TextStyle s, TextScaler scaler) =>
      '${s.fontFamily}|${s.fontSize}|${s.fontWeight?.value}|'
      '${s.fontFeatures}|${scaler.scale(1000)}';

  static ({double slot, List<double> advances}) _measure(
    TextStyle style,
    TextScaler scaler,
  ) {
    final key = _key(style, scaler);
    return _cache[key] ??= () {
      final plain = style.copyWith(letterSpacing: 0);
      final advances = <double>[];
      for (var d = 0; d < 10; d++) {
        final tp = TextPainter(
          text: TextSpan(text: '$d', style: plain),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        advances.add(tp.width);
        tp.dispose();
      }
      return (slot: advances.reduce(math.max), advances: advances);
    }();
  }

  /// The width of one digit slot for [style] at [scaler].
  static double slotWidth(
    TextStyle style, [
    TextScaler scaler = TextScaler.noScaling,
  ]) => _measure(style, scaler).slot;

  /// The letter spacing that makes digit [digit] fill its slot.
  static double spacingFor(int digit, TextStyle style, TextScaler scaler) =>
      (style.letterSpacing ?? 0) + padFor(digit, style, scaler);

  /// How much narrower [digit] is than its slot: the padding that centres
  /// it, half on each side.
  static double padFor(int digit, TextStyle style, TextScaler scaler) {
    final m = _measure(style, scaler);
    return m.slot - m.advances[digit];
  }

  /// Forget every measurement (fonts reloaded in tests).
  static void clearCache() => _cache.clear();

  /// [line] painted back by half of [firstSpacing], the letter spacing of
  /// its first glyph: the engine draws a line that far to the right of its
  /// box. Layout is untouched.
  static Widget unshiftLine(Widget line, double firstSpacing) =>
      firstSpacing == 0
      ? line
      : Transform.translate(offset: Offset(-firstSpacing / 2, 0), child: line);
}

bool _isDigit(String ch) {
  final u = ch.codeUnitAt(0);
  return u >= 0x30 && u <= 0x39;
}

/// One character of the number and whether it belongs to the fraction.
typedef _Glyph = ({String ch, bool fraction});

/// [text] split into glyphs; the fraction is the decimal mark [separator]
/// and the digits after it, when the mark is followed by a digit.
List<_Glyph> _glyphs(String text, String separator, bool scaleFraction) {
  final chars = text.characters.toList();
  var fractionStart = chars.length;
  if (scaleFraction) {
    final at = chars.lastIndexOf(separator);
    if (at >= 0 && at + 1 < chars.length && _isDigit(chars[at + 1])) {
      fractionStart = at;
    }
  }
  var fractionEnd = fractionStart;
  if (fractionStart < chars.length) {
    fractionEnd = fractionStart + 1;
    while (fractionEnd < chars.length && _isDigit(chars[fractionEnd])) {
      fractionEnd++;
    }
  }
  return [
    for (var i = 0; i < chars.length; i++)
      (ch: chars[i], fraction: i >= fractionStart && i < fractionEnd),
  ];
}

/// A number set in fixed digit slots that moves by why it changed (§4.19).
///
/// The text is formatted by the caller ([formatMoney], a percentage, a
/// count); this only lays it out and moves it. Digits sit in fixed slots
/// ([DigitSlots]); the fraction (the decimal mark and the digits after it)
/// is [fractionScale] of the size (0.6 em, same colour, on the baseline).
/// Everything sits in a `FittedBox(scaleDown, centerLeft)` on one line: an
/// amount never wraps and never ends in "…" — `+₺1.234.567,89` at 40 sp
/// fits 280 dp at ≈ 0.86.
///
/// A screen reader hears [semanticsLabel] (the full signed amount) once;
/// the digit cells are excluded.
///
/// Reduced motion shows the final value in one frame, for every cause.
class RollingNumber extends StatefulWidget {
  const RollingNumber({
    super.key,
    required this.text,
    required this.style,
    this.cause = NumberCause.background,
    this.fractionScale = 0.6,
    this.semanticsLabel,
    this.decimalSeparator,
  });

  final String text;
  final TextStyle style;

  /// Why the value is what it is now: read when it mounts (only
  /// [NumberCause.firstLoad] moves then, and only through an open gate) and
  /// whenever [text] changes.
  final NumberCause cause;

  /// The fraction's size against [style]; 1 keeps one size.
  final double fractionScale;

  final String? semanticsLabel;

  /// The decimal mark that starts the fraction; null is the language's
  /// ([decimalMark]).
  final String? decimalSeparator;

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

enum _Mode { rest, count, roll, typing }

class _RollingNumberState extends State<RollingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _mode = _Mode.rest);
        }
      });
  }

  _Mode _mode = _Mode.rest;
  bool _mounted = false;

  /// What the number showed before the change being animated.
  String _from = '';

  /// +1 when the value went up, −1 when it went down.
  int _direction = 1;

  bool get _reduced => Motion.reduced(context);

  String get _separator => widget.decimalSeparator ?? decimalMark();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mounted) return;
    _mounted = true;
    if (widget.cause == NumberCause.firstLoad &&
        entranceShouldPlay(context) &&
        _digitsOf(widget.text) > 0) {
      _mode = _Mode.count;
      _controller
        ..duration = Motion.countUp
        ..forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(RollingNumber old) {
    super.didUpdateWidget(old);
    if (widget.text == old.text) return;
    if (_reduced) {
      _controller.stop();
      _mode = _Mode.rest;
      return;
    }
    switch (widget.cause) {
      case NumberCause.user:
        _from = old.text;
        _direction = _value(widget.text) >= _value(old.text) ? 1 : -1;
        _mode = _Mode.roll;
        _controller
          ..duration = Motion.roll
          ..forward(from: 0);
      case NumberCause.typing:
        _from = old.text;
        final removed = old.text.length - widget.text.length;
        _mode = _Mode.typing;
        _controller
          ..duration = removed > 1
              ? Motion.typeClear
              : removed > 0
              ? Motion.typeDelete
              : Motion.typeIn
          ..forward(from: 0);
      case NumberCause.firstLoad:
      case NumberCause.background:
        // The cross-fade of the rest state does it.
        _controller.stop();
        _mode = _Mode.rest;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static int _digitsOf(String text) => text.characters.where(_isDigit).length;

  /// [text] read as a number — its whole digits, then its fraction —
  /// signed by a leading minus. "12,5" and "12,50" are the same value.
  double _value(String text) {
    final whole = StringBuffer();
    final fraction = StringBuffer();
    for (final g in _glyphs(text, _separator, true)) {
      if (_isDigit(g.ch)) (g.fraction ? fraction : whole).write(g.ch);
    }
    final v = double.tryParse(
          '${whole.isEmpty ? '0' : whole}.${fraction.isEmpty ? '0' : fraction}',
        ) ??
        0;
    final negative = text.contains(minusSign) || text.startsWith('-');
    return negative ? -v : v;
  }

  TextStyle get _fractionStyle => widget.style.copyWith(
    fontSize: (widget.style.fontSize ?? 14) * widget.fractionScale,
  );

  bool get _scaleFraction => widget.fractionScale != 1;

  /// The style [g] is set in: the fraction smaller when it is scaled.
  TextStyle _styleOf(_Glyph g) =>
      g.fraction && _scaleFraction ? _fractionStyle : widget.style;

  /// The padding that centres digit [g] in its slot (0 for anything else).
  double _pad(_Glyph g, TextScaler scaler) => _isDigit(g.ch)
      ? DigitSlots.padFor(int.parse(g.ch), _styleOf(g), scaler)
      : 0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    Widget body;
    switch (_mode) {
      case _Mode.rest:
        body = AnimatedSwitcher(
          duration: Motion.orInstant(context, Motion.quick),
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: _rest(widget.text, scaler, key: ValueKey(widget.text)),
        );
      case _Mode.count:
        body = AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _rest(
            _counted(widget.text, Motion.enter.transform(_controller.value)),
            scaler,
          ),
        );
      case _Mode.roll:
      case _Mode.typing:
        body = AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _cells(scaler),
        );
    }
    return Semantics(
      label: widget.semanticsLabel ?? widget.text,
      container: true,
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: body,
        ),
      ),
    );
  }

  /// The number at rest: one paragraph, digits centred in their slots.
  Widget _rest(String text, TextScaler scaler, {Key? key}) {
    final glyphs = _glyphs(text, _separator, true);
    // Letter spacing lands after a glyph: each glyph carries half of its own
    // padding and half of the next digit's.
    final spans = <TextSpan>[
      for (var i = 0; i < glyphs.length; i++)
        TextSpan(
          text: glyphs[i].ch,
          style: _spacedBy(
            glyphs[i],
            _pad(glyphs[i], scaler) / 2 +
                (i + 1 < glyphs.length ? _pad(glyphs[i + 1], scaler) / 2 : 0),
          ),
        ),
    ];
    final lead = glyphs.isEmpty ? 0.0 : _pad(glyphs.first, scaler) / 2;
    return Padding(
      key: key,
      padding: EdgeInsets.only(left: lead),
      child: DigitSlots.unshiftLine(
        Text.rich(
          TextSpan(children: spans),
          style: widget.style,
          maxLines: 1,
          softWrap: false,
        ),
        spans.isEmpty ? 0 : spans.first.style?.letterSpacing ?? 0,
      ),
    );
  }

  /// [g]'s style with [extra] letter spacing after it.
  TextStyle _spacedBy(_Glyph g, double extra) {
    final style = _styleOf(g);
    return extra == 0
        ? style
        : style.copyWith(letterSpacing: (style.letterSpacing ?? 0) + extra);
  }

  /// [text] with its digits counted up to [t] of their value: the digits
  /// are read as one integer, scaled, and written back into the same slots
  /// from the right; leading slots not reached yet (and the separators
  /// between them) are left out, the units digit and the fraction stay.
  String _counted(String text, double t) {
    if (t >= 1) return text;
    final chars = text.characters.toList();
    final digitAt = [
      for (var i = 0; i < chars.length; i++)
        if (_isDigit(chars[i])) i,
    ];
    final target = BigInt.parse(digitAt.map((i) => chars[i]).join());
    final now = (target.toDouble() * t).round().toString();
    final glyphs = _glyphs(text, _separator, true);
    // Digits that must always show: the fraction and the units digit.
    final fractionDigits = [
      for (final i in digitAt)
        if (glyphs[i].fraction) i,
    ].length;
    final keep = math.max(now.length, fractionDigits + 1);
    final out = [...chars];
    for (var k = 0; k < digitAt.length; k++) {
      final i = digitAt[digitAt.length - 1 - k];
      out[i] = k < now.length ? now[now.length - 1 - k] : (k < keep ? '0' : '');
    }
    // Drop separators left of the first digit still shown.
    final firstShown = digitAt.firstWhere(
      (i) => out[i].isNotEmpty,
      orElse: () => chars.length,
    );
    for (var i = 0; i < firstShown; i++) {
      if (!_isDigit(chars[i]) && digitAt.isNotEmpty && i > digitAt.first) {
        out[i] = '';
      }
    }
    return out.join();
  }

  /// The number while it moves: one cell per character.
  Widget _cells(TextScaler scaler) {
    final from = _glyphs(_from, _separator, true);
    final to = _glyphs(widget.text, _separator, true);
    final typing = _mode == _Mode.typing;
    final t = _controller.value;
    // Typing lines up from the left (the end is where digits come and go);
    // rolling by the number's parts, so only the slots that changed move.
    final pairs = typing ? _pair(from, to) : _pairByParts(from, to);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (final (a, b) in pairs) _cell(a, b, t, scaler, typing: typing),
      ],
    );
  }

  /// [a] and [b] side by side, from the left — or from the right with
  /// [fromRight]; the shorter one's missing glyphs are null.
  static List<(_Glyph?, _Glyph?)> _pair(
    List<_Glyph> a,
    List<_Glyph> b, {
    bool fromRight = false,
  }) {
    final count = math.max(a.length, b.length);
    _Glyph? at(List<_Glyph> g, int n) {
      final i = fromRight ? g.length - count + n : n;
      return i >= 0 && i < g.length ? g[i] : null;
    }

    return [for (var n = 0; n < count; n++) (at(a, n), at(b, n))];
  }

  /// A rolled number lined up by its parts: the sign and currency before
  /// the digits and the whole part from the right (₺ stays by the digits,
  /// units under units), the fraction and what follows it from the decimal
  /// mark. 999 → 1.000 gives birth to "1." alone; 12,5 → 12,50 to one "0".
  static List<(_Glyph?, _Glyph?)> _pairByParts(
    List<_Glyph> a,
    List<_Glyph> b,
  ) {
    final pa = _parts(a);
    final pb = _parts(b);
    return [
      ..._pair(pa.prefix, pb.prefix, fromRight: true),
      ..._pair(pa.whole, pb.whole, fromRight: true),
      ..._pair(pa.fraction, pb.fraction),
      ..._pair(pa.suffix, pb.suffix),
    ];
  }

  /// [g] split into what comes before the first digit, the whole part, the
  /// fraction (decimal mark included) and what follows.
  static ({
    List<_Glyph> prefix,
    List<_Glyph> whole,
    List<_Glyph> fraction,
    List<_Glyph> suffix,
  }) _parts(List<_Glyph> g) {
    final first = g.indexWhere((x) => _isDigit(x.ch));
    if (first < 0) {
      return (prefix: g, whole: const [], fraction: const [], suffix: const []);
    }
    final lastDigit = g.lastIndexWhere((x) => _isDigit(x.ch));
    var wholeEnd = g.indexWhere((x) => x.fraction, first);
    if (wholeEnd < 0) wholeEnd = lastDigit + 1;
    var fractionEnd = wholeEnd;
    while (fractionEnd < g.length && g[fractionEnd].fraction) {
      fractionEnd++;
    }
    return (
      prefix: g.sublist(0, first),
      whole: g.sublist(first, wholeEnd),
      fraction: g.sublist(wholeEnd, fractionEnd),
      suffix: g.sublist(fractionEnd),
    );
  }

  /// One glyph in its cell; a digit centred in its slot.
  Widget _glyphText(_Glyph g, TextScaler scaler) {
    final pad = _pad(g, scaler);
    final style = _spacedBy(g, pad / 2);
    final text = DigitSlots.unshiftLine(
      Text(g.ch, style: style, maxLines: 1, softWrap: false),
      style.letterSpacing ?? 0,
    );
    return pad == 0
        ? text
        : Padding(padding: EdgeInsets.only(left: pad / 2), child: text);
  }

  double _width(_Glyph g, TextScaler scaler) {
    final style = _styleOf(g);
    if (_isDigit(g.ch)) {
      return DigitSlots.slotWidth(style, scaler) + (style.letterSpacing ?? 0);
    }
    final tp = TextPainter(
      text: TextSpan(text: g.ch, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  Widget _cell(
    _Glyph? a,
    _Glyph? b,
    double t,
    TextScaler scaler, {
    required bool typing,
  }) {
    // Unchanged: the glyph itself.
    if (a != null && b != null && a.ch == b.ch && a.fraction == b.fraction) {
      return _glyphText(b, scaler);
    }
    if (typing && a != null && b != null) return _glyphText(b, scaler);

    final em = scaler.scale(widget.style.fontSize ?? 14);
    final dir = _direction.toDouble();
    final inT = Motion.enter.transform(t);
    // The outgoing glyph leaves in 180 of the 250 ms.
    final outT = typing
        ? Motion.exit.transform(t)
        : Motion.exit.transform(
            (t * Motion.roll.inMicroseconds / Motion.rollOut.inMicroseconds)
                .clamp(0.0, 1.0),
          );

    final wa = a == null ? 0.0 : _width(a, scaler);
    final wb = b == null ? 0.0 : _width(b, scaler);
    final width = wa + (wb - wa) * inT;

    final children = <Widget>[];
    if (a != null) {
      final dy = typing ? 0.35 * em * outT : -dir * 0.6 * em * outT;
      children.add(
        Opacity(
          opacity: 1 - outT,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: _glyphText(a, scaler),
          ),
        ),
      );
    }
    if (b != null) {
      final rise = typing ? 0.35 : dir * 0.6;
      children.add(
        Opacity(
          opacity: inT,
          child: Transform.translate(
            offset: Offset(0, rise * em * (1 - inT)),
            child: _glyphText(b, scaler),
          ),
        ),
      );
    }
    return ClipRect(
      child: SizedBox(
        width: width,
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          fit: OverflowBoxFit.deferToChild,
          minWidth: 0,
          maxWidth: math.max(wa, wb),
          child: Stack(alignment: Alignment.centerLeft, children: children),
        ),
      ),
    );
  }
}
