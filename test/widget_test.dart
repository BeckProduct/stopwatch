import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/chrono_screen.dart';
import 'package:stopwatch/chrono_theme.dart';
import 'package:stopwatch/run_persistence.dart';
import 'package:stopwatch/run_session.dart';
import 'package:stopwatch/timing_engine.dart';

import 'support/clock_pair.dart';

void main() {
  late ClockPair clocks;
  late MemoryRunStore store;
  late RunSession session;

  /// Pumps twice: the ticker's callback calls setState, which builds on the
  /// frame after the tick.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// Shows the real screen. These assert survival, so they must run against
  /// what ships -- a harness that shares only the session proves nothing about
  /// the screen the user has in front of them.
  Future<void> showScreen(WidgetTester tester, {RunSession? existing}) async {
    session =
        existing ??
        RunSession(
          store: store,
          monotonic: clocks.monotonic,
          wall: clocks.wall,
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: chronoThemeData(Brightness.light),
        home: ChronoScreen(session: session),
      ),
    );
    // initState kicks off an async restore; let it settle before asserting.
    await tester.pump();
  }

  Future<void> showHarness(WidgetTester tester) async {
    clocks = ClockPair();
    store = MemoryRunStore();
    await showScreen(tester);
  }

  /// The three case controls carry their state on the Semantics node, not on a
  /// disabled button: [ID-13] is refused by the mechanism while nothing dims.
  bool enabled(WidgetTester tester, String label) {
    final node = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      ),
    );
    return node.properties.enabled ?? false;
  }

  testWidgets('opens idle at zero', (tester) async {
    await showHarness(tester);

    expect(find.text('00:00.00'), findsOneWidget);
    expect(session.engine.state, TimingState.idle);
    expect(enabled(tester, 'Start'), isTrue);
    // Split is dead at idle; Reset is live and simply changes nothing.
    expect(enabled(tester, 'Split'), isFalse);
    expect(enabled(tester, 'Reset'), isTrue);
  });

  testWidgets('the display advances with the clock while running', (
    tester,
  ) async {
    await showHarness(tester);

    await tester.tap(find.bySemanticsLabel('Start'));
    await settle(tester);
    clocks.advance(const Duration(milliseconds: 1500));
    await settle(tester);

    // A value that exists only if the engine ran and the ticker rebuilt.
    expect(find.text('00:01.50'), findsOneWidget);
    expect(session.engine.state, TimingState.running);
  });

  testWidgets('the display holds while stopped', (tester) async {
    await showHarness(tester);

    await tester.tap(find.bySemanticsLabel('Start'));
    await settle(tester);
    clocks.advance(const Duration(seconds: 2));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Stop'));
    await settle(tester);

    clocks.advance(const Duration(minutes: 5));
    await settle(tester);

    expect(find.text('00:02.00'), findsOneWidget);
    expect(session.engine.state, TimingState.stopped);
    // Splitting a stopped chronograph is legal, and Reset is now live.
    expect(enabled(tester, 'Split'), isTrue);
    expect(enabled(tester, 'Reset'), isTrue);
  });

  testWidgets('lap records a row and reset clears it', (tester) async {
    await showHarness(tester);

    await tester.tap(find.bySemanticsLabel('Start'));
    await settle(tester);
    clocks.advance(const Duration(seconds: 3));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Split'));
    await settle(tester);

    expect(find.text('LAP 1'), findsOneWidget);
    expect(find.text('00:03.00'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('Stop'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Reset'));
    await settle(tester);

    expect(find.text('LAP 1'), findsNothing);
    expect(find.text('00:00.00'), findsOneWidget);
    expect(session.engine.state, TimingState.idle);
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

    await showScreen(tester);
    await settle(tester);

    // 30s on the dial plus the 15s the app was not running.
    expect(find.text('00:45.00'), findsOneWidget);
    expect(session.engine.state, TimingState.running);
    expect(find.text('LAP 1'), findsOneWidget);
    // The face is showing a live run, so the top pusher offers to stop it.
    expect(find.bySemanticsLabel('Stop'), findsOneWidget);
  });

  testWidgets(
    'a suspension the monotonic clock missed is corrected on resume',
    (tester) async {
      await showHarness(tester);

      await tester.tap(find.bySemanticsLabel('Start'));
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

      // 4s counted, 26s the monotonic clock missed, credited on resume.
      expect(find.text('00:30.00'), findsOneWidget);
    },
  );

  testWidgets(
    'a suspension the monotonic clock covered is not double-counted',
    (tester) async {
      await showHarness(tester);

      await tester.tap(find.bySemanticsLabel('Start'));
      await settle(tester);
      clocks.advance(const Duration(seconds: 4));
      await settle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      clocks.advance(const Duration(seconds: 26)); // both clocks saw it
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      // 30s, not 56s: the monotonic clock already counted the suspension, so
      // crediting the wall gap on top would double it.
      expect(find.text('00:30.00'), findsOneWidget);
    },
  );

  testWidgets('suspending records the run for a force-quit', (tester) async {
    await showHarness(tester);

    await tester.tap(find.bySemanticsLabel('Start'));
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
