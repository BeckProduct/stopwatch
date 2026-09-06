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

  test('the cache holds one entry per string per theme, and no more', () {
    final light = chronoThemeData(Brightness.light).extension<ChronoTheme>()!;
    final dark = chronoThemeData(Brightness.dark).extension<ChronoTheme>()!;

    ChronoPainter painterFor(ChronoTheme theme, int i) => ChronoPainter(
      theme: theme,
      elapsed: Duration(milliseconds: i * 17),
      splitDeg: (i * 7) % 360,
      splitState: SplitState.joined,
      reduceMotion: false,
      smearFromDeg: null,
      splitFade: 1,
    );

    paintOnce(painterFor(light, 0));
    final perTheme = ChronoPainter.textCacheSize;
    expect(perTheme, greaterThan(10));

    // Sixty frames of each theme, at sixty elapsed values, plus every step of
    // a light-to-dark transition. Nothing the app can do keys a third theme's
    // worth of entries: no dial style carries an animated value, and
    // ChronoTheme.lerp snaps rather than interpolating. Were either to change,
    // this count would climb with the frame number instead of standing still.
    for (var i = 0; i <= 60; i++) {
      paintOnce(painterFor(light, i));
      paintOnce(painterFor(dark, i));
      paintOnce(painterFor(light.lerp(dark, i / 60), i));
    }
    expect(ChronoPainter.textCacheSize, perTheme * 2);
  });
}
