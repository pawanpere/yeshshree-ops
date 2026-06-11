/// Inward QC / goods receipt (P20, app map scr-o-qc + scr-o-anom).
/// Worklist mode (gateEntry == null): open + matched gate entries; tap one to
/// open the form. Form: locked part + expected qty, operator-typed received qty
/// (NEVER prefilled — Domain_QA: 100% physical count), pass/fail, rejects,
/// optional weighbridge weight. 422 ANOMALY_HARD ⇒ re-type or confirm-escalate.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/retry_queue.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class GrFormScreen extends ConsumerStatefulWidget {
  const GrFormScreen({super.key, this.gateEntry});

  /// When pushed with a gate entry, the form opens directly on it.
  final Map<String, dynamic>? gateEntry;

  @override
  ConsumerState<GrFormScreen> createState() => _GrFormScreenState();
}

class _GrFormScreenState extends ConsumerState<GrFormScreen> {
  Map<String, dynamic>? _entry;
  List<Map<String, dynamic>>? _worklist;
  Map<int, String> _vendorNames = const {};
  Map<int, Map<String, dynamic>> _materials = const {};
  String? _error;

  final _received = TextEditingController();
  final _rejected = TextEditingController(text: '0');
  final _weight = TextEditingController();
  final _remarks = TextEditingController();
  String _qc = 'pass';
  bool _submitting = false;
  String? _pendingRef; // survives the re-type / escalate round-trip
  ({String title, String body})? _success;

  @override
  void initState() {
    super.initState();
    _entry = widget.gateEntry;
    _loadLookups();
    _loadWorklist();
  }

  @override
  void dispose() {
    _received.dispose();
    _rejected.dispose();
    _weight.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    try {
      final v = await Api.dio
          .get('/master/vendors', queryParameters: {'limit': 500});
      final m = await Api.dio
          .get('/master/materials', queryParameters: {'limit': 500});
      if (!mounted) return;
      setState(() {
        _vendorNames = {
          for (final x in v.data as List) (x as Map)['id'] as int: '${x['name']}',
        };
        _materials = {
          for (final x in m.data as List)
            (x as Map)['id'] as int: Map<String, dynamic>.from(x),
        };
      });
    } on DioException {
      // labels degrade to ids
    }
  }

