/// Unmatched-PO review folder (P18, app map scr-o-unmatched). Open entries that
/// did not auto-match a PO + pending backfills, oldest first (they age toward
/// the >24h purchase alarm). Resolve by linking a PO, marking consumable, or
/// completing a §11.3 backfill via the gate form.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class UnmatchedScreen extends ConsumerStatefulWidget {
  const UnmatchedScreen({super.key});

  @override
  ConsumerState<UnmatchedScreen> createState() => _UnmatchedScreenState();
}

class _UnmatchedScreenState extends ConsumerState<UnmatchedScreen> {
  List<Map<String, dynamic>>? _entries;
  Map<int, String> _vendorNames = const {};
  Map<int, String> _materialNames = const {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final r = await Api.dio.get('/gate-entries/unmatched');
      var vendors = _vendorNames;
      var materials = _materialNames;
      try {
        final v = await Api.dio
            .get('/master/vendors', queryParameters: {'limit': 500});
        vendors = {
          for (final m in v.data as List)
            (m as Map)['id'] as int: '${m['name']}',
        };
        final mt = await Api.dio
            .get('/master/materials', queryParameters: {'limit': 500});
        materials = {
          for (final m in mt.data as List)
            (m as Map)['id'] as int: '${m['sap_code']} · ${m['description']}',
        };
      } on DioException {
        // name lookups are best-effort; ids still render
      }
      if (!mounted) return;
      setState(() {
        _entries = (r.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _vendorNames = vendors;
        _materialNames = materials;
        _error = null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiException.from(e).message);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  String _vendorOf(Map<String, dynamic> e) {
    final id = e['vendor_id'];
    if (id is int && _vendorNames.containsKey(id)) return _vendorNames[id]!;
    final text = e['vendor_name_text'];
    if (text != null && '$text'.isNotEmpty) return '$text';
    return S.t('Unknown vendor', 'अज्ञात पुरवठादार');
  }

  String _age(dynamic iso) {
    final t = DateTime.tryParse('${iso ?? ''}');
    if (t == null) return '';
    final tu = t.isUtc
        ? t
        : DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);
    final d = DateTime.now().toUtc().difference(tu);
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Future<void> _markConsumable(Map<String, dynamic> e) async {
    try {
      await Api.dio.post('/gate-entries/${e['id']}/mark-consumable');
      if (!mounted) return;
      _toast(S.t('Marked consumable', 'उपभोग्य म्हणून नोंदले'));
      await _refresh();
    } on DioException catch (ex) {
      if (!mounted) return;
      _toast(ApiException.from(ex).message);
    }
  }

  Future<void> _linkPo(Map<String, dynamic> e) async {
    List<Map<String, dynamic>> pos;
    try {
      final r = await Api.dio.get('/master/purchase-orders', queryParameters: {
        if (e['vendor_id'] != null) 'vendor_id': e['vendor_id'],
      });
      pos = (r.data as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
    } on DioException catch (ex) {
      if (!mounted) return;
      _toast(ApiException.from(ex).message);
      return;
    }
    if (!mounted) return;
    if (pos.isEmpty) {
      _toast(S.t('No open POs found for this vendor',
          'या पुरवठादारासाठी खुले PO सापडले नाहीत'));
      return;
    }
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            Text(S.t('Link a purchase order', 'खरेदी ऑर्डर (PO) जोडा'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: YColors.navy)),
            const SizedBox(height: 8),
            for (final po in pos)
              ListRow(
                title: '${po['sap_po_no']} · '
                    '${_materialNames[po['material_id']] ?? '#${po['material_id']}'}',
                subtitle:
                    '${S.t('Open qty', 'खुले प्रमाण')} ${po['open_qty'] ?? '—'} '
                    '${po['uom'] ?? ''}',
                onTap: () => Navigator.of(ctx).pop(po),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      await Api.dio.post('/gate-entries/${e['id']}/link-po',
          data: {'po_id': chosen['id']});
      if (!mounted) return;
      _toast(S.t('PO linked — entry matched', 'PO जोडला — नोंद जुळली'));
      await _refresh();
    } on DioException catch (ex) {
      if (!mounted) return;
      _toast(ApiException.from(ex).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(S.t('Review folder · unmatched',
              'पुनरावलोकन फोल्डर · न जुळलेले'))),
      body: _body(),
    );
  }

  Widget _body() {
    if (_entries == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entries == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: YColors.red, fontSize: 12)),
          TextButton(
              onPressed: _refresh,
              child: Text(S.t('Retry', 'पुन्हा प्रयत्न'))),
        ]),
      );
    }
    final entries = _entries!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (entries.isEmpty)
            AlertBanner(
                kind: 'success',
                title: S.t('Nothing unmatched', 'सर्व नोंदी जुळल्या आहेत'),
                body: S.t('Every gate entry is matched or resolved.',
                    'प्रत्येक गेट नोंद जुळलेली किंवा निकाली आहे.'))
          else
            AlertBanner(
                kind: 'warn',
                title: S.t("These didn't auto-match a PO",
                    'या नोंदी PO शी आपोआप जुळल्या नाहीत'),
                body: S.t(
                    'Nothing posts to stock until matched. Link the right PO or mark consumable.',
                    'जुळेपर्यंत साठ्यात काहीही जमा होत नाही. योग्य PO जोडा किंवा उपभोग्य म्हणून नोंदवा.')),
          for (final e in entries) _card(e),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> e) {
    final backfillPending = e['backfill_status'] == 'pending_completion';
    final invoice = e['invoice_no'] == null
        ? S.t('No invoice', 'इनव्हॉइस नाही')
        : '${S.t('Invoice', 'इनव्हॉइस')} ${e['invoice_no']}';
    return AppCard(
      kind: 'warn',
      title: '${e['doc_no']} · ${_vendorOf(e)}',
      meta: '$invoice · ${e['vehicle_no'] ?? ''} · '
          '${_age(e['created_at'])} ${S.t('old', 'जुनी')}',
      trailing: StatusBadge(
          backfillPending ? S.t('BACKFILL', 'बॅकफिल') : S.t('NO PO', 'PO नाही'),
          kind: backfillPending ? 'purple' : 'warn'),
      child: backfillPending
          ? ElevatedButton(
              onPressed: () async {
                await context.push('/gate/entry', extra: {
                  'mode': 'complete-backfill',
                  'entry_id': e['id'],
                });
                if (mounted) _refresh();
              },
              child: Text(S.t('Complete', 'पूर्ण करा')),
            )
          : Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _markConsumable(e),
                  child: Text(S.t('Consumable', 'उपभोग्य')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _linkPo(e),
                  child: Text(S.t('Link PO', 'PO जोडा')),
                ),
              ),
            ]),
    );
  }
}
