import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/chrono_geometry.dart';
import 'package:stopwatch/rattrapante.dart';

import 'support/fake_monotonic_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMonotonicClock clock;
  late RattrapanteController split;

  /// A monotonic clock reads from an arbitrary origin, so elapsed time is the
  /// difference from where it stood when the run began -- never the raw
  /// reading.
  late Duration origin;

  setUp(() {
    clock = FakeMonotonicClock();
    origin = clock.now;
    split = RattrapanteController(clock: clock);
  });

  tearDown(() => split.dispose());

  /// Elapsed on the chronograph. The controller's own clock is the same one, so
  /// advancing it advances both the animation and the sweep hand -- which is
  /// the whole point: the target moves while the whip is in flight.
  Duration elapsed() => clock.now - origin;

  double angle() => split.angleAt(elapsed(), reduceMotion: false);

  /// One frame of the ticker: advance the mechanism, then read what the
  /// painter would read.
  double frame({bool reduceMotion = false}) {
    split.advance(elapsed(), reduceMotion: reduceMotion);
    return split.angleAt(elapsed(), reduceMotion: reduceMotion);
  }

  void freezeAt(Duration at) {
    clock.advance(at - elapsed());
    split.freeze(elapsed());
  }

  group('the freeze', () {
    test('holds the hand at the frozen value while the sweep hand runs on', () {
      freezeAt(const Duration(seconds: 10));
      final held = angle();

      clock.advance(const Duration(seconds: 5));

      expect(split.state, SplitState.frozen);
      expect(angle(), held, reason: 'a clamped hand does not move');
      expect(held, closeTo(sweepDegFor(const Duration(seconds: 10)), 1e-9));
    });

    test('is instant: no tween, no curve', () {
      freezeAt(const Duration(seconds: 10));

      // One microsecond after the clamp the hand is already at rest, not
      // easing towards it.
      clock.advance(const Duration(microseconds: 1));
      expect(angle(), closeTo(sweepDegFor(const Duration(seconds: 10)), 1e-9));
    });
  });

  group('the catch-up', () {
    test('starts at the frozen angle and ends on the live one', () {
      freezeAt(const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 8));
      final fromDeg = sweepDegFor(const Duration(seconds: 10));

      split.release(elapsed: elapsed(), reduceMotion: false);
      expect(angle(), closeTo(fromDeg, 1e-9));

      // 150 ms whip (under a minute behind) plus a 90 ms ring-down.
      clock.advance(const Duration(milliseconds: 240));

      expect(frame(), closeTo(sweepDegFor(elapsed()), 0.001));
      expect(split.state, SplitState.joined);
    });

    test('overshoots the cam and rings down onto the hand', () {
      freezeAt(const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 8));
      split.release(elapsed: elapsed(), reduceMotion: false);

      // At the end of the whip the roller has thrown the hand past its mark.
      clock.advance(const Duration(milliseconds: 150));
      final atCam = angle();
      expect(
        forwardDelta(sweepDegFor(elapsed()), atCam),
        closeTo(RattrapanteController.overshootDeg, 0.05),
      );

      // Halfway through the settle it has come back most of the way.
      clock.advance(const Duration(milliseconds: 45));
      final settling = forwardDelta(sweepDegFor(elapsed()), angle());
      expect(settling, lessThan(RattrapanteController.overshootDeg));
      expect(settling, greaterThan(0));
    });

    test('never runs backwards, however far behind the hand is', () {
      freezeAt(const Duration(seconds: 50));
      // 70 s later the sweep hand is at a SMALLER angle than the frozen one.
      clock.advance(const Duration(seconds: 70));
      final fromDeg = sweepDegFor(const Duration(seconds: 50));
      expect(sweepDegFor(elapsed()), lessThan(fromDeg));

      split.release(elapsed: elapsed(), reduceMotion: false);
      var previous = angle();
      for (var i = 0; i < 12; i++) {
        clock.advance(const Duration(milliseconds: 16));
        final now = angle();
        // Forward means the shortest step from the previous angle is small and
        // positive, never a jump back round the dial.
        expect(forwardDelta(previous, now), lessThan(180));
        previous = now;
      }
    });

    test('caps at two revolutions but still lands exactly', () {
      freezeAt(const Duration(seconds: 5));
      clock.advance(const Duration(minutes: 40)); // 40 turns behind
      split.release(elapsed: elapsed(), reduceMotion: false);

      // Two revs -> a 240 ms whip, plus the 90 ms settle.
      clock.advance(const Duration(milliseconds: 330));

      expect(frame(), closeTo(sweepDegFor(elapsed()), 0.001));
      expect(split.state, SplitState.joined);
    });

    test('leaves catchingUp exactly once, and notifies when it does', () {
      var notifications = 0;
      split.addListener(() => notifications++);

      freezeAt(const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 3));
      split.release(elapsed: elapsed(), reduceMotion: false);
      final afterRelease = notifications;

      final states = <SplitState>[];
      for (var i = 0; i < 30; i++) {
        clock.advance(const Duration(milliseconds: 16));
        frame();
        states.add(split.state);
      }

      expect(states.last, SplitState.joined);
      expect(
        states.where((s) => s == SplitState.catchingUp).length,
        states.indexOf(SplitState.joined),
        reason: 'it goes catchingUp -> joined once, and does not go back',
      );
      // The transition happens in the frame loop, not on a press. It is
      // fired from the ticker rather than a press. It must still arrive, or
      // the Split control keeps reporting busy to VoiceOver.
      expect(notifications, greaterThan(afterRelease));
    });

    // The obvious wrong implementation captures toDeg at release and tweens to
    // it. Hold the animation clock still and vary ONLY the live elapsed value:
    // a precomputed target gives the same angle for both, a live one cannot.
    test('recomputes against the live sweep angle every frame', () {
      freezeAt(const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 3));
      split.release(elapsed: elapsed(), reduceMotion: false);

      // 75 ms into a 150 ms whip. Both reads happen at this same instant, so
      // the animation's own progress is identical between them.
      clock.advance(const Duration(milliseconds: 75));
      final againstNow = split.angleAt(elapsed(), reduceMotion: false);
      final againstLater = split.angleAt(
        elapsed() + const Duration(seconds: 20),
        reduceMotion: false,
      );

      expect(
        againstLater,
        isNot(closeTo(againstNow, 0.01)),
        reason: 'a target captured at release would ignore the second value',
      );
    });
  });

  group('the smear', () {
    test('measures the sector actually crossed since the previous frame', () {
      freezeAt(const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 8));
      split.release(elapsed: elapsed(), reduceMotion: false);

      // Nothing to smear from on the first frame after release.
      clock.advance(const Duration(milliseconds: 16));
      frame();
      expect(split.smearFrom, isNull);

      // From the second frame on it is the previous frame's angle, not this
      // one's -- a sector of zero width draws nothing.
      final swept = <double>[];
      for (var i = 0; i < 8; i++) {
        clock.advance(const Duration(milliseconds: 16));
        final before = split.smearFrom;
        final now = frame();
        if (split.smearFrom != null) {
          expect(split.smearFrom, isNot(closeTo(now, 1e-9)));
          swept.add(forwardDelta(split.smearFrom!, now));
        }
        expect(before, isNot(same(now)));
      }

      expect(swept, isNotEmpty);
      expect(
        swept.where((d) => d > 6),
        isNotEmpty,
        reason: 'the whip crosses far more than 6 degrees a frame',
      );
    });

    test('is not drawn once the hand has joined', () {
      freezeAt(const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 3));
      split.release(elapsed: elapsed(), reduceMotion: false);
      clock.advance(const Duration(milliseconds: 300));
      frame();

      expect(split.state, SplitState.joined);
      expect(split.smearFrom, isNull);
    });

    test('a sector under six degrees is not worth drawing', () {
      expect(smearSweep(10, 12), isNull);
      expect(smearSweep(10, 40), closeTo(30, 1e-9));
      // Across the top of the dial, forward, never the short way back.
      expect(smearSweep(350, 20), closeTo(30, 1e-9));
    });
  });

  group('the split hand opacity', () {
    test('is fully opaque except during a Reduce Motion cross-fade', () {
      expect(split.splitOpacity, 1.0);

      freezeAt(const Duration(seconds: 10));
      expect(split.splitOpacity, 1.0);

      clock.advance(const Duration(seconds: 3));
      split.release(elapsed: elapsed(), reduceMotion: false);
      clock.advance(const Duration(milliseconds: 75));
      expect(split.splitOpacity, 1.0, reason: 'the whip is travel, not a fade');
    });

    test('dissolves out and back in across the cross-fade', () {
      freezeAt(const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 3));
      split.release(elapsed: elapsed(), reduceMotion: true);

      expect(split.splitOpacity, closeTo(1.0, 1e-9));

      // Out over the first 100 ms, while the hand is still held.
      clock.advance(const Duration(milliseconds: 50));
      final half = split.splitOpacity;
      expect(half, lessThan(1.0));
      expect(half, greaterThan(0.0));

      clock.advance(const Duration(milliseconds: 50));
      expect(split.splitOpacity, closeTo(0.0, 0.01));

      // Back in over the second 100 ms, now at the live angle.
      clock.advance(const Duration(milliseconds: 50));
      final backHalf = split.splitOpacity;
      expect(backHalf, greaterThan(0.0));
      expect(backHalf, lessThan(1.0));

      clock.advance(const Duration(milliseconds: 60));
      frame(reduceMotion: true);
      expect(split.state, SplitState.joined);
      expect(split.splitOpacity, 1.0);
    });
  });

  group('reading the angle is safe from a build', () {
    test('angleAt changes nothing and fires nothing', () {
      freezeAt(const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 3));
      split.release(elapsed: elapsed(), reduceMotion: false);

      var notifications = 0;
      split.addListener(() => notifications++);

      // Well past the end of the whip: if reading advanced the mechanism, this
      // would land it and notify from inside what is a build in production.
      clock.advance(const Duration(milliseconds: 400));
      final first = split.angleAt(elapsed(), reduceMotion: false);
      final second = split.angleAt(elapsed(), reduceMotion: false);

      expect(first, second);
      expect(split.state, SplitState.catchingUp);
      expect(split.smearFrom, isNull);
      expect(notifications, 0);

      // The ticker is what advances it.
      split.advance(elapsed(), reduceMotion: false);
      expect(split.state, SplitState.joined);
      expect(notifications, 1);
    });
  });

  group('Reduce Motion', () {
    test('cross-fades instead of whipping, and still lands joined', () {
      freezeAt(const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 8));
      split.release(elapsed: elapsed(), reduceMotion: true);

      // No travel: the hand is held, then it is home.
      clock.advance(const Duration(milliseconds: 50));
      expect(angle(), closeTo(sweepDegFor(const Duration(seconds: 10)), 1e-9));
      frame(reduceMotion: true);
      expect(split.smearFrom, isNull, reason: 'no smear under RM');

      clock.advance(const Duration(milliseconds: 200));
      expect(angle(), closeTo(sweepDegFor(elapsed()), 0.001));
      frame(reduceMotion: true);
      expect(split.state, SplitState.joined);
    });

    test('both hands quantise through one function', () {
      freezeAt(const Duration(milliseconds: 10350));
      // 10350 ms falls in the 10200 ms bucket, not the 10400 one.
      expect(
        split.angleAt(clock.now, reduceMotion: true),
        closeTo(sweepDegFor(const Duration(milliseconds: 10200)), 1e-9),
      );
    });
  });

  test('resume mid-catch-up drops the hand home with no animation', () {
    freezeAt(const Duration(seconds: 10));
    clock.advance(const Duration(seconds: 3));
    split.release(elapsed: elapsed(), reduceMotion: false);

    split.cancelToJoined();

    expect(split.state, SplitState.joined);
    expect(angle(), closeTo(sweepDegFor(elapsed()), 1e-9));
  });
}
