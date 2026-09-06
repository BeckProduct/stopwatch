import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/main.dart';
import 'package:stopwatch/timing_engine.dart';

import 'support/fake_monotonic_clock.dart';

void main() {
  late FakeMonotonicClock clock;

  /// Pumps twice: the ticker's callback calls setState, which builds on the
  /// frame after the tick.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
  }

  Future<void> showHarness(WidgetTester tester) async {
    clock = FakeMonotonicClock();
    await tester.pumpWidget(
      MaterialApp(
        home: EngineHarness(engine: TimingEngine(clock: clock)),
      ),
    );
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
    clock.advance(const Duration(milliseconds: 1500));
    await settle(tester);

    // A value that exists only if the engine ran and the ticker rebuilt.
    expect(find.text('00:01.50'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('the display holds while stopped', (tester) async {
    await showHarness(tester);

    await tester.tap(find.text('Start'));
    await settle(tester);
    clock.advance(const Duration(seconds: 2));
    await settle(tester);
    await tester.tap(find.text('Stop'));
    await settle(tester);

    clock.advance(const Duration(minutes: 5));
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
    clock.advance(const Duration(seconds: 3));
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
}
