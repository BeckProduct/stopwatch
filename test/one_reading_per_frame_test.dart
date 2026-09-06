import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/chrono_geometry.dart';
import 'package:stopwatch/chrono_painter.dart';
import 'package:stopwatch/chrono_screen.dart';
import 'package:stopwatch/chrono_theme.dart';
import 'package:stopwatch/run_persistence.dart';
import 'package:stopwatch/run_session.dart';

import 'support/clock_pair.dart';

/// The app's load-bearing rule: every hand and every digit in a frame comes
/// from one reading of the clock. Two readings and the dial disagrees with the
/// numerals, by a gap that grows with the run.
///
/// This is only testable against a clock that moves on every read. Against a
/// still fake, a second reading returns the same value as the first and a
/// violation leaves nothing behind to assert on.
void main() {
  testWidgets('the dial and the readout come from one reading', (tester) async {
    // A second apart is far more than any real frame, so a double read cannot
    // hide inside the hundredths the readout prints.
    final clocks = ClockPair(monotonicTickPerRead: const Duration(seconds: 1));
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
    await tester.pump();

    // The engine only reads the clock while running; stopped, elapsed is a
    // stored total and every read of it agrees for free.
    await tester.tap(find.bySemanticsLabel('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final painter =
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is ChronoPainter,
                  ),
                )
                .painter
            as ChronoPainter;

    // What the hand was drawn from has to be what the digits say. Asserted
    // against the painter's own value rather than a number the test picked,
    // so it holds whatever frame the assertion lands on.
    expect(
      find.text(formatElapsed(painter.elapsed)),
      findsOneWidget,
      reason:
          'the hand and the digits are a whole reading apart, so build took '
          'more than one',
    );
  });
}
