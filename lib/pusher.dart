import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chrono_theme.dart';

/// A chronograph pusher, below the dial rather than on a case flank.
///
/// Still a turned steel object with real travel: it sits in a boss it can be
/// driven into, so a press reads as a mechanism being worked and not as a
/// rectangle changing colour. Enablement lives on the semantics node -- a
/// pusher that is refused by the mechanism does not dim.
class Pusher extends StatelessWidget {
  const Pusher({
    super.key,
    required this.travel,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.isCrown = false,
  });

  /// Depression, 0..1 of full travel. Driven by the screen's controllers so
  /// the head is still rising while the next press is possible.
  final Animation<double> travel;
  final String label;
  final bool enabled;
  final bool isCrown;
  final VoidCallback onTap;

  static const double headWidth = 60;
  static const double crownWidth = 68;
  static const double headHeight = 46;

  /// Slop around the painted head, so the finger is not asked to be precise.
  static const double _slop = 9;

  static double get boxHeight => headHeight + _slop * 2;

  @override
  Widget build(BuildContext context) {
    final chrono = ChronoTheme.of(context);
    final width = isCrown ? crownWidth : headWidth;
    return Semantics(
      button: true,
      enabled: enabled,
      // Busy stays enabled: the press is swallowed, not refused.
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width + _slop * 2,
          height: boxHeight,
          child: Center(
            child: AnimatedBuilder(
              animation: travel,
              builder: (context, _) => CustomPaint(
                size: Size(width, headHeight),
                painter: PusherPainter(
                  theme: chrono,
                  travel: travel.value,
                  isCrown: isCrown,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The head and the boss it rides in. A pure function of its inputs.
class PusherPainter extends CustomPainter {
  const PusherPainter({
    required this.theme,
    required this.travel,
    required this.isCrown,
  });

  final ChronoTheme theme;
  final double travel;
  final bool isCrown;

  /// Logical pixels of head movement at full depression.
  static const double fullTravel = 5;

  /// The fixed collar the head disappears into.
  static const double _bossHeight = 11;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final headHeight = h - _bossHeight;
    final dy = travel.clamp(0.0, 1.0) * fullTravel;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.09, h - _bossHeight, w * 0.82, _bossHeight),
        const Radius.circular(3),
      ),
      _p
        ..shader = ui.Gradient.linear(
          Offset(w * 0.09, 0),
          Offset(w * 0.91, 0),
          [theme.steel3, theme.steel1, theme.steel3],
          const [0, 0.4, 1],
        ),
    );

    final head = Rect.fromLTWH(0, dy, w, headHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(head, Radius.circular(headHeight * 0.34)),
      _p
        ..shader = ui.Gradient.linear(
          head.topLeft,
          head.topRight,
          [theme.steel3, theme.steel0, theme.steel2, theme.steel3],
          const [0, 0.32, 0.68, 1],
        ),
    );

    // The lit top face. It goes out as the head is driven down, which is what
    // reads as travel at this size -- 5 px of movement on its own does not.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.13, dy + 3, w * 0.74, 5),
        const Radius.circular(2.5),
      ),
      _p..color = theme.steel0.withValues(alpha: 0.8 * (1 - travel * 0.75)),
    );

    // Knurling.
    final knurl = _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = theme.steel3.withValues(alpha: 0.45);
    for (var i = 1; i < 8; i++) {
      final x = w * i / 8;
      canvas.drawLine(
        Offset(x, dy + headHeight * 0.34),
        Offset(x, dy + headHeight * 0.82),
        knurl,
      );
    }

    if (isCrown) {
      canvas.drawCircle(
        Offset(w / 2, dy + headHeight / 2),
        5.4,
        _p..color = theme.accent1,
      );
    }
  }

  Paint get _p => Paint()..isAntiAlias = true;

  @override
  bool shouldRepaint(PusherPainter old) =>
      old.travel != travel || old.theme != theme || old.isCrown != isCrown;
}
