import 'package:stopwatch/wall_clock.dart';

/// A wall clock the test drives by hand.
///
/// Unlike [FakeMonotonicClock] this one *can* be stepped backwards, because a
/// real wall clock can: the tests use that to check the dial never rewinds.
class FakeWallClock implements WallClock {
  FakeWallClock([DateTime? start])
    : _now = start ?? DateTime.utc(2026, 9, 6, 12, 0, 0);

  DateTime _now;

  @override
  DateTime get now => _now;

  void advance(Duration amount) => _now = _now.add(amount);

  /// Simulates the system clock being stepped — by the user, or by NTP.
  void stepTo(DateTime instant) => _now = instant;
}
