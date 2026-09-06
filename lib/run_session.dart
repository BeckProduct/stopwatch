import 'dart:async';

import 'package:flutter/widgets.dart';

import 'live_activity.dart';
import 'monotonic_clock.dart';
import 'run_persistence.dart';
import 'timing_engine.dart';
import 'wall_clock.dart';

/// Keeps one run correct across suspension and relaunch.
///
/// Owns a [TimingEngine] and the record of it on disk, and nothing else. The
/// engine still does all the timing; this adds only what the engine cannot know
/// on its own — how long the process was not running.
///
/// Two gaps, closed differently:
///
/// * **Suspended, same process.** The engine survives, so the monotonic clock
///   is still authoritative. The wall clock is consulted only to detect a
///   *shortfall* — time the monotonic clock failed to count — and the engine is
///   credited that difference and nothing more. Measured on the iPhone 17 Pro
///   simulator the shortfall is 0ms, so this is a no-op there. It exists for
///   the case the simulator cannot reproduce: a real device in deep sleep,
///   where the monotonic clock may stop.
/// * **Force-quit.** The process is gone and the monotonic clock has restarted
///   at zero, so the persisted wall-clock instant is the only surviving
///   evidence. Elapsed is re-derived from it on the next launch.
///
/// Correcting only the shortfall is what keeps the two safe together: crediting
/// the wall gap unconditionally would double-count every suspension on any
/// platform whose monotonic clock keeps running.
class RunSession {
  factory RunSession({
    required RunStore store,
    MonotonicClock? monotonic,
    WallClock wall = const SystemWallClock(),
    LiveActivityBridge? liveActivity,
  }) => RunSession._(
    store,
    monotonic ?? SystemMonotonicClock(),
    wall,
    liveActivity ?? LiveActivityBridge(),
  );

  /// Takes the resolved clock, so the session and the engine it builds cannot
  /// end up on two different ones — which is what happens if the nullable is
  /// forwarded and each side defaults it separately.
  RunSession._(
    this.store,
    MonotonicClock monotonic,
    this.wall,
    this._liveActivity,
  ) : _monotonic = monotonic,
      _engine = TimingEngine(clock: monotonic);

  final RunStore store;
  final WallClock wall;
  final MonotonicClock _monotonic;
  final LiveActivityBridge _liveActivity;

  TimingEngine _engine;

  /// The clock this session and its [engine] both run on.
  ///
  /// Public because the screen needs it too: the split hand's mechanism has to
  /// be driven from the same clock as the engine, or its animation and the
  /// sweep hand's angle are measured against two different timelines.
  MonotonicClock get monotonic => _monotonic;

  /// Replaced wholesale by [restore], so read it fresh rather than holding it.
  TimingEngine get engine => _engine;

  /// Wall-clock instant and dial reading captured at suspend, held only until
  /// the matching resume.
  DateTime? _suspendedAtWall;
  Duration _suspendedAtElapsed = Duration.zero;

  /// Brings back an in-flight run left by a previous launch.
  ///
  /// A run recorded as running has kept running: the time since the record was
  /// written is added. A run recorded as stopped has not moved. No record, or an
  /// unreadable one, leaves a fresh idle engine.
  Future<void> restore() async {
    final snapshot = await store.read();
    if (snapshot == null) return;

    _engine = TimingEngine.restored(
      state: snapshot.state,
      elapsed: _broughtForward(snapshot),
      splits: snapshot.splits,
      clock: _monotonic,
    );
    // A run that outlived the process gets its Lock Screen mirror back.
    unawaited(_mirror());
  }

  Duration _broughtForward(RunSnapshot snapshot) {
    if (snapshot.state != TimingState.running) return snapshot.elapsed;

    final gap = wall.now.difference(snapshot.takenAt);
    // This sum cannot overflow, and not by luck: RunSnapshot rejects an elapsed
    // past RunSnapshot.maxRun and a takenAt outside its sane window, so both
    // terms are bounded long before they reach here. Validating at the parse
    // boundary is what lets every reader downstream do plain arithmetic.
    //
    // A wall clock stepped backwards between write and read must never rewind
    // the dial. Losing the gap is wrong; running the clock backwards is worse.
    return gap.isNegative ? snapshot.elapsed : snapshot.elapsed + gap;
  }

