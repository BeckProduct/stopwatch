import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/chrono_geometry.dart';

void main() {
  group('the tenths register', () {
    test('turns once a second', () {
      expect(tenthDegFor(Duration.zero), 0);
      expect(tenthDegFor(const Duration(milliseconds: 100)), closeTo(36, 1e-9));
      expect(
        tenthDegFor(const Duration(milliseconds: 500)),
        closeTo(180, 1e-9),
      );
      // A full turn lands back at the top rather than running on past it.
      expect(tenthDegFor(const Duration(seconds: 1)), 0);
      expect(
        tenthDegFor(const Duration(milliseconds: 1700)),
        closeTo(252, 1e-9),
      );
    });

    test('steps with the sweep hand under Reduce Motion', () {
      // The sweep hand and the tenths hand read the same quantised value, so
      // they beat together: five steps a second, 72 degrees apart here.
      Duration q(int ms) =>
          quantise(Duration(milliseconds: ms), reduceMotion: true);

      expect(tenthDegFor(q(199)), 0);
      expect(tenthDegFor(q(200)), closeTo(72, 1e-9));
      expect(tenthDegFor(q(399)), closeTo(72, 1e-9));
      expect(tenthDegFor(q(800)), closeTo(288, 1e-9));
    });
  });

  test('the dial box holds the rim with air to spare', () {
    // A clipped outer hairline is the failure this guards: the box has to
    // reach past the rim, not stop on it.
    expect(Dial.centre - Dial.boxLeft, greaterThan(Dial.rimOuter));
    expect(
      Dial.boxLeft + Dial.boxWidth - Dial.centre,
      greaterThan(Dial.rimOuter),
    );
    expect(Dial.boxWidth, Dial.boxHeight);
  });
}
