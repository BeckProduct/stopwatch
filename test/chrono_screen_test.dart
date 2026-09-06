import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/chrono_painter.dart';
import 'package:stopwatch/chrono_screen.dart';
import 'package:stopwatch/chrono_theme.dart';
import 'package:stopwatch/run_persistence.dart';
import 'package:stopwatch/run_session.dart';
import 'package:stopwatch/timing_engine.dart';

import 'support/clock_pair.dart';

void main() {
  Future<RunSession> pumpScreen(WidgetTester tester, ClockPair clocks) async {
    final session = RunSession(
      store: MemoryRunStore(),
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
    return session;
  }

  testWidgets('the readout tracks the injected clock', (tester) async {
    final clocks = ClockPair();
    await pumpScreen(tester, clocks);

    expect(find.text('00:00.00'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Start'));
    await tester.pump();
    clocks.advance(const Duration(milliseconds: 1230));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('00:01.23'), findsOneWidget);
  });

  testWidgets('the split pusher is disabled at idle and enabled once running', (
    tester,
  ) async {
    final clocks = ClockPair();
    final session = await pumpScreen(tester, clocks);
    TimingEngine engine() => session.engine;

    // "ignored" at idle: disabled, and the press records no lap.
    await tester.tap(find.bySemanticsLabel('Split'));
    await tester.pump();
    expect(engine().splits, isEmpty);

    await tester.tap(find.bySemanticsLabel('Start'));
    await tester.pump();
    clocks.advance(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.bySemanticsLabel('Split'));
    await tester.pump();
    expect(engine().splits, [const Duration(seconds: 5)]);
    // The label flips only on split state, never on run state.
    expect(find.bySemanticsLabel('Rejoin split hand'), findsOneWidget);
  });

  testWidgets('a second crown tap inside 120 ms is swallowed', (tester) async {
    final clocks = ClockPair();
    final session = await pumpScreen(tester, clocks);
    TimingEngine engine() => session.engine;

    await tester.tap(find.bySemanticsLabel('Start'));
    await tester.pump();
    clocks.advance(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(
      find.bySemanticsLabel('Rejoin split hand').evaluate().isEmpty
          ? find.bySemanticsLabel('Split')
          : find.bySemanticsLabel('Rejoin split hand'),
    );
    await tester.pump();
    expect(engine().splits, hasLength(1));

    // Same gesture, 80 ms later: the pincers have not reopened.
    clocks.advance(const Duration(milliseconds: 80));
    await tester.tap(find.bySemanticsLabel('Rejoin split hand'));
    await tester.pump();
    expect(
      engine().splits,
      hasLength(1),
      reason: 'the release was swallowed, so the hand is still frozen',
    );

    clocks.advance(const Duration(milliseconds: 200));
    await tester.tap(find.bySemanticsLabel('Rejoin split hand'));
    await tester.pump();
    // Past the debounce the release is accepted: the hand is catching up, and
    // a release records no new lap.
    expect(find.bySemanticsLabel('Split'), findsOneWidget);
  });

  testWidgets(
    'the controls sit below the dial and answer where they are drawn',
    (tester) async {
      final clocks = ClockPair();
      final session = await pumpScreen(tester, clocks);

      final dial = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is ChronoPainter,
        ),
      );
      // The case is gone, so nothing rides its flank any more. Measured against
      // where the dial is actually painted rather than against the arithmetic
      // that placed it.
      for (final label in ['Start', 'Split', 'Reset']) {
        expect(
          tester.getRect(find.bySemanticsLabel(label)).top,
          greaterThanOrEqualTo(dial.bottom),
          reason: '$label sits below the face, not on a case flank',
        );
      }

      await tester.tapAt(tester.getCenter(find.bySemanticsLabel('Start')));
      await tester.pump();

      expect(
        session.engine.state,
        TimingState.running,
        reason: 'the pusher answers where its head is drawn',
      );
    },
  );

  testWidgets('reset is refused while running and clears once stopped', (
    tester,
  ) async {
    final clocks = ClockPair();
    final session = await pumpScreen(tester, clocks);
    TimingEngine engine() => session.engine;

    await tester.tap(find.bySemanticsLabel('Start'));
    await tester.pump();
    clocks.advance(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.bySemanticsLabel('Reset'));
    await tester.pump();
    expect(
      engine().state,
      TimingState.running,
      reason: 'blocked while running',
    );

    await tester.tap(find.bySemanticsLabel('Stop'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Reset'));
    await tester.pump();

    expect(engine().state, TimingState.idle);
    expect(find.text('00:00.00'), findsOneWidget);
  });

  /// Every control has to be reachable by assistive tech, and a pointer tap
  /// proves nothing about that: it lands on the button underneath and works
  /// whether or not the semantics node carries an action at all. These drive
  /// the node itself, which is what VoiceOver does.
  group('activation through the semantics tree', () {
    testWidgets('every control carries a tap action', (tester) async {
      final handle = tester.ensureSemantics();
      final clocks = ClockPair();
      final session = await pumpScreen(tester, clocks);

      // Split and reset both need a state where they are live, so the three
      // are checked where each one is enabled.
      await tester.tap(find.bySemanticsLabel('Start'));
      await tester.pump();
      clocks.advance(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.bySemanticsLabel('Stop'));
      await tester.pump();

      for (final label in ['Start', 'Split', 'Reset']) {
        expect(
          tester
              .getSemantics(find.bySemanticsLabel(label))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
          reason: '$label cannot be activated by VoiceOver',
        );
      }

      expect(session.engine.state, TimingState.stopped);
      handle.dispose();
    });

    testWidgets('start runs the chronograph', (tester) async {
      final handle = tester.ensureSemantics();
      final clocks = ClockPair();
      final session = await pumpScreen(tester, clocks);

      tester.semantics.performAction(
        find.semantics.byLabel('Start'),
        SemanticsAction.tap,
      );
      await tester.pump();

      expect(session.engine.state, TimingState.running);
      handle.dispose();
    });

    testWidgets('split records a lap', (tester) async {
      final handle = tester.ensureSemantics();
      final clocks = ClockPair();
      final session = await pumpScreen(tester, clocks);

      tester.semantics.performAction(
        find.semantics.byLabel('Start'),
        SemanticsAction.tap,
      );
      await tester.pump();
      clocks.advance(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 16));

      tester.semantics.performAction(
        find.semantics.byLabel('Split'),
        SemanticsAction.tap,
      );
      await tester.pump();

      expect(session.engine.splits, [const Duration(seconds: 4)]);
      handle.dispose();
    });

    testWidgets('reset clears a stopped run', (tester) async {
      final handle = tester.ensureSemantics();
      final clocks = ClockPair();
      final session = await pumpScreen(tester, clocks);

      tester.semantics.performAction(
        find.semantics.byLabel('Start'),
        SemanticsAction.tap,
      );
      await tester.pump();
      clocks.advance(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 16));
      tester.semantics.performAction(
        find.semantics.byLabel('Stop'),
        SemanticsAction.tap,
      );
      await tester.pump();

      tester.semantics.performAction(
        find.semantics.byLabel('Reset'),
        SemanticsAction.tap,
      );
      await tester.pump();

      expect(session.engine.state, TimingState.idle);
      expect(find.text('00:00.00'), findsOneWidget);
      handle.dispose();
    });
  });
}
