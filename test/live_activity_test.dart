import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/live_activity.dart';
import 'package:stopwatch/run_persistence.dart';
import 'package:stopwatch/run_session.dart';

import 'support/clock_pair.dart';

/// Records what the session pushed, without a platform channel under it.
class RecordingBridge extends LiveActivityBridge {
  RecordingBridge() : super(channel: const MethodChannel('test/absent'));

  final List<String> methods = <String>[];
  final List<LiveActivityPayload> payloads = <LiveActivityPayload>[];

  @override
  Future<bool> start(LiveActivityPayload payload) async {
    methods.add('start');
    payloads.add(payload);
    return true;
  }

  @override
  Future<bool> update(LiveActivityPayload payload) async {
    methods.add('update');
    payloads.add(payload);
    return true;
  }

  @override
  Future<bool> end() async {
    methods.add('end');
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 9, 6, 12, 0, 0);

  group('LiveActivityPayload.forRun', () {
    test('anchors the start date elapsed-time before now', () {
      final payload = LiveActivityPayload.forRun(
        elapsed: const Duration(minutes: 3, seconds: 20),
        isRunning: true,
        lapCount: 0,
        now: now,
      );

      expect(payload.startDate, DateTime.utc(2026, 9, 6, 11, 56, 40));
    });

    test('leaves pausedElapsed null while running, so the widget ticks', () {
      final payload = LiveActivityPayload.forRun(
        elapsed: const Duration(seconds: 5),
        isRunning: true,
        lapCount: 2,
        now: now,
      );

      expect(payload.pausedElapsed, isNull);
      expect(payload.lapCount, 2);
    });

    test('carries the frozen total while stopped', () {
      final payload = LiveActivityPayload.forRun(
        elapsed: const Duration(seconds: 90),
        isRunning: false,
        lapCount: 1,
        now: now,
      );

      expect(payload.pausedElapsed, const Duration(seconds: 90));
      // Still anchored, so the two fields cannot disagree about the total.
      expect(payload.startDate, DateTime.utc(2026, 9, 6, 11, 58, 30));
    });

    test('re-anchors on each derivation rather than drifting', () {
      final first = LiveActivityPayload.forRun(
        elapsed: const Duration(seconds: 10),
        isRunning: true,
        lapCount: 0,
        now: now,
      );
      // A run resumed after 30 s stopped: 10 s more on the dial, 40 s of wall
      // clock gone. The anchor must move forward by the 30 s not counted.
      final second = LiveActivityPayload.forRun(
        elapsed: const Duration(seconds: 20),
        isRunning: true,
        lapCount: 0,
        now: now.add(const Duration(seconds: 40)),
      );

      expect(
        second.startDate.difference(first.startDate),
        const Duration(seconds: 30),
      );
    });

    test('sends seconds on the wire', () {
      final arguments = LiveActivityPayload.forRun(
        elapsed: const Duration(milliseconds: 2500),
        isRunning: false,
        lapCount: 3,
        now: now,
      ).toArguments();

      // Anchored 2.5 s before now, not at now.
      expect(arguments['startDate'], now.millisecondsSinceEpoch / 1000 - 2.5);
      expect(arguments['pausedElapsed'], 2.5);
      expect(arguments['lapCount'], 3);
    });
  });

  group('LiveActivityBridge', () {
    late MethodChannel channel;
    late List<MethodCall> calls;

    void answerWith(Object? Function(MethodCall) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return handler(call);
          });
    }

