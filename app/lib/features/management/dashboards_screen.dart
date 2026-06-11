/// Management dashboards (app map scr-m-home/achv/sales/yield): one screen,
/// four tabs (Overview / Achievement / Sales / Yield), desktop-dashboard feel —
/// content centered at maxWidth 980, dtab-style chips, KPI grids, hbar lists.
/// Auto-refreshes every 30 s (backend answers unchanged polls with a 304).
/// Field names mirror backend/app/schemas/dashboards.py exactly.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Indian money formatting: ₹X.XX Cr / ₹X.X L / plain ₹ below a lakh.
/// (Local helper by convention — copy into other features when needed;
/// shared files stay untouched.)
String _inr(String? raw) {
  final v = double.tryParse(raw ?? '') ?? 0;
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)} L';
  return '₹${v.toStringAsFixed(0)}';
}

/// Quantities are Decimal-as-string ("258.000") — show them as plain numbers.
String _qty(String? raw) {
  final v = double.tryParse(raw ?? '');
  if (v == null) return raw ?? '—';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// pct fields are null when the denominator is 0 — show '—' (schema contract).
String _pct(String? raw) {
  if (raw == null) return '—';
  final v = double.tryParse(raw);
  if (v == null) return '$raw%';
  return '${v.toStringAsFixed(1)}%';
}

class DashboardsScreen extends StatefulWidget {
  const DashboardsScreen({super.key});

  @override
  State<DashboardsScreen> createState() => _DashboardsScreenState();
}

class _DashboardsScreenState extends State<DashboardsScreen> {
  static const _paths = [
    '/dashboards/overview',
    '/dashboards/achievement',
    '/dashboards/sales',
    '/dashboards/yield',
  ];

  int _tab = 0;
  Timer? _timer;
  final Map<int, Map<String, dynamic>> _data = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(
        const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final tab = _tab;
    if (!silent) {
      setState(() {
        _loading = _data[tab] == null;
        _error = null;
      });
    }
    try {
      final r = await Api.dio.get(_paths[tab]);
      if (!mounted || tab != _tab) return;
      setState(() {
        _data[tab] = Map<String, dynamic>.from(r.data as Map);
        _loading = false;
        _error = null;
      });
    } on DioException catch (e) {
      if (!mounted || tab != _tab) return;
      if (silent && _data[tab] != null) return; // keep stale data quietly
      setState(() {
        _loading = false;
        _error = ApiException.from(e).message;
      });
    }
  }

  void _switchTab(int i) {
    if (_tab == i) return;
    setState(() => _tab = i);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('Management dashboards', 'व्यवस्थापन डॅशबोर्ड')),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: S.t('Refresh', 'रिफ्रेश'),
              onPressed: _load),
        ],
      ),
      body: Column(children: [
        _tabBar(),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _tabBar() {
    final labels = [
      S.t('Overview', 'आढावा'),
      S.t('Achievement', 'उद्दिष्टपूर्ती'),
      S.t('Sales', 'विक्री'),
      S.t('Yield', 'यील्ड'),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _tabChip(i, labels[i]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabChip(int i, String label) {
    final active = _tab == i;
    return InkWell(
      onTap: () => _switchTab(i),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? YColors.navy : Colors.white,
          border: Border.all(color: active ? YColors.navy : YColors.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : YColors.navy)),
      ),
    );
  }

  Widget _body() {
    final d = _data[_tab];
    if (d == null && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (d == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error ?? S.t('Something went wrong', 'काहीतरी चूक झाली'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: YColors.red, fontSize: 12)),
          TextButton(
              onPressed: _load, child: Text(S.t('Retry', 'पुन्हा प्रयत्न'))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth > 640;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: switch (_tab) {
                    0 => _overview(d, wide),
                    1 => _achievement(d, wide),
                    2 => _sales(d, wide),
                    _ => _yield(d, wide),
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // --- shared bits ---------------------------------------------------------

  Widget _kpiGrid(List<Widget> kpis, bool wide) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: wide ? 3 : 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 86,
      ),
      children: kpis,
    );
  }

  Widget _sectionHead(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: YColors.muted)),
      );

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static int _int(dynamic v) => v is num ? v.toInt() : 0;

  // --- OVERVIEW -------------------------------------------------------------

  List<Widget> _overview(Map<String, dynamic> d, bool wide) {
    final anomalies = _map(d['open_anomalies']);
    final outbox = _map(d['outbox_backlog']);
    final hard = _int(anomalies['hard']);
    final anomTotal = _int(anomalies['total']);
    final approvals = _int(d['approvals_pending']);
    final overrides = _int(d['open_override_reviews']);
    final unmatched = _int(d['unmatched_gate_entries']);
    final failed = _int(outbox['failed']);
    final outboxPending = _int(outbox['pending']);
    final holds = _int(d['holds_open']);

    final attention = <Widget>[
      if (hard > 0)
        AppCard(
          kind: 'urgent',
          title: S.t('$hard hard-block ${hard == 1 ? 'anomaly' : 'anomalies'} open',
              '$hard हार्ड-ब्लॉक विसंगती खुल्या'),
          body: S.t('Material is blocked until these are resolved.',
              'या निकाली निघेपर्यंत मटेरियल ब्लॉक आहे.'),
          trailing: const StatusBadge('HARD', kind: 'bad'),
          onTap: () => context.push('/mgmt/anomalies'),
        ),
      if (approvals > 0)
        AppCard(
          kind: 'warn',
          title: S.t('$approvals approval${approvals == 1 ? '' : 's'} pending',
              '$approvals मंजुरी प्रलंबित'),
          body: S.t('Waivers, corrections and debits waiting on a decision.',
              'सवलती, दुरुस्त्या आणि डेबिट निर्णयाच्या प्रतीक्षेत.'),
          trailing: const StatusBadge('APPROVAL', kind: 'warn'),
          onTap: () => context.push('/mgmt/approvals'),
        ),
      if (overrides > 0)
        AppCard(
          kind: 'info',
          title: S.t('$overrides override review${overrides == 1 ? '' : 's'} open',
              '$overrides ओव्हरराइड तपासणी खुल्या'),
          body: S.t('Emergency overrides awaiting post-facto review.',
              'आपत्कालीन ओव्हरराइडची पश्चात तपासणी बाकी.'),
          trailing: const StatusBadge('OVERRIDE', kind: 'purple'),
          onTap: () => context.push('/mgmt/approvals'),
        ),
      if (failed > 0)
        AppCard(
          kind: 'urgent',
          title: S.t('SAP postback failing — $failed records',
              'SAP पोस्टबॅक अयशस्वी — $failed नोंदी'),
          body: S.t('Outbox retries are exhausted; SAP may be out of date.',
              'आउटबॉक्स पुनःप्रयत्न संपले; SAP मागे पडले असू शकते.'),
          trailing: const StatusBadge('SAP', kind: 'bad'),
        ),
      if (unmatched > 0)
        AppCard(
          kind: 'warn',
          title: S.t('$unmatched unmatched gate entr${unmatched == 1 ? 'y' : 'ies'}',
              '$unmatched जुळणी नसलेल्या गेट नोंदी'),
          body: S.t('Inward entries without a matching SAP document.',
              'SAP दस्तऐवजाशी जुळणी नसलेल्या आवक नोंदी.'),
          trailing: const StatusBadge('GATE', kind: 'warn'),
        ),
      if (holds > 0)
        AppCard(
          kind: 'warn',
          title: S.t('$holds production hold${holds == 1 ? '' : 's'} open',
              '$holds उत्पादन होल्ड खुले'),
          body: S.t('Lines or batches currently on hold.',
              'लाईन किंवा बॅच सध्या होल्डवर.'),
          trailing: const StatusBadge('HOLD', kind: 'warn'),
        ),
    ];

    return [
      _kpiGrid([
        KpiCard(
            label: S.t('Achievement', 'उद्दिष्टपूर्ती'),
            value: _pct(d['achievement_pct'] as String?),
            delta: S.t('vs plan today', 'आजच्या योजनेविरुद्ध')),
        KpiCard(
            label: S.t('Billed today', 'आज बिलिंग'),
            value: _inr(d['billed_today_value'] as String?)),
        KpiCard(
            label: S.t('Yield today', 'आजचे यील्ड'),
            value: _pct(d['yield_pct'] as String?),
            delta: S.t('target 98%', 'लक्ष्य ९८%')),
        KpiCard(
            label: S.t('Open anomalies', 'खुल्या विसंगती'),
            value: '$anomTotal',
            delta: hard > 0 ? S.t('$hard hard', '$hard हार्ड') : null,
            deltaBad: true),
        KpiCard(
            label: S.t('Approvals pending', 'मंजुरी प्रलंबित'),
            value: '$approvals',
            delta: approvals > 0
                ? S.t('needs a decision', 'निर्णय हवा')
                : null,
            deltaBad: true),
        KpiCard(
            label: S.t('Override reviews', 'ओव्हरराइड तपासणी'),
            value: '$overrides',
            delta: overrides > 0
                ? S.t('post-facto review', 'पश्चात तपासणी')
                : null,
            deltaBad: overrides > 0),
      ], wide),
      _sectionHead(S.t('Needs your attention', 'आपले लक्ष हवे')),
      if (attention.isEmpty)
        AlertBanner(
            kind: 'success',
            title: S.t('All clear', 'सर्व ठीक'),
            body: S.t('Nothing needs a management decision right now.',
                'सध्या व्यवस्थापन निर्णयाची गरज नाही.'))
      else
        ...attention,
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
            S.t('SAP outbox: $outboxPending pending · $failed failed',
                'SAP आउटबॉक्स: $outboxPending प्रलंबित · $failed अयशस्वी'),
            style: const TextStyle(fontSize: 10.5, color: YColors.muted)),
      ),
    ];
  }

  // --- ACHIEVEMENT ----------------------------------------------------------

  List<Widget> _achievement(Map<String, dynamic> d, bool wide) {
    final lines = (d['lines'] as List? ?? const []);
    final totals = _map(d['totals']);

    var downtimeTotal = 0;
    Map<String, dynamic>? topReason;
    String topReasonLine = '';
    for (final raw in lines) {
      final l = _map(raw);
      downtimeTotal += _int(l['downtime_total_min']);
      final r = l['top_downtime_reason'];
      if (r is Map) {
        final reason = Map<String, dynamic>.from(r);
        if (topReason == null ||
            _int(reason['minutes']) > _int(topReason['minutes'])) {
          topReason = reason;
          topReasonLine = (l['line_name'] as String?) ?? '';
        }
      }
    }

    return [
      AlertBanner(
        kind: 'info',
        title: S.t('These bars move in real time.',
            'हे बार प्रत्यक्ष वेळेत हलतात.'),
        body: S.t(
            'Each number is a supervisor confirmation from the shop floor, not an end-of-day report.',
            'प्रत्येक आकडा शॉप फ्लोअरवरील सुपरवायझरची नोंद आहे, दिवसअखेरचा अहवाल नाही.'),
      ),
      _kpiGrid([
        KpiCard(
            label: S.t('Planned', 'नियोजित'),
            value: _qty(totals['planned'] as String?)),
        KpiCard(
            label: S.t('Confirmed good', 'चांगले नोंदवलेले'),
            value: _qty(totals['confirmed_good'] as String?),
            delta: S.t('${_qty(totals['confirmed_rejected'] as String?)} rejected',
                '${_qty(totals['confirmed_rejected'] as String?)} नाकारलेले'),
            deltaBad: true),
        KpiCard(
            label: S.t('Achievement', 'उद्दिष्टपूर्ती'),
            value: _pct(totals['pct'] as String?)),
      ], wide),
      _sectionHead(S.t('By line', 'लाईननुसार')),
      if (lines.isEmpty)
        Text(S.t('No plan for this day.', 'या दिवसासाठी योजना नाही.'),
            style: const TextStyle(fontSize: 12, color: YColors.muted)),
      ...lines.map((raw) {
        final l = _map(raw);
        final planned = double.tryParse(l['planned'] as String? ?? '') ?? 0;
        final good = double.tryParse(l['confirmed_good'] as String? ?? '') ?? 0;
        return AppCard(
          title: (l['line_name'] as String?) ?? '—',
          trailing: Text(
              '${_qty(l['confirmed_good'] as String?)}/${_qty(l['planned'] as String?)} · ${_pct(l['pct'] as String?)}',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: YColors.navy)),
          child: ProgressBar(fraction: planned > 0 ? good / planned : 0),
        );
      }),
      _sectionHead(S.t('By shift', 'शिफ्टनुसार')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.2),
            },
            children: [
              TableRow(children: [
                _th(S.t('Line', 'लाईन')),
                _th(S.t('A · good / rej', 'A · चांगले / नाकारलेले')),
                _th(S.t('B · good / rej', 'B · चांगले / नाकारलेले')),
              ]),
              ...lines.map((raw) {
                final l = _map(raw);
                final shifts = _map(l['shifts']);
                return TableRow(children: [
                  _td((l['line_name'] as String?) ?? '—'),
                  _td(_shiftSplit(shifts['A'])),
                  _td(_shiftSplit(shifts['B'])),
                ]);
              }),
            ],
          ),
        ),
      ),
      if (downtimeTotal > 0)
        AlertBanner(
          kind: 'warn',
          title: S.t('Downtime today: $downtimeTotal min',
              'आजचा डाउनटाइम: $downtimeTotal मिनिटे'),
          body: topReason == null
              ? null
              : S.t(
                  'Top reason: ${(topReason['label_en'] as String?) ?? (topReason['reason_code'] as String?) ?? 'unspecified'} · ${_int(topReason['minutes'])} min ($topReasonLine)',
                  'मुख्य कारण: ${(topReason['label_en'] as String?) ?? (topReason['reason_code'] as String?) ?? 'अनिर्दिष्ट'} · ${_int(topReason['minutes'])} मि. ($topReasonLine)'),
        ),
    ];
  }

  String _shiftSplit(dynamic s) {
    if (s is! Map) return '—';
    final m = Map<String, dynamic>.from(s);
    return '${_qty(m['good'] as String?)} / ${_qty(m['rejected'] as String?)}';
  }

  Widget _th(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
                color: YColors.muted)),
      );

  Widget _td(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(t,
            style: const TextStyle(fontSize: 11.5, color: YColors.ink)),
      );

  // --- SALES ----------------------------------------------------------------

  List<Widget> _sales(Map<String, dynamic> d, bool wide) {
    final today = _map(d['billed_today']);
    final mtd = _map(d['billed_mtd']);
    final materials = (d['materials'] as List? ?? const []);
    final awaiting = _int(d['awaiting_invoice']);

    return [
      _kpiGrid([
        KpiCard(
            label: S.t('Billed today', 'आज बिलिंग'),
            value: _inr(today['value'] as String?),
            delta: S.t('${_qty(today['pcs'] as String?)} pcs',
                '${_qty(today['pcs'] as String?)} नग')),
        KpiCard(
            label: S.t('MTD value', 'महिन्याची किंमत'),
            value: _inr(mtd['value'] as String?),
            delta: S.t('${_qty(mtd['pcs'] as String?)} pcs',
                '${_qty(mtd['pcs'] as String?)} नग')),
        KpiCard(
            label: S.t('Awaiting invoice', 'इनव्हॉइस प्रतीक्षेत'),
            value: '$awaiting',
            delta: awaiting > 0
                ? S.t('open dispatches', 'खुले डिस्पॅच')
                : null,
            deltaBad: awaiting > 0),
      ], wide),
      _sectionHead(S.t('By material · ${d['month'] ?? ''}',
          'मटेरियलनुसार · ${d['month'] ?? ''}')),
      if (materials.isEmpty)
        Text(S.t('No billing this month yet.', 'या महिन्यात अजून बिलिंग नाही.'),
            style: const TextStyle(fontSize: 12, color: YColors.muted))
      else if (wide)
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 28,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 42,
              columns: [
                DataColumn(label: Text(S.t('SAP code', 'SAP कोड'))),
                DataColumn(label: Text(S.t('Description', 'वर्णन'))),
                DataColumn(
                    label: Text(S.t('Today pcs', 'आज नग')), numeric: true),
                DataColumn(
                    label: Text(S.t('MTD pcs', 'महिना नग')), numeric: true),
                DataColumn(
                    label: Text(S.t('MTD value', 'महिना किंमत')),
                    numeric: true),
              ],
              rows: materials.map((raw) {
                final m = _map(raw);
                return DataRow(cells: [
                  DataCell(Text((m['sap_code'] as String?) ?? '—',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600))),
                  DataCell(Text((m['description'] as String?) ?? '—',
                      style: const TextStyle(fontSize: 11.5))),
                  DataCell(Text(_qty(m['today_pcs'] as String?),
                      style: const TextStyle(fontSize: 11.5))),
                  DataCell(Text(_qty(m['mtd_pcs'] as String?),
                      style: const TextStyle(fontSize: 11.5))),
                  DataCell(Text(_inr(m['mtd_value'] as String?),
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600))),
                ]);
              }).toList(),
            ),
          ),
        )
      else
        ...materials.map((raw) {
          final m = _map(raw);
          return AppCard(
            title: '${m['sap_code'] ?? '—'} · ${m['description'] ?? ''}',
            body: S.t(
                'Today ${_qty(m['today_pcs'] as String?)} pcs · MTD ${_qty(m['mtd_pcs'] as String?)} pcs · ${_inr(m['mtd_value'] as String?)}',
                'आज ${_qty(m['today_pcs'] as String?)} नग · महिना ${_qty(m['mtd_pcs'] as String?)} नग · ${_inr(m['mtd_value'] as String?)}'),
          );
        }),
    ];
  }

  // --- YIELD ----------------------------------------------------------------

  List<Widget> _yield(Map<String, dynamic> d, bool wide) {
    final overall = _map(d['overall']);
    final rows = (d['rows'] as List? ?? const []);
    final reasons = (d['reject_reasons'] as List? ?? const []);
    final yieldPctRaw = overall['yield_pct'] as String?;
    final yieldPct = double.tryParse(yieldPctRaw ?? '');
    final headlineColor = yieldPct == null
        ? YColors.muted
        : yieldPct >= 98
            ? YColors.green
            : YColors.amber;

    var maxReject = 0.0;
    for (final raw in reasons) {
      final q = double.tryParse(_map(raw)['qty'] as String? ?? '') ?? 0;
      if (q > maxReject) maxReject = q;
    }

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(children: [
            Text(_pct(yieldPctRaw),
                style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    color: headlineColor)),
            const SizedBox(height: 2),
            Text(
                S.t(
                    'good ${_qty(overall['good'] as String?)} · rejected ${_qty(overall['rejected'] as String?)} · target 98%',
                    'चांगले ${_qty(overall['good'] as String?)} · नाकारलेले ${_qty(overall['rejected'] as String?)} · लक्ष्य ९८%'),
                style: const TextStyle(fontSize: 11, color: YColors.muted)),
          ]),
        ),
      ),
      _sectionHead(S.t('By line & shift', 'लाईन व शिफ्टनुसार')),
      if (rows.isEmpty)
        Text(S.t('No confirmations for this day.', 'या दिवसाच्या नोंदी नाहीत.'),
            style: const TextStyle(fontSize: 12, color: YColors.muted)),
      ...rows.map((raw) {
        final r = _map(raw);
        return ListRow(
          title: '${r['line_name'] ?? '—'} · ${S.t('Shift', 'शिफ्ट')} ${r['shift'] ?? '—'}',
          subtitle: S.t(
              'good ${_qty(r['good'] as String?)} · rejected ${_qty(r['rejected'] as String?)}',
              'चांगले ${_qty(r['good'] as String?)} · नाकारलेले ${_qty(r['rejected'] as String?)}'),
          trailing: Text(_pct(r['yield_pct'] as String?),
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: YColors.navy)),
        );
      }),
      _sectionHead(S.t('Reject reasons', 'नाकारण्याची कारणे')),
      if (reasons.isEmpty)
        Text(S.t('No rejections recorded.', 'नाकारलेल्या नोंदी नाहीत.'),
            style: const TextStyle(fontSize: 12, color: YColors.muted)),
      ...reasons.map((raw) {
        final r = _map(raw);
        final qty = double.tryParse(r['qty'] as String? ?? '') ?? 0;
        final label = (r['label_en'] as String?) ??
            (r['reason_code'] as String?) ??
            S.t('Unspecified', 'अनिर्दिष्ट');
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: YColors.navy))),
              Text(_qty(r['qty'] as String?),
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: YColors.red)),
            ]),
            const SizedBox(height: 3),
            ProgressBar(fraction: maxReject > 0 ? qty / maxReject : 0),
          ]),
        );
      }),
      AlertBanner(
        kind: 'warn',
        title: S.t(
            'Imputed scrap value: ${_inr(d['imputed_scrap_value'] as String?)}',
            'अनुमानित स्क्रॅप किंमत: ${_inr(d['imputed_scrap_value'] as String?)}'),
        body: S.t(
            'Proxy only — rejected qty × material price, not an accounting figure.',
            'फक्त अंदाज — नाकारलेले नग × मटेरियल किंमत; लेखा आकडा नाही.'),
      ),
    ];
  }
}
