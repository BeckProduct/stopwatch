import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'timing_engine.dart';

void main() {
  runApp(const StopwatchApp());
}

class StopwatchApp extends StatelessWidget {
  const StopwatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Stopwatch', home: EngineHarness());
  }
}

/// A deliberately plain screen that proves the engine ticks.
///
/// Not the chronograph and not a sketch of it — PAT-209 replaces this wholesale
/// against the UI spec. Nothing here is a design decision worth carrying
/// forward, but two things about it are worth keeping:
///
/// * it reads [TimingEngine.elapsed] exactly once per frame and derives
///   everything shown from that one value, and
/// * the ticker runs only while the engine does.
class EngineHarness extends StatefulWidget {
  const EngineHarness({super.key, this.engine});

  /// Injectable so a widget test can drive the clock behind it.
  final TimingEngine? engine;

  @override
  State<EngineHarness> createState() => _EngineHarnessState();
}

class _EngineHarnessState extends State<EngineHarness>
    with SingleTickerProviderStateMixin {
  late final TimingEngine _engine = widget.engine ?? TimingEngine();
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _toggleRun() {
    setState(() {
      if (_engine.isRunning) {
        _engine.stop();
        _ticker.stop();
      } else {
        _engine.start();
        _ticker.start();
      }
    });
  }

  void _split() => setState(_engine.split);

  void _reset() => setState(_engine.reset);

  @override
  Widget build(BuildContext context) {
    // One reading, one frame: every digit below comes from this value.
    final elapsed = _engine.elapsed;
    final laps = _engine.lapTimes;

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
            Text(_engine.state.name),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: _toggleRun,
                  child: Text(_engine.isRunning ? 'Stop' : 'Start'),
                ),
                OutlinedButton(
                  onPressed: _engine.isRunning ? _split : null,
                  child: const Text('Lap'),
                ),
                OutlinedButton(
                  onPressed: _engine.state == TimingState.stopped
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
