import 'package:stopwatch/monotonic_clock.dart';

/// A clock the test drives by hand.
///
/// Lets timing be asserted exactly, with no sleeping and no tolerance windows:
/// advance it by the interval under test and read the result.
class FakeMonotonicClock implements MonotonicClock {
  /// Starts at a non-zero origin, so a test that accidentally treats a raw
  /// reading as an elapsed duration produces a wrong answer instead of a
  /// coincidentally right one.
  Duration _now = const Duration(hours: 3, minutes: 17);

  @override
  Duration get now => _now;

  /// Moves the clock forward. A real monotonic clock cannot go backwards, so
  /// neither can this one.
  void advance(Duration amount) {
    if (amount.isNegative) {
      throw ArgumentError.value(
        amount,
        'amount',
        'A monotonic clock cannot go backwards',
      );
    }
    _now += amount;
  }
}
