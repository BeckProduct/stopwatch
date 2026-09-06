import 'dart:math' as math;

/// Dial geometry, in the spec's painter units: a 314-unit dial plate centred
/// at (200, 200), inside a square box just wide enough to hold its rim.
///
/// Pure functions of elapsed time. Nothing here reads a clock, so every value
/// rendered in one frame can be derived from a single elapsed reading.
class Dial {
  const Dial._();

  static const double centre = 200;
  static const double plateRadius = 157;

  /// The rim. With the case gone nothing else frames the dial, so this ring
  /// carries the weight the bezel used to and is drawn, not implied.
  static const double rimInner = 157;
  static const double rimOuter = 164;

  static const double rFifthOuter = 156;
  static const double rFifthInner = 152;
  static const double rMinOuter = 150;
  static const double rMinInner = 145;
  static const double rMin5Inner = 140;
  static const double rIndexOuter = 134;
  static const double rIndexInner = 112;

  /// The painter's own coordinate box, before scaling to the widget. Two
  /// units of air outside the rim so the outer hairline is not clipped.
  static const double boxLeft = 34;
  static const double boxTop = 34;
  static const double boxWidth = 332;
  static const double boxHeight = 332;

  /// Sub-register centres.
  static const minutesCentre = (dx: 130.0, dy: 200.0);
  static const hoursCentre = (dx: 270.0, dy: 200.0);
  static const tenthsCentre = (dx: 200.0, dy: 270.0);
  static const double registerRadius = 42;
}

/// Deadbeat quantisation for Reduce Motion: 200 ms steps, five beats a second.
///
/// Every hand that reads the sweep angle goes through this one function. Two
/// call sites quantising separately can land either side of a boundary and
/// split the hands by 1.2 degrees for a frame.
Duration quantise(Duration elapsed, {required bool reduceMotion}) {
  if (!reduceMotion) return elapsed;
  final ms = elapsed.inMilliseconds ~/ 200 * 200;
  return Duration(milliseconds: ms);
}

/// The sweep hand's angle: one revolution a minute.
double sweepDegFor(Duration elapsed) =>
    (elapsed.inMilliseconds % 60000) / 60000 * 360;

/// The minutes register: one revolution per 30 minutes.
double minuteDegFor(Duration elapsed) =>
    (elapsed.inMilliseconds % 1800000) / 1800000 * 360;

/// The hours register: one revolution per 12 hours.
double hourDegFor(Duration elapsed) =>
    (elapsed.inMilliseconds % 43200000) / 43200000 * 360;

/// The tenths register: one revolution a second, ten divisions.
///
/// The fastest hand on the dial, so it is the one Reduce Motion has to reach:
/// callers pass elapsed through [quantise] exactly as the sweep hand does.
double tenthDegFor(Duration elapsed) =>
    (elapsed.inMilliseconds % 1000) / 1000 * 360;

/// The shortest forward rotation from [fromDeg] to [toDeg], in [0, 360).
///
/// Dart's `%` on a negative left operand returns a negative, and a split hand
/// that catches up anticlockwise is running time backwards.
double forwardDelta(double fromDeg, double toDeg) =>
    ((toDeg - fromDeg) % 360 + 360) % 360;

/// The sector a hand crossed between two frames, or null when it is too narrow
/// to read as motion rather than as a smudge on the dial.
double? smearSweep(double fromDeg, double toDeg) {
  final swept = forwardDelta(fromDeg, toDeg);
  return swept > 6 ? swept : null;
}

/// Cartesian point at [deg] clockwise from 12 o'clock, [r] from ([cx], [cy]).
({double dx, double dy}) polar(double cx, double cy, double r, double deg) {
  final a = (deg - 90) * math.pi / 180;
  return (dx: cx + r * math.cos(a), dy: cy + r * math.sin(a));
}

/// The main readout: `mm:ss.cc`, or `h:mm:ss.t` past an hour.
String formatElapsed(Duration d) {
  final ms = d.inMilliseconds;
  final hours = ms ~/ 3600000;
  final minutes = ms ~/ 60000 % 60;
  final seconds = ms ~/ 1000 % 60;
  if (hours > 0) {
    final tenths = ms ~/ 100 % 10;
    return '$hours:${_p2(minutes)}:${_p2(seconds)}.$tenths';
  }
  return '${_p2(minutes)}:${_p2(seconds)}.${_p2(ms ~/ 10 % 100)}';
}

/// A lap's own duration, signed positive: `+ss.cc`, or `+mm:ss.cc` past a
/// minute.
String formatDelta(Duration d) {
  final ms = d.inMilliseconds;
  final minutes = ms ~/ 60000;
  final seconds = ms ~/ 1000 % 60;
  final hundredths = _p2(ms ~/ 10 % 100);
  if (minutes > 0) {
    return '+${_p2(minutes)}:${_p2(seconds)}.$hundredths';
  }
  return '+${_p2(seconds)}.$hundredths';
}

String _p2(int n) => n.toString().padLeft(2, '0');
