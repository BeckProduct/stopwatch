import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chrono_geometry.dart';
import 'chrono_theme.dart';
import 'rattrapante.dart';

/// The dial and everything on it. No case: the rim is the only frame.
///
/// A pure function of its inputs: it reads no clock and holds no state. The
/// elapsed value is read once per frame by the widget above and handed down, so
/// every hand on the dial is derived from the same reading.
class ChronoPainter extends CustomPainter {
  const ChronoPainter({
    required this.theme,
    required this.elapsed,
    required this.splitDeg,
    required this.splitState,
    required this.reduceMotion,
    required this.smearFromDeg,
    required this.splitFade,
  });

  final ChronoTheme theme;
  final Duration elapsed;
  final double splitDeg;
  final SplitState splitState;
  final bool reduceMotion;

  /// Where the split hand was last frame, when the sector between then and now
  /// is wide enough to be worth smearing.
  final double? smearFromDeg;

  /// Cross-fade weight for the Reduce Motion catch-up, 0..1.
  final double splitFade;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final scale = size.width / Dial.boxWidth;
    canvas.scale(scale);
    canvas.translate(-Dial.boxLeft, -Dial.boxTop);

    _paintDialPlate(canvas);
    _paintRim(canvas);
    _paintTracks(canvas);
    _paintBatons(canvas);
    _paintSignature(canvas);
    _paintRegisters(canvas);
    _paintSmear(canvas);
    _paintSplitHand(canvas);
    _paintSweepHand(canvas);
    _paintCentreCap(canvas);
    _paintGlare(canvas);

