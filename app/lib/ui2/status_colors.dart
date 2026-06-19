import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// `ui2` status palette — same shape as the existing `statusColors()` in
/// `lib/core/theme.dart`, but in the prototype's colors. Maps a status string
/// to (foreground, background-tint, hairline-border).
({Color fg, Color bg, Color line}) statusColors2(String kind) => switch (kind) {
      'ok' || 'green' || 'synced' || 'posted' || 'matched' || 'confirmed' ||
      'approved' || 'resolved' || 'on_station' || 'released' =>
        (fg: Y2.green, bg: Y2.greenTint, line: Y2.greenLine),
      'warn' || 'amber' || 'orange' || 'pending' || 'hold' || 'parked' ||
      'unmatched' || 'over_plan' || 'draft' =>
        (fg: Y2.orange, bg: Y2.orangeTint, line: Y2.orangeLine),
      'bad' || 'red' || 'hard' || 'failed' || 'offline' || 'blocked' ||
      'declined' || 'critical' =>
        (fg: Y2.red, bg: Y2.redTint, line: Y2.redLine),
      _ => (fg: Y2.accent, bg: Color(0x141D4ED8), line: Color(0x331D4ED8)),
    };