  /// Call when the app stops executing. Records where the run had got to, on
  /// both clocks.
  Future<void> handleSuspend() async {
    // iOS delivers hidden then paused for one suspension. Keep the earliest
    // instant, or the second call would erase the gap the first was measuring.
    if (_suspendedAtWall != null) return;

    _suspendedAtWall = wall.now;
    _suspendedAtElapsed = _engine.elapsed;
    await persist();
  }

  /// Call when the app starts executing again. Credits the engine with any time
  /// the monotonic clock missed while suspended.
  ///
  /// Returns the correction applied, for tests and for diagnostics.
  Duration handleResume() {
    final suspendedAt = _suspendedAtWall;
    _suspendedAtWall = null;

    if (suspendedAt == null || !_engine.isRunning) return Duration.zero;

    final wallGap = wall.now.difference(suspendedAt);
    final monotonicGap = _engine.elapsed - _suspendedAtElapsed;
    final shortfall = wallGap - monotonicGap;
    if (shortfall <= Duration.zero) return Duration.zero;

    _engine.absorbSuspendedGap(shortfall);
    // The dial just jumped by the shortfall, so the activity's anchor is stale.
    // Re-anchor, or the Lock Screen and the face disagree by exactly the gap.
    unawaited(_mirror());
    return shortfall;
  }

  Future<void> start() async {
    _engine.start();
    await persist();
    unawaited(_mirror());
  }

  Future<void> stop() async {
    _engine.stop();
    await persist();
    unawaited(_mirror());
  }

  Future<Duration> split() async {
    final mark = _engine.split();
    await persist();
    unawaited(_mirror());
    return mark;
  }

  /// Clears the dial and the record together. Nothing survives a reset — there
  /// is no session history by design.
  Future<void> reset() async {
    _engine.reset();
    await store.clear();
    unawaited(_mirror());
  }

  /// Pushes the run to the Live Activity, or ends it when there is no run.
  ///
  /// Always called unawaited. A transition must not wait on a platform
  /// round-trip to a surface the app does not own: awaiting it makes the
  /// pusher's response time hostage to ActivityKit.
  ///
  /// Called on transitions only — never per frame. The activity ticks its own
  /// numerals from the anchor it was handed, and pushing per second is
  /// rate-limited by the system and costs real battery.
  ///
  /// The mirror failing is not the run failing: every call answers `false`
  /// rather than throwing, and nothing here reads the answer.
  Future<void> _mirror() async {
    if (_engine.state == TimingState.idle) {
      _activityShowing = false;
      await _liveActivity.end();
      return;
    }
    final payload = LiveActivityPayload.forRun(
      elapsed: _engine.elapsed,
      isRunning: _engine.isRunning,
      lapCount: _engine.splits.length,
      now: wall.now,
    );
    if (_activityShowing) {
      await _liveActivity.update(payload);
    } else {
      _activityShowing = true;
      await _liveActivity.start(payload);
    }
  }

  /// Whether an activity is up, so a transition knows to update rather than
  /// request a second one.
  bool _activityShowing = false;

  /// Writes the current run, or clears the record if there is no run.
  ///
  /// Every transition persists, so a kill that delivers no suspend callback
  /// still leaves a record correct as of the last thing the user did.
  @visibleForTesting
  Future<void> persist() async {
    if (_engine.state == TimingState.idle) return store.clear();

    return store.write(
      RunSnapshot(
        state: _engine.state,
        elapsed: _engine.elapsed,
        splits: _engine.splits.toList(growable: false),
        takenAt: wall.now,
      ),
    );
  }
}
