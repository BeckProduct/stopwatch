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

    test('two splits at the same instant give a zero lap', () {
      engine.start();
      clock.advance(const Duration(seconds: 3));
      engine.split();
      engine.split();

      expect(engine.splits, const [Duration(seconds: 3), Duration(seconds: 3)]);
      expect(engine.lapTimes, const [Duration(seconds: 3), Duration.zero]);
    });

    test('split is rejected while idle', () {
      expect(engine.split, throwsStateError);
    });

    test('split is rejected while stopped', () {
      engine.start();
      engine.stop();

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
