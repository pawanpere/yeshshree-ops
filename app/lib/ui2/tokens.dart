import 'package:flutter/widgets.dart';

/// Design tokens for the `ui2` layer — the prototype's visual language.
///
/// Every value here is lifted directly from the source prototype
/// `Yeshshree Ops - Prototype (standalone) (1).html` (inline styles), so the
/// rebuild matches the HTML. Do not invent values; read them from the file.
class Y2 {
  Y2._();

  // ---- Brand / surfaces ----
  static const accent = Color(0xFF1D4ED8); // var(--accent)
  static const navy = Color(0xFF11243F); // headings / ink
  static const navyDeep = Color(0xFF0A1626); // phone frame inner shell
  static const navyEdge = Color(0xFF060D18); // phone frame bezel border
  static const screen = Color(0xFFFBFCFE); // inner screen surface
  static const card = Color(0xFFFFFFFF);

  // ---- Text ----
  static const ink = Color(0xFF11243F);
  static const body = Color(0xFF516079);
  static const muted = Color(0xFF8190A6);
  static const muted2 = Color(0xFF8FA3C0);

  // ---- Lines / fills ----
  static const line = Color(0xFFE0E6EF);
  static const lineSoft = Color(0xFFEEF2F7); // progress track
  static const tabBorder = Color(0xFFC2C9D4); // inactive tab glyph border

  // ---- Status ----
  static const green = Color(0xFF0E9F6E);
  static const orange = Color(0xFFC2410C);
  static const red = Color(0xFFE02424);

  // Status tints (background + hairline border), from the prototype's rgba()s.
  static const greenTint = Color(0x1A0E9F6E); // rgba(14,159,110,.10)
  static const greenLine = Color(0x590E9F6E); // rgba(14,159,110,.35)
  static const orangeTint = Color(0x1AC2410C); // rgba(194,65,12,.10)
  static const orangeLine = Color(0x59C2410C); // rgba(194,65,12,.35)
  static const redTint = Color(0x0FE02424); // rgba(224,36,36,.06)
  static const redLine = Color(0xFFF3B4B4);

  // ---- Radii ----
  static const rPill = 7.0;
  static const rRow = 11.0; // task rows
  static const rCard = 13.0; // cockpit cards / stat tiles
  static const rIssue = 15.0; // secondary home cards
  static const rPrimary = 17.0; // home primary "record output" card
  static const rSheet = 18.0; // bottom sheet top corners
  static const rFrame = 48.0; // device bezel
  static const rScreen = 39.0; // inner screen surface

  // ---- Shadows ----
  static const shPrimary = <BoxShadow>[
    BoxShadow(color: Color(0x521D4ED8), blurRadius: 22, offset: Offset(0, 10)),
  ]; // 0 10px 22px rgba(29,78,216,.32)
  static const shFrame = <BoxShadow>[
    BoxShadow(color: Color(0x6B0A1626), blurRadius: 52, offset: Offset(0, 26)),
  ]; // 0 26px 52px rgba(10,22,38,.42)
}

/// Typed font builders that mirror the prototype's CSS `font:` shorthand
/// (`font: <weight> <size>px '<family>'`). Keeps call sites 1:1 with the HTML.
class F {
  F._();

  static TextStyle khand(double size,
          {FontWeight w = FontWeight.w600,
          double ls = 0,
          Color? color,
          double? height,
          TextDecoration? decoration}) =>
      TextStyle(
          fontFamily: 'Khand',
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls,
          color: color,
          height: height,
          decoration: decoration);

  static TextStyle hind(double size,
          {FontWeight w = FontWeight.w500,
          double ls = 0,
          Color? color,
          double? height,
          TextDecoration? decoration}) =>
      TextStyle(
          fontFamily: 'Hind',
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls,
          color: color,
          height: height,
          decoration: decoration);

  static TextStyle mono(double size,
          {FontWeight w = FontWeight.w500,
          double ls = 0,
          Color? color,
          double? height,
          TextDecoration? decoration}) =>
      TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls,
          color: color,
          height: height,
          decoration: decoration);
}
