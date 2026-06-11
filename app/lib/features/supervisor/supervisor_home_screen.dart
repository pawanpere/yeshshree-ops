/// Supervisor cockpit — scr-s-home + scr-s-pick + scr-s-plan in ONE flow:
/// step 1 pick line & shift (shift suggested from the clock), step 2 today's
/// plan per part with progress; tap a part to open the confirm sheet (hero).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../widgets/common.dart';

double _num(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

String _qty(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

String _todayIso() => DateTime.now().toIso8601String().substring(0, 10);

class SupervisorHomeScreen extends ConsumerStatefulWidget {
  const SupervisorHomeScreen({super.key});

  @override
  ConsumerState<SupervisorHomeScreen> createState() =>
      _SupervisorHomeScreenState();
}

class _SupervisorHomeScreenState extends ConsumerState<SupervisorHomeScreen> {
  List<dynamic>? _lines;
  String? _linesError;
  int? _lineId;
  String? _lineName;
  late String _shift;
  Future<List<dynamic>>? _planFuture;

  @override
  void initState() {
    super.initState();
    // Suggest shift from the clock: before 14:30 → A, else B (app map step 1).
    final now = DateTime.now();
    _shift = (now.hour < 14 || (now.hour == 14 && now.minute < 30)) ? 'A' : 'B';
    _loadLines();
  }

  Future<void> _loadLines() async {
    setState(() => _linesError = null);
    try {
      final r = await Api.dio.get('/master/lines');
      if (!mounted) return;
      setState(() => _lines = r.data as List<dynamic>);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _linesError = ApiException.from(e).message);
    }
  }

  Future<List<dynamic>> _fetchPlan(int lineId) async {
    try {
      final r = await Api.dio.get('/plans/supervisor-view',
          queryParameters: {'line_id': lineId, 'date': _todayIso()});
      return r.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  void _reloadPlan() {
    final id = _lineId;
    if (id != null) setState(() => _planFuture = _fetchPlan(id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('Confirm output', 'उत्पादन नोंदवा')),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _loadLines();
                _reloadPlan();
              }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(S.t('Step 1 · line & shift', 'पायरी 1 · लाईन व पाळी'),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          if (_linesError != null)
            AlertBanner(
                title: S.t('Could not load lines', 'लाईन्स लोड झाल्या नाहीत'),
                body: _linesError, kind: 'danger'),
          DropdownButtonFormField<int>(
            value: _lineId,
            hint: Text(S.t('Select line', 'लाईन निवडा')),
            items: (_lines ?? [])
                .map((l) => DropdownMenuItem<int>(
                    value: l['id'] as int,
                    child: Text(l['name'] as String? ?? '—')))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              final line = (_lines ?? []).firstWhere((l) => l['id'] == v,
                  orElse: () => null);
              setState(() {
                _lineId = v;
                _lineName = line == null ? null : line['name'] as String?;
                _planFuture = _fetchPlan(v);
              });
            },
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                  value: 'A', label: Text(S.t('A shift', 'A पाळी'))),
              ButtonSegment(
                  value: 'B', label: Text(S.t('B shift', 'B पाळी'))),
            ],
            selected: {_shift},
            onSelectionChanged: (s) => setState(() => _shift = s.first),
          ),
          const SizedBox(height: 4),
          Text(
              S.t('Shift suggested from the clock — confirm it.',
                  'पाळी घड्याळावरून सुचवली आहे — खात्री करा.'),
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.history, size: 18),
                label: Text(S.t('History', 'इतिहास')),
                onPressed: () => context.push('/supervisor/history'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.pause_circle_outline, size: 18),
                label: Text(S.t('Holds', 'होल्ड्स')),
                onPressed: () => context.push('/supervisor/holds'),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          if (_lineId == null)
            AlertBanner(
                title: S.t('Pick a line to see today\'s plan',
                    'आजचा प्लॅन पाहण्यासाठी लाईन निवडा'),
                kind: 'info')
          else ...[
            Text(
                S.t('Step 2 · tap a part to confirm',
                    'पायरी 2 · नोंदवण्यासाठी भागावर टॅप करा'),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B))),
            const SizedBox(height: 6),
            SizedBox(
              // Bounded height not needed: AsyncBody renders inline widgets.
              child: AsyncBody<List<dynamic>>(
                key: ValueKey('plan-$_lineId-$_shift'),
                future: _planFuture!,
                onRetry: _reloadPlan,
                builder: (context, rows) => _planBody(context, rows),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _planBody(BuildContext context, List<dynamic> rows) {
    double good = 0, rej = 0, rem = 0;
    for (final r in rows) {
      good += _num(r['confirmed_good']);
      rej += _num(r['confirmed_reject']);
      rem += _num(r['remaining']);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: KpiCard(
                label: S.t('Confirmed good', 'चांगले नोंदवले'),
                value: _qty(good))),
        const SizedBox(width: 8),
        Expanded(
            child: KpiCard(
                label: S.t('Rejected', 'नाकारले'),
                value: _qty(rej), delta: rej > 0 ? '▲' : null,
                deltaBad: rej > 0)),
        const SizedBox(width: 8),
        Expanded(
            child: KpiCard(
                label: S.t('Remaining', 'शिल्लक'), value: _qty(rem))),
      ]),
      const SizedBox(height: 10),
      if (rows.isEmpty)
        AlertBanner(
            title: S.t('No plan for this line today',
                'या लाईनसाठी आज प्लॅन नाही'),
            kind: 'warn'),
      for (final row in rows) _partCard(context, row as Map<String, dynamic>),
    ]);
  }

  Widget _partCard(BuildContext context, Map<String, dynamic> row) {
    final planned = _num(row['planned_qty']);
    final good = _num(row['confirmed_good']);
    final rej = _num(row['confirmed_reject']);
    final rem = _num(row['remaining']);
    final orderNo = row['sap_order_no'] as String?;
    return AppCard(
      title: row['description'] as String? ?? '—',
      meta: row['sap_code'] as String? ?? '',
      kind: orderNo == null ? 'urgent' : null,
      trailing: orderNo == null
          ? StatusBadge(S.t('NEEDS ORDER', 'ऑर्डर हवी'), kind: 'red')
          : StatusBadge(orderNo, kind: 'green'),
      onTap: () async {
        await context.push('/supervisor/confirm', extra: {
        'line_id': _lineId,
        'line_name': _lineName,
        'shift': _shift,
        'material_id': row['material_id'],
        'sap_code': row['sap_code'],
        'description': row['description'],
        'planned': row['planned_qty'],
        'good': row['confirmed_good'],
        'rejected': row['confirmed_reject'],
        });
        _reloadPlan(); // counts move after a post
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProgressBar(fraction: planned > 0 ? good / planned : 0),
        const SizedBox(height: 5),
        Text(
            '${S.t('Planned', 'नियोजित')} ${_qty(planned)} · '
            '${S.t('good', 'चांगले')} ${_qty(good)} · '
            '${S.t('reject', 'नाकारले')} ${_qty(rej)} · '
            '${S.t('remaining', 'शिल्लक')} ${_qty(rem)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF334155))),
      ]),
    );
  }
}
