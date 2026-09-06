import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'run_persistence.dart';
import 'run_session.dart';
import 'timing_engine.dart';

void main() {
  // SharedPreferences needs the binding up before the first read.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StopwatchApp());
}

class StopwatchApp extends StatelessWidget {
  const StopwatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Stopwatch', home: EngineHarness());
  }
}

/// A deliberately plain screen that proves the engine ticks and survives.
///
/// Not the chronograph and not a sketch of it — PAT-209 replaces this wholesale
/// against the UI spec. What is worth carrying forward is not the layout but
/// the wiring: it reads [TimingEngine.elapsed] once per frame, runs the ticker
/// only while the engine does, and hands every lifecycle transition to
/// [RunSession].
class EngineHarness extends StatefulWidget {
  const EngineHarness({super.key, this.session});

  /// Injectable so tests drive the clocks and an in-memory store.
  final RunSession? session;

  @override
  State<EngineHarness> createState() => _EngineHarnessState();
}

class _EngineHarnessState extends State<EngineHarness>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final RunSession _session =
      widget.session ?? RunSession(store: PreferencesRunStore());
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  /// The last suspension's correction, surfaced only so the three lifecycle
  /// paths can be read off the screen while exercising them.
  Duration _lastCorrection = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  Future<void> _restore() async {
    await _session.restore();
    if (!mounted) return;
    setState(() {});
    if (_session.engine.isRunning) _ticker.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _session.handleSuspend();
      case AppLifecycleState.resumed:
        final correction = _session.handleResume();
        setState(() => _lastCorrection = correction);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _toggleRun() async {
    if (_session.engine.isRunning) {
      _ticker.stop();
      await _session.stop();
    } else {
      _ticker.start();
      await _session.start();
    }
    if (mounted) setState(() {});
  }

  Future<void> _split() async {
    await _session.split();
    if (mounted) setState(() {});
  }

  Future<void> _reset() async {
    await _session.reset();
    if (mounted) setState(() => _lastCorrection = Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final engine = _session.engine;
    // One reading, one frame: every digit below comes from this value.
    final elapsed = engine.elapsed;
    final laps = engine.lapTimes;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Text(
              _format(elapsed),
              style: const TextStyle(
                fontSize: 56,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(engine.state.name),
            Text('resume correction ${_lastCorrection.inMilliseconds}ms'),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: _toggleRun,
                  child: Text(engine.isRunning ? 'Stop' : 'Start'),
                ),
                OutlinedButton(
                  onPressed: engine.isRunning ? _split : null,
                  child: const Text('Lap'),
                ),
                OutlinedButton(
                  onPressed: engine.state == TimingState.stopped
                      ? _reset
                      : null,
                  child: const Text('Reset'),
                ),
              ],
            ),
            const Spacer(),
            Expanded(
              child: ListView.builder(
                itemCount: laps.length,
                itemBuilder: (context, index) {
                  final lap = laps[laps.length - 1 - index];
                  return ListTile(
                    dense: true,
                    title: Text('Lap ${laps.length - index}'),
                    trailing: Text(_format(lap)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _format(Duration d) {
  final minutes = d.inMinutes.toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  final hundredths = (d.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, '0');
  return '$minutes:$seconds.$hundredths';
}
