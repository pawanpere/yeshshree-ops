import 'dart:async';

import 'package:flutter/material.dart';

import '../tokens.dart';

/// GRN service-level timer (P-T). A gate entry must be receipted (GRN: quality +
/// quantity) within [grnWindow] of arrival. These widgets show a LIVE countdown
/// to that deadline so the floor can see which receipts are running out of time.
const Duration grnWindow = Duration(days: 3);

enum SlaState { ok, soon, overdue }

/// >24h left = ok (green), within 24h = soon (orange), past due = overdue (red).
SlaState slaStateFor(Duration remaining) {
  if (remaining.isNegative) return SlaState.overdue;
  if (remaining.inHours < 24) return SlaState.soon;
  return SlaState.ok;
}

({Color fg, Color bg, Color line}) slaColors(SlaState s) => switch (s) {
      SlaState.ok => (fg: Y2.green, bg: Y2.greenTint, line: Y2.greenLine),
      SlaState.soon => (fg: Y2.orange, bg: Y2.orangeTint, line: Y2.orangeLine),
      SlaState.overdue => (fg: Y2.red, bg: Y2.redTint, line: Y2.redLine),
    };

/// Compact remaining-time label: "2d 4h", "7h 12m", "8m 30s", or "OVERDUE 3h 5m".
String slaLabel(Duration remaining) {
  final neg = remaining.isNegative;
  final a = remaining.abs();
  String core;
  if (a.inDays >= 1) {
    core = '${a.inDays}d ${a.inHours % 24}h';
  } else if (a.inHours >= 1) {
    core = '${a.inHours}h ${a.inMinutes % 60}m';
  } else {
    core = '${a.inMinutes}m ${a.inSeconds % 60}s';
  }
  return neg ? 'OVERDUE $core' : core;
}

/// The deadline for a gate entry that arrived [hoursAgo] hours ago, computed from
/// a STABLE reference [from] (capture it once in the screen's state so the
/// countdown actually ticks down instead of staying constant).
DateTime grnDueFrom(DateTime from, num hoursAgo) =>
    from.subtract(Duration(minutes: (hoursAgo * 60).round())).add(grnWindow);

/// Rebuilds [builder] once a second. The Timer is cancelled on dispose, so widget
/// tests never see a pending timer after teardown. Use this anywhere a value needs
/// to refresh live (countdowns, the overdue banner).
class SlaTick extends StatefulWidget {
  const SlaTick({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  State<SlaTick> createState() => _SlaTickState();
}

class _SlaTickState extends State<SlaTick> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// A live countdown pill toward a GRN deadline. Set [dense] for tight list rows.
class SlaCountdown extends StatelessWidget {
  const SlaCountdown(this.due, {super.key, this.dense = false});
  final DateTime due;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return SlaTick(builder: (context) {
      final remaining = due.difference(DateTime.now());
      final st = slaStateFor(remaining);
      final c = slaColors(st);
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: dense ? 7 : 8, vertical: dense ? 3 : 4),
        decoration: BoxDecoration(
          color: c.bg,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Y2.rPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                st == SlaState.overdue
                    ? Icons.warning_amber_rounded
                    : Icons.schedule,
                size: dense ? 11 : 12,
                color: c.fg),
            SizedBox(width: dense ? 4 : 5),
            Text(slaLabel(remaining),
                style:
                    F.mono(dense ? 10 : 11, w: FontWeight.w700, color: c.fg)),
          ],
        ),
      );
    });
  }
}
