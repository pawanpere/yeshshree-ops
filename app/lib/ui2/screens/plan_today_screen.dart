import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/polish2.dart';

/// Planning — Today's Plan (office). Shows every line's plan for today: per-row
/// progress (good vs planned), remaining qty, and a reject count, with a top
/// summary of total good vs total planned across all lines. Reads from
/// [Data.linePlans] (mirror PlanRow; numbers arrive as STRINGS) with a
/// clearly-marked DEMO fallback when the backend is unreachable or no plan
/// exists yet. Renders inside the office shell — no responsive code of its own.
class Ui2PlanTodayScreen extends StatefulWidget {
  const Ui2PlanTodayScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2PlanTodayScreen> createState() => _Ui2PlanTodayScreenState();
}

class _Ui2PlanTodayScreenState extends State<Ui2PlanTodayScreen> {
  Loaded<List<Json>>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.linePlans();
    if (!mounted) return;
    setState(() => _data = res);
  }

  // Numbers arrive as STRINGS — parse defensively.
  double _n(Object? v) => double.tryParse('${v ?? ''}') ?? 0;

  String _qty(double v) {
    // Whole quantities render without a trailing .0.
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];

    var totalPlanned = 0.0;
    var totalGood = 0.0;
    for (final r in rows) {
      totalPlanned += _n(r['planned_qty']);
      totalGood += _n(r['confirmed_good']);
    }

    return Column(
      children: [
        ScreenHeader2(
          title: S.t("TODAY'S PLAN", 'आजची योजना'),
          demo: loaded?.demo ?? false,
          trailing: rows.isEmpty
              ? null
              : Text('${rows.length}', style: F.mono(12, color: Y2.muted)),
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: Icons.event_note_outlined,
                      title: S.t('No plan for today', 'आजसाठी योजना नाही'),
                      subtitle: S.t(
                          'No line plans have been released yet.',
                          'अद्याप कोणतीही लाईन योजना जारी केलेली नाही.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      itemCount: rows.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return _summary(totalGood, totalPlanned);
                        }
                        return _card(rows[i - 1]);
                      },
                    ),
        ),
      ],
    );
  }

  // Top summary: total good vs total planned across all lines.
  Widget _summary(double good, double planned) {
    final frac = planned <= 0 ? 0.0 : (good / planned);
    final pct = (frac * 100).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(Y2.rCard),
        border: Border.all(color: Y2.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    S.t('Total — good vs planned', 'एकूण — चांगले विरुद्ध नियोजित'),
                    style: F.hind(12, color: Y2.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('$pct%',
                  style: F.mono(13, w: FontWeight.w600, color: Y2.accent)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Ticker2(good.round(),
                  style: F.khand(22, color: Y2.ink)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(S.t('of ${_qty(planned)} planned',
                        '${_qty(planned)} पैकी नियोजित'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(12, color: Y2.body)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedBar2(fraction: frac),
        ],
      ),
    );
  }

  Widget _card(Json row) {
    final lineName = '${row['line_name'] ?? S.t('Line', 'लाईन')}';
    final material = '${row['description'] ?? '—'}';
    final sapCode = '${row['sap_code'] ?? ''}';
    final planned = _n(row['planned_qty']);
    final good = _n(row['confirmed_good']);
    final reject = _n(row['confirmed_reject']);
    final remaining = _n(row['remaining']);
    final frac = planned <= 0 ? 0.0 : (good / planned);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(Y2.rRow),
        border: Border.all(color: Y2.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line label + reject chip.
          Row(
            children: [
              Expanded(
                child: Text(lineName,
                    style: F.khand(15, ls: 0.2, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (reject > 0) ...[
                const SizedBox(width: 8),
                Pill2(
                    text: S.t('${_qty(reject)} reject', '${_qty(reject)} नापास'),
                    fg: Y2.red,
                    bg: Y2.redTint,
                    borderColor: Y2.redLine),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Material (+ SAP code).
          Row(
            children: [
              Expanded(
                child: Text(material,
                    style: F.hind(13, w: FontWeight.w600, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (sapCode.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(sapCode, style: F.mono(11, color: Y2.muted)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // good / planned.
          Row(
            children: [
              Text('${_qty(good)} / ${_qty(planned)}',
                  style: F.mono(13, w: FontWeight.w600, color: Y2.ink)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(S.t('good / planned', 'चांगले / नियोजित'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(11, color: Y2.muted)),
              ),
              const SizedBox(width: 6),
              Text(
                  S.t('${_qty(remaining)} left', '${_qty(remaining)} बाकी'),
                  style: F.hind(12, w: FontWeight.w600, color: Y2.body)),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedBar2(fraction: frac),
        ],
      ),
    );
  }
}
