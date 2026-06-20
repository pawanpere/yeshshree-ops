import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/polish2.dart';

/// Management — Dashboards (Phase 6, office). One-screen KPI summary for the
/// plant head: today's achievement & yield, value billed, and the action-count
/// chips that need management attention (approvals, anomalies, holds, unmatched
/// gate entries, SAP outbox backlog). Tapping the approvals / anomalies chips
/// drills into those registers. Loaded from [Data.overview] (a single object);
/// clearly-marked DEMO fallback when the backend is unreachable.
class Ui2MgmtDashboardsScreen extends StatefulWidget {
  const Ui2MgmtDashboardsScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2MgmtDashboardsScreen> createState() =>
      _Ui2MgmtDashboardsScreenState();
}

class _Ui2MgmtDashboardsScreenState extends State<Ui2MgmtDashboardsScreen> {
  Loaded<Json>? _data;
  Loaded<List<Json>>? _plans;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Future.wait([Data.overview(), Data.linePlans()]);
    if (!mounted) return;
    setState(() {
      _data = res[0] as Loaded<Json>;
      _plans = res[1] as Loaded<List<Json>>;
    });
  }

  /// INR (paise as a string) → a compact "₹X.YL" lakhs label.
  String _lakhs(dynamic raw) {
    final v = double.tryParse('${raw ?? ''}') ?? 0;
    final l = v / 100000;
    if (l >= 100) return '₹${l.round()}L';
    return '₹${l.toStringAsFixed(1)}L';
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _data;
    final o = loaded?.data;
    final isEmpty = o == null || o.isEmpty;
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('DASHBOARDS', 'डॅशबोर्ड'),
          demo: (loaded?.demo ?? false) || (_plans?.demo ?? false),
        ),
        Expanded(
          child: loaded == null || _plans == null
              ? const SkeletonRows(count: 4)
              : isEmpty
                  ? EmptyState2(
                      icon: Icons.insights_outlined,
                      title: S.t('No data yet', 'अद्याप डेटा नाही'),
                      subtitle: S.t(
                          "Today's plant summary will appear here once the day gets going.",
                          'दिवस सुरू झाल्यावर आजचा प्लांट सारांश येथे दिसेल.'),
                    )
                  : _body(o, _plans?.data ?? const <Json>[]),
        ),
      ],
    );
  }

  Widget _body(Json o, List<Json> plans) {
    final achievement = double.tryParse('${o['achievement_pct'] ?? ''}') ?? 0;
    final yieldPct = double.tryParse('${o['yield_pct'] ?? ''}') ?? 0;

    final anomalies = (o['open_anomalies'] is Map)
        ? Json.from(o['open_anomalies'] as Map)
        : const <String, dynamic>{};
    final anomTotal = (double.tryParse('${anomalies['total'] ?? ''}') ?? 0).round();
    final anomHard = (double.tryParse('${anomalies['hard'] ?? ''}') ?? 0).round();

    final outbox = (o['outbox_backlog'] is Map)
        ? Json.from(o['outbox_backlog'] as Map)
        : const <String, dynamic>{};
    final outPending = (double.tryParse('${outbox['pending'] ?? ''}') ?? 0).round();
    final outFailed = (double.tryParse('${outbox['failed'] ?? ''}') ?? 0).round();
    final outboxTotal = outPending + outFailed;

    final approvals = (double.tryParse('${o['approvals_pending'] ?? ''}') ?? 0).round();
    final holds = (double.tryParse('${o['holds_open'] ?? ''}') ?? 0).round();
    final unmatched =
        (double.tryParse('${o['unmatched_gate_entries'] ?? ''}') ?? 0).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        // ---- KPI cards: a 2-column Wrap so it fits office + narrow ----
        LayoutBuilder(
          builder: (context, c) {
            // Two columns with an 11px gutter; cards reflow to one column when narrow.
            final w = (c.maxWidth - 11) / 2;
            final cardW = w < 150 ? c.maxWidth : w;
            return Wrap(
              spacing: 11,
              runSpacing: 11,
              children: [
                SizedBox(
                  width: cardW,
                  child: _gaugeCard(
                    label: S.t('ACHIEVEMENT', 'साध्यता'),
                    pct: achievement,
                    color: achievement >= 85
                        ? Y2.green
                        : (achievement >= 60 ? Y2.accent : Y2.orange),
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: _gaugeCard(
                    label: S.t('YIELD', 'उत्पन्न'),
                    pct: yieldPct,
                    color: yieldPct >= 95 ? Y2.green : Y2.orange,
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: _valueCard(
                    label: S.t('BILLED TODAY', 'आज बिल केले'),
                    value: _lakhs(o['billed_today_value']),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        // ---- two centerpiece chart cards: line achievement + 7-day trend ----
        LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 11) / 2;
            // Charts need room; collapse to one column on a phone width.
            final wide = c.maxWidth >= 520;
            final cardW = wide ? w : c.maxWidth;
            return Wrap(
              spacing: 11,
              runSpacing: 11,
              children: [
                SizedBox(width: cardW, child: _lineAchievementCard(plans)),
                SizedBox(width: cardW, child: _trendCard()),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(S.t('NEEDS ATTENTION', 'लक्ष आवश्यक'),
            style: F.hind(11, w: FontWeight.w600, ls: 0.5, color: Y2.muted)),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _actionChip(
              label: S.t('Approvals', 'मंजुरी'),
              count: approvals,
              onTap: () => nav.go(ScreenId.mgmtApprovals),
            ),
            _actionChip(
              label: S.t('Anomalies', 'विसंगती'),
              count: anomTotal,
              glyph: anomHard > 0
                  ? const Glyph(GlyphShape.diamond, Y2.red, size: 9)
                  : null,
              danger: anomHard > 0,
              onTap: () => nav.go(ScreenId.mgmtAnomalies),
            ),
            _actionChip(
              label: S.t('Holds', 'होल्ड'),
              count: holds,
            ),
            _actionChip(
              label: S.t('Unmatched gate', 'न जुळलेले गेट'),
              count: unmatched,
            ),
            _actionChip(
              label: S.t('SAP outbox', 'SAP आउटबॉक्स'),
              count: outboxTotal,
              warn: outFailed > 0,
            ),
          ],
        ),
      ],
    );
  }

  // ---- centerpiece: per-line achievement (good / planned) bar chart ----
  Widget _lineAchievementCard(List<Json> plans) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(Y2.rCard),
        border: Border.all(color: Y2.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.t('LINE ACHIEVEMENT', 'लाईन साध्यता'),
              style: F.hind(11, w: FontWeight.w600, ls: 0.5, color: Y2.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 11),
          if (plans.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                  S.t('No line plans for today.',
                      'आजसाठी कोणतेही लाईन नियोजन नाही.'),
                  style: F.hind(12, color: Y2.muted)),
            )
          else
            for (var i = 0; i < plans.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _lineRow(plans[i]),
            ],
        ],
      ),
    );
  }

  Widget _lineRow(Json p) {
    final name = '${p['line_name'] ?? p['description'] ?? '—'}';
    final planned = double.tryParse('${p['planned_qty'] ?? ''}') ?? 0;
    final good = double.tryParse('${p['confirmed_good'] ?? ''}') ?? 0;
    final frac = planned > 0 ? (good / planned).clamp(0.0, 1.0) : 0.0;
    final pct = (frac * 100).round();
    final color = frac >= 0.9 ? Y2.green : Y2.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(name,
                  style: F.hind(12, w: FontWeight.w600, color: Y2.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text('$pct%',
                style: F.mono(12, w: FontWeight.w600, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedBar2(fraction: frac, color: color),
      ],
    );
  }

  // ---- centerpiece: 7-day achievement % trend sparkline ----
  Widget _trendCard() {
    const trend = Data.demoMgmtTrend;
    final latest = trend.isEmpty ? 0 : trend.last.round();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
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
                child: Text(S.t('7-DAY ACHIEVEMENT', '७-दिवस साध्यता'),
                    style: F.hind(11,
                        w: FontWeight.w600, ls: 0.5, color: Y2.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Ticker2(latest, style: F.khand(22, color: Y2.accent), suffix: '%'),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) => Sparkline2(
              trend,
              width: c.maxWidth < 260 ? c.maxWidth : 260,
              height: 46,
              color: Y2.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(S.t('daily achievement trend', 'दैनिक साध्यता कल'),
              style: F.hind(11, color: Y2.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ---- a KPI card: big animated % + a fill bar (achievement / yield) ----
  Widget _gaugeCard({
    required String label,
    required double pct,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(Y2.rCard),
        border: Border.all(color: Y2.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: F.hind(11, w: FontWeight.w600, ls: 0.5, color: Y2.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Ticker2(pct.round(),
              style: F.khand(30, color: color), suffix: '%'),
          const SizedBox(height: 9),
          AnimatedBar2(fraction: pct / 100, color: color),
        ],
      ),
    );
  }

  // ---- a KPI card: a single value string (billed today) ----
  Widget _valueCard({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(Y2.rCard),
        border: Border.all(color: Y2.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: F.hind(11, w: FontWeight.w600, ls: 0.5, color: Y2.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(value,
              style: F.khand(30, color: Y2.navy),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(S.t('value billed today', 'आज बिल केलेले मूल्य'),
              style: F.hind(11, color: Y2.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ---- an action-count chip; optionally tappable, danger (red) or warn (orange) ----
  Widget _actionChip({
    required String label,
    required int count,
    VoidCallback? onTap,
    Widget? glyph,
    bool danger = false,
    bool warn = false,
  }) {
    final fg = danger ? Y2.red : (warn ? Y2.orange : Y2.navy);
    final countBg = danger
        ? Y2.redTint
        : (warn ? Y2.orangeTint : Y2.lineSoft);
    final countBorder = danger
        ? Y2.redLine
        : (warn ? Y2.orangeLine : Y2.line);
    final inner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(Y2.rPill),
        border: Border.all(color: Y2.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[glyph, const SizedBox(width: 6)],
          Text(label,
              style: F.hind(13, w: FontWeight.w600, color: fg)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: countBg,
              borderRadius: BorderRadius.circular(Y2.rPill),
              border: Border.all(color: countBorder),
            ),
            child: Text('$count',
                style: F.mono(12, w: FontWeight.w600, color: fg)),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: Y2.muted),
          ],
        ],
      ),
    );
    if (onTap == null) return inner;
    return Pressable2(onTap: onTap, child: inner);
  }
}
