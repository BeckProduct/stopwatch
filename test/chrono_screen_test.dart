import 'dart:async';

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

    await tester.tap(find.bySemanticsLabel('Split'));
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

  testWidgets('a split fumbled onto the start press is swallowed', (
    tester,
  ) async {
    // The debounce is the mechanism's recovery, not the crown's alone: a
    // finger coming off `Start` and catching the crown on the way records a
    // first lap of a few hundredths that nobody asked for.
    final clocks = ClockPair();
    final session = await pumpScreen(tester, clocks);
    TimingEngine engine() => session.engine;

    await tester.tap(find.bySemanticsLabel('Start'));
    await tester.pump();
    clocks.advance(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.bySemanticsLabel('Split'));
    await tester.pump();
    expect(
      engine().splits,
      isEmpty,
      reason: '20 ms after the start press the pincers have not reopened',
    );

    // Past the window the same press is honoured -- nothing here sets a
    // minimum lap length, only a recovery after the last thing the mechanism
    // did.
    clocks.advance(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.bySemanticsLabel('Split'));
    await tester.pump();
    expect(engine().splits, [const Duration(milliseconds: 220)]);
  });

  testWidgets('the idle stub does not buy a fumbled first split a pass', (
    tester,
  ) async {
    // The field sequence. A crown press at idle is refused, but it is still a
    // press: counted against the crown's own clock it burns the window, so the
    // real split 20 ms after the start lands with the window already spent and
    // is let through.
    final clocks = ClockPair();
    final session = await pumpScreen(tester, clocks);
    TimingEngine engine() => session.engine;

    await tester.tap(find.bySemanticsLabel('Split'));
    await tester.pump();

    clocks.advance(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.bySemanticsLabel('Start'));
    await tester.pump();

    clocks.advance(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.bySemanticsLabel('Split'));
    await tester.pump();

    expect(
      engine().splits,
      isEmpty,
      reason: 'the stub burned the window, the start press reopened it',
    );
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

  testWidgets('crown presses inside a pending persist record one lap', (
    tester,
  ) async {
    // The freeze branch does not move the split hand until its write returns,
    // so while that write is in flight the toggle still reads "joined". The
    // presses are far enough apart to clear the 120 ms debounce and each would
    // mark a *different* instant, so the engine's own repeat guard cannot see
    // them either -- this window has to be closed at the press.
    final clocks = ClockPair();
    final store = GatedRunStore();
    final session = RunSession(
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
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Start'));
    await tester.pump();
    clocks.advance(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 16));

    store.hold = true;
    await tester.tap(find.bySemanticsLabel('Split'));
    await tester.pump();

    // Still labelled Split: the hand has not frozen, because the write has not
    // come back. This is the window.
    expect(find.bySemanticsLabel('Split'), findsOneWidget);

    for (final gap in const [
      Duration(milliseconds: 200),
      Duration(milliseconds: 200),
    ]) {
      clocks.advance(gap);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.bySemanticsLabel('Split'));
      await tester.pump();
    }

    store.release();
    await tester.pump();
    await tester.pump();

    expect(session.engine.splits, [const Duration(seconds: 5)]);
    expect(find.bySemanticsLabel('Rejoin split hand'), findsOneWidget);
  });
  group('the ticker', () {
    // A transient frame callback is what a running [Ticker] registers, so the
    // count is the direct answer to "is this screen asking for another frame".
    // Nothing else on the dial registers one at rest; the ink splash under a
    // pusher does, briefly, which is what the settling pump below is for.
    int frameCallbacks(WidgetTester tester) =>
        tester.binding.transientCallbackCount;

    /// Long enough for a pusher's ink splash and its 90 ms travel to finish,
    /// so what remains is the ticker and only the ticker.
    Future<void> settleInk(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 1));

    testWidgets('never starts while the chronograph is idle', (tester) async {
      final clocks = ClockPair();
      await pumpScreen(tester, clocks);
      await settleInk(tester);

      expect(frameCallbacks(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('runs while the chronograph runs and stops when it stops', (
      tester,
    ) async {
      final clocks = ClockPair();
      final session = await pumpScreen(tester, clocks);

      await tester.tap(find.bySemanticsLabel('Start'));
      await tester.pump();
      await settleInk(tester);
      expect(session.engine.state, TimingState.running);
      expect(frameCallbacks(tester), 1);

      await tester.tap(find.bySemanticsLabel('Stop'));
      await tester.pump();
      await settleInk(tester);

      expect(session.engine.state, TimingState.stopped);
      expect(frameCallbacks(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('keeps running for a split hand catching up on a stopped '
        'chronograph, and stops once it lands', (tester) async {
      final clocks = ClockPair();
      final session = await pumpScreen(tester, clocks);

      await tester.tap(find.bySemanticsLabel('Start'));
      await tester.pump();
      clocks.advance(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 16));

      await tester.tap(find.bySemanticsLabel('Split'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Stop'));
      await tester.pump();
      await settleInk(tester);

      // Stopped with the split hand clamped: nothing is moving.
      expect(session.engine.state, TimingState.stopped);
      expect(frameCallbacks(tester), 0);

      // Past the crown's 120 ms debounce, which is measured on the monotonic
      // clock rather than the frame clock.
      clocks.advance(const Duration(milliseconds: 200));
      await tester.tap(find.bySemanticsLabel('Rejoin split hand'));
      await tester.pump();
      // The frame clock runs on so the ink splash finishes, but the monotonic
      // clock does not, so the whip cannot have landed yet. What is left
      // asking for frames is the catch-up.
      await settleInk(tester);
      expect(frameCallbacks(tester), 1);

      // Past the whip and its ring-down.
      clocks.advance(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();

      expect(frameCallbacks(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}

/// A store whose writes can be held open, so a test can stand inside the
/// window a real slow disk opens.
class GatedRunStore implements RunStore {
  RunSnapshot? _snapshot;
  final List<Completer<void>> _pending = <Completer<void>>[];

  /// While set, [write] does not complete until [release] is called.
  bool hold = false;

  @override
  Future<RunSnapshot?> read() async => _snapshot;

  @override
  Future<void> write(RunSnapshot snapshot) async {
    _snapshot = snapshot;
    if (!hold) return;
    final gate = Completer<void>();
    _pending.add(gate);
    return gate.future;
  }

  @override
  Future<void> clear() async => _snapshot = null;

  void release() {
    hold = false;
    for (final gate in _pending) {
      gate.complete();
    }
    _pending.clear();
  }
}
