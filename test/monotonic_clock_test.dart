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
      // Burn measurable time so the two origins cannot coincide.
      final spin = Stopwatch()..start();
      while (spin.elapsedMicroseconds < 2000) {}
      final second = SystemMonotonicClock();

      // Not the guard, whatever an earlier comment here claimed. Arguments
      // evaluate left to right, so `second.now` is read before `first.now`;
      // on a shared source the later read is the larger one and strict-less
      // passes. It fails only when two adjacent reads happen to land in the
      // same microsecond tick -- 153 catches in 200 runs of the shared-source
      // mutation on this machine. That is clock resolution, not a test.
      expect(second.now, lessThan(first.now));

      // This is the guard. The gap between the two readings is the difference
      // in their origins, so it stays positive however the reads fall either
      // side of it. A shared source reads one number twice and has no gap:
      // 200 catches in 200 runs of the same mutation.
      final gapBefore = first.now - second.now;
      while (spin.elapsedMicroseconds < 8000) {}
      final gapAfter = first.now - second.now;

      expect(gapAfter, greaterThan(Duration.zero));
      expect(
        (gapAfter - gapBefore).abs(),
        lessThan(const Duration(milliseconds: 50)),
        // Guards rate, not origin, so it catches none of the shared-source
        // mutation -- 0 in 200. Left in place because it is the only thing
        // asserting the two clocks do not drift apart once separated.
        reason: 'both clocks run at the same rate, only from different origins',
      );
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

    test('advances on every read when given a tick', () {
      final clock = FakeMonotonicClock(
        tickPerRead: const Duration(milliseconds: 10),
      );

      final first = clock.now;
      final second = clock.now;

      expect(second - first, const Duration(milliseconds: 10));
    });

    test('a tick does not stop it being advanced by hand', () {
      final clock = FakeMonotonicClock(
        tickPerRead: const Duration(milliseconds: 10),
      );

      final before = clock.now; // reading 1, clock now +10ms
      clock.advance(const Duration(seconds: 1));

      expect(clock.now - before, const Duration(milliseconds: 1010));
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
