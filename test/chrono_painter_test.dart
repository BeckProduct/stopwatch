import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/chrono_geometry.dart';
import 'package:stopwatch/chrono_painter.dart';
import 'package:stopwatch/chrono_theme.dart';
import 'package:stopwatch/rattrapante.dart';

void main() {
  ChronoPainter painterAt(Duration elapsed) => ChronoPainter(
    theme: chronoThemeData(Brightness.light).extension<ChronoTheme>()!,
    elapsed: elapsed,
    splitDeg: sweepDegFor(elapsed),
    splitState: SplitState.joined,
    reduceMotion: false,
    smearFromDeg: null,
    splitFade: 1,
  );

  /// Paints into a throwaway recorder, the way the widget layer would.
  void paintOnce(ChronoPainter painter) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(332, 332));
    recorder.endRecording().dispose();
  }

  setUp(ChronoPainter.clearTextCache);
  tearDown(ChronoPainter.clearTextCache);

  test('the dial text is laid out once and reused on later frames', () {
    expect(ChronoPainter.textCacheSize, 0);

    paintOnce(painterAt(Duration.zero));
    final afterFirstFrame = ChronoPainter.textCacheSize;
    // The signature, the dial foot and every register's numerals and label.
    expect(afterFirstFrame, greaterThan(10));

    // A second frame at a different elapsed value moves the hands and nothing
    // else: not one more string is typeset.
    paintOnce(painterAt(const Duration(milliseconds: 8300)));
    expect(ChronoPainter.textCacheSize, afterFirstFrame);

    for (var i = 0; i < 20; i++) {
      paintOnce(painterAt(Duration(milliseconds: 100 * i)));
    }
    expect(ChronoPainter.textCacheSize, afterFirstFrame);
  });

  test('a change of theme does not grow the cache without bound', () {
    // Every intermediate colour of a theme cross-fade is a distinct TextStyle.
    // The cache is emptied rather than allowed to keep all of them.
    final light = chronoThemeData(Brightness.light).extension<ChronoTheme>()!;
    final dark = chronoThemeData(Brightness.dark).extension<ChronoTheme>()!;
    for (var i = 0; i <= 60; i++) {
      final theme = light.lerp(dark, i / 60);
      paintOnce(
        ChronoPainter(
          theme: theme,
          elapsed: Duration(milliseconds: i * 17),
          splitDeg: 0,
          splitState: SplitState.joined,
          reduceMotion: false,
          smearFromDeg: null,
          splitFade: 1,
        ),
      );
    }
    expect(ChronoPainter.textCacheSize, greaterThan(0));
    expect(ChronoPainter.textCacheSize, lessThanOrEqualTo(64));
  });
}
