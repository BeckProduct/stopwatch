import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'chrono_geometry.dart';
import 'chrono_painter.dart';
import 'chrono_theme.dart';
import 'monotonic_clock.dart';
import 'rattrapante.dart';
import 'timing_engine.dart';

/// The chronograph. One screen: the watch, the readout under it, the laps
/// under that.
class ChronoScreen extends StatefulWidget {
  const ChronoScreen({super.key, this.engine, this.clock});

  /// Injectable so a widget test can drive the mechanism from a fake clock.
  final TimingEngine? engine;
  final MonotonicClock? clock;

  @override
  State<ChronoScreen> createState() => _ChronoScreenState();
}

class _ChronoScreenState extends State<ChronoScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final MonotonicClock _clock = widget.clock ?? SystemMonotonicClock();
  late final TimingEngine _engine =
      widget.engine ?? TimingEngine(clock: _clock);
  late final RattrapanteController _split = RattrapanteController(
    clock: _clock,
  );
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  /// Pusher depression, 0..1 of the 3-unit full travel. Released over 90 ms.
  late final AnimationController _startTravel = _travelController();
  late final AnimationController _crownTravel = _travelController();
  late final AnimationController _resetTravel = _travelController();

  AnimationController _travelController() => AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    value: 0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _split.addListener(_onSplitChanged);
    // The catch-up runs on the ticker, so the ticker has to be live for it even
    // when the chronograph itself is stopped.
    _ticker.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _split.removeListener(_onSplitChanged);
    _ticker.dispose();
    _startTravel.dispose();
    _crownTravel.dispose();
    _resetTravel.dispose();
    _split.dispose();
    super.dispose();
  }

  void _onSplitChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A whip that finished while the app was away never happened on screen.
    // Drop the hand home rather than animating a stale one.
    if (state == AppLifecycleState.resumed && _split.isCatchingUp) {
      _split.cancelToJoined();
    }
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  /// [ID-11]. Always enabled, always full travel.
  void _pressStart() {
    HapticFeedback.mediumImpact();
    _travel(_startTravel, 1);
    setState(() {
      if (_engine.isRunning) {
        _engine.stop();
      } else {
        _engine.start();
      }
    });
  }

  /// [ID-12]. Disabled at idle, swallowed while a catch-up is in flight.
  void _pressCrown() {
    if (_engine.state == TimingState.idle) {
      // "ignored": disabled, but the head still gives a stub of travel so the
      // finger knows it was heard.
      HapticFeedback.lightImpact();
      _travel(_crownTravel, 0.35);
      return;
    }
    // "busy": enabled, press swallowed. No travel, no haptic, no state change.
    if (_split.isCatchingUp) return;

    _travel(_crownTravel, 1);
    setState(() {
      if (_split.state == SplitState.joined) {
        _split.freeze(_engine.split());
      } else {
        _split.release(
          elapsed: _engine.elapsed,
          reduceMotion: _reduceMotion,
        );
      }
    });
  }

  /// [ID-13]. Live unless running, where the mechanism refuses it.
  void _pressReset() {
    if (_engine.isRunning) {
      // "blocked": enabled to the eye, refused by the mechanism. A hard stop
      // after a fraction of the travel.
      HapticFeedback.lightImpact();
      _travel(_resetTravel, 0.06);
      return;
    }
    HapticFeedback.heavyImpact();
    _travel(_resetTravel, 1);
    setState(() {
      _split.reset();
      if (_engine.state == TimingState.stopped) _engine.reset();
    });
  }

  void _travel(AnimationController c, double depth) {
    c
      ..value = depth
      ..animateTo(0, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    // One reading, one frame. Both hands and every digit come from this value,
    // or they disagree and the disagreement grows with the run.
    final elapsed = _engine.elapsed;
    final reduceMotion = _reduceMotion;
    final splitDeg = _split.angleFor(elapsed, reduceMotion: reduceMotion);
    final chrono = ChronoTheme.of(context);
    final splits = _engine.splits;
    final laps = _engine.lapTimes;

    return Scaffold(
      backgroundColor: chrono.env,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.9,
            colors: [chrono.env, chrono.envEdge],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _watch(chrono, elapsed, splitDeg, reduceMotion, splits.length),
              const SizedBox(height: 8),
              _readout(chrono, elapsed, splits, laps),
              Expanded(child: _lapStack(chrono, splits, laps)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _watch(
    ChronoTheme chrono,
    Duration elapsed,
    double splitDeg,
    bool reduceMotion,
    int lapCount,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth.clamp(0.0, 402.0);
        return SizedBox(
          width: side,
          height: side * Dial.boxHeight / Dial.boxWidth,
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _startTravel,
                      _crownTravel,
                      _resetTravel,
                    ]),
                    builder: (context, _) => CustomPaint(
                      painter: ChronoPainter(
                        theme: chrono,
                        elapsed: elapsed,
                        splitDeg: splitDeg,
                        splitState: _split.state,
                        lapCount: lapCount,
                        reduceMotion: reduceMotion,
                        pusherTravel: (
                          start: _startTravel.value,
                          crown: _crownTravel.value,
                          reset: _resetTravel.value,
                        ),
                        smearFromDeg: _split.smearsThisFrame
                            ? _split.previousDeg
                            : null,
                        splitFade: _split.isReducedMotionFade
                            ? (_split.fadeProgress < 0.5 ? 1.0 : 1.0)
                            : 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              // Case controls. Hit targets sit over the pushers on the right
              // flank; the painted heads move, the targets do not.
              _hit(
                top: 0.16,
                label: _engine.isRunning ? 'Stop' : 'Start',
                enabled: true,
                onTap: _pressStart,
              ),
              _hit(
                top: 0.42,
                label: _split.state == SplitState.frozen
                    ? 'Rejoin split hand'
                    : 'Split',
                enabled: _engine.state != TimingState.idle,
                busy: _split.isCatchingUp,
                onTap: _pressCrown,
              ),
              _hit(
                top: 0.66,
                label: 'Reset',
                // "blocked" is semantically disabled even though nothing dims.
                enabled: !_engine.isRunning,
                onTap: _pressReset,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _hit({
    required double top,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return Positioned(
      right: 0,
      top: top * 402,
      child: Semantics(
        button: true,
        enabled: enabled,
        // Busy stays enabled: the press is swallowed, not refused.
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(width: 52, height: busy ? 62 : 56),
        ),
      ),
    );
  }

  Widget _readout(
    ChronoTheme chrono,
    Duration elapsed,
    List<Duration> splits,
    List<Duration> laps,
  ) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            label: 'Elapsed ${formatElapsed(elapsed)}',
            excludeSemantics: true,
            child: Text(
              formatElapsed(elapsed),
              textAlign: TextAlign.center,
              style: text.displayLarge?.copyWith(color: chrono.readout),
            ),
          ),
          if (splits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Text(
                    'LAP ${splits.length}',
                    style: text.labelSmall?.copyWith(color: chrono.readoutDim),
                  ),
                  const Spacer(),
                  Text(
                    formatElapsed(splits.last),
                    style: text.titleMedium?.copyWith(color: chrono.readout),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    formatDelta(laps.last),
                    style: text.titleMedium?.copyWith(color: chrono.readoutDim),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _lapStack(
    ChronoTheme chrono,
    List<Duration> splits,
    List<Duration> laps,
  ) {
    final text = Theme.of(context).textTheme;
    if (splits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Text(
          'PRESS THE CROWN TO SPLIT',
          style: text.labelSmall?.copyWith(color: chrono.readoutDim),
        ),
      );
    }
    // Newest first, and the row already shown above the rule is not repeated.
    final count = splits.length - 1;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 24),
      itemCount: count,
      itemBuilder: (context, i) {
        final index = count - 1 - i;
        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            children: [
              Text(
                'LAP ${index + 1}',
                style: text.labelSmall?.copyWith(color: chrono.readoutDim),
              ),
              const Spacer(),
              Text(
                formatElapsed(splits[index]),
                style: text.bodyMedium?.copyWith(color: chrono.readout),
              ),
              const SizedBox(width: 16),
              Text(
                formatDelta(laps[index]),
                style: text.bodyMedium?.copyWith(color: chrono.readoutDim),
              ),
            ],
          ),
        );
      },
    );
  }
}
