import 'package:stopwatch/monotonic_clock.dart';

/// A clock the test drives by hand.
///
/// Lets timing be asserted exactly, with no sleeping and no tolerance windows:
/// advance it by the interval under test and read the result.
class FakeMonotonicClock implements MonotonicClock {
  FakeMonotonicClock({this.tickPerRead = Duration.zero});

  /// How far the clock moves on every read.
  ///
  /// Zero by default: a clock that moves only when the test moves it, which is
  /// what makes exact assertions possible. Set it and every reading is a
  /// different one, which is the only way a second read inside a single frame
  /// becomes visible -- against a still clock a double read returns the same
  /// value and the bug it would cause leaves no trace.
  final Duration tickPerRead;

  /// Starts at a non-zero origin, so a test that accidentally treats a raw
  /// reading as an elapsed duration produces a wrong answer instead of a
  /// coincidentally right one.
  Duration _now = const Duration(hours: 3, minutes: 17);

  @override
  Duration get now {
    final reading = _now;
    _now += tickPerRead;
    return reading;
  }

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
