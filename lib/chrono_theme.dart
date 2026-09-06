import 'package:flutter/material.dart';

/// The chronograph's palette.
///
/// `ColorScheme` has no role for "dial plate" or "sub-register azurage", so the
/// dial's colours live here instead of being flattened into surface/onSurface.
/// Only three values map to the stock scheme: [env] to `surface`, [accent1] to
/// `primary`, [readout] to `onSurface`.
@immutable
class ChronoTheme extends ThemeExtension<ChronoTheme> {
  const ChronoTheme({
    required this.env,
    required this.envEdge,
    required this.dial0,
    required this.dial1,
    required this.dial2,
    required this.reg0,
    required this.reg1,
    required this.regRing,
    required this.regHand,
    required this.regLabel,
    required this.ink,
    required this.inkSoft,
    required this.accent0,
    required this.accent1,
    required this.rat0,
    required this.rat1,
    required this.lume,
    required this.lumeGlow,
    required this.steel0,
    required this.steel1,
    required this.steel2,
    required this.steel3,
    required this.bez0,
    required this.bez1,
    required this.bez2,
    required this.bezText,
    required this.readout,
    required this.readoutDim,
    required this.glareOpacity,
  });

  final Color env;
  final Color envEdge;
  final Color dial0;
  final Color dial1;
  final Color dial2;
  final Color reg0;
  final Color reg1;
  final Color regRing;
  final Color regHand;
  final Color regLabel;
  final Color ink;
  final Color inkSoft;
  final Color accent0;
  final Color accent1;
  final Color rat0;
  final Color rat1;
  final Color lume;

  /// Blur sigma multiplier for the lume bloom: 0 in light, 1 in dark.
  final double lumeGlow;

  final Color steel0;
  final Color steel1;
  final Color steel2;
  final Color steel3;
  final Color bez0;
  final Color bez1;
  final Color bez2;
  final Color bezText;
  final Color readout;
  final Color readoutDim;
  final double glareOpacity;

  static const ChronoTheme light = ChronoTheme(
    env: Color(0xFFD6D7D9),
    envEdge: Color(0xFFBFC2C6),
    dial0: Color(0xFFF6F4EE),
    dial1: Color(0xFFF1EFE8),
    dial2: Color(0xFFDCD8CD),
    reg0: Color(0xFF26262E),
    reg1: Color(0xFF101015),
    regRing: Color(0xFF3A3A44),
    regHand: Color(0xFFEFEDE7),
    regLabel: Color(0xFF8C8C96),
    ink: Color(0xFF141418),
    inkSoft: Color(0xFF3B3B42),
    accent0: Color(0xFFE23A50),
    accent1: Color(0xFFC8102E),
    rat0: Color(0xFF3A5A9E),
    rat1: Color(0xFF23407A),
    lume: Color(0xFFE5DCC2),
    lumeGlow: 0,
    steel0: Color(0xFFE7E9EC),
    steel1: Color(0xFFA8ADB4),
    steel2: Color(0xFFD2D6DB),
    steel3: Color(0xFF6E747C),
    bez0: Color(0xFF26262C),
    bez1: Color(0xFF101014),
    bez2: Color(0xFF050507),
    bezText: Color(0xFFEDEAE2),
    readout: Color(0xFF141418),
    readoutDim: Color(0xFF6B6B72),
    glareOpacity: 0.34,
  );

  static const ChronoTheme dark = ChronoTheme(
    env: Color(0xFF08090A),
    envEdge: Color(0xFF000000),
    dial0: Color(0xFFCCC8BE),
    dial1: Color(0xFFC4C0B6),
    dial2: Color(0xFFABA79D),
    reg0: Color(0xFF16161B),
    reg1: Color(0xFF0A0A0C),
    regRing: Color(0xFF2A2A32),
    regHand: Color(0xFFC9C5BC),
    regLabel: Color(0xFF6C6C74),
    ink: Color(0xFF0A0A0C),
    inkSoft: Color(0xFF2E2E34),
    accent0: Color(0xFFB41A32),
    accent1: Color(0xFF9E1226),
    rat0: Color(0xFF5478B8),
    rat1: Color(0xFF42639E),
    lume: Color(0xFF7FE3C8),
    lumeGlow: 1,
    steel0: Color(0xFF6E747C),
    steel1: Color(0xFF40454C),
    steel2: Color(0xFF585E66),
    steel3: Color(0xFF22262B),
    bez0: Color(0xFF131317),
    bez1: Color(0xFF0A0A0D),
    bez2: Color(0xFF000000),
    bezText: Color(0xFFB9B5AA),
    readout: Color(0xFFD6D2C8),
    readoutDim: Color(0xFF7A776F),
    glareOpacity: 0.10,
  );

  static ChronoTheme of(BuildContext context) =>
      Theme.of(context).extension<ChronoTheme>() ?? light;

  @override
  ChronoTheme copyWith() => this;

  @override
  ChronoTheme lerp(ThemeExtension<ChronoTheme>? other, double t) =>
      t < 0.5 ? this : (other as ChronoTheme? ?? this);
}

/// Builds the app theme for one brightness, with [ChronoTheme] attached.
ThemeData chronoThemeData(Brightness brightness) {
  final chrono = brightness == Brightness.dark
      ? ChronoTheme.dark
      : ChronoTheme.light;
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: chrono.env,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: chrono.accent1,
          brightness: brightness,
        ).copyWith(
          surface: chrono.env,
          primary: chrono.accent1,
          onSurface: chrono.readout,
        ),
    extensions: <ThemeExtension<dynamic>>[chrono],
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'IBMPlexMono',
        fontWeight: FontWeight.w500,
        fontSize: 64,
        height: 1.0,
        letterSpacing: -2.9,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      titleMedium: TextStyle(
        fontFamily: 'IBMPlexMono',
        fontWeight: FontWeight.w400,
        fontSize: 19,
        height: 1.2,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      bodyMedium: TextStyle(
        fontFamily: 'IBMPlexMono',
        fontWeight: FontWeight.w400,
        fontSize: 16,
        height: 1.25,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      labelSmall: TextStyle(
        fontFamily: 'Archivo',
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 1.76,
      ),
    ),
  );
}
