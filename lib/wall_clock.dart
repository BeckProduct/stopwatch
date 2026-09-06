/// A reading of civil time, used only to measure how long the app was not
/// running.
///
/// The counterpart to `MonotonicClock`, and strictly the weaker of the two: a
/// wall clock can be stepped by the user, by a timezone change, or by NTP, so
/// it never carries the running total. It answers exactly one question — how
/// much time passed while no Dart code was executing — because it is the only
/// clock that survives the process dying.
abstract interface class WallClock {
  DateTime get now;
}

class SystemWallClock implements WallClock {
  const SystemWallClock();

  @override
  DateTime get now => DateTime.now();
}
