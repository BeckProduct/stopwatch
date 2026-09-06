import 'fake_monotonic_clock.dart';
import 'fake_wall_clock.dart';

/// The two fake clocks moved together.
///
/// Most lifecycle tests need both to advance by the same amount — that is the
/// ordinary case, where the monotonic clock keeps running while suspended. The
/// interesting cases are the ones that move them apart, and those call
/// [FakeMonotonicClock.advance] or [FakeWallClock.advance] directly so the
/// divergence is visible in the test body.
class ClockPair {
  final FakeMonotonicClock monotonic = FakeMonotonicClock();
  final FakeWallClock wall = FakeWallClock();

  /// Time passes and both clocks see it.
  void advance(Duration amount) {
    monotonic.advance(amount);
    wall.advance(amount);
  }

  /// Time passes but the monotonic clock does not see it — a device asleep
  /// with a halted monotonic source.
  void advanceWallOnly(Duration amount) => wall.advance(amount);
}
