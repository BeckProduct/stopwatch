import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/main.dart';
import 'package:stopwatch/run_persistence.dart';
import 'package:stopwatch/run_session.dart';
import 'package:stopwatch/timing_engine.dart';

import 'support/clock_pair.dart';

void main() {
  late ClockPair clocks;
  late MemoryRunStore store;

  /// Pumps twice: the ticker's callback calls setState, which builds on the
  /// frame after the tick.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
  }

  Future<void> showHarness(WidgetTester tester) async {
    clocks = ClockPair();
    store = MemoryRunStore();
    await tester.pumpWidget(
      MaterialApp(
        home: EngineHarness(
          session: RunSession(
            store: store,
            monotonic: clocks.monotonic,
            wall: clocks.wall,
          ),
        ),
      ),
    );
    // initState kicks off an async restore; let it settle before asserting.
    await tester.pump();
  }

  bool enabled(WidgetTester tester, String label) {
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        // byType matches the exact runtime type, and ButtonStyleButton is
        // abstract — FilledButton and OutlinedButton need a predicate.
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    return button.onPressed != null;
  }

  testWidgets('opens idle at zero', (tester) async {
    await showHarness(tester);

    expect(find.text('00:00.00'), findsOneWidget);
    expect(find.text('idle'), findsOneWidget);
    expect(enabled(tester, 'Start'), isTrue);
    expect(enabled(tester, 'Lap'), isFalse);
    expect(enabled(tester, 'Reset'), isFalse);
  });

  testWidgets('the display advances with the clock while running', (
    tester,
  ) async {
    await showHarness(tester);

    await tester.tap(find.text('Start'));
    await settle(tester);
    clocks.advance(const Duration(milliseconds: 1500));
    await settle(tester);

    // A value that exists only if the engine ran and the ticker rebuilt.
    expect(find.text('00:01.50'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('the display holds while stopped', (tester) async {
    await showHarness(tester);

    await tester.tap(find.text('Start'));
    await settle(tester);
    clocks.advance(const Duration(seconds: 2));
    await settle(tester);
    await tester.tap(find.text('Stop'));
    await settle(tester);

    clocks.advance(const Duration(minutes: 5));
    await settle(tester);

    expect(find.text('00:02.00'), findsOneWidget);
    expect(find.text('stopped'), findsOneWidget);
    expect(enabled(tester, 'Lap'), isFalse);
    expect(enabled(tester, 'Reset'), isTrue);
  });

  testWidgets('lap records a row and reset clears it', (tester) async {
    await showHarness(tester);

    await tester.tap(find.text('Start'));
    await settle(tester);
    clocks.advance(const Duration(seconds: 3));
    await settle(tester);
    await tester.tap(find.text('Lap'));
    await settle(tester);

    expect(find.text('Lap 1'), findsOneWidget);
    expect(find.text('00:03.00'), findsWidgets);

    await tester.tap(find.text('Stop'));
    await settle(tester);
    await tester.tap(find.text('Reset'));
    await settle(tester);

    expect(find.text('Lap 1'), findsNothing);
    expect(find.text('00:00.00'), findsOneWidget);
    expect(find.text('idle'), findsOneWidget);
  });

  testWidgets('a running run left by a previous launch is picked up', (
    tester,
  ) async {
    clocks = ClockPair();
    store = MemoryRunStore();
    await store.write(
      RunSnapshot(
        state: TimingState.running,
        elapsed: const Duration(seconds: 30),
        splits: const [Duration(seconds: 12)],
        takenAt: clocks.wall.now,
      ),
    );
    clocks.advance(const Duration(seconds: 15)); // dead for 15s

    await tester.pumpWidget(
      MaterialApp(
        home: EngineHarness(
          session: RunSession(
            store: store,
            monotonic: clocks.monotonic,
            wall: clocks.wall,
          ),
        ),
      ),
    );
    await settle(tester);

    // 30s on the dial plus the 15s the app was not running.
    expect(find.text('00:45.00'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
    expect(find.text('Lap 1'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets(
    'a suspension the monotonic clock missed is corrected on resume',
    (tester) async {
      await showHarness(tester);

      await tester.tap(find.text('Start'));
      await settle(tester);
      clocks.advance(const Duration(seconds: 4));
      await settle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      clocks.advanceWallOnly(
        const Duration(seconds: 26),
      ); // asleep, mono halted
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(find.text('00:30.00'), findsOneWidget);
      expect(find.text('resume correction 26000ms'), findsOneWidget);
    },
  );

  testWidgets(
    'a suspension the monotonic clock covered is not double-counted',
    (tester) async {
      await showHarness(tester);

      await tester.tap(find.text('Start'));
      await settle(tester);
      clocks.advance(const Duration(seconds: 4));
      await settle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      clocks.advance(const Duration(seconds: 26)); // both clocks saw it
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(find.text('00:30.00'), findsOneWidget);
      expect(find.text('resume correction 0ms'), findsOneWidget);
    },
  );

  testWidgets('suspending records the run for a force-quit', (tester) async {
    await showHarness(tester);

    await tester.tap(find.text('Start'));
    await settle(tester);
    clocks.advance(const Duration(seconds: 8));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    final recorded = await store.read();
    expect(recorded, isNotNull);
    expect(recorded!.state, TimingState.running);
    expect(recorded.elapsed, const Duration(seconds: 8));
  });
}
