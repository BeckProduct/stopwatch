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

  Map<String, Object?> toJson() => {
    'version': _version,
    'state': state.name,
    'elapsedMicros': elapsed.inMicroseconds,
    'splitMicros': [for (final s in splits) s.inMicroseconds],
    'takenAtMicros': takenAt.microsecondsSinceEpoch,
  };

  /// Returns null for anything unreadable — wrong version, missing field, wrong
  /// type, or a state that should never have been written. A corrupt record is
  /// treated as no record, so a bad write can never wedge the app on launch.
  static RunSnapshot? tryParse(String source) {
    try {
      final json = jsonDecode(source);
      if (json is! Map<String, Object?>) return null;
      if (json['version'] != _version) return null;

      final state = TimingState.values.asNameMap()[json['state']];
      if (state == null || state == TimingState.idle) return null;

      final elapsedMicros = json['elapsedMicros'];
      final takenAtMicros = json['takenAtMicros'];
      final splitMicros = json['splitMicros'];
      if (elapsedMicros is! int ||
          takenAtMicros is! int ||
          splitMicros is! List) {
        return null;
      }

      final splits = <Duration>[];
      for (final micros in splitMicros) {
        if (micros is! int) return null;
        splits.add(Duration(microseconds: micros));
      }

      return RunSnapshot(
        state: state,
        elapsed: Duration(microseconds: elapsedMicros),
        splits: splits,
        takenAt: DateTime.fromMicrosecondsSinceEpoch(takenAtMicros),
      );
    } on FormatException {
      return null;
    }
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
    final source = await _preferences.getString(_key);
    if (source == null) return null;
    final snapshot = RunSnapshot.tryParse(source);
    // Drop anything unreadable so it cannot be re-read on every launch.
    if (snapshot == null) await clear();
    return snapshot;
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
