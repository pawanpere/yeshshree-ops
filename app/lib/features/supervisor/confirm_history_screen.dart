/// Confirmation history (scr-s-history): today's posts with SAP sync status,
/// locally-queued posts pinned on top (grey QUEUED), and the safe correction
/// path on long-press — corrections go for approval, never silent edits.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/retry_queue.dart';
import '../../core/strings.dart';
import '../../widgets/common.dart';

class ConfirmHistoryScreen extends ConsumerStatefulWidget {
  const ConfirmHistoryScreen({super.key});

  @override
  ConsumerState<ConfirmHistoryScreen> createState() =>
      _ConfirmHistoryScreenState();
}

class _ConfirmHistoryScreenState extends ConsumerState<ConfirmHistoryScreen> {
  List<dynamic>? _lines;
  int? _lineId;
  DateTime _date = DateTime.now();
  Future<List<dynamic>>? _future;

  String get _dateIso => _date.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _loadLines();
    _reload();
  }

  Future<void> _loadLines() async {
    try {
      final r = await Api.dio.get('/master/lines');
      if (mounted) setState(() => _lines = r.data as List<dynamic>);
    } on DioException catch (_) {}
  }

  Future<List<dynamic>> _fetch() async {
    try {
      final r = await Api.dio.get('/confirmations', queryParameters: {
        if (_lineId != null) 'line_id': _lineId,
        'date': _dateIso,
      });
      return r.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  void _reload() => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    final queued = ref
        .watch(retryQueueProvider)
        .where((q) => q.path == '/confirmations')
        .toList();
    return Scaffold(
      appBar:
          AppBar(title: Text(S.t('Confirmation history', 'नोंद इतिहास'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _lineId,
                hint: Text(S.t('All lines', 'सर्व लाईन्स')),
                items: [
                  DropdownMenuItem<int?>(
                      value: null,
                      child: Text(S.t('All lines', 'सर्व लाईन्स'))),
                  ...(_lines ?? []).map((l) => DropdownMenuItem<int?>(
                      value: l['id'] as int,
                      child: Text(l['name'] as String? ?? '—'))),
                ],
                onChanged: (v) {
                  _lineId = v;
                  _reload();
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(_dateIso),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030));
                if (d != null) {
                  _date = d;
                  _reload();
                }
              },
            ),
          ]),
          const SizedBox(height: 10),
          // Locally queued posts — first-class: visible before they ever
          // reach the server, drained automatically by the retry queue.
          for (final q in queued) _queuedRow(q),
          if (_future != null)
            AsyncBody<List<dynamic>>(
              key: ValueKey('hist-$_lineId-$_dateIso'),
              future: _future!,
              onRetry: _reload,
              builder: (context, rows) {
                if (rows.isEmpty && queued.isEmpty) {
                  return AlertBanner(
                      title: S.t('No confirmations for this day',
                          'या दिवशी नोंदी नाहीत'),
                      kind: 'info');
                }
                return Column(children: [
                  for (final row in rows)
                    _postedRow(row as Map<String, dynamic>),
                ]);
              },
            ),
        ],
      ),
    );
  }

  Widget _queuedRow(QueuedPost q) {
    final t = q.queuedAt;
    final hh = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    return ListRow(
      title: '$hh · ${S.t('good', 'चांगले')} ${q.body['good_qty'] ?? '?'} · '
          '${S.t('rej', 'नाकारले')} ${q.body['rejected_qty'] ?? '0'}',
      subtitle: q.label,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(20)),
        child: Text(S.t('QUEUED', 'रांगेत'),
            style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 9.5,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _postedRow(Map<String, dynamic> row) {
    final posted = DateTime.tryParse(row['posted_at'] as String? ?? '');
    final local = posted?.toLocal();
    final hh = local == null
        ? '--:--'
        : '${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}';
    final downtime = (row['downtime_min'] as num?)?.toInt() ?? 0;
    final sync = row['sap_sync_status'] as String? ?? 'pending';
    final syncKind = switch (sync) {
      'pending' => 'amber',
      'batched' || 'sent' || 'acked' => 'green',
      'failed' => 'red',
      _ => 'blue',
    };
    return GestureDetector(
      onLongPress: () => _correctionDialog(row),
      child: ListRow(
        title: '$hh · ${S.t('good', 'चांगले')} ${row['good_qty']} · '
            '${S.t('rej', 'नाकारले')} ${row['rejected_qty']}',
        subtitle: '${row['kind']}'
            '${downtime > 0 ? ' · ${S.t('downtime', 'डाउनटाइम')} ${downtime}m' : ''}',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (row['posted_after_close'] == true) ...[
            StatusBadge(S.t('LATE', 'उशिरा'), kind: 'amber'),
            const SizedBox(width: 4),
          ],
          StatusBadge(sync, kind: syncKind),
        ]),
      ),
    );
  }

  Future<void> _correctionDialog(Map<String, dynamic> row) async {
    final dGood = TextEditingController();
    final dRej = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('Request correction', 'दुरुस्ती विनंती')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: dGood,
              keyboardType:
                  const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: InputDecoration(
                  labelText: S.t('Delta good (±)', 'चांगले फरक (±)'))),
          const SizedBox(height: 8),
          TextField(
              controller: dRej,
              keyboardType:
                  const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: InputDecoration(
                  labelText: S.t('Delta reject (±)', 'नाकारले फरक (±)'))),
          const SizedBox(height: 8),
          TextField(
              controller: reason,
              decoration:
                  InputDecoration(labelText: S.t('Reason', 'कारण'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(S.t('Cancel', 'रद्द'))),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(S.t('Submit', 'पाठवा'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (double.tryParse(dGood.text.trim()) == null ||
        reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(S.t('Delta good and reason are required',
              'फरक व कारण आवश्यक आहे'))));
      return;
    }
    try {
      await Api.dio.post('/confirmations/${row['id']}/correction', data: {
        'delta_good': dGood.text.trim(),
        'delta_reject': dRej.text.trim().isEmpty ? '0' : dRej.text.trim(),
        'reason': reason.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(S.t('Correction submitted — goes for approval',
              'दुरुस्ती पाठवली — मंजुरीसाठी जाईल'))));
      _reload();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiException.from(e).message)));
    }
  }
}
