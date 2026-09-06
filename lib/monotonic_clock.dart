/// A source of elapsed time that only ever moves forward.
///
/// Readings are taken from an arbitrary, fixed origin, so one reading on its
/// own means nothing — only the difference between two readings does.
///
/// Deliberately not backed by [DateTime]. Wall-clock time jumps when the system
/// clock is corrected, adjusted for a timezone, or slewed by NTP, and a
/// stopwatch must not jump with it.
abstract interface class MonotonicClock {
  /// The current reading. Never decreases.
  Duration get now;
}

/// The real clock, backed by the platform's monotonic timer.
///
/// [Stopwatch] reads the host's high-resolution monotonic source, which is what
/// makes it the right primitive here and `DateTime.now()` the wrong one.
class SystemMonotonicClock implements MonotonicClock {
  SystemMonotonicClock() : _source = Stopwatch()..start();

  final Stopwatch _source;

  @override
  Duration get now => _source.elapsed;
}
