import 'package:flutter/material.dart';

import 'tokens.dart';

/// The `ui2` theme — the prototype's design language. Parallel to
/// `yeshshreeTheme()` in `lib/core/theme.dart` (which it will eventually
/// replace). Screens mostly use explicit `F.*` text styles from `tokens.dart`;
/// this sets the defaults (Hind body font, accent seed, screen surface).
ThemeData theme2() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Hind',
    colorScheme: ColorScheme.fromSeed(
      seedColor: Y2.accent,
      primary: Y2.accent,
      surface: Y2.screen,
    ),
    scaffoldBackgroundColor: Y2.navy,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Hind',
      bodyColor: Y2.ink,
      displayColor: Y2.ink,
    ),
  );
}
