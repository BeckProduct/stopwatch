import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'timing_engine.dart';

/// A run captured at one instant of wall-clock time.
///
/// Reads as a sentence: *as of [takenAt], the run was in [state] with [elapsed]
/// on the dial and these [splits]*. Restoring re-derives the present from that,
/// so the same record serves a resume and a cold start after a force-quit.
///
/// Only the in-flight run is ever recorded. There is no history here, by
/// design — [RunStore.clear] wipes it on reset and nothing accumulates.
class RunSnapshot {
  const RunSnapshot({
    required this.state,
    required this.elapsed,
    required this.splits,
    required this.takenAt,
  });

  /// [TimingState.idle] is never persisted: an idle run is the absence of one.
  final TimingState state;

  /// The dial reading at [takenAt].
  final Duration elapsed;

  final List<Duration> splits;

  /// Wall-clock instant the record describes.
  final DateTime takenAt;

  /// Bumped only if the shape changes incompatibly. An unrecognised version is
  /// discarded rather than guessed at.
  static const int _version = 1;

  /// The longest run that will ever be restored.
  ///
  /// A stopwatch left running for a year is not a run in progress. Bounding it
  /// here is also what keeps the arithmetic downstream inside 64 bits: nothing
  /// that reads a snapshot has to defend itself against a maxInt elapsed,
  /// because one never gets past this point.
  static const Duration maxRun = Duration(days: 365);

  /// More marks than a person can press in [maxRun], by a wide margin. A record
  /// claiming more is not a run, it is a way to exhaust memory on launch.
  static const int maxSplits = 100000;

  /// The window [takenAt] must fall inside.
  ///
  /// Outside it there is no run to reconstruct — a device claiming 1904 or
  /// 40000 cannot tell us how long the app was dead. The far ends are also
  /// where `DateTime.fromMicrosecondsSinceEpoch` itself throws, so bounding the
  /// value is what makes constructing it safe.
  static final DateTime earliestSaneInstant = DateTime.utc(2001);
  static final DateTime latestSaneInstant = DateTime.utc(2200);

  Map<String, Object?> toJson() => {
    'version': _version,
    'state': state.name,
    'elapsedMicros': elapsed.inMicroseconds,
    'splitMicros': [for (final s in splits) s.inMicroseconds],
    'takenAtMicros': takenAt.microsecondsSinceEpoch,
  };

  /// Reads a record, or returns null if it cannot be wholly trusted.
  ///
  /// A persisted record is untrusted input: it may have been written by an
  /// older build, truncated by a kill mid-write, or corrupted on disk. So this
  /// checks the *domain* and not merely the types — a negative elapsed, splits
  /// out of order, a nonsense instant and a maxInt overflow are all shapes that
  /// type checks wave through and that every reader downstream would then have
  /// to defend against separately.
  ///
  /// Any failure at all means the same thing — there is no usable record — so
  /// there is one catch-all rather than a list of exception types to forget to
  /// keep up to date.
  static RunSnapshot? tryParse(String source) {
    try {
      return _parse(source);
    } catch (_) {
      return null;
    }
  }

  static RunSnapshot? _parse(String source) {
    final json = jsonDecode(source);
    if (json is! Map<String, Object?>) return null;
    if (json['version'] != _version) return null;

    final state = TimingState.values.asNameMap()[json['state']];
    // Idle is the absence of a run, so a record claiming it is already wrong.
    if (state == null || state == TimingState.idle) return null;

    final elapsedMicros = json['elapsedMicros'];
    final takenAtMicros = json['takenAtMicros'];
    final splitMicros = json['splitMicros'];
    if (elapsedMicros is! int ||
        takenAtMicros is! int ||
        splitMicros is! List) {
      return null;
    }

    if (elapsedMicros < 0 || elapsedMicros > maxRun.inMicroseconds) return null;
    if (takenAtMicros < earliestSaneInstant.microsecondsSinceEpoch ||
        takenAtMicros > latestSaneInstant.microsecondsSinceEpoch) {
      return null;
    }
    if (splitMicros.length > maxSplits) return null;

    final splits = <Duration>[];
    var previous = 0;
    for (final micros in splitMicros) {
      // Marks are cumulative, so they run forward and stop at the dial reading.
      // Out of order or past the end, lap arithmetic produces a negative lap.
      if (micros is! int) return null;
      if (micros < previous || micros > elapsedMicros) return null;
      previous = micros;
      splits.add(Duration(microseconds: micros));
    }

    return RunSnapshot(
      state: state,
      elapsed: Duration(microseconds: elapsedMicros),
      splits: splits,
      takenAt: DateTime.fromMicrosecondsSinceEpoch(takenAtMicros),
    );
  }
}

/// Where the in-flight run is kept between launches.
///
/// An interface so tests never touch a real store, and so the backing choice
/// stays swappable — the engine has no opinion about it.
abstract interface class RunStore {
  Future<RunSnapshot?> read();

  Future<void> write(RunSnapshot snapshot);

  Future<void> clear();
}

/// The real store. The payload is a few hundred bytes, so key-value storage is
/// the whole requirement — nothing here warrants a file or a database.
class PreferencesRunStore implements RunStore {
  PreferencesRunStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _key = 'stopwatch.inFlightRun';

  final SharedPreferencesAsync _preferences;

  @override
  Future<RunSnapshot?> read() async {
    final String? source;
    try {
      source = await _preferences.getString(_key);
    } catch (_) {
      // The store itself is unreadable. There is nothing to restore and
      // nothing to discard, and launch must not depend on either.
      return null;
    }
    if (source == null) return null;

    final snapshot = RunSnapshot.tryParse(source);
    if (snapshot != null) return snapshot;

    // Unreadable, so discard it — otherwise the same bad record is re-read on
    // every subsequent launch and the app is wedged for good. The discard is
    // itself allowed to fail without taking launch down with it.
    try {
      await clear();
    } catch (_) {
      return null;
    }
    return null;
  }

  @override
  Future<void> write(RunSnapshot snapshot) =>
      _preferences.setString(_key, jsonEncode(snapshot.toJson()));

  @override
  Future<void> clear() => _preferences.remove(_key);
}

/// An in-memory store for tests, and the reference for what a store must do.
class MemoryRunStore implements RunStore {
  RunSnapshot? _snapshot;

  /// Counts writes so a test can assert that a transition persisted.
  int writeCount = 0;

  @override
  Future<RunSnapshot?> read() async => _snapshot;

  @override
  Future<void> write(RunSnapshot snapshot) async {
    _snapshot = snapshot;
    writeCount++;
  }

  @override
  Future<void> clear() async => _snapshot = null;
}
