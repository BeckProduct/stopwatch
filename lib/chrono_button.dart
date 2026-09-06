import 'package:flutter/material.dart';

import 'chrono_theme.dart';

/// One of the three controls below the dial.
///
/// [onTap] is always live, even when [enabled] is false: the mechanism refuses
/// the press itself and answers with a haptic and a stub of travel, so a
/// button that swallowed the tap at the widget layer would lose that. What
/// [enabled] drives is the semantics node -- VoiceOver hears a disabled
/// control while nothing on screen dims.
class ChronoButton extends StatelessWidget {
  const ChronoButton({
    super.key,
    required this.travel,
    required this.text,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  /// Depression, 0..1. The screen drives full travel for a press the mechanism
  /// accepts and a stub for one it refuses, so the two do not feel alike.
  final Animation<double> travel;

  /// What the button says.
  final String text;

  /// What VoiceOver says, which is not always the same thing.
  final String label;

  final bool enabled;
  final VoidCallback onTap;

  static const double height = 44;
  static const double width = 100;

  @override
  Widget build(BuildContext context) {
    final chrono = ChronoTheme.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      // Busy stays enabled: the press is swallowed, not refused.
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: height,
          child: AnimatedBuilder(
            animation: travel,
            builder: (context, child) => Transform.scale(
              // The press the mechanism refuses barely moves; the one it takes
              // goes all the way down.
              scale: 1 - travel.value * 0.03,
              child: child,
            ),
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: chrono.steel3,
                foregroundColor: chrono.dial0,
                padding: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
              child: Text(
                text,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: chrono.dial0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
