import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../responsive.dart';
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
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- phone layout (unchanged) ----

  Widget _phone() {
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

  // ---- desktop layout (summary + dense data table) ----

  Widget _desktop() {
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
          child: ResponsiveContent(
            maxWidth: 1200,
            child: loaded == null
                ? const SkeletonRows(count: 6)
                : rows.isEmpty
                    ? EmptyState2(
                        icon: Icons.event_note_outlined,
                        title: S.t('No plan for today', 'आजसाठी योजना नाही'),
                        subtitle: S.t(
                            'No line plans have been released yet.',
                            'अद्याप कोणतीही लाईन योजना जारी केलेली नाही.'),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _summary(totalGood, totalPlanned),
                            const SizedBox(height: 14),
                            _table(rows),
                          ],
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  // Column widths shared by header + rows so the cells line up. A gap is inserted
  // between adjacent columns (see _gap) so right-aligned numbers/pills never butt
  // up against the next column's text. Numeric cells use FittedBox. Total of all
  // fixed widths + gaps stays well under 900px; the line·material column is
  // Expanded and absorbs the slack.
  static const _wReject = 96.0;
  static const _wGood = 120.0;
  static const _wRemain = 110.0;
  static const _wProgress = 200.0;
  static const _gap = SizedBox(width: 16);

  Widget _table(List<Json> rows) {
    return Card2(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header row.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8FB),
              border: Border(bottom: BorderSide(color: Y2.line)),
            ),
            child: Row(
              children: [
                Expanded(
                    flex: 5,
                    child: _th(S.t('Line · material', 'लाईन · माल'))),
                _gap,
                SizedBox(width: _wGood, child: _th(S.t('Good / planned', 'चांगले / नियोजित'), right: true)),
                _gap,
                SizedBox(width: _wRemain, child: _th(S.t('Remaining', 'बाकी'), right: true)),
                _gap,
                SizedBox(width: _wReject, child: _th(S.t('Reject', 'नापास'), right: true)),
                _gap,
                SizedBox(width: _wProgress, child: _th(S.t('Progress', 'प्रगती'))),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) _tableRow(rows[i], i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _th(String s, {bool right = false}) => Text(s,
      textAlign: right ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));

  /// Scale-to-fit wrapper so numeric cells never overflow their fixed column,
  /// whatever the font metrics (matches the repo's big-number tiles).
  Widget _fit(Widget child, {Alignment align = Alignment.centerRight}) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: align, child: child);

  Widget _tableRow(Json row, bool last) {
    final lineName = '${row['line_name'] ?? S.t('Line', 'लाईन')}';
    final material = '${row['description'] ?? '—'}';
    final sapCode = '${row['sap_code'] ?? ''}';
    final planned = _n(row['planned_qty']);
    final good = _n(row['confirmed_good']);
    final reject = _n(row['confirmed_reject']);
    final remaining = _n(row['remaining']);
    final frac = planned <= 0 ? 0.0 : (good / planned);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border:
            last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Line + material (+ SAP code).
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lineName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.khand(15, ls: 0.2, color: Y2.ink)),
                Row(
                  children: [
                    Flexible(
                      child: Text(material,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: F.hind(12, w: FontWeight.w600, color: Y2.body)),
                    ),
                    if (sapCode.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(sapCode, style: F.mono(11, color: Y2.muted)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          _gap,
          // Good / planned.
          SizedBox(
            width: _wGood,
            child: _fit(Text('${_qty(good)} / ${_qty(planned)}',
                maxLines: 1,
                style: F.mono(13, w: FontWeight.w600, color: Y2.ink))),
          ),
          _gap,
          // Remaining.
          SizedBox(
            width: _wRemain,
            child: _fit(Text('${_qty(remaining)} ${S.t('left', 'बाकी')}',
                maxLines: 1,
                style: F.hind(12, w: FontWeight.w600, color: Y2.body))),
          ),
          _gap,
          // Reject.
          SizedBox(
            width: _wReject,
            child: _fit(reject > 0
                ? Pill2(
                    text: '${_qty(reject)}',
                    fg: Y2.red,
                    bg: Y2.redTint,
                    borderColor: Y2.redLine,
                    dot: false)
                : Text('—', style: F.mono(13, color: Y2.muted))),
          ),
          _gap,
          // Progress bar + percent.
          SizedBox(
            width: _wProgress,
            child: Row(
              children: [
                Expanded(child: AnimatedBar2(fraction: frac)),
                const SizedBox(width: 10),
                _fit(Text('${(frac * 100).round()}%',
                    maxLines: 1,
                    style: F.mono(12, w: FontWeight.w600, color: Y2.accent))),
              ],
            ),
          ),
        ],
      ),
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
