import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'chrono_geometry.dart';
import 'chrono_painter.dart';
import 'chrono_theme.dart';
import 'chrono_button.dart';
import 'rattrapante.dart';
import 'run_persistence.dart';
import 'run_session.dart';
import 'timing_engine.dart';

/// The chronograph. One screen: the dial, the pushers under it, the readout,
/// the laps under that.
class ChronoScreen extends StatefulWidget {
  const ChronoScreen({super.key, this.session});

  /// Injectable so a test can drive both clocks and an in-memory store.
  final RunSession? session;

  @override
  State<ChronoScreen> createState() => _ChronoScreenState();
}

class _ChronoScreenState extends State<ChronoScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final RunSession _session =
      widget.session ?? RunSession(store: PreferencesRunStore());

  /// [RunSession.restore] replaces the engine wholesale, so this is read fresh
  /// every time rather than held in a field.
  TimingEngine get _engine => _session.engine;

  /// The same monotonic clock the engine runs on. Two clocks here would let the
  /// split hand's animation and the sweep hand's angle disagree.
  late final RattrapanteController _split = RattrapanteController(
    clock: _session.monotonic,
  );
  late final Ticker _ticker = createTicker(_onFrame);

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
    _restore();
  }

  /// A run left by a previous launch is picked up before the first frame the
  /// user can act on.
  Future<void> _restore() async {
    await _session.restore();
    if (!mounted) return;
    setState(_syncTicker);
  }

  /// One frame. The mechanism advances here, never in [build] -- reading an
  /// angle must not fire haptics or rebuild the tree mid-build.
  void _onFrame(Duration _) {
    _split.advance(_engine.elapsed, reduceMotion: _reduceMotion);
    setState(_syncTicker);
  }

  /// The ticker runs while something is moving: the chronograph itself, or a
  /// split hand still catching up on a stopped one. Left running at idle it
  /// rebuilds the whole dial at the display's refresh rate forever.
  void _syncTicker() {
    final wanted = _engine.isRunning || _split.isCatchingUp;
    if (wanted && !_ticker.isActive) {
      _ticker.start();
    } else if (!wanted && _ticker.isActive) {
      _ticker.stop();
    }
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
    if (mounted) setState(_syncTicker);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _session.handleSuspend();
      case AppLifecycleState.resumed:
        // A whip that finished while the app was away never happened on
        // screen. Drop the hand home rather than animating a stale one.
        if (_split.isCatchingUp) _split.cancelToJoined();
        _session.handleResume();
        setState(_syncTicker);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  /// [ID-11]. Always enabled, always full travel.
  Future<void> _pressStart() async {
    HapticFeedback.mediumImpact();
    _travel(_startTravel, 1);
    if (_engine.isRunning) {
      await _session.stop();
    } else {
      await _session.start();
    }
    if (mounted) setState(_syncTicker);
  }

  /// The last crown press the mechanism accepted. A rattrapante's pincers
  /// cannot be worked faster than this, and a double-tap that freezes and
  /// releases in the same gesture reads as the hand not having moved at all.
  Duration _lastCrownPress = const Duration(days: -1);
  static const Duration _crownDebounce = Duration(milliseconds: 120);

  /// Set from the moment a crown press claims the mechanism until it has
  /// finished writing.
  ///
  /// The toggle's next state is read off [_split], and the freeze branch does
  /// not move [_split] until `_session.split()` has persisted. That await is a
  /// disk write, not a frame -- long enough on a slow store to outlast the
  /// debounce. A second press inside the window would read `joined` a second
  /// time and record a second mark, and a third a third: the presses are far
  /// enough apart that each mark advances the dial, so the engine's own guard
  /// cannot see them for what they are. The window has to be closed here,
  /// where the press is.
  bool _crownInFlight = false;

  /// [ID-12]. Disabled at idle, swallowed while a catch-up is in flight.
  Future<void> _pressCrown() async {
    // Debounced on every tap, the disabled stub included.
    final now = _session.monotonic.now;
    if (now - _lastCrownPress < _crownDebounce) return;
    _lastCrownPress = now;

    if (_engine.state == TimingState.idle) {
      // "ignored": disabled, but the head still gives a stub of travel so the
      // finger knows it was heard.
      HapticFeedback.lightImpact();
      _travel(_crownTravel, 0.35);
      return;
    }
    // "busy": enabled, press swallowed. No travel, no haptic, no state change.
    // A press still working through its persist is busy too -- see
    // [_crownInFlight].
    if (_split.isCatchingUp || _crownInFlight) return;

    _travel(_crownTravel, 1);
    _crownInFlight = true;
    try {
      if (_split.state == SplitState.joined) {
        // The mark is recorded through the session, so a lap survives a
        // force-quit along with the run it belongs to.
        _split.freeze(await _session.split());
      } else {
        _split.release(elapsed: _engine.elapsed, reduceMotion: _reduceMotion);
      }
    } finally {
      _crownInFlight = false;
    }
    if (mounted) setState(_syncTicker);
  }

  /// [ID-13]. Live unless running, where the mechanism refuses it.
  Future<void> _pressReset() async {
    if (_engine.isRunning) {
      // "blocked": enabled to the eye, refused by the mechanism. A hard stop
      // after a fraction of the travel.
      HapticFeedback.lightImpact();
      _travel(_resetTravel, 0.06);
      return;
    }
    HapticFeedback.heavyImpact();
    _travel(_resetTravel, 1);
    _split.reset();
    // Reset is live at idle and changes nothing there -- the engine refuses it
    // and the record is already clear.
    if (_engine.state == TimingState.stopped) await _session.reset();
    if (mounted) setState(_syncTicker);
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
    final splitDeg = _split.angleAt(elapsed, reduceMotion: reduceMotion);
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The box is square now that the case is gone. The dial gives way
              // to the pushers and the readout on a short screen rather than
              // overflowing them, and is capped a shade under 320 -- about 9%
              // down on the cased face, which is the breathing room.
              final side = math
                  .min(constraints.maxWidth - 32, constraints.maxHeight * 0.46)
                  .clamp(0.0, 318.0);
              return Column(
                children: [
                  _dial(chrono, elapsed, splitDeg, reduceMotion, side),
                  const SizedBox(height: 14),
                  _controls(),
                  const SizedBox(height: 10),
                  _readout(chrono, elapsed, splits, laps),
                  Expanded(child: _lapStack(chrono, splits, laps)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _dial(
    ChronoTheme chrono,
    Duration elapsed,
    double splitDeg,
    bool reduceMotion,
    double side,
  ) {
    return SizedBox(
      width: side,
      height: side * Dial.boxHeight / Dial.boxWidth,
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: ChronoPainter(
            theme: chrono,
            elapsed: elapsed,
            splitDeg: splitDeg,
            splitState: _split.state,
            reduceMotion: reduceMotion,
            smearFromDeg: _split.smearFrom,
            splitFade: _split.splitOpacity,
          ),
        ),
      ),
    );
  }

  /// The three controls, below the face. Left to right in the order they sat
  /// on the case: start above the crown, reset below it.
  Widget _controls() {
    final running = _engine.isRunning;
    final frozen = _split.state == SplitState.frozen;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ChronoButton(
          travel: _startTravel,
          text: running ? 'STOP' : 'START',
          label: running ? 'Stop' : 'Start',
          enabled: true,
          onTap: _pressStart,
        ),
        const SizedBox(width: 12),
        ChronoButton(
          travel: _crownTravel,
          text: frozen ? 'REJOIN' : 'SPLIT',
          label: frozen ? 'Rejoin split hand' : 'Split',
          enabled: _engine.state != TimingState.idle,
          onTap: _pressCrown,
        ),
        const SizedBox(width: 12),
        ChronoButton(
          travel: _resetTravel,
          text: 'RESET',
          label: 'Reset',
          // "blocked" is semantically disabled even though nothing dims.
          enabled: !running,
          onTap: _pressReset,
        ),
      ],
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
