import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/monotonic_clock.dart';

import 'support/fake_monotonic_clock.dart';

void main() {
  group('SystemMonotonicClock', () {
    test('never goes backwards', () {
      final clock = SystemMonotonicClock();

      var previous = clock.now;
      for (var i = 0; i < 1000; i++) {
        final current = clock.now;
        expect(current, greaterThanOrEqualTo(previous));
        previous = current;
      }
    });

    test('reads from its own origin, not the wall clock', () {
      // A DateTime-derived implementation would return time since the Unix
      // epoch here — decades, not microseconds. This is the cheap structural
      // guard on the app's load-bearing correctness rule.
      final clock = SystemMonotonicClock();

      expect(clock.now, lessThan(const Duration(seconds: 1)));
    });

    test('two clocks advance independently of each other', () {
      final first = SystemMonotonicClock();
      for (var i = 0; i < 1000; i++) {
        first.now;
      }
      final second = SystemMonotonicClock();

      expect(second.now, lessThanOrEqualTo(first.now));
    });
  });

  group('FakeMonotonicClock', () {
    test('advances by exactly the amount given', () {
      final clock = FakeMonotonicClock();

      final before = clock.now;
      clock.advance(const Duration(milliseconds: 1500));

      expect(clock.now - before, const Duration(milliseconds: 1500));
    });

    test('does not advance on its own', () {
      final clock = FakeMonotonicClock();

      expect(clock.now, clock.now);
    });

    test('refuses to go backwards', () {
      final clock = FakeMonotonicClock();

      expect(
        () => clock.advance(const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });
  });
}