    setUp(() {
      channel = const MethodChannel(LiveActivityBridge.channelName);
      calls = <MethodCall>[];
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('start sends the payload and reports the native answer', () async {
      answerWith((_) => true);
      final bridge = LiveActivityBridge(channel: channel);

      final started = await bridge.start(
        LiveActivityPayload.forRun(
          elapsed: Duration.zero,
          isRunning: true,
          lapCount: 0,
          now: now,
        ),
      );

      expect(started, isTrue);
      expect(calls.single.method, 'start');
      expect(
        (calls.single.arguments as Map)['startDate'],
        now.millisecondsSinceEpoch / 1000,
      );
    });

    test('end sends end', () async {
      answerWith((_) => true);

      await LiveActivityBridge(channel: channel).end();

      expect(calls.single.method, 'end');
      expect(calls.single.arguments, isNull);
    });

    test('reports false when the platform refuses the activity', () async {
      // areActivitiesEnabled == false, or the system limit hit.
      answerWith((_) => false);

      expect(await LiveActivityBridge(channel: channel).isSupported(), isFalse);
    });

    test('swallows a platform error rather than failing the run', () async {
      answerWith((_) => throw PlatformException(code: 'unavailable'));

      expect(
        await LiveActivityBridge(channel: channel).end(),
        isFalse,
        reason: 'a failed mirror must never take the chronograph down',
      );
    });

    test('swallows a missing native side', () async {
      // No mock handler registered: exactly what a widget test with no
      // platform sees.
      expect(
        await LiveActivityBridge(
          channel: const MethodChannel('beck.stopwatch/absent'),
        ).end(),
        isFalse,
      );
    });
  });

  group('RunSession mirrors the run', () {
    late ClockPair clocks;
    late RecordingBridge bridge;
    late RunSession session;

    setUp(() {
      clocks = ClockPair();
      bridge = RecordingBridge();
      session = RunSession(
        store: MemoryRunStore(),
        monotonic: clocks.monotonic,
        wall: clocks.wall,
        liveActivity: bridge,
      );
    });

    test('start requests the activity, later transitions update it', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 5));
      await session.split();
      await session.stop();

      expect(bridge.methods, <String>['start', 'update', 'update']);
    });

    test('reset ends it', () async {
      await session.start();
      await session.stop();
      await session.reset();

      expect(bridge.methods.last, 'end');
    });

    test('a second run after a reset requests a fresh activity', () async {
      await session.start();
      await session.stop();
      await session.reset();
      await session.start();

      // Not 'update': the previous activity was ended, so updating it would
      // push into nothing and the Lock Screen would stay blank.
      expect(bridge.methods, <String>['start', 'update', 'end', 'start']);
    });

    test('the pushed anchor tracks the dial across a stop', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 30));
      await session.stop();

      final stopped = bridge.payloads.last;
      expect(stopped.pausedElapsed, const Duration(seconds: 30));
      expect(
        stopped.startDate,
        clocks.wall.now.subtract(stopped.pausedElapsed!),
      );
    });

    test('the split count reaches the activity', () async {
      await session.start();
      await session.split();
      // The dial has to move between the two, or the second mark repeats the
      // first and the engine drops it -- a second lap needs a second instant.
      clocks.advance(const Duration(milliseconds: 10));
      await session.split();

      expect(bridge.payloads.last.lapCount, 2);
    });

    test('a resume correction re-anchors the activity', () async {
      await session.start();
      clocks.advance(const Duration(seconds: 1));
      await session.handleSuspend();
      // The monotonic clock stopped while the device slept: the engine is
      // credited the shortfall and the dial jumps.
      clocks.advanceWallOnly(const Duration(minutes: 4));
      final before = bridge.methods.length;

      session.handleResume();
      await Future<void>.delayed(Duration.zero);

      expect(bridge.methods.length, before + 1);
      final anchor = bridge.payloads.last.startDate;
      // Anchored the full 4m01s back, not 1s: the mirror carries the
      // correction, or the Lock Screen trails the face by the whole gap.
      expect(
        clocks.wall.now.difference(anchor),
        const Duration(minutes: 4, seconds: 1),
      );
    });

    test('a restored run gets its mirror back', () async {
      final store = MemoryRunStore();
      final first = RunSession(
        store: store,
        monotonic: clocks.monotonic,
        wall: clocks.wall,
        liveActivity: RecordingBridge(),
      );
      await first.start();
      clocks.advance(const Duration(seconds: 12));
      await first.handleSuspend();

      // A relaunch: new process, nothing on screen yet.
      final relaunched = RunSession(
        store: store,
        monotonic: clocks.monotonic,
        wall: clocks.wall,
        liveActivity: bridge,
      );
      await relaunched.restore();

      expect(bridge.methods, <String>['start']);
      expect(bridge.payloads.single.pausedElapsed, isNull);
    });

    test('an idle session with no record pushes nothing on restore', () async {
      await session.restore();

      expect(bridge.methods, isEmpty);
    });
  });
}
