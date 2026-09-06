import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'chrono_geometry.dart';
import 'monotonic_clock.dart';

/// Where the split hand is in its cycle.
enum SplitState {
  /// Riding with the sweep hand.
  joined,

  /// Clamped by the pincers, held at the elapsed value it was frozen at.
  frozen,

  /// Released, whipping around to rejoin the sweep hand.
  catchingUp,
}

/// The split-seconds hand's mechanism.
///
/// Not a tween. The pincers clamp in zero milliseconds; on release the roller
/// falls down the heart cam and slams the hand at the sweep hand, overshooting
/// and ringing down onto it.
///
/// The target is **live**. The sweep hand runs on through the whip, so the
/// remaining delta is recomputed every frame against the current elapsed value.
/// Precomputing `toDeg` at release lands the hand roughly 1.4 degrees short and
/// snaps it straight on the final frame.
///
/// Holds no widget types: driveable from a test with an injected
/// [MonotonicClock] and no pumping.
class RattrapanteController extends ChangeNotifier {
  RattrapanteController({required this.clock});

  static const double overshootDeg = 3.2;
  static const int settleMs = 90;
  static const Cubic easeWhip = Cubic(0.20, 0.90, 0.35, 1.00);

  /// Reduce Motion replaces the whip with a cross-fade of the same total
  /// length. It removes the travel, never the feedback.
  static const int reducedWhipMs = 100;
  static const int reducedSettleMs = 100;

  /// Injected so a test can step the mechanism by hand.
  final MonotonicClock clock;

  SplitState _state = SplitState.joined;
  SplitState get state => _state;

  bool get isCatchingUp => _state == SplitState.catchingUp;

  /// The elapsed value the hand is held at. Meaningless while [joined].
  Duration _frozenElapsed = Duration.zero;
  Duration get frozenElapsed => _frozenElapsed;

  bool _reduceMotion = false;

  // Captured once, at the moment of release.
  Duration _releasedAt = Duration.zero;
  double _fromDeg = 0;
  int _revs = 0;
  int _whipMs = 150;
  int _settle = settleMs;
  bool _landed = false;

  /// Where the hand was drawn on the previous frame [advance] saw.
  double? _previousDeg;

  /// The angle to smear *from* this frame: the previous frame's, never this
  /// one's. Null when there is nothing to smear -- the first frame after a
  /// release, a cross-fade, or a hand that has landed.
  double? _smearFrom;
  double? get smearFrom => _smearFrom;

  /// The split hand's opacity.
  ///
  /// 1 everywhere except the Reduce Motion cross-fade, which has no travel to
  /// show and dissolves instead: out over the first half while the hand is
  /// still held, back in over the second at the live angle.
  double get splitOpacity {
    if (!_reduceMotion || _state != SplitState.catchingUp) return 1;
    final t = (clock.now - _releasedAt).inMilliseconds;
    final half = _whipMs;
    if (t < half) return (1 - t / half).clamp(0.0, 1.0);
    return ((t - half) / _settle).clamp(0.0, 1.0);
  }