    canvas.restore();
  }

  static const Offset _c = Offset(Dial.centre, Dial.centre);

  Paint get _p => Paint()..isAntiAlias = true;

  void _paintDialPlate(Canvas canvas) {
    canvas.drawCircle(
      _c,
      Dial.plateRadius,
      _p
        ..shader = ui.Gradient.radial(
          const Offset(0.38 * 314 + 43, 0.3 * 314 + 43),
          0.86 * 314,
          [theme.dial0, theme.dial1, theme.dial2],
          const [0, 0.62, 1],
        ),
    );
  }

  /// The rim. A bare dial on a bare background needs an edge of its own, so
  /// this is a turned ring with a lit outer hairline and a dark seam against
  /// the plate -- the reading the bezel used to give for free.
  void _paintRim(Canvas canvas) {
    canvas.drawCircle(
      _c,
      (Dial.rimInner + Dial.rimOuter) / 2,
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = Dial.rimOuter - Dial.rimInner
        ..shader = ui.Gradient.linear(
          const Offset(64, 44),
          const Offset(336, 356),
          [theme.bez0, theme.bez1, theme.bez2],
          const [0, 0.55, 1],
        ),
    );
    canvas.drawCircle(
      _c,
      Dial.rimOuter,
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = theme.steel1.withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      _c,
      Dial.rimInner + 0.7,
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.black.withValues(alpha: 0.55),
    );
  }

  void _paintTracks(Canvas canvas) {
    // 1/5-second hairlines, 300 of them, with the second marks left out.
    final fifth = _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = theme.ink.withValues(alpha: 0.5);
    for (var i = 0; i < 300; i++) {
      if (i % 5 == 0) continue;
      _tick(
        canvas,
        Dial.rFifthInner,
        Dial.rFifthOuter,
        i.toDouble() * 1.2,
        fifth,
      );
    }

    final minor = _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = theme.ink.withValues(alpha: 0.85);
    final major = _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = theme.ink;
    for (var i = 0; i < 60; i++) {
      final deg = i * 6.0;
      if (i % 5 == 0) {
        _tick(canvas, Dial.rMin5Inner, Dial.rMinOuter, deg, major);
      } else {
        _tick(canvas, Dial.rMinInner, Dial.rMinOuter, deg, minor);
      }
    }
  }

  /// Applied hour batons. 3, 6 and 9 are omitted -- the sub-registers take
  /// those seats -- and 12 gets the classic double baton.
  void _paintBatons(Canvas canvas) {
    const seats = <double>[0, 30, 60, 120, 150, 210, 240, 300, 330];
    for (final deg in seats) {
      if (deg == 0) {
        _baton(canvas, deg - 4.6);
        _baton(canvas, deg + 4.6);
      } else {
        _baton(canvas, deg);
      }
    }
  }

  void _baton(Canvas canvas, double deg) {
    _tick(
      canvas,
      Dial.rIndexInner,
      Dial.rIndexOuter,
      deg,
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.4
        ..color = theme.ink,
    );
    final lume = _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..color = theme.lume;
    if (theme.lumeGlow > 0) {
      lume.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6);
      _tick(canvas, Dial.rIndexInner + 3, Dial.rIndexOuter - 3, deg, lume);
      lume.maskFilter = null;
    }
    _tick(canvas, Dial.rIndexInner + 3, Dial.rIndexOuter - 3, deg, lume);
  }

  void _paintSignature(Canvas canvas) {
    _text(
      canvas,
      'BECK.',
      const Offset(Dial.centre, 113),
      TextStyle(
        fontSize: 15,
        letterSpacing: 5.5,
        fontWeight: FontWeight.w800,
        color: theme.ink,
        fontFamily: 'Archivo',
      ),
    );
    _text(
      canvas,
      'RATTRAPANTE',
      const Offset(Dial.centre, 131),
      TextStyle(
        fontSize: 7.6,
        letterSpacing: 2.9,
        fontWeight: FontWeight.w600,
        color: theme.inkSoft,
        fontFamily: 'Archivo',
      ),
    );
    // Not "SWISS MADE": this watch is not, and the term is protected. The
    // dial foot says what is actually true of the movement behind it.
    _text(
      canvas,
      'MONOTONIC',
      const Offset(Dial.centre, 324),
      TextStyle(
        fontSize: 6,
        letterSpacing: 1.9,
        fontWeight: FontWeight.w600,
        color: theme.inkSoft,
        fontFamily: 'Archivo',
      ),
    );
  }

  void _paintRegisters(Canvas canvas) {
    _register(
      canvas,
      Offset(Dial.minutesCentre.dx, Dial.minutesCentre.dy),
      'MIN',
      minuteDegFor(elapsed),
      30,
      5,
      const [(10, 120.0), (20, 240.0), (30, 0.0)],
      38,
      false,
    );
    _register(
      canvas,
      Offset(Dial.hoursCentre.dx, Dial.hoursCentre.dy),
      'HR',
      hourDegFor(elapsed),
      12,
      3,
      const [(3, 90.0), (6, 180.0), (9, 270.0), (12, 0.0)],
      36,
      false,
    );
    // Ten divisions, a revolution a second. Quantised with the sweep hand:
    // it is the fastest thing on the dial and the one Reduce Motion is for.
    _register(
      canvas,
      Offset(Dial.tenthsCentre.dx, Dial.tenthsCentre.dy),
      '1/10',
      tenthDegFor(quantise(elapsed, reduceMotion: reduceMotion)),
      10,
      5,
      const [(5, 180.0), (10, 0.0)],
      36,
      splitState != SplitState.joined,
    );
  }

  void _register(
    Canvas canvas,
    Offset centre,
    String label,
    double handDeg,
    int tickCount,
    int every,
    List<(int, double)> numerals,
    double handLength,
    bool capLit,
  ) {
    canvas.drawCircle(
      centre,
      Dial.registerRadius,
      _p
        ..shader = ui.Gradient.radial(centre.translate(-12, -14), 0.9 * 84, [
          theme.reg0,
          theme.reg1,
        ]),
    );
    canvas.drawCircle(
      centre,
      Dial.registerRadius,
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = theme.reg1,
    );
    // Azurage: concentric turning marks.
    for (final ring in const [(36.0, 0.7), (29.0, 0.55), (22.0, 0.4)]) {
      canvas.drawCircle(
        centre,
        ring.$1,
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = theme.regRing.withValues(alpha: ring.$2),
      );
    }
    for (var i = 0; i < tickCount; i++) {
      final deg = i * 360 / tickCount;
      final heavy = i % every == 0;
      final a = polar(centre.dx, centre.dy, heavy ? 30 : 33, deg);
      final b = polar(centre.dx, centre.dy, 37, deg);
      canvas.drawLine(
        Offset(a.dx, a.dy),
        Offset(b.dx, b.dy),
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = heavy ? 1.4 : 0.7
          ..color = theme.regHand.withValues(alpha: heavy ? 0.9 : 0.5),
      );
    }
    for (final n in numerals) {
      final p = polar(centre.dx, centre.dy, 24, n.$2);
      _text(
        canvas,
        '${n.$1}',
        Offset(p.dx, p.dy + 3),
        TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: theme.regHand.withValues(alpha: 0.85),
          fontFamily: 'Archivo',
        ),
      );
    }
    _text(
      canvas,
      label,
      centre.translate(0, 26),
      TextStyle(
        fontSize: 6,
        letterSpacing: 1.9,
        fontWeight: FontWeight.w600,
        color: theme.regLabel,
        fontFamily: 'Archivo',
      ),
    );

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(handDeg * math.pi / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-1.4, -(handLength - 8), 2.8, handLength),
        const Radius.circular(1.2),
      ),
      _p..color = theme.regHand,
    );
    canvas.restore();
    canvas.drawCircle(
      centre,
      3.4,
      _p..color = capLit ? theme.accent1 : theme.regHand,
    );
  }

  /// The catch-up smear: the sector the split hand actually crossed since the
  /// last frame, measured rather than drawn.
  void _paintSmear(Canvas canvas) {
    final from = smearFromDeg;
    if (from == null) return;
    final sweptDeg = smearSweep(from, splitDeg);
    if (sweptDeg == null) return;
    final path = Path()
      ..moveTo(Dial.centre, Dial.centre)
      ..arcTo(
        Rect.fromCircle(center: _c, radius: Dial.plateRadius),
        (from - 90) * math.pi / 180,
        sweptDeg * math.pi / 180,
        false,
      )
      ..close();
    canvas.save();
    canvas.clipPath(path);
    canvas.drawCircle(
      _c,
      Dial.plateRadius,
      _p..color = theme.rat1.withValues(alpha: 0.24),
    );
    canvas.drawCircle(_c, 60, _p..blendMode = BlendMode.clear);
    canvas.restore();
  }

  void _paintSplitHand(Canvas canvas) {
    final opacity = splitFade.clamp(0.0, 1.0);
    if (opacity <= 0) return;
    canvas.save();
    canvas.translate(Dial.centre, Dial.centre);
    canvas.rotate(splitDeg * math.pi / 180);
    // A Paint carrying a shader ignores its colour, so the cross-fade has to
    // go into the gradient's own stops and into every solid fill beside it.
    final rat0 = theme.rat0.withValues(alpha: opacity);
    final rat1 = theme.rat1.withValues(alpha: opacity);
    final paint = _p
      ..shader = ui.Gradient.linear(
        const Offset(0, -154),
        const Offset(0, 34),
        [rat0, rat1],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-2.6, -142, 5.2, 150),
        const Radius.circular(1.4),
      ),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, -154)
        ..lineTo(4.8, -138)
        ..lineTo(-4.8, -138)
        ..close(),
      paint,
    );
    canvas.drawCircle(Offset.zero, 9.5, _p..color = rat1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-2.6, 0, 5.2, 34),
        const Radius.circular(2.4),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(0, 32), 6.5, _p..color = rat1);
    canvas.restore();
  }

  void _paintSweepHand(Canvas canvas) {
    canvas.save();
    canvas.translate(Dial.centre, Dial.centre);
    canvas.rotate(
      sweepDegFor(quantise(elapsed, reduceMotion: reduceMotion)) *
          math.pi /
          180,
    );
    final paint = _p
      ..shader = ui.Gradient.linear(
        const Offset(0, -146),
        const Offset(0, 36),
        [theme.accent0, theme.accent1],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-1.8, -146, 3.6, 154),
        const Radius.circular(1.2),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(0, -128), 4.2, _p..color = theme.lume);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-1.8, 0, 3.6, 36),
        const Radius.circular(1.8),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(0, 34), 7.4, _p..color = theme.accent1);
    canvas.restore();
  }

  void _paintCentreCap(Canvas canvas) {
    canvas.drawCircle(_c, 7, _p..color = theme.ink);
    canvas.drawCircle(_c, 4, _p..color = theme.accent1);
  }

  void _paintGlare(Canvas canvas) {
    if (theme.glareOpacity <= 0) return;
    canvas.save();
    // Clipped to the crystal. The case used to cover the corner of this oval
    // that reaches past 10 o'clock; on a bare background it read as a smudge
    // sitting outside the dial.
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: _c, radius: Dial.plateRadius)),
    );
    canvas.translate(150, 128);
    canvas.rotate(-24 * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 252, height: 156),
      _p
        ..shader = ui.Gradient.linear(
          const Offset(-126, -78),
          const Offset(50, 78),
          [
            Colors.white.withValues(alpha: theme.glareOpacity),
            Colors.white.withValues(alpha: 0),
          ],
        ),
    );
    canvas.restore();
  }

  void _tick(Canvas canvas, double r1, double r2, double deg, Paint paint) {
    final a = polar(Dial.centre, Dial.centre, r1, deg);
    final b = polar(Dial.centre, Dial.centre, r2, deg);
    canvas.drawLine(Offset(a.dx, a.dy), Offset(b.dx, b.dy), paint);
  }

  void _text(Canvas canvas, String s, Offset centre, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre.translate(-tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(ChronoPainter old) =>
      old.elapsed != elapsed ||
      old.splitDeg != splitDeg ||
      old.splitState != splitState ||
      old.theme != theme ||
      old.reduceMotion != reduceMotion ||
      old.smearFromDeg != smearFromDeg ||
      old.splitFade != splitFade;
}
