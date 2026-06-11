/// Gate entry form (P16+P18, app map scr-o-gate). Prefilled from scanner
/// suggestions when present; PO selection LOCKS item + qty (server re-locks from
/// the PO line). Submits through the retry queue (offline ⇒ queued — will sync).
/// §11.6: 409 DUPLICATE_INVOICE offers explicit consignment continuation.
/// §11.3: extra {'mode':'complete-backfill','entry_id':X} turns the same form
/// into the backfill completion POST (direct, no queue — needs the 422 answers).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/retry_queue.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class GateEntryScreen extends ConsumerStatefulWidget {
  const GateEntryScreen({super.key, this.scanSuggestions});

  /// Scanner suggestions payload (scans/pending), OR
  /// {'mode': 'complete-backfill', 'entry_id': X} for §11.3 completion.
  final Map<String, dynamic>? scanSuggestions;

  @override
  ConsumerState<GateEntryScreen> createState() => _GateEntryScreenState();
}

class _GateEntryScreenState extends ConsumerState<GateEntryScreen> {
  final _clientRef = const Uuid().v4();

  String _docType = 'invoice';
  String? _inwardCategory;
  Map<String, dynamic>? _vendor;
  List<Map<String, dynamic>> _pos = const [];
  Map<String, dynamic>? _po;
  Map<int, Map<String, dynamic>> _materials = const {};

  final _invoiceNo = TextEditingController();
  final _invoiceValue = TextEditingController();
  final _vehicle = TextEditingController();
  final _driver = TextEditingController();
  DateTime? _invoiceDate;
  String? _irn;
  bool _submitting = false;

  bool get _isBackfill =>
      widget.scanSuggestions?['mode'] == 'complete-backfill';
  int? get _backfillEntryId => widget.scanSuggestions?['entry_id'] as int?;
  Map<String, dynamic> get _sugg =>
      _isBackfill ? const {} : (widget.scanSuggestions ?? const {});

  @override
  void initState() {
    super.initState();
    final s = _sugg;
    _invoiceNo.text = '${s['invoice_no'] ?? ''}';
    if (s['invoice_value'] != null) _invoiceValue.text = '${s['invoice_value']}';
    _vehicle.text = '${s['vehicle_no'] ?? ''}';
    _invoiceDate = _parseDate(s['invoice_date']);
    if (s['irn'] != null) _irn = '${s['irn']}';
    _loadMaterials();
  }

