/// Visual language lifted from the approved app map (Yeshshree_Operations_App_Map.html):
/// navy top bars, light slate background, white rounded cards, status colors
/// green/amber/red/purple, blue action buttons.
import 'package:flutter/material.dart';

class YColors {
  static const navy = Color(0xFF1E3A5F); // top bars, headings
  static const blue = Color(0xFF1E40AF); // primary actions
  static const blueBg = Color(0xFFDBEAFE);
  static const bg = Color(0xFFF1F5F9); // scaffold background
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const line = Color(0xFFE2E8F0); // card borders

  static const green = Color(0xFF15803D); // good / confirmed / on-track
  static const greenBg = Color(0xFFDCFCE7);
  static const amber = Color(0xFFC2410C); // warning / at risk
  static const amberBg = Color(0xFFFEF3C7);
  static const red = Color(0xFFB91C1C); // problem / blocked
  static const redBg = Color(0xFFFEE2E2);
  static const purple = Color(0xFF7C3AED); // new module / special
  static const purpleBg = Color(0xFFEDE9FE);
}

ThemeData yeshshreeTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: YColors.blue,
      primary: YColors.blue,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: YColors.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: YColors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardTheme(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: YColors.line),
      ),
      margin: const EdgeInsets.only(bottom: 8),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: YColors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: YColors.blue,
      unselectedItemColor: YColors.muted,
      type: BottomNavigationBarType.fixed,
    ),
  );
}

/// Status → (fg, bg) used by badges/cards everywhere, matching the app map legend.
({Color fg, Color bg}) statusColors(String kind) => switch (kind) {
      'ok' || 'green' || 'posted' || 'matched' || 'confirmed' || 'approved' ||
      'resolved' || 'sent' || 'acked' || 'completed' || 'released' =>
        (fg: YColors.green, bg: YColors.greenBg),
      'warn' || 'amber' || 'soft' || 'pending' || 'waiver_pending' || 'hold' ||
      'unmatched' || 'batched' || 'in_review' || 'draft' =>
        (fg: YColors.amber, bg: YColors.amberBg),
      'bad' || 'red' || 'hard' || 'failed' || 'declined' || 'blocked' ||
      'cancelled' || 'mismatch' => (fg: YColors.red, bg: YColors.redBg),
      'new' || 'purple' || 'overridden' || 'override_review' =>
        (fg: YColors.purple, bg: YColors.purpleBg),
      _ => (fg: YColors.blue, bg: YColors.blueBg),
    };
