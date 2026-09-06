import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/timing_engine.dart';

import 'support/fake_monotonic_clock.dart';

void main() {
  late FakeMonotonicClock clock;
  late TimingEngine engine;

  setUp(() {
    clock = FakeMonotonicClock();
    engine = TimingEngine(clock: clock);
  });

  group('state machine', () {
    test('begins idle, at zero, with no splits', () {
      expect(engine.state, TimingState.idle);
      expect(engine.elapsed, Duration.zero);
      expect(engine.splits, isEmpty);
      expect(engine.lapTimes, isEmpty);
    });

    test('idle time does not accumulate', () {
      clock.advance(const Duration(minutes: 5));

      expect(engine.elapsed, Duration.zero);
    });

    test('start moves idle to running', () {
      engine.start();

      expect(engine.state, TimingState.running);
      expect(engine.isRunning, isTrue);
    });

    test('stop moves running to stopped', () {
      engine.start();
      engine.stop();

      expect(engine.state, TimingState.stopped);
      expect(engine.isRunning, isFalse);
    });

    test('reset moves stopped to idle', () {
      engine.start();
      clock.advance(const Duration(seconds: 9));
      engine.stop();
      engine.reset();

      expect(engine.state, TimingState.idle);
      expect(engine.elapsed, Duration.zero);
    });

    test('start is rejected while running', () {
      engine.start();

      expect(engine.start, throwsStateError);
    });

    test('stop is rejected while idle', () {
      expect(engine.stop, throwsStateError);
    });

    test('stop is rejected while stopped', () {
      engine.start();
      engine.stop();

      expect(engine.stop, throwsStateError);
    });

    test('reset is rejected while idle', () {
      expect(engine.reset, throwsStateError);
    });

    test('reset is rejected while running', () {
      engine.start();

      expect(engine.reset, throwsStateError);
    });

    test('a rejected transition leaves the engine untouched', () {
      engine.start();
      clock.advance(const Duration(seconds: 4));
      final before = engine.elapsed;

      expect(engine.start, throwsStateError);
      expect(engine.reset, throwsStateError);

      expect(engine.state, TimingState.running);
      expect(engine.elapsed, before);
    });
  });

  group('elapsed', () {
    test('tracks the clock exactly while running', () {
      engine.start();
      clock.advance(const Duration(milliseconds: 1234));

      expect(engine.elapsed, const Duration(milliseconds: 1234));
    });

    test('is measured from start, not from the clock origin', () {
      clock.advance(const Duration(hours: 2));
      engine.start();
      clock.advance(const Duration(seconds: 3));

      expect(engine.elapsed, const Duration(seconds: 3));
    });

    test('freezes when stopped', () {
      engine.start();
      clock.advance(const Duration(seconds: 7));
      engine.stop();

      clock.advance(const Duration(minutes: 30));

      expect(engine.elapsed, const Duration(seconds: 7));
    });

    test('excludes the interval spent stopped when resumed', () {
      engine.start();
      clock.advance(const Duration(seconds: 1));
      engine.stop();
      clock.advance(const Duration(seconds: 5)); // must not be counted
      engine.start();
      clock.advance(const Duration(seconds: 2));

      expect(engine.elapsed, const Duration(seconds: 3));
    });

    test('accumulates across many stop/resume cycles', () {
      for (var i = 0; i < 4; i++) {
        engine.start();
        clock.advance(const Duration(milliseconds: 250));
        engine.stop();
        clock.advance(const Duration(seconds: 10)); // must not be counted
      }

      expect(engine.elapsed, const Duration(seconds: 1));
    });

    test('sub-millisecond advances are not rounded away', () {
      engine.start();
      for (var i = 0; i < 1000; i++) {
        clock.advance(const Duration(microseconds: 1));
      }

      expect(engine.elapsed, const Duration(milliseconds: 1));
    });

    test('restarts from zero after a reset', () {
      engine.start();
      clock.advance(const Duration(seconds: 20));
      engine.stop();
      engine.reset();

      engine.start();
      clock.advance(const Duration(seconds: 2));

      expect(engine.elapsed, const Duration(seconds: 2));
    });
  });

  group('splits', () {
    test('record cumulative elapsed, not lap time', () {
      engine.start();
      clock.advance(const Duration(seconds: 10));
      engine.split();
      clock.advance(const Duration(seconds: 15));
      engine.split();

      expect(engine.splits, const [
        Duration(seconds: 10),
        Duration(seconds: 25),
      ]);
    });

    test('split returns the mark it recorded', () {
      engine.start();
      clock.advance(const Duration(seconds: 8));

      expect(engine.split(), const Duration(seconds: 8));
    });

    test('lap times are the gaps between consecutive splits', () {
      engine.start();
      clock.advance(const Duration(seconds: 10));
      engine.split();
      clock.advance(const Duration(seconds: 15));
      engine.split();
      clock.advance(const Duration(seconds: 4));
      engine.split();

      expect(engine.lapTimes, const [
        Duration(seconds: 10),
        Duration(seconds: 15),
        Duration(seconds: 4),
      ]);
    });

    test('the first lap is measured from zero', () {
      engine.start();
      clock.advance(const Duration(seconds: 6));
      engine.split();

      expect(engine.lapTimes, const [Duration(seconds: 6)]);
    });

    test('lap times sum to the last split', () {
      engine.start();
      for (final gap in const [
        Duration(milliseconds: 1500),
        Duration(milliseconds: 2250),
        Duration(milliseconds: 999),
      ]) {
        clock.advance(gap);
        engine.split();
      }

      final total = engine.lapTimes.fold(
        Duration.zero,
        (sum, lap) => sum + lap,
      );
      expect(total, engine.splits.last);
    });

    test('a lap spanning a pause excludes the paused interval', () {
      engine.start();
      clock.advance(const Duration(seconds: 5));
      engine.split();

      clock.advance(const Duration(seconds: 5));
      engine.stop();
      clock.advance(const Duration(minutes: 2)); // must not be counted
      engine.start();
      clock.advance(const Duration(seconds: 5));
      engine.split();

      expect(engine.splits, const [
        Duration(seconds: 5),
        Duration(seconds: 15),
      ]);
      expect(engine.lapTimes, const [
        Duration(seconds: 5),
        Duration(seconds: 10),
      ]);
    });

    // Replaces 'two splits at the same instant give a zero lap'. A zero lap is
    // not a lap: nothing happened between the two marks, by definition of the
    // dial not having moved.
    test('a second split at the same instant records nothing', () {
      engine.start();
      clock.advance(const Duration(seconds: 3));
      engine.split();
      engine.split();

      expect(engine.splits, const [Duration(seconds: 3)]);
      expect(engine.lapTimes, const [Duration(seconds: 3)]);
    });

    test('the dropped repeat returns the mark that is still standing', () {
      engine.start();
      clock.advance(const Duration(seconds: 3));
      engine.split();

      // The split hand has to land somewhere whether or not a lap was written.
      expect(engine.split(), const Duration(seconds: 3));
    });

    test('a fast split is still a split: 20 ms is kept', () {
      // The floor is movement, not duration. Two marks a hundredth apart is
      // the case a rattrapante exists for, and rejecting it would be the bug.
      engine.start();
      clock.advance(const Duration(seconds: 3));
      engine.split();
      clock.advance(const Duration(milliseconds: 20));

      expect(engine.split(), const Duration(seconds: 3, milliseconds: 20));
      expect(engine.lapTimes, const [
        Duration(seconds: 3),
        Duration(milliseconds: 20),
      ]);
    });

    test('repeated splits while stopped record one lap, not one each', () {
      engine.start();
      clock.advance(
        const Duration(minutes: 12, seconds: 16, milliseconds: 600),
      );
      engine.stop();

      // The dial cannot move while stopped, so however long the user leans on
      // the crown there is exactly one final lap to record.
      for (var i = 0; i < 20; i++) {
        clock.advance(const Duration(milliseconds: 250));
        engine.split();
      }

      expect(engine.splits, const [
        Duration(minutes: 12, seconds: 16, milliseconds: 600),
      ]);
      expect(engine.lapTimes, const [
        Duration(minutes: 12, seconds: 16, milliseconds: 600),
      ]);
    });

    test('a repeat is dropped and the run then carries on recording', () {
      engine.start();
      clock.advance(const Duration(seconds: 5));
      engine.split();
      engine.split(); // dropped
      clock.advance(const Duration(seconds: 7));
      engine.split();

      expect(engine.splits, const [
        Duration(seconds: 5),
        Duration(seconds: 12),
      ]);
    });

    test('a mark restored on the dial cannot be recorded again', () {
      // A stopped run comes back with its last mark equal to the dial reading,
      // which is exactly the shape the guard has to catch across a relaunch.
      final restored = TimingEngine.restored(
        state: TimingState.stopped,
        elapsed: const Duration(seconds: 30),
        splits: const [Duration(seconds: 12), Duration(seconds: 30)],
        clock: clock,
      );

      expect(restored.split(), const Duration(seconds: 30));
      expect(restored.splits, const [
        Duration(seconds: 12),
        Duration(seconds: 30),
      ]);
    });

    test('split is rejected while idle', () {
      expect(engine.split, throwsStateError);
    });

    // Replaces 'split is rejected while stopped'. That assertion contradicted
    // the chronograph's own mechanism: a stopped watch holding a frozen split
    // hand is a real state, and recording a final lap after stopping is what
    // it is for. Only idle refuses now -- there is nothing yet to mark.
    test('split is accepted while stopped, and the lap equals the total', () {
      engine.start();
      clock.advance(const Duration(seconds: 4));
      engine.stop();

      expect(engine.split(), const Duration(seconds: 4));
      expect(engine.lapTimes, [const Duration(seconds: 4)]);
    });

    test('split is rejected while idle', () {
      expect(engine.split, throwsStateError);
    });

    test('reset discards the splits', () {
      engine.start();
      clock.advance(const Duration(seconds: 3));
      engine.split();
      engine.stop();
      engine.reset();

      expect(engine.splits, isEmpty);
      expect(engine.lapTimes, isEmpty);
    });

    test('splits cannot be mutated through the exposed list', () {
      engine.start();
      clock.advance(const Duration(seconds: 1));
      engine.split();

      expect(() => engine.splits.add(Duration.zero), throwsUnsupportedError);
      expect(() => engine.splits.clear(), throwsUnsupportedError);
    });

    test('the exposed list reflects splits recorded after it was read', () {
      engine.start();
      final view = engine.splits;
      clock.advance(const Duration(seconds: 1));
      engine.split();

      expect(view, hasLength(1));
    });
  });
}
