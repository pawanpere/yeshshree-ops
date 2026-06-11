/// Anomaly register (app map scr-m-anom): hard-blocks and soft flags raised by
/// validation rules, filterable by status (open / in_review / resolved) and
/// severity (hard / soft). Field names mirror AnomalyRead in
/// backend/app/schemas/receiving.py exactly.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class AnomaliesScreen extends StatefulWidget {
  const AnomaliesScreen({super.key});

  @override
  State<AnomaliesScreen> createState() => _AnomaliesScreenState();
}

class _AnomaliesScreenState extends State<AnomaliesScreen> {
  String _status = 'open'; // open | in_review | resolved
  String? _severity; // null = all | hard | soft

  List<dynamic>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items == null;
      _error = null;
    });
    try {
      final r = await Api.dio.get('/anomalies', queryParameters: {
        'status': _status,
        if (_severity != null) 'severity': _severity,
      });
      if (!mounted) return;
      setState(() {
        _items = r.data as List;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiException.from(e).message;
      });
    }
  }

  void _setFilter({String? status, String? severity, bool clearSeverity = false}) {
    setState(() {
      if (status != null) _status = status;
      if (severity != null || clearSeverity) _severity = severity;
      _items = null; // force a fresh spinner for the new filter
    });
    _load();
  }

  Future<void> _resolve(Map<String, dynamic> a) async {
    final note = await _noteDialog(
        title: S.t('Resolve anomaly #${a['id']}',
            'विसंगती #${a['id']} निकाली काढा'));
    if (note == null || note.isEmpty) return;
    try {
      await Api.dio.post('/anomalies/${a['id']}/resolve', data: {'note': note});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('Anomaly resolved', 'विसंगती निकाली'))));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiException.from(e).message)));
    }
  }

  /// Resolution note is mandatory (it is stored in the audit diff).
  Future<String?> _noteDialog({required String title}) {
    final ctrl = TextEditingController();
    String? err;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 16)),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: S.t('What was done? (required)',
                  'काय केले? (आवश्यक)'),
              errorText: err,
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(S.t('Cancel', 'रद्द करा'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(110, 40)),
              onPressed: () {
                final v = ctrl.text.trim();
                if (v.isEmpty) {
                  setLocal(() =>
                      err = S.t('A note is required', 'टीप आवश्यक आहे'));
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: Text(S.t('Resolve', 'निकाली काढा')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('Anomaly register', 'विसंगती नोंदवही'))),
      body: Column(children: [
        _filters(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_error != null)
                                AlertBanner(
                                    kind: 'danger',
                                    title: _error!,
                                    body: S.t('Pull to retry.',
                                        'पुन्हा प्रयत्नासाठी खाली ओढा.')),
                              if (_items != null && _items!.isEmpty)
                                AlertBanner(
                                    kind: 'success',
                                    title:
                                        S.t('Nothing here', 'येथे काही नाही'),
                                    body: S.t(
                                        'No anomalies match this filter.',
                                        'या फिल्टरमध्ये विसंगती नाहीत.')),
                              ...?_items?.map((raw) => _anomalyCard(
                                  Map<String, dynamic>.from(raw as Map))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _filters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip(S.t('Open', 'खुल्या'), _status == 'open',
                  () => _setFilter(status: 'open')),
              _chip(S.t('In review', 'तपासणीत'), _status == 'in_review',
                  () => _setFilter(status: 'in_review')),
              _chip(S.t('Resolved', 'निकाली'), _status == 'resolved',
                  () => _setFilter(status: 'resolved')),
              Container(
                  width: 1,
                  height: 22,
                  color: YColors.line,
                  margin: const EdgeInsets.symmetric(horizontal: 8)),
              _chip(S.t('All', 'सर्व'), _severity == null,
                  () => _setFilter(clearSeverity: true)),
              _chip(S.t('Hard', 'हार्ड'), _severity == 'hard',
                  () => _setFilter(severity: 'hard')),
              _chip(S.t('Soft', 'सॉफ्ट'), _severity == 'soft',
                  () => _setFilter(severity: 'soft')),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? YColors.navy : Colors.white,
            border: Border.all(color: active ? YColors.navy : YColors.line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : YColors.navy)),
        ),
      ),
    );
  }

  Widget _anomalyCard(Map<String, dynamic> a) {
    final severity = (a['severity'] as String?) ?? 'soft';
    final status = (a['status'] as String?) ?? 'open';
    final hard = severity == 'hard';
    final resolved = status == 'resolved';
    final message = S.lang.value == 'mr'
        ? (a['message_mr'] as String?) ?? (a['message_en'] as String?) ?? ''
        : (a['message_en'] as String?) ?? '';
    final observed = a['observed'] is Map
        ? Map<String, dynamic>.from(a['observed'] as Map)
        : <String, dynamic>{};
    final expected = a['expected'] is Map
        ? Map<String, dynamic>.from(a['expected'] as Map)
        : <String, dynamic>{};

    return AppCard(
      kind: resolved
          ? 'ok'
          : hard
              ? 'urgent'
              : 'warn',
      title: message,
      meta:
          '${a['ref_type'] ?? ''} #${a['ref_id'] ?? ''} · ${_age(a['created_at'] as String?)}',
      trailing: StatusBadge(hard ? 'HARD-BLOCK' : 'SOFT FLAG',
          kind: hard ? 'bad' : 'warn'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 5, runSpacing: 4, children: [
            StatusBadge((a['rule_code'] as String?) ?? '—', kind: 'blue'),
            if (status == 'in_review')
              const StatusBadge('IN REVIEW', kind: 'warn'),
            if (resolved) const StatusBadge('RESOLVED', kind: 'ok'),
          ]),
          if (observed.isNotEmpty || expected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: _kvBlock(
                          S.t('Observed', 'आढळले'), observed)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _kvBlock(
                          S.t('Expected', 'अपेक्षित'), expected)),
                ],
              ),
            ),
          if (!resolved)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: YColors.green,
                      minimumSize: const Size(120, 36)),
                  onPressed: () => _resolve(a),
                  child: Text(S.t('Resolve', 'निकाली काढा')),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kvBlock(String heading, Map<String, dynamic> m) {
    if (m.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading.toUpperCase(),
            style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
                color: YColors.muted)),
        ...m.entries.map((e) => Text(
            '${e.key.replaceAll('_', ' ')}: ${e.value ?? '—'}',
            style: const TextStyle(fontSize: 11, color: YColors.ink))),
      ],
    );
  }

  String _age(String? iso) {
    if (iso == null) return '';
    var t = DateTime.tryParse(iso);
    if (t == null) return '';
    if (!t.isUtc) t = DateTime.tryParse('${iso}Z') ?? t.toUtc();
    final diff = DateTime.now().toUtc().difference(t);
    if (diff.inMinutes < 1) return S.t('just now', 'आत्ताच');
    if (diff.inMinutes < 60) {
      return S.t('${diff.inMinutes} min ago', '${diff.inMinutes} मि. पूर्वी');
    }
    if (diff.inHours < 24) {
      return S.t('${diff.inHours} h ago', '${diff.inHours} ता. पूर्वी');
    }
    return S.t('${diff.inDays} d ago', '${diff.inDays} दि. पूर्वी');
  }
}
