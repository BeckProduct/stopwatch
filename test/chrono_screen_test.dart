import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/chrono_geometry.dart';
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

  testWidgets('a tap on the painted pusher head reaches the control', (
    tester,
  ) async {
    final clocks = ClockPair();
    final session = await pumpScreen(tester, clocks);

    // Taken from where the case is actually painted rather than from the
    // widget's own placement arithmetic. A regression guard: it pins the
    // targets to the painted heads so a change to either has to move both.
    final canvas = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ChronoPainter,
      ),
    );
    final scale = canvas.width / Dial.boxWidth;
    const headRadius = 220.0;
    final head = polar(Dial.centre, Dial.centre, headRadius, 60);
    final target = Offset(
      canvas.left + (head.dx - Dial.boxLeft) * scale,
      canvas.top + (head.dy - Dial.boxTop) * scale,
    );

    await tester.tapAt(target);
    await tester.pump();

    expect(
      session.engine.state,
      TimingState.running,
      reason: 'the top pusher answers where it is drawn',
    );
  });

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
}
