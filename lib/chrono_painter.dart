import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chrono_geometry.dart';
import 'chrono_theme.dart';
import 'rattrapante.dart';

/// Everything inside the crystal, plus the case and the pushers around it.
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
    required this.lapCount,
    required this.reduceMotion,
    required this.pusherTravel,
    required this.smearFromDeg,
    required this.splitFade,
  });

  final ChronoTheme theme;
  final Duration elapsed;
  final double splitDeg;
  final SplitState splitState;
  final int lapCount;
  final bool reduceMotion;

  /// Depression of each pusher, 0..1 of full 3-unit travel.
  final ({double start, double crown, double reset}) pusherTravel;

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

    _paintLugs(canvas);
    _paintPushers(canvas);
    _paintCase(canvas);
    _paintBezel(canvas);
    _paintDialPlate(canvas);
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

  void _paintLugs(Canvas canvas) {
    final steel = _p
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(162, 400),
        [theme.steel0, theme.steel1, theme.steel2, theme.steel3],
        const [0, 0.42, 0.72, 1],
      );
    for (final l in const [
      [112.0, 76.0, 88.0, -16.0],
      [288.0, 76.0, 312.0, -16.0],
      [112.0, 324.0, 88.0, 416.0],
      [288.0, 324.0, 312.0, 416.0],
    ]) {
      canvas.drawLine(Offset(l[0], l[1]), Offset(l[2], l[3]), steel);
    }
  }

  /// Case controls at 60, 90 and 120 degrees. Travel is 3 dial units at full
  /// depression, scaled by how far each pusher is pressed.
  void _paintPushers(Canvas canvas) {
    _pusher(canvas, 60, pusherTravel.start, 15, 26, false);
    _pusher(canvas, 120, pusherTravel.reset, 15, 26, false);
    _pusher(canvas, 90, pusherTravel.crown, 18, 30, true);
  }

  void _pusher(
    Canvas canvas,
    double deg,
    double travel,
    double halfWidth,
    double height,
    bool isCrown,
  ) {
    canvas.save();
    canvas.translate(Dial.centre, Dial.centre);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-Dial.centre, -Dial.centre);
    // Depression pushes the head towards the case: +y in this rotated frame.
    canvas.translate(0, travel * 3);

    final body = _p
      ..shader = ui.Gradient.linear(
        Offset(Dial.centre - halfWidth, 0),
        Offset(Dial.centre + halfWidth, 0),
        [theme.steel3, theme.steel0, theme.steel3],
        const [0, 0.35, 1],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(Dial.centre - halfWidth, -34, halfWidth * 2, height + 34),
        const Radius.circular(5),
      ),
      body,
    );
    if (isCrown) {
      canvas.drawCircle(
        const Offset(Dial.centre, -25),
        6.4,
        _p..color = theme.accent1,
      );
    }
    canvas.restore();
  }

  void _paintCase(Canvas canvas) {
    canvas.drawCircle(
      _c,
      Dial.caseRadius,
      _p
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(162, 400),
          [theme.steel0, theme.steel1, theme.steel2, theme.steel3],
          const [0, 0.42, 0.72, 1],
        ),
    );
    canvas.drawCircle(
      _c,
      188,
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = theme.steel3.withValues(alpha: 0.55),
    );
  }

  void _paintBezel(Canvas canvas) {
    canvas.drawCircle(
      _c,
      186,
      _p
        ..shader = ui.Gradient.radial(
          const Offset(0.34 * 372 + 14, 0.24 * 372 + 14),
          0.92 * 372,
          [theme.bez0, theme.bez1, theme.bez2],
          const [0, 0.6, 1],
        ),
    );

    // Tachymeter. Each value sits at the angle a lap of that speed takes.
    const values = [
      400, 300, 240, 200, 180, 160, 150, 140, 130, 125, 120, 115, 110, //
      105, 100, 95, 90, 85, 80, 75, 70, 65, 60,
    ];
    final tick = _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = theme.bezText.withValues(alpha: 0.75);
    for (final v in values) {
      final deg = (3600 / v) / 60 * 360;
      final a = polar(Dial.centre, Dial.centre, 162, deg);
      final b = polar(Dial.centre, Dial.centre, 168, deg);
      canvas.drawLine(Offset(a.dx, a.dy), Offset(b.dx, b.dy), tick);
      final p = polar(Dial.centre, Dial.centre, Dial.rTachy, deg);
      _rotatedText(
        canvas,
        '$v',
        Offset(p.dx, p.dy),
        deg,
        TextStyle(
          fontSize: 9.4,
          fontWeight: FontWeight.w600,
          color: theme.bezText,
          fontFamily: 'Archivo',
        ),
      );
    }
    _text(
      canvas,
      'TACHYMETRE',
      const Offset(Dial.centre, 176),
      TextStyle(
        fontSize: 7.2,
        letterSpacing: 3.2,
        fontWeight: FontWeight.w600,
        color: theme.bezText.withValues(alpha: 0.8),
        fontFamily: 'Archivo',
      ),
    );
    canvas.drawCircle(
      _c,
      158,
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Colors.black.withValues(alpha: 0.55),
    );
  }

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
    _text(
      canvas,
      'SWISS MADE',
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
    _register(
      canvas,
      Offset(Dial.lapsCentre.dx, Dial.lapsCentre.dy),
      'LAP',
      lapDegFor(lapCount),
      12,
      4,
      const [(4, 120.0), (8, 240.0), (12, 0.0)],
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
    final sweptDeg = forwardDelta(from, splitDeg);
    if (sweptDeg <= 6) return;
    final path = Path()
      ..moveTo(Dial.centre, Dial.centre)
      ..arcTo(
        Rect.fromCircle(center: _c, radius: 200),
        (from - 90) * math.pi / 180,
        sweptDeg * math.pi / 180,
        false,
      )
      ..close();
    canvas.save();
    canvas.clipPath(path);
    canvas.drawCircle(_c, 200, _p..color = theme.rat1.withValues(alpha: 0.24));
    canvas.drawCircle(_c, 60, _p..blendMode = BlendMode.clear);
    canvas.restore();
  }

  void _paintSplitHand(Canvas canvas) {
    final opacity = splitFade.clamp(0.0, 1.0);
    if (opacity <= 0) return;
    canvas.save();
    canvas.translate(Dial.centre, Dial.centre);
    canvas.rotate(splitDeg * math.pi / 180);
    final shader = ui.Gradient.linear(
      const Offset(0, -154),
      const Offset(0, 34),
      [theme.rat0, theme.rat1],
    );
    final paint = _p
      ..shader = shader
      ..color = Colors.white.withValues(alpha: opacity);
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
    canvas.drawCircle(Offset.zero, 9.5, _p..color = theme.rat1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-2.6, 0, 5.2, 34),
        const Radius.circular(2.4),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(0, 32), 6.5, _p..color = theme.rat1);
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

  void _rotatedText(
    Canvas canvas,
    String s,
    Offset centre,
    double deg,
    TextStyle style,
  ) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(deg * math.pi / 180);
    _text(canvas, s, Offset.zero, style);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ChronoPainter old) =>
      old.elapsed != elapsed ||
      old.splitDeg != splitDeg ||
      old.splitState != splitState ||
      old.lapCount != lapCount ||
      old.theme != theme ||
      old.reduceMotion != reduceMotion ||
      old.pusherTravel != pusherTravel ||
      old.smearFromDeg != smearFromDeg ||
      old.splitFade != splitFade;
}
