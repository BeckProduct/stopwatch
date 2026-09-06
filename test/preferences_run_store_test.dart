import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:stopwatch/run_persistence.dart';
import 'package:stopwatch/timing_engine.dart';

/// Exercises the real [PreferencesRunStore] against a real
/// [SharedPreferencesAsync], with only the platform channel replaced.
void main() {
  const key = 'stopwatch.inFlightRun';
  final takenAt = DateTime.utc(2026, 9, 6, 12);

  late InMemorySharedPreferencesAsync backing;
  late PreferencesRunStore store;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    backing = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = backing;
    store = PreferencesRunStore();
  });

  RunSnapshot sample({
    Duration elapsed = const Duration(seconds: 90),
    List<Duration> splits = const [Duration(seconds: 30)],
  }) => RunSnapshot(
    state: TimingState.running,
    elapsed: elapsed,
    splits: splits,
    takenAt: takenAt,
  );

  Future<String?> raw() => SharedPreferencesAsync().getString(key);

  Future<void> seed(String value) =>
      SharedPreferencesAsync().setString(key, value);

  test('reads back a record it wrote', () async {
    await store.write(sample());

    final read = await store.read();

    expect(read, isNotNull);
    expect(read!.state, TimingState.running);
    expect(read.elapsed, const Duration(seconds: 90));
    expect(read.splits, const [Duration(seconds: 30)]);
    expect(read.takenAt.toUtc(), takenAt);
  });

  test('reads null when nothing was ever written', () async {
    expect(await store.read(), isNull);
  });

  test('write replaces the previous record rather than accumulating', () async {
    await store.write(
      sample(elapsed: const Duration(seconds: 10), splits: const []),
    );
    await store.write(
      sample(elapsed: const Duration(seconds: 20), splits: const []),
    );

    expect((await store.read())!.elapsed, const Duration(seconds: 20));
  });

  test('clear removes the record from the store', () async {
    await store.write(sample());
    await store.clear();

    expect(await raw(), isNull);
    expect(await store.read(), isNull);
  });

  group('a record that cannot be read is discarded from disk', () {
    /// Every one of these must leave the store *empty*, not merely return null.
    /// A bad record that survives is re-read on every subsequent launch.
    Future<void> expectDiscarded(String badRecord) async {
      await seed(badRecord);

      expect(await store.read(), isNull, reason: 'must not be restored');
      expect(
        await raw(),
        isNull,
        reason: 'must not survive to the next launch',
      );
    }

    test('not JSON at all', () => expectDiscarded('}{ truncated'));

    test('a truncated write', () async {
      final whole = jsonEncode(sample().toJson());
      await expectDiscarded(whole.substring(0, whole.length ~/ 2));
    });

    test('a future version', () async {
      final json = sample().toJson()..['version'] = 99;
      await expectDiscarded(jsonEncode(json));
    });

    test('maxInt takenAt, which throws inside DateTime', () async {
      final json = sample().toJson()..['takenAtMicros'] = 9223372036854775807;
      await expectDiscarded(jsonEncode(json));
    });

    test('a negative elapsed', () async {
      final json = sample().toJson()..['elapsedMicros'] = -1;
      await expectDiscarded(jsonEncode(json));
    });

    test('splits out of order', () async {
      final json = sample().toJson()..['splitMicros'] = [-9999999, 5];
      await expectDiscarded(jsonEncode(json));
    });
  });

  test('a readable record is left exactly where it is', () async {
    await store.write(sample());
    final before = await raw();

    await store.read();

    expect(await raw(), before);
  });
}