  /// Clamps the hand where it stands. Zero duration: no tween, no curve. The
  /// dead stop is the effect.
  void freeze(Duration elapsed) {
    _frozenElapsed = elapsed;
    _state = SplitState.frozen;
    _previousDeg = null;
    _smearFrom = null;
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  /// Releases the pincers. The hand whips forward onto the sweep hand.
  void release({required Duration elapsed, required bool reduceMotion}) {
    _reduceMotion = reduceMotion;
    _releasedAt = clock.now;
    _fromDeg = sweepDegFor(
      quantise(_frozenElapsed, reduceMotion: reduceMotion),
    );
    final behind = elapsed - _frozenElapsed;
    // Capped at two turns: a 40-minute split would spin 40 times in 240 ms and
    // strobe into noise. Cosmetic only -- the hand still lands on the live
    // angle.
    _revs = reduceMotion ? 0 : math.min(2, behind.inMilliseconds ~/ 60000);
    _whipMs = reduceMotion ? reducedWhipMs : 150 + 45 * _revs;
    _settle = reduceMotion ? reducedSettleMs : settleMs;
    _landed = false;
    _previousDeg = null;
    _smearFrom = null;
    _state = SplitState.catchingUp;
    HapticFeedback.heavyImpact();
    notifyListeners();
  }

  /// Drops the hand back onto the sweep hand with no animation. Used when the
  /// app is resumed mid-catch-up: the whip happened while nobody was watching.
  void cancelToJoined() {
    if (_state == SplitState.joined) return;
    _state = SplitState.joined;
    _previousDeg = null;
    _smearFrom = null;
    notifyListeners();
  }

  /// Back to zero. Nothing but this and the whip's own completion clears
  /// [SplitState.catchingUp].
  void reset() {
    _state = SplitState.joined;
    _frozenElapsed = Duration.zero;
    _previousDeg = null;
    _smearFrom = null;
    notifyListeners();
  }

  /// Advances the mechanism by one frame. Called from the ticker.
  ///
  /// Everything that changes lives here and nowhere else: the landing haptic,
  /// the roll of the smear's start angle, and the transition back to joined.
  /// Keeping it out of [angleAt] is what lets the painter read an angle during
  /// build without firing feedback or rebuilding mid-build.
  void advance(Duration elapsed, {required bool reduceMotion}) {
    if (_state != SplitState.catchingUp) {
      _previousDeg = null;
      _smearFrom = null;
      return;
    }

    final t = (clock.now - _releasedAt).inMilliseconds;

    // The roller hits the cam at the end of the whip.
    if (!_landed && t >= _whipMs) {
      _landed = true;
      HapticFeedback.selectionClick();
    }

    final deg = angleAt(elapsed, reduceMotion: reduceMotion);
    // Last frame's angle, so the sector between the two has width. Setting it
    // from this frame's angle is a sector of zero and draws nothing at all.
    _smearFrom = _reduceMotion ? null : _previousDeg;
    _previousDeg = deg;

    if (t >= _whipMs + _settle) {
      _state = SplitState.joined;
      _previousDeg = null;
      _smearFrom = null;
      // The transition happens here rather than on a press, so it has to
      // announce itself or the Split control keeps reporting busy to
      // VoiceOver. Safe to do synchronously: this is the ticker, not build.
      notifyListeners();
    }
  }

  /// The split hand's angle for a frame whose elapsed reading is [elapsed].
  ///
  /// Pure: reading it changes nothing and fires nothing, so the painter can
  /// call it during build. Call it with the same elapsed value the sweep hand
  /// is drawn from, or the two hands can land in different Reduce Motion
  /// buckets and break the hairline they are specified around.
  double angleAt(Duration elapsed, {required bool reduceMotion}) {
    final live = sweepDegFor(quantise(elapsed, reduceMotion: reduceMotion));
    switch (_state) {
      case SplitState.joined:
        return live;
      case SplitState.frozen:
        return sweepDegFor(
          quantise(_frozenElapsed, reduceMotion: reduceMotion),
        );
      case SplitState.catchingUp:
        return _whipAngle(live);
    }
  }

  double _whipAngle(double live) {
    final t = (clock.now - _releasedAt).inMilliseconds;

    if (t >= _whipMs + _settle) return live;

    if (_reduceMotion) {
      // No travel under Reduce Motion: the hand is either held or joined, and
      // the two dissolve into each other. Both haptics still fire.
      return t < _whipMs ? _fromDeg : live;
    }

    // Recomputed against the LIVE angle every frame, never a captured target.
    final remaining = forwardDelta(_fromDeg, live) + 360 * _revs;

    if (t < _whipMs) {
      final p = easeWhip.transform(t / _whipMs);
      return _fromDeg + (remaining + overshootDeg) * p;
    }
    // Ring-down: the overshoot decays onto the live angle, which is itself
    // still moving.
    final settle = ((t - _whipMs) / _settle).clamp(0.0, 1.0);
    return live + overshootDeg * (1 - Curves.easeOut.transform(settle));
  }
}
