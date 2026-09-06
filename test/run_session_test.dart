import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/run_persistence.dart';
import 'package:stopwatch/run_session.dart';
import 'package:stopwatch/timing_engine.dart';

import 'support/clock_pair.dart';

void main() {
  late ClockPair clocks;
  late MemoryRunStore store;
  late RunSession session;

  setUp(() {
    clocks = ClockPair();
    store = MemoryRunStore();
    session = RunSession(
      store: store,
      monotonic: clocks.monotonic,
      wall: clocks.wall,
    );
  });

  /// A second session over the same store, as a relaunch would build.
  RunSession relaunch() =>
      RunSession(store: store, monotonic: clocks.monotonic, wall: clocks.wall);

  group('suspension, same process', () {
    test(
      'a monotonic clock that ticks through suspension needs no correction',
      () async {
        // What the iPhone 17 Pro simulator actually does: measured drift 0ms.
        await session.start();
        clocks.advance(const Duration(seconds: 2));

        await session.handleSuspend();
        clocks.advance(const Duration(minutes: 10));
        final correction = session.handleResume();

        expect(correction, Duration.zero);
        expect(session.engine.elapsed, const Duration(minutes: 10, seconds: 2));
      },
    );

    test(
      'a monotonic clock that halts while suspended is credited the gap',
      () async {
        // What a real device in deep sleep may do. Unverified on hardware; this
        // is the case the correction exists for.
        await session.start();
        clocks.advance(const Duration(seconds: 2));

        await session.handleSuspend();
        clocks.advanceWallOnly(const Duration(minutes: 10));
        final correction = session.handleResume();

        expect(correction, const Duration(minutes: 10));
        expect(session.engine.elapsed, const Duration(minutes: 10, seconds: 2));
      },
    );

    test(
      'a partially-halted monotonic clock is credited only the shortfall',
      () async {
        await session.start();
        await session.handleSuspend();

        clocks.advance(const Duration(seconds: 20)); // counted by both
        clocks.advanceWallOnly(const Duration(seconds: 40)); // missed
        final correction = session.handleResume();

        expect(correction, const Duration(seconds: 40));
        expect(session.engine.elapsed, const Duration(seconds: 60));
      },
    );

    test('suspension while stopped adds nothing', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 5));
      await session.stop();

      await session.handleSuspend();
      clocks.advanceWallOnly(const Duration(hours: 1));
      final correction = session.handleResume();

      expect(correction, Duration.zero);
      expect(session.engine.elapsed, const Duration(seconds: 5));
    });

    test('hidden then paused keeps the earlier instant', () async {
      await session.start();

      await session.handleSuspend(); // hidden
      clocks.advanceWallOnly(const Duration(seconds: 30));
      await session.handleSuspend(); // paused — must not reset the anchor
      clocks.advanceWallOnly(const Duration(seconds: 30));

      expect(session.handleResume(), const Duration(seconds: 60));
    });

    test('a resume with no suspend on record corrects nothing', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 3));

      expect(session.handleResume(), Duration.zero);
      expect(session.engine.elapsed, const Duration(seconds: 3));
    });

    test(
      'a wall clock stepped backwards while suspended never rewinds the dial',
      () async {
        await session.start();
        clocks.advance(const Duration(seconds: 30));

        await session.handleSuspend();
        clocks.wall.stepTo(clocks.wall.now.subtract(const Duration(hours: 5)));
        final correction = session.handleResume();

        expect(correction, Duration.zero);
        expect(session.engine.elapsed, const Duration(seconds: 30));
      },
    );
  });

  group('force-quit and relaunch', () {
    test('a running run keeps running while the app is dead', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 10));
      await session.persist();

      // The process dies. Only the store survives.
      clocks.advance(const Duration(minutes: 3));
      final revived = relaunch();
      await revived.restore();

      expect(revived.engine.state, TimingState.running);
      expect(revived.engine.elapsed, const Duration(minutes: 3, seconds: 10));
    });

    test('a stopped run does not advance while the app is dead', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 10));
      await session.stop();

      clocks.advance(const Duration(hours: 2));
      final revived = relaunch();
      await revived.restore();

      expect(revived.engine.state, TimingState.stopped);
      expect(revived.engine.elapsed, const Duration(seconds: 10));
    });

    test('splits survive the relaunch with their arithmetic intact', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 5));
      await session.split();
      clocks.advance(const Duration(seconds: 7));
      await session.split();

      clocks.advance(const Duration(seconds: 60));
      final revived = relaunch();
      await revived.restore();

      expect(revived.engine.splits, const [
        Duration(seconds: 5),
        Duration(seconds: 12),
      ]);
      expect(revived.engine.lapTimes, const [
        Duration(seconds: 5),
        Duration(seconds: 7),
      ]);
      expect(revived.engine.elapsed, const Duration(seconds: 72));
    });

    test('a restored run keeps running from the restore point', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 10));
      await session.persist();
      clocks.advance(const Duration(seconds: 30));

      final revived = relaunch();
      await revived.restore();
      clocks.advance(const Duration(seconds: 5));

      expect(revived.engine.elapsed, const Duration(seconds: 45));
    });

    test('no record leaves a fresh idle engine', () async {
      final revived = relaunch();
      await revived.restore();

      expect(revived.engine.state, TimingState.idle);
      expect(revived.engine.elapsed, Duration.zero);
    });

    test('a run that was never started leaves no record', () async {
      await session.persist();

      expect(await store.read(), isNull);
    });

    test(
      'a wall clock stepped backwards across a relaunch does not rewind',
      () async {
        await session.start();
        clocks.advance(const Duration(seconds: 30));
        await session.persist();

        clocks.wall.stepTo(clocks.wall.now.subtract(const Duration(days: 1)));
        final revived = relaunch();
        await revived.restore();

        expect(revived.engine.elapsed, const Duration(seconds: 30));
      },
    );
  });

  group('the record tracks the run', () {
    test('every transition persists', () async {
      await session.start();
      expect(store.writeCount, 1);

      await session.split();
      expect(store.writeCount, 2);

      await session.stop();
      expect(store.writeCount, 3);
    });

    test('suspend persists', () async {
      await session.start();
      final before = store.writeCount;

      await session.handleSuspend();

      expect(store.writeCount, before + 1);
    });

    test('reset clears the record', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 3));
      await session.split();
      await session.stop();

      await session.reset();

      expect(await store.read(), isNull);
    });

    test('nothing survives a reset into the next launch', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 3));
      await session.stop();
      await session.reset();

      final revived = relaunch();
      await revived.restore();

      expect(revived.engine.state, TimingState.idle);
      expect(revived.engine.elapsed, Duration.zero);
      expect(revived.engine.splits, isEmpty);
    });
  });
}
