/// Confirmation holds (§11.11): confirmations parked because no production
/// order resolved. Planning/admin resolve with the SAP order number — the
/// frozen payload then posts; everyone else sees "waiting for PPC".
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/strings.dart';
import '../../widgets/common.dart';

class HoldsScreen extends ConsumerStatefulWidget {
  const HoldsScreen({super.key});

  @override
  ConsumerState<HoldsScreen> createState() => _HoldsScreenState();
}

class _HoldsScreenState extends ConsumerState<HoldsScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<dynamic>> _fetch() async {
    try {
      final r = await Api.dio
          .get('/confirmations/holds', queryParameters: {'status': 'open'});
      return r.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  void _reload() => setState(() => _future = _fetch());

  String _age(String? createdAt) {
    final t = DateTime.tryParse(createdAt ?? '');
    if (t == null) return '';
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 48) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).role;
    final canResolve = role == 'planning' || role == 'admin';
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('Holds — needs order', 'होल्ड्स — ऑर्डर हवी')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: AsyncBody<List<dynamic>>(
          future: _future,
          onRetry: _reload,
          builder: (context, holds) {
            if (holds.isEmpty) {
              return AlertBanner(
                  title: S.t('No open holds', 'कोणतेही होल्ड्स नाहीत'),
                  kind: 'success');
            }
            return ListView(children: [
              for (final h in holds)
                _holdCard(h as Map<String, dynamic>, canResolve),
            ]);
          },
        ),
      ),
    );
  }

  Widget _holdCard(Map<String, dynamic> h, bool canResolve) {
    final payload =
        Map<String, dynamic>.from(h['payload'] as Map? ?? const {});
    final age = _age(h['created_at'] as String?);
    return AppCard(
      kind: 'warn',
      title: '${S.t('Hold', 'होल्ड')} #${h['id']} · '
          '${S.t('material', 'मटेरियल')} ${h['material_id']}',
      meta:
          '${S.t('line', 'लाईन')} ${h['line_id']} · $age ${S.t('old', 'जुने')}',
      body: '${S.t('good', 'चांगले')} ${payload['good_qty'] ?? '?'} · '
          '${S.t('rej', 'नाकारले')} ${payload['rejected_qty'] ?? '0'} · '
          '${S.t('shift', 'पाळी')} ${payload['shift'] ?? '?'} · '
          '${payload['kind'] ?? 'interim'}',
      trailing: StatusBadge(S.t('NEEDS ORDER', 'ऑर्डर हवी'), kind: 'red'),
      child: canResolve
          ? Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton(
                onPressed: () => _resolveDialog(h),
                child: Text(S.t('Resolve', 'सोडवा')),
              ),
            )
          : Text(S.t('Waiting for PPC to supply the production order.',
                  'PPC कडून उत्पादन ऑर्डरची वाट पाहत आहे.'),
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
    );
  }

  Future<void> _resolveDialog(Map<String, dynamic> h) async {
    final orderCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('Resolve hold #${h['id']}',
            'होल्ड #${h['id']} सोडवा')),
        content: TextField(
          controller: orderCtrl,
          decoration: InputDecoration(
              labelText: S.t('SAP order no', 'SAP ऑर्डर क्रमांक')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(S.t('Cancel', 'रद्द'))),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(S.t('Resolve & post', 'सोडवा व नोंदवा'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final orderNo = orderCtrl.text.trim();
    if (orderNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              S.t('SAP order no is required', 'SAP ऑर्डर क्रमांक आवश्यक'))));
      return;
    }
    try {
      await Api.dio.post('/confirmations/holds/${h['id']}/resolve',
          data: {'sap_order_no': orderNo});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(S.t('Hold resolved — confirmation posted',
              'होल्ड सोडवला — नोंद झाली'))));
      _reload();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiException.from(e).message)));
    }
  }
}
