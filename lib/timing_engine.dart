import 'dart:collection';

import 'package:meta/meta.dart';

import 'monotonic_clock.dart';

/// Where the chronograph is in its cycle.
enum TimingState {
  /// Never started, or reset back to zero. Elapsed is zero and there are no
  /// splits.
  idle,

  /// Accumulating time.
  running,

  /// Halted with time on the dial. Can be resumed, or reset back to [idle].
  stopped,
}

/// The chronograph's timing core.
///
/// Holds no Flutter types and needs no widget tree: every transition is a plain
/// method call and every reading is a pure function of the injected clock.
///
/// Elapsed time is derived from a [MonotonicClock] and nothing else — not frame
/// counts, not wall-clock deltas. One elapsed value backs every reading, so the
/// hand and the numerals cannot drift apart.
///
/// Transitions, and what each rejects:
///
/// * [start] — [idle] or [stopped] to [running]. Rejected while running.
/// * [stop] — [running] to [stopped]. Rejected unless running.
/// * [reset] — [stopped] to [idle]. Rejected from any other state.
/// * [split] — records a mark that advances the dial. Rejected while
///   [idle]; a mark that repeats the last one is dropped.
///
/// [start] from [stopped] resumes: it adds to the time already on the dial
/// rather than starting over, and the interval spent stopped is not counted.
/// That is what the top pusher of a mechanical chronograph does. Only [reset]
/// returns the dial to zero.
class TimingEngine {
  /// Pass a [clock] to drive the engine from a test. Defaults to the real one.
  TimingEngine({MonotonicClock? clock})
    : _clock = clock ?? SystemMonotonicClock();

  /// Rebuilds an engine part-way through a run.
  ///
  /// [elapsed] is the dial reading as of now, already brought forward across
  /// whatever gap the process was not running for — this constructor does no
  /// reconciliation of its own.
  TimingEngine.restored({
    required TimingState state,
    required Duration elapsed,
    required List<Duration> splits,
    MonotonicClock? clock,
  }) : _clock = clock ?? SystemMonotonicClock() {
    if (state == TimingState.idle) {
      throw ArgumentError.value(
        state,
        'state',
        'An idle run is the absence of a run; construct a fresh engine instead',
      );
    }
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'Cannot be negative');
    }
    _state = state;
    _banked = elapsed;
    _splits.addAll(splits);
    if (state == TimingState.running) {
      _runStartedAt = _clock.now;
    }
  }

  final MonotonicClock _clock;

  final List<Duration> _splits = <Duration>[];

  TimingState _state = TimingState.idle;

  /// Time banked by runs that have already ended. The whole of [elapsed] while
  /// not running.
  Duration _banked = Duration.zero;

  /// The clock reading at which the current run began. Meaningless unless
  /// running.
  Duration _runStartedAt = Duration.zero;

  /// The clock this engine reads.
  ///
  /// Exposed so a test can prove that a session and the engine it builds share
  /// one clock rather than defaulting to two.
  @visibleForTesting
  MonotonicClock get clock => _clock;

  TimingState get state => _state;

  bool get isRunning => _state == TimingState.running;

  /// Total time on the dial.
  ///
  /// Cheap and allocation-free: safe to read once per frame and derive
  /// everything rendered that frame from the single value returned.
  Duration get elapsed =>
      isRunning ? _banked + (_clock.now - _runStartedAt) : _banked;

  /// Cumulative marks, oldest first: each is the value of [elapsed] when
  /// [split] was called.
  ///
  /// A live view of the engine's own list, so it tracks later splits and costs
  /// no allocation to read.
  late final List<Duration> splits = UnmodifiableListView<Duration>(_splits);

  /// Individual lap durations, oldest first — the gaps between consecutive
  /// [splits], with the first measured from zero.
  ///
  /// Derived, not stored: [splits] is the only record. Allocates, so compute it
  /// when the splits change rather than every frame.
  List<Duration> get lapTimes {
    final laps = <Duration>[];
    var previous = Duration.zero;
    for (final split in _splits) {
      laps.add(split - previous);
      previous = split;
    }
    return laps;
  }

  /// Starts from [idle], or resumes from [stopped].
  void start() {
    if (isRunning) {
      throw StateError('Cannot start: already running.');
    }
    _runStartedAt = _clock.now;
    _state = TimingState.running;
  }

  /// Halts, keeping the time on the dial.
  void stop() {
    if (!isRunning) {
      throw StateError('Cannot stop: not running (state is $_state).');
    }
    // Bank the running total before dropping out of the running state, or the
    // current run's contribution is lost.
    _banked = elapsed;
    _state = TimingState.stopped;
  }

  /// Returns the dial to zero and discards the splits.
  ///
  /// Legal only from [stopped]: resetting a running chronograph is a different
  /// mechanism (flyback), and resetting an idle one is a no-op that almost
  /// always means the caller lost track of the state.
  void reset() {
    if (_state != TimingState.stopped) {
      throw StateError(
        'Cannot reset: only legal from stopped '
        '(state is $_state).',
      );
    }
    _banked = Duration.zero;
    _runStartedAt = Duration.zero;
    _splits.clear();
    _state = TimingState.idle;
  }

  /// Adds time that the monotonic clock failed to count while the process was
  /// suspended.
  ///
  /// Called only with a measured shortfall — the amount by which the wall clock
  /// outran the monotonic clock across a suspension. When the monotonic clock
  /// ticks through suspension the shortfall is zero and nothing is added, so
  /// this can never double-count the gap.
  void absorbSuspendedGap(Duration shortfall) {
    if (!isRunning) {
      throw StateError('Cannot absorb a gap: not running (state is $_state).');
    }
    if (shortfall.isNegative) {
      throw ArgumentError.value(
        shortfall,
        'shortfall',
        'The dial cannot be wound backwards',
      );
    }
    _banked += shortfall;
  }

  /// Records the current [elapsed] as a cumulative mark and returns the mark
  /// now standing at the top of [splits].
  ///
  /// Legal while running and while stopped. A stopped chronograph with a
  /// frozen split hand is a real state on a real watch, and it is what lets
  /// someone record a final lap after stopping; that lap equals the total. Only
  /// [idle] refuses, because there is nothing yet to mark.
  ///
  /// **A mark that does not advance the dial is not recorded**, and the
  /// existing last mark comes back instead. The bar is movement, not a minimum
  /// lap length: two marks a hundredth of a second apart are exactly what a
  /// rattrapante is for — two competitors over one line — so a fast split is a
  /// split. A *repeated* mark is a different thing. The dial cannot move while
  /// stopped, so every crown press after the first records the same instant
  /// again: not a second lap, the same lap counted twice, and unbounded for as
  /// long as the user keeps pressing.
  ///
  /// The caller still gets a mark to freeze the split hand on, because the hand
  /// belongs where the dial is whether or not a lap was written.
  Duration split() {
    if (_state == TimingState.idle) {
      throw StateError('Cannot split: nothing to mark yet (state is $_state).');
    }
    final mark = elapsed;
    if (_splits.isNotEmpty && mark <= _splits.last) return _splits.last;
    _splits.add(mark);
    return mark;
  }
}