  @override
  void dispose() {
    _invoiceNo.dispose();
    _invoiceValue.dispose();
    _vehicle.dispose();
    _driver.dispose();
    super.dispose();
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(s); // GST QR DocDt format
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMaterials() async {
    try {
      final r = await Api.dio
          .get('/master/materials', queryParameters: {'limit': 500});
      if (!mounted) return;
      setState(() => _materials = {
            for (final m in r.data as List)
              (m as Map)['id'] as int: Map<String, dynamic>.from(m),
          });
    } on DioException {
      // labels degrade to material ids; the form still works
    }
  }

  Future<void> _loadPos() async {
    final vendorId = _vendor?['id'];
    if (vendorId == null) return;
    try {
      final r = await Api.dio.get('/master/purchase-orders',
          queryParameters: {'vendor_id': vendorId});
      if (!mounted) return;
      final pos = (r.data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      Map<String, dynamic>? preselect;
      final poNo = _sugg['po_no'];
      if (poNo != null) {
        for (final p in pos) {
          if ('${p['sap_po_no']}' == '$poNo') {
            preselect = p;
            break;
          }
        }
      }
      setState(() {
        _pos = pos;
        _po = preselect;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      _toast(ApiException.from(e).message);
    }
  }

  String _matLabel(dynamic materialId) {
    final m = _materials[materialId];
    if (m == null) return materialId == null ? '—' : '#$materialId';
    return '${m['sap_code']} · ${m['description']}';
  }

  String _poLabel(Map<String, dynamic> po) =>
      '${po['sap_po_no']} · ${_matLabel(po['material_id'])} · '
      '${S.t('open', 'शिल्लक')} ${po['open_qty'] ?? '—'} ${po['uom'] ?? ''}';

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // --- submit ---------------------------------------------------------------

  Future<void> _submit({int? consignmentNo, int? consignmentTotal}) async {
    if (_docType == 'invoice' &&
        (_vendor == null || _invoiceNo.text.trim().isEmpty)) {
      _toast(S.t('Invoice entries need a vendor and an invoice number',
          'इनव्हॉइस नोंदीसाठी पुरवठादार आणि इनव्हॉइस क्रमांक आवश्यक'));
      return;
    }
    if (_docType == 'other_inward' && _inwardCategory == null) {
      _toast(S.t('Select the inward category', 'आवक प्रकार निवडा'));
      return;
    }
    if (!_isBackfill &&
        (_vehicle.text.trim().isEmpty || _driver.text.trim().isEmpty)) {
      _toast(S.t('Vehicle number and driver name are required',
          'वाहन क्रमांक आणि चालकाचे नाव आवश्यक'));
      return;
    }

    final body = <String, dynamic>{
      'doc_type': _docType,
      if (_docType == 'other_inward') 'inward_category': _inwardCategory,
      if (_vendor != null) 'vendor_id': _vendor!['id'],
      if (_invoiceNo.text.trim().isNotEmpty)
        'invoice_no': _invoiceNo.text.trim(),
      if (_invoiceDate != null)
        'invoice_date': DateFormat('yyyy-MM-dd').format(_invoiceDate!),
      if (_invoiceValue.text.trim().isNotEmpty)
        'invoice_value': _invoiceValue.text.trim(), // Decimal as String
      if (_irn != null) 'irn': _irn,
      if (_po != null) 'po_id': _po!['id'],
      if (consignmentNo != null) 'consignment_no': consignmentNo,
      if (consignmentTotal != null) 'consignment_total': consignmentTotal,
    };

    setState(() => _submitting = true);
    try {
      if (_isBackfill) {
        // Direct (not queued): completion needs immediate 409/422 answers.
        final r = await Api.dio.post(
            '/gate-entries/$_backfillEntryId/complete-backfill',
            data: body);
        if (!mounted) return;
        final data = Map<String, dynamic>.from(r.data as Map);
        await _successDialog(
            S.t('Entry completed', 'नोंद पूर्ण झाली'),
            '${data['doc_no']} · ${S.t('match', 'जुळणी')}: '
            '${data['match_status']}');
      } else {
        body['client_ref'] = _clientRef;
        body['vehicle_no'] = _vehicle.text.trim();
        body['driver_name'] = _driver.text.trim();
        final r = await ref.read(retryQueueProvider.notifier).post(
            '/gate-entries', body,
            label: 'Gate entry ${_vehicle.text.trim()}');
        if (!mounted) return;
        if (r == null) {
          _toast(S.t('Queued — will sync', 'रांगेत — नंतर सिंक होईल'));
          if (context.canPop()) context.pop();
        } else {
          await _successDialog(
              S.t('Gate pass created', 'गेट पास तयार झाला'),
              S.t('Gate pass ${r['doc_no']} created · QC notified',
                  'गेट पास ${r['doc_no']} तयार झाला · QC ला कळवले'));
        }
      }
    } on ApiException catch (ex) {
      _handleApi(ex);
    } on DioException catch (e) {
      _handleApi(ApiException.from(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleApi(ApiException ex) {
    if (!mounted) return;
    if (ex.code == 'DUPLICATE_INVOICE') {
      _duplicateDialog(ex);
    } else {
      _toast(ex.message);
    }
  }

  /// §11.6 split-delivery continuation.
  Future<void> _duplicateDialog(ApiException ex) async {
    final next = (ex.details['next_consignment_no'] as num?)?.toInt() ?? 2;
    final existingDoc = '${ex.details['existing_doc_no'] ?? '—'}';
    final totalCtl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('Duplicate invoice', 'इनव्हॉइस आधीच नोंदले आहे')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ex.message, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Text('${S.t('Existing entry', 'आधीची नोंद')}: $existingDoc',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
              S.t('This is consignment $next of a split delivery?',
                  'ही विभागलेल्या डिलिव्हरीची खेप क्र. $next आहे का?'),
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: totalCtl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: S.t('Total consignments (optional)',
                    'एकूण खेपा (ऐच्छिक)')),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(S.t('Cancel', 'रद्द'))),
          FilledButton(
            onPressed: () {
              final total = int.tryParse(totalCtl.text.trim());
              Navigator.of(ctx).pop();
              _submit(consignmentNo: next, consignmentTotal: total);
            },
            child: Text(S.t('Continue as consignment $next',
                'खेप $next म्हणून पुढे जा')),
          ),
        ],
      ),
    );
  }

  Future<void> _successDialog(String title, String body) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: YColors.green, size: 36),
        title: Text(title),
        content: Text(body, textAlign: TextAlign.center),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(S.t('OK', 'ठीक'))),
        ],
      ),
    );
    if (!mounted) return;
    if (context.canPop()) context.pop();
  }

  // --- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isBackfill
            ? S.t('Complete entry', 'नोंद पूर्ण करा')
            : S.t('Gate entry · new', 'गेट नोंद · नवीन')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_isBackfill)
            AlertBanner(
                kind: 'info',
                title: S.t('Completing backfill entry #$_backfillEntryId',
                    'बॅकफिल नोंद #$_backfillEntryId पूर्ण करत आहोत'),
                body: S.t(
                    'Vehicle and driver were captured at the gate; add the document details.',
                    'वाहन व चालक गेटवर नोंदले आहेत; कागदपत्र तपशील भरा.')),
          if (!_isBackfill && _sugg.isNotEmpty)
            AlertBanner(
                kind: 'success',
                title: S.t('Prefilled from scan', 'स्कॅनमधून आधीच भरले'),
                body: S.t('Check every field before submitting.',
                    'सबमिट करण्यापूर्वी प्रत्येक रकाना तपासा.')),
          _label(S.t('Document type', 'कागदपत्र प्रकार')),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: 'invoice',
                  label: Text(S.t('Invoice', 'इनव्हॉइस'))),
              ButtonSegment(
                  value: 'challan', label: Text(S.t('Challan', 'चलन'))),
              ButtonSegment(
                  value: 'other_inward',
                  label: Text(S.t('Other', 'इतर'))),
            ],
            selected: {_docType},
            onSelectionChanged: (sel) => setState(() => _docType = sel.first),
          ),
          if (_docType == 'other_inward') ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _inwardCategory,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: S.t('Inward category', 'आवक प्रकार')),
              items: [
                DropdownMenuItem(
                    value: 'po_supply',
                    child: Text(S.t('PO supply', 'PO पुरवठा'))),
                DropdownMenuItem(
                    value: 'customer_return',
                    child: Text(S.t('Customer return', 'ग्राहक परतावा'))),
                DropdownMenuItem(
                    value: 'consumable',
                    child: Text(S.t('Consumable', 'उपभोग्य'))),
                DropdownMenuItem(
                    value: 'repair', child: Text(S.t('Repair', 'दुरुस्ती'))),
              ],
              onChanged: (v) => setState(() => _inwardCategory = v),
            ),
          ],
          const SizedBox(height: 10),
          _RemoteAutocomplete(
            path: '/master/vendors',
            label: S.t('Vendor', 'पुरवठादार'),
            initialText: _vendor == null ? '' : '${_vendor!['name']}',
            labelOf: (v) => '${v['name']} (${v['sap_code']})',
            onSelected: (v) {
              setState(() {
                _vendor = v;
                _po = null;
                _pos = const [];
              });
              _loadPos();
            },
          ),
          if (_sugg['vendor_gstin'] != null && _vendor == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  '${S.t('Scanned GSTIN', 'स्कॅन केलेला GSTIN')}: '
                  '${_sugg['vendor_gstin']} — '
                  '${S.t('pick the matching vendor', 'जुळणारा पुरवठादार निवडा')}',
                  style:
                      const TextStyle(fontSize: 11, color: YColors.muted)),
            ),
          if (_docType != 'other_inward') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _invoiceNo,
              decoration: InputDecoration(
                  labelText: _docType == 'invoice'
                      ? S.t('Invoice no. *', 'इनव्हॉइस क्र. *')
                      : S.t('Invoice no.', 'इनव्हॉइस क्र.')),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _invoiceDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setState(() => _invoiceDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                        labelText: S.t('Invoice date', 'इनव्हॉइस तारीख')),
                    child: Text(
                        _invoiceDate == null
                            ? '—'
                            : DateFormat('dd MMM yyyy').format(_invoiceDate!),
                        style: const TextStyle(fontSize: 14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _invoiceValue,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: S.t('Invoice value ₹', 'इनव्हॉइस रक्कम ₹')),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _po?['id'] as int?,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: S.t('Purchase order', 'खरेदी ऑर्डर (PO)'),
                helperText: _vendor == null
                    ? S.t('Select a vendor first', 'आधी पुरवठादार निवडा')
                    : (_pos.isEmpty
                        ? S.t('No open POs for this vendor',
                            'या पुरवठादाराचे खुले PO नाहीत')
                        : null)),
            items: [
              for (final po in _pos)
                DropdownMenuItem(
                    value: po['id'] as int,
                    child: Text(_poLabel(po),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5))),
            ],
            onChanged: (id) => setState(() {
              _po = null;
              for (final p in _pos) {
                if (p['id'] == id) {
                  _po = p;
                  break;
                }
              }
            }),
          ),
          if (_po != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                flex: 3,
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: S.t('Item (locked)', 'आयटम (लॉक)')),
                  child: Text('${_matLabel(_po!['material_id'])} 🔒',
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: S.t('Qty (locked)', 'प्रमाण (लॉक)')),
                  child: Text(
                      '${_po!['open_qty'] ?? '—'} ${_po!['uom'] ?? ''} 🔒',
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ]),
          ],
          if (!_isBackfill) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _vehicle,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                      labelText: S.t('Vehicle no. *', 'वाहन क्र. *')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _driver,
                  decoration: InputDecoration(
                      labelText: S.t('Driver name *', 'चालकाचे नाव *')),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitting ? null : () => _submit(),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(_isBackfill
                    ? S.t('Complete entry', 'नोंद पूर्ण करा')
                    : S.t('Generate gate pass · notify QC',
                        'गेट पास तयार करा · QC ला कळवा')),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: .4,
                color: YColors.muted,
                fontWeight: FontWeight.w700)),
      );
}

/// Async master-data autocomplete (vendors/materials) over GET ?q=.
class _RemoteAutocomplete extends StatelessWidget {
  const _RemoteAutocomplete(
      {required this.path,
      required this.label,
      required this.labelOf,
      required this.onSelected,
      this.initialText});

  final String path;
  final String label;
  final String Function(Map<String, dynamic>) labelOf;
  final void Function(Map<String, dynamic>) onSelected;
  final String? initialText;

  Future<Iterable<Map<String, dynamic>>> _search(String q) async {
    if (q.trim().length < 2) return const [];
    try {
      final r = await Api.dio
          .get(path, queryParameters: {'q': q.trim(), 'limit': 20});
      return (r.data as List)
          .map((e) => Map<String, dynamic>.from(e as Map));
    } on DioException {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Map<String, dynamic>>(
      initialValue: TextEditingValue(text: initialText ?? ''),
      displayStringForOption: labelOf,
      optionsBuilder: (v) => _search(v.text),
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
          TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (_) => onFieldSubmitted(),
      ),
    );
  }
}
