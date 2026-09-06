import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/run_persistence.dart';
import 'package:stopwatch/timing_engine.dart';

void main() {
  final takenAt = DateTime.utc(2026, 9, 6, 12, 34, 56, 789);

  RunSnapshot sample({
    TimingState state = TimingState.running,
    Duration elapsed = const Duration(
      minutes: 1,
      seconds: 23,
      milliseconds: 456,
    ),
    List<Duration> splits = const [
      Duration(seconds: 20),
      Duration(seconds: 55),
    ],
  }) => RunSnapshot(
    state: state,
    elapsed: elapsed,
    splits: splits,
    takenAt: takenAt,
  );

  String encoded(RunSnapshot snapshot) => jsonEncode(snapshot.toJson());

  group('round trip', () {
    test('survives encode and decode intact', () {
      final parsed = RunSnapshot.tryParse(encoded(sample()))!;

      expect(parsed.state, TimingState.running);
      expect(
        parsed.elapsed,
        const Duration(minutes: 1, seconds: 23, milliseconds: 456),
      );
      expect(parsed.splits, const [
        Duration(seconds: 20),
        Duration(seconds: 55),
      ]);
      expect(parsed.takenAt.toUtc(), takenAt);
    });

    test('keeps microsecond precision', () {
      final parsed = RunSnapshot.tryParse(
        encoded(sample(elapsed: const Duration(microseconds: 1))),
      )!;

      expect(parsed.elapsed, const Duration(microseconds: 1));
    });

    test('a stopped run round trips', () {
      final parsed = RunSnapshot.tryParse(
        encoded(sample(state: TimingState.stopped)),
      )!;

      expect(parsed.state, TimingState.stopped);
    });

    test('an empty split list round trips', () {
      final parsed = RunSnapshot.tryParse(encoded(sample(splits: const [])))!;

      expect(parsed.splits, isEmpty);
    });
  });

  group('a record that cannot be trusted is discarded', () {
    test('not JSON at all', () {
      expect(RunSnapshot.tryParse('this is not json'), isNull);
    });

    test('JSON but not an object', () {
      expect(RunSnapshot.tryParse('[1, 2, 3]'), isNull);
    });

    test('a future version', () {
      final json = sample().toJson()..['version'] = 99;

      expect(RunSnapshot.tryParse(jsonEncode(json)), isNull);
    });

    test('a missing field', () {
      final json = sample().toJson()..remove('elapsedMicros');

      expect(RunSnapshot.tryParse(jsonEncode(json)), isNull);
    });

    test('a field of the wrong type', () {
      final json = sample().toJson()..['elapsedMicros'] = 'soon';

      expect(RunSnapshot.tryParse(jsonEncode(json)), isNull);
    });

    test('a split of the wrong type', () {
      final json = sample().toJson()..['splitMicros'] = [1, 'two', 3];

      expect(RunSnapshot.tryParse(jsonEncode(json)), isNull);
    });

    test('an unknown state', () {
      final json = sample().toJson()..['state'] = 'flyback';

      expect(RunSnapshot.tryParse(jsonEncode(json)), isNull);
    });

    test('idle, which is the absence of a run', () {
      final json = sample().toJson()..['state'] = 'idle';

      expect(RunSnapshot.tryParse(jsonEncode(json)), isNull);
    });
  });

  group('MemoryRunStore', () {
    test('reads back what was written', () async {
      final store = MemoryRunStore();
      await store.write(sample());

      expect((await store.read())!.elapsed, sample().elapsed);
    });

    test('reads null before anything is written', () async {
      expect(await MemoryRunStore().read(), isNull);
    });

    test('clear removes the record', () async {
      final store = MemoryRunStore();
      await store.write(sample());
      await store.clear();

      expect(await store.read(), isNull);
    });
  });
}