  Future<void> _loadWorklist() async {
    try {
      final r = await Api.dio.get('/gate-entries',
          queryParameters: {'status': 'open', 'match_status': 'matched'});
      if (!mounted) return;
      setState(() {
        _worklist = (r.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _error = null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiException.from(e).message);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  String _matLabel(dynamic id) {
    final m = _materials[id];
    if (m == null) return id == null ? '—' : '#$id';
    return '${m['sap_code']} · ${m['description']}';
  }

  String _vendorOf(Map<String, dynamic> e) {
    final id = e['vendor_id'];
    if (id is int && _vendorNames.containsKey(id)) return _vendorNames[id]!;
    return '${e['vendor_name_text'] ?? S.t('Unknown vendor', 'अज्ञात पुरवठादार')}';
  }

  void _resetForm() {
    _received.clear();
    _rejected.text = '0';
    _weight.clear();
    _remarks.clear();
    _qc = 'pass';
    _pendingRef = null;
  }

  // --- submit -----------------------------------------------------------------

  Future<void> _submit({bool confirmEscalate = false}) async {
    final entry = _entry!;
    final received = _received.text.trim();
    if ((double.tryParse(received) ?? 0) <= 0) {
      _toast(S.t('Type the physically counted received qty',
          'प्रत्यक्ष मोजलेले प्राप्त प्रमाण टाका'));
      return;
    }
    final rejected =
        _rejected.text.trim().isEmpty ? '0' : _rejected.text.trim();
    _pendingRef ??= const Uuid().v4();
    final body = <String, dynamic>{
      'gate_entry_id': entry['id'],
      'received_qty': received, // Decimal as String
      'rejected_qty': rejected,
      'qc_result': _qc,
      if (_remarks.text.trim().isNotEmpty) 'qc_remarks': _remarks.text.trim(),
      if (_weight.text.trim().isNotEmpty)
        'weighbridge_weight': _weight.text.trim(),
      'confirm_escalate': confirmEscalate,
      'client_ref': _pendingRef,
    };
    setState(() => _submitting = true);
    try {
      final r = await ref
          .read(retryQueueProvider.notifier)
          .post('/goods-receipts', body, label: 'GR ${entry['doc_no']}');
      if (!mounted) return;
      if (r == null) {
        _toast(S.t('Queued — will sync', 'रांगेत — नंतर सिंक होईल'));
        _resetForm();
        setState(() => _entry = null);
        await _loadWorklist();
        return;
      }
      final shortage = double.tryParse('${r['shortage_qty'] ?? 0}') ?? 0;
      var bodyText = S.t(
          'GR ${r['doc_no']} posted · stock updated · synced to SAP',
          'GR ${r['doc_no']} पोस्ट झाला · साठा अद्ययावत · SAP कडे पाठवले');
      if (shortage > 0) {
        bodyText += ' · ${S.t(
            'Shortage ${r['shortage_qty']} → 5× debit drafted for approval',
            'तूट ${r['shortage_qty']} → ५× डेबिट नोट मंजुरीसाठी तयार')}';
      }
      if (r['qc_result'] == 'fail') {
        bodyText += ' · ${S.t('Full lot rejected — return gate pass issued',
            'संपूर्ण लॉट नाकारला — रिटर्न गेट पास जारी')}';
      }
      _resetForm();
      setState(() {
        _success =
            (title: S.t('Goods receipt posted', 'GR पोस्ट झाला'), body: bodyText);
        _entry = null;
      });
      await _loadWorklist();
    } on ApiException catch (ex) {
      if (!mounted) return;
      if (ex.code == 'ANOMALY_HARD') {
        await _hardBlockDialog(ex);
      } else {
        _toast(ex.message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _kv(dynamic m) => m is Map
      ? m.entries.map((e) => '${e.key}: ${e.value}').join(' · ')
      : '$m';

  /// §5.8 hard block: re-type, or confirm — escalate (supervisor + management).
  Future<void> _hardBlockDialog(ApiException ex) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.block, color: YColors.red, size: 36),
        title: Text(S.t('Hard block — number looks wrong',
            'कडक अडथळा — आकडा चुकीचा वाटतो')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ex.message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          if (ex.details['observed'] != null)
            Text('${S.t('Observed', 'नोंदवलेले')}: ${_kv(ex.details['observed'])}',
                style: const TextStyle(fontSize: 12, color: YColors.muted)),
          if (ex.details['expected'] != null)
            Text('${S.t('Expected', 'अपेक्षित')}: ${_kv(ex.details['expected'])}',
                style: const TextStyle(fontSize: 12, color: YColors.muted)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.t('Re-type', 'पुन्हा टाका')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: YColors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              _submit(confirmEscalate: true);
            },
            child: Text(S.t('Confirm — escalate', 'खात्री — वर पाठवा')),
          ),
        ],
      ),
    );
  }

  // --- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final formMode = _entry != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(formMode
            ? S.t('Goods receipt · ${_entry!['doc_no']}',
                'GR · ${_entry!['doc_no']}')
            : S.t('QC worklist', 'QC कामांची यादी')),
        leading: formMode && widget.gateEntry == null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _entry = null))
            : null,
      ),
      body: formMode ? _form() : _worklistBody(),
    );
  }

  Widget _worklistBody() {
    if (_worklist == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_worklist == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: YColors.red, fontSize: 12)),
          TextButton(
              onPressed: _loadWorklist,
              child: Text(S.t('Retry', 'पुन्हा प्रयत्न'))),
        ]),
      );
    }
    final list = _worklist!;
    return RefreshIndicator(
      onRefresh: _loadWorklist,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (_success != null)
            AlertBanner(
                kind: 'success',
                title: _success!.title,
                body: _success!.body),
          if (list.isEmpty)
            AlertBanner(
                kind: 'info',
                title: S.t('No receipts pending', 'कोणतेही GR प्रलंबित नाहीत'),
                body: S.t('Matched gate entries appear here for QC.',
                    'जुळलेल्या गेट नोंदी QC साठी येथे दिसतात.')),
          for (final e in list)
            ListRow(
              title: '${e['doc_no']} · ${_vendorOf(e)}',
              subtitle: '${_matLabel(e['material_id'])} · '
                  '${S.t('expected', 'अपेक्षित')} ${e['qty_expected'] ?? '—'} · '
                  '${e['vehicle_no'] ?? ''}',
              trailing: const Icon(Icons.chevron_right, color: YColors.muted),
              onTap: () => setState(() {
                _success = null;
                _entry = e;
              }),
            ),
        ],
      ),
    );
  }

  Widget _form() {
    final e = _entry!;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AppCard(
          kind: 'info',
          title: S.t('Linked to gate entry ${e['doc_no']}',
              'गेट नोंद ${e['doc_no']} शी जोडलेले'),
          meta: _vendorOf(e),
          child: Column(children: [
            InputDecorator(
              decoration:
                  InputDecoration(labelText: S.t('Part (locked)', 'भाग (लॉक)')),
              child: Text('${_matLabel(e['material_id'])} 🔒',
                  style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: InputDecoration(
                  labelText: S.t('Expected qty (locked)',
                      'अपेक्षित प्रमाण (लॉक)')),
              child: Text('${e['qty_expected'] ?? '—'} 🔒',
                  style: const TextStyle(fontSize: 13)),
            ),
          ]),
        ),
        TextField(
          controller: _received,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: S.t('Received qty *', 'प्राप्त प्रमाण *'),
            // Domain_QA / §11.18: NEVER prefilled — 100% physical count.
            helperText: S.t('Count physically, then type — never copy the invoice',
                'प्रत्यक्ष मोजा, मगच टाका — इनव्हॉइसवरून कॉपी करू नका'),
            helperStyle: const TextStyle(color: YColors.muted),
          ),
        ),
        const SizedBox(height: 12),
        Text(S.t('QUALITY DECISION', 'गुणवत्ता निर्णय'),
            style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: .4,
                color: YColors.muted,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'pass', label: Text(S.t('✓ Pass', '✓ पास'))),
            ButtonSegment(value: 'fail', label: Text(S.t('✗ Fail', '✗ फेल'))),
          ],
          selected: {_qc},
          onSelectionChanged: (s) => setState(() => _qc = s.first),
        ),
        const SizedBox(height: 10),
        if (_qc == 'fail')
          AlertBanner(
              kind: 'danger',
              title: S.t('Full-lot reject (§11.9)',
                  'संपूर्ण लॉट नाकारला जाईल (§11.9)'),
              body: S.t(
                  'Fail rejects the ENTIRE lot: no stock is posted, a return gate pass is issued and a full-value debit note is drafted.',
                  'फेल म्हणजे संपूर्ण लॉट नाकारला जातो: साठ्यात काही जमा होत नाही, रिटर्न गेट पास निघतो आणि पूर्ण रकमेची डेबिट नोट तयार होते.')),
        if (_qc == 'pass')
          TextField(
            controller: _rejected,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: S.t('Rejected qty', 'नाकारलेले प्रमाण'),
                helperText: S.t('Rejects are logged separately from received',
                    'नाकारलेले प्रमाण प्राप्त प्रमाणापासून वेगळे नोंदते')),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText:
                  S.t('Weighbridge weight, KG (optional)', 'वजन काटा, किलो (ऐच्छिक)')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _remarks,
          maxLines: 2,
          decoration:
              InputDecoration(labelText: S.t('QC remarks', 'QC शेरा')),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _submitting ? null : () => _submit(),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(S.t('Submit · post goods receipt',
                  'सबमिट करा · GR पोस्ट करा')),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
