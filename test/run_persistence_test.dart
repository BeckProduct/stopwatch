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
        encoded(
          sample(elapsed: const Duration(microseconds: 1), splits: const []),
        ),
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

  group('the domain is checked, not just the types', () {
    /// The parser is the boundary. Everything downstream does plain arithmetic
    /// and trusts these bounds, so a value that gets past here is a value the
    /// whole app has to defend against separately.
    void expectRejected(String what, Map<String, Object?> Function() build) {
      test(
        what,
        () => expect(RunSnapshot.tryParse(jsonEncode(build())), isNull),
      );
    }

    expectRejected(
      'a negative elapsed',
      () => sample().toJson()..['elapsedMicros'] = -1,
    );

    expectRejected(
      'an elapsed longer than a run can be',
      () =>
          sample().toJson()
            ..['elapsedMicros'] = RunSnapshot.maxRun.inMicroseconds + 1,
    );

    expectRejected(
      'a maxInt elapsed, which overflows every sum downstream',
      () => sample().toJson()..['elapsedMicros'] = 9223372036854775807,
    );

    expectRejected(
      'a maxInt instant, which throws inside DateTime',
      () => sample().toJson()..['takenAtMicros'] = 9223372036854775807,
    );

    expectRejected(
      'a minInt instant',
      () => sample().toJson()..['takenAtMicros'] = -9223372036854775808,
    );

    expectRejected(
      'an instant before the app could have written one',
      () => sample().toJson()
        ..['takenAtMicros'] =
            RunSnapshot.earliestSaneInstant.microsecondsSinceEpoch - 1,
    );

    expectRejected(
      'an instant past the sane window',
      () => sample().toJson()
        ..['takenAtMicros'] =
            RunSnapshot.latestSaneInstant.microsecondsSinceEpoch + 1,
    );

    expectRejected(
      'a negative split, which parses to a negative lap',
      () => sample().toJson()..['splitMicros'] = [-9999999, 5],
    );

    expectRejected(
      'splits out of order, which parse to a negative lap',
      () => sample().toJson()
        ..['splitMicros'] = [
          const Duration(seconds: 40).inMicroseconds,
          const Duration(seconds: 20).inMicroseconds,
        ],
    );

    expectRejected(
      'a split past the dial reading',
      () =>
          sample(elapsed: const Duration(seconds: 10)).toJson()
            ..['splitMicros'] = [const Duration(seconds: 11).inMicroseconds],
    );

    expectRejected(
      'more splits than a person could press',
      () =>
          sample().toJson()
            ..['splitMicros'] = List<int>.filled(RunSnapshot.maxSplits + 1, 0),
    );

    test('the boundary values themselves are accepted', () {
      final json = sample().toJson()
        ..['elapsedMicros'] = RunSnapshot.maxRun.inMicroseconds
        ..['splitMicros'] = [0, RunSnapshot.maxRun.inMicroseconds]
        ..['takenAtMicros'] =
            RunSnapshot.earliestSaneInstant.microsecondsSinceEpoch;

      final parsed = RunSnapshot.tryParse(jsonEncode(json));

      expect(parsed, isNotNull);
      expect(parsed!.elapsed, RunSnapshot.maxRun);
      expect(parsed.splits.last, RunSnapshot.maxRun);
    });

    test('a zero-elapsed run with no splits is a real record', () {
      final json = sample().toJson()
        ..['elapsedMicros'] = 0
        ..['splitMicros'] = <int>[];

      expect(RunSnapshot.tryParse(jsonEncode(json)), isNotNull);
    });

    test('splits equal to each other are allowed, being a zero lap', () {
      final json = sample().toJson()..['splitMicros'] = [5000, 5000];

      expect(RunSnapshot.tryParse(jsonEncode(json))!.splits, hasLength(2));
    });
  });

  test('no input makes the parser throw', () {
    // The contract the store depends on: tryParse answers, it never raises.
    // Systematic truncation covers a write killed part-way; single-character
    // substitution covers a record corrupted in place.
    final whole = jsonEncode(sample().toJson());
    final corpus = <String>[
      '',
      ' ',
      'null',
      'true',
      '[]',
      '{}',
      '"a bare string"',
      '{"version":1}',
      '\u0000',
      for (var i = 0; i <= whole.length; i++) whole.substring(0, i),
      for (var i = 0; i < whole.length; i++) whole.replaceRange(i, i + 1, 'X'),
      for (var i = 0; i < whole.length; i++) whole.replaceRange(i, i + 1, '9'),
    ];

    for (final input in corpus) {
      expect(
        () => RunSnapshot.tryParse(input),
        returnsNormally,
        reason: 'threw on: $input',
      );
    }
  });
}
