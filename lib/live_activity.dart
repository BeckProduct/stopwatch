import 'package:flutter/services.dart';

/// What the Live Activity is told about the run.
///
/// The activity is rendered by iOS, out of process, and keeps ticking with the
/// app suspended. It cannot read [TimingEngine.elapsed] per frame, so it is
/// handed a wall-clock anchor instead: the instant the run would have begun to
/// reach the elapsed value the engine currently holds.
///
/// That anchor is *derived from* the monotonic elapsed value at push time, and
/// recomputed on every push. It is not a second clock: nothing in the app reads
/// it back, and a resumed run re-anchors rather than accumulating error. The
/// engine remains the only source of elapsed time.
class LiveActivityPayload {
  const LiveActivityPayload({
    required this.startDate,
    required this.pausedElapsed,
    required this.lapCount,
  });

  /// Derives the payload for a run of [elapsed] as of [now].
  ///
  /// [now] is injected so this stays a pure function and a test does not need a
  /// real clock.
  factory LiveActivityPayload.forRun({
    required Duration elapsed,
    required bool isRunning,
    required int lapCount,
    required DateTime now,
  }) {
    return LiveActivityPayload(
      startDate: now.subtract(elapsed),
      pausedElapsed: isRunning ? null : elapsed,
      lapCount: lapCount,
    );
  }

  /// Anchor for the self-ticking numerals. Always sent, so the activity has a
  /// coherent origin even while paused.
  final DateTime startDate;

  /// The frozen total while stopped; `null` while running. Its nullness is what
  /// tells the widget whether to tick.
  final Duration? pausedElapsed;

  final int lapCount;

  /// Wire form. Seconds since the epoch, because `Date` and `TimeInterval` are
  /// what ActivityKit takes on the other side.
  Map<String, Object?> toArguments() => <String, Object?>{
    'startDate': startDate.millisecondsSinceEpoch / 1000,
    'pausedElapsed': pausedElapsed == null
        ? null
        : pausedElapsed!.inMicroseconds / Duration.microsecondsPerSecond,
    'lapCount': lapCount,
  };
}

/// Thin wrapper over `MethodChannel('beck.stopwatch/liveactivity')`.
///
/// Every call answers `false` rather than throwing when the activity is not
/// showing — Live Activities switched off in Settings, the system limit hit, or
/// the OS too old. A stopwatch that will not start because its lock-screen
/// mirror could not is worse than no mirror, so failures are swallowed here and
/// the caller is free to ignore the result.
class LiveActivityBridge {
  LiveActivityBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'beck.stopwatch/liveactivity';

  final MethodChannel _channel;

  /// Whether the system will show an activity at all right now.
  Future<bool> isSupported() => _invoke('isSupported');

  /// Shows the activity, replacing one already up.
  Future<bool> start(LiveActivityPayload payload) =>
      _invoke('start', payload.toArguments());

  /// Re-anchors the running activity. Called on transitions and splits only —
  /// never per second, which the system rate-limits and which costs battery.
  Future<bool> update(LiveActivityPayload payload) =>
      _invoke('update', payload.toArguments());

  /// Dismisses the activity immediately.
  Future<bool> end() => _invoke('end');

  Future<bool> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } catch (_) {
      // Deliberately every failure, not a chosen few. This class exists to
      // mirror a run onto a surface the app does not own, and there is no
      // failure of that mirror worth taking the chronograph down for:
      // MissingPluginException off-device, PlatformException when the system
      // refuses the activity, and a binding that was never initialised in a
      // unit test that has no business reaching a platform channel at all.
      return false;
    }
  }
}
