/// Gate · pending scans (P17, app map scr-o-gate). One card per scanner drop:
/// decode badge + e-invoice suggestions; "Create entry" carries the suggestions
/// into the gate form. §11.4: GET /system/station-status — a gate_agent stale
/// > 5 min shows the "Scanner offline" danger banner (phone-camera fallback).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class ScansPendingScreen extends ConsumerStatefulWidget {
  const ScansPendingScreen({super.key});

  @override
  ConsumerState<ScansPendingScreen> createState() => _ScansPendingScreenState();
}

class _ScansPendingScreenState extends ConsumerState<ScansPendingScreen> {
  List<Map<String, dynamic>>? _items;
  List<Map<String, dynamic>> _stations = const [];
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
        const Duration(seconds: 30), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final r = await Api.dio.get('/gate-entries/scans/pending');
      var stations = const <Map<String, dynamic>>[];
      try {
        final st = await Api.dio.get('/system/station-status');
        stations = (st.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } on DioException {
        // status poll failing must never hide the scans list
      }
      if (!mounted) return;
      setState(() {
        _items = (r.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _stations = stations;
        _error = null;
      });
    } on DioException catch (e) {
      if (!mounted || silent) return;
      setState(() => _error = ApiException.from(e).message);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _discard(int scanId) async {
    try {
      await Api.dio.post('/gate-entries/scans/$scanId/discard');
      if (!mounted) return;
      _toast(S.t('Scan discarded', 'स्कॅन रद्द केले'));
      await _refresh(silent: true);
    } on DioException catch (e) {
      if (!mounted) return;
      _toast(ApiException.from(e).message);
    }
  }

  /// §11.4: any gate_agent with stale_seconds > 300 = scanner offline.
  Map<String, dynamic>? get _staleAgent {
    for (final s in _stations) {
      final stale = s['stale_seconds'];
      if (s['kind'] == 'gate_agent' && stale is num && stale > 300) return s;
    }
    return null;
  }

  String _offlineSince(Map<String, dynamic> agent) {
    final t = DateTime.tryParse('${agent['last_heartbeat_at'] ?? ''}');
    if (t == null) return '—';
    final local = (t.isUtc ? t : DateTime.utc(t.year, t.month, t.day, t.hour,
            t.minute, t.second))
        .toLocal();
    return DateFormat('HH:mm').format(local);
  }

  String _badgeKind(String decodeStatus) => switch (decodeStatus) {
        'decoded' => 'ok',
        'partial' => 'warn',
        _ => 'none', // falls to the default (no grey in statusColors)
      };

  String _summary(Map<String, dynamic> sugg) {
    final parts = <String>[];
    if (sugg['vendor_gstin'] != null) {
      parts.add('${S.t('Vendor GSTIN', 'पुरवठादार GSTIN')} ${sugg['vendor_gstin']}');
    }
    if (sugg['invoice_no'] != null) {
      var inv = '${S.t('Invoice', 'इनव्हॉइस')} ${sugg['invoice_no']}';
      if (sugg['invoice_date'] != null) inv += ' · ${sugg['invoice_date']}';
      if (sugg['invoice_value'] != null) inv += ' · ₹${sugg['invoice_value']}';
      parts.add(inv);
    }
    if (sugg['po_no'] != null) parts.add('PO ${sugg['po_no']}');
    if (sugg['vehicle_no'] != null) {
      parts.add('${S.t('Vehicle', 'वाहन')} ${sugg['vehicle_no']}');
    }
    if (parts.isEmpty) {
      parts.add(S.t('Nothing decoded — enter manually',
          'काहीही डीकोड झाले नाही — हाताने भरा'));
    }
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('Pending scans', 'प्रलंबित स्कॅन')),
        actions: [
          IconButton(
              onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_items == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: YColors.red, fontSize: 12)),
          TextButton(
              onPressed: _refresh, child: Text(S.t('Retry', 'पुन्हा प्रयत्न'))),
        ]),
      );
    }
    final stale = _staleAgent;
    final items = _items!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (stale != null)
            AlertBanner(
              kind: 'danger',
              title: S.t('Scanner offline since ${_offlineSince(stale)}',
                  'स्कॅनर ${_offlineSince(stale)} पासून बंद आहे'),
              body: S.t(
                  'Use the phone camera or manual entry — agent ${stale['device_key']} is not sending heartbeats.',
                  'फोन कॅमेरा किंवा हाताने नोंद वापरा — एजंट ${stale['device_key']} कडून संदेश येत नाहीत.'),
            ),
          if (items.isEmpty)
            AlertBanner(
                kind: 'info',
                title: S.t('No pending scans', 'प्रलंबित स्कॅन नाहीत'),
                body: S.t('New scanner drops appear here automatically.',
                    'नवीन स्कॅन येथे आपोआप दिसतील.')),
          for (final item in items) _scanCard(item),
        ],
      ),
    );
  }

  Widget _scanCard(Map<String, dynamic> item) {
    final scan = Map<String, dynamic>.from(item['scan'] as Map? ?? {});
    final sugg = Map<String, dynamic>.from(item['suggestions'] as Map? ?? {});
    final decode = '${scan['decode_status'] ?? 'none'}';
    return AppCard(
      title: sugg['invoice_no'] != null
          ? '${S.t('Invoice', 'इनव्हॉइस')} ${sugg['invoice_no']}'
          : '${S.t('Scan', 'स्कॅन')} #${scan['id']}',
      kind: decode == 'decoded' ? 'ok' : (decode == 'partial' ? 'warn' : null),
      meta: '${S.t('Scan', 'स्कॅन')} #${scan['id']} · ${scan['source']}',
      body: _summary(sugg),
      trailing: StatusBadge(decode, kind: _badgeKind(decode)),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: YColors.red),
            onPressed: () => _discard(scan['id'] as int),
            child: Text(S.t('Discard', 'रद्द करा')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: () async {
              await context.push('/gate/entry',
                  extra: Map<String, dynamic>.from(sugg));
              if (mounted) _refresh(silent: true);
            },
            child: Text(S.t('Create entry', 'नोंद करा')),
          ),
        ),
      ]),
    );
  }
}
