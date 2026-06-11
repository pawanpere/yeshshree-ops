/// Sale / billing confirmation (P34, app map scr-o-billing). Pick an open
/// dispatch → record the SAP invoice against it (SAP's invoice is truth —
/// lines prefill from the dispatch but stay editable). 422
/// INVOICE_MISMATCH_REASON_REQUIRED ⇒ reason dialog ⇒ resubmit. Then
/// "Confirm sale" pushes it into the live sales report.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/retry_queue.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _InvoiceLine {
  _InvoiceLine(this.materialId, String qty)
      : qtyCtl = TextEditingController(text: qty),
        valueCtl = TextEditingController();
  final int materialId;
  final TextEditingController qtyCtl;
  final TextEditingController valueCtl;
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  List<Map<String, dynamic>>? _dispatches;
  Map<int, String> _customers = const {};
  Map<int, String> _materialNames = const {};
  String? _error;

  Map<String, dynamic>? _dispatch; // selected ⇒ form mode
  List<_InvoiceLine> _lines = const [];
  final _invoiceNo = TextEditingController();
  DateTime _invoiceDate = DateTime.now();
  final _irn = TextEditingController();
  final _eway = TextEditingController();
  final _totalValue = TextEditingController();
  bool _submitting = false;
  String? _pendingRef; // survives the mismatch-reason round-trip
  Map<String, dynamic>? _invoice; // recorded ⇒ confirm step

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _invoiceNo.dispose();
    _irn.dispose();
    _eway.dispose();
    _totalValue.dispose();
    for (final l in _lines) {
      l.qtyCtl.dispose();
      l.valueCtl.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await Api.dio
          .get('/dispatches', queryParameters: {'status': 'open'});
      var customers = _customers;
      var materials = _materialNames;
      try {
        final c = await Api.dio.get('/master/customers');
        customers = {
          for (final x in c.data as List) (x as Map)['id'] as int: '${x['name']}',
        };
        final m = await Api.dio
            .get('/master/materials', queryParameters: {'limit': 500});
        materials = {
          for (final x in m.data as List)
            (x as Map)['id'] as int: '${x['sap_code']} · ${x['description']}',
        };
      } on DioException {
        // best-effort labels
      }
      if (!mounted) return;
      setState(() {
        _dispatches = (r.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _customers = customers;
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

  void _pick(Map<String, dynamic> d) {
    setState(() {
      _dispatch = d;
      _invoice = null;
      _pendingRef = null;
      _invoiceNo.clear();
      _irn.clear();
      _eway.clear();
      _totalValue.clear();
      _invoiceDate = DateTime.now();
      _lines = [
        for (final ln in (d['lines'] as List? ?? const []))
          _InvoiceLine((ln as Map)['material_id'] as int, '${ln['qty']}'),
      ];
    });
  }

  void _backToList() {
    setState(() {
      _dispatch = null;
      _invoice = null;
      _pendingRef = null;
    });
    _refresh();
  }

  // --- record invoice ---------------------------------------------------------

  Future<void> _submit({String? mismatchReason}) async {
    if (_invoiceNo.text.trim().isEmpty) {
      _toast(S.t('SAP invoice number is required',
          'SAP इनव्हॉइस क्रमांक आवश्यक'));
      return;
    }
    if ((double.tryParse(_totalValue.text.trim()) ?? 0) <= 0) {
      _toast(S.t('Total value is required', 'एकूण रक्कम आवश्यक'));
      return;
    }
    final lines = <Map<String, dynamic>>[];
    for (final l in _lines) {
      final qty = l.qtyCtl.text.trim();
      final value = l.valueCtl.text.trim();
      if ((double.tryParse(qty) ?? 0) <= 0 || double.tryParse(value) == null) {
        _toast(S.t('Every line needs qty and value from the SAP invoice',
            'प्रत्येक ओळीत SAP इनव्हॉइसमधील प्रमाण व रक्कम हवी'));
        return;
      }
      lines.add({
        'material_id': l.materialId,
        'qty': qty, // Decimal as String
        'value': value,
      });
    }
    _pendingRef ??= const Uuid().v4();
    final body = <String, dynamic>{
      'invoice_no': _invoiceNo.text.trim(),
      'invoice_date': DateFormat('yyyy-MM-dd').format(_invoiceDate),
      'dispatch_id': _dispatch!['id'],
      if (_irn.text.trim().isNotEmpty) 'irn': _irn.text.trim(),
      if (_eway.text.trim().isNotEmpty) 'eway_bill_no': _eway.text.trim(),
      'total_value': _totalValue.text.trim(),
      'lines': lines,
      if (mismatchReason != null) 'mismatch_reason': mismatchReason,
      'client_ref': _pendingRef,
    };
    setState(() => _submitting = true);
    try {
      final r = await ref.read(retryQueueProvider.notifier).post(
          '/invoices', body,
          label: 'Invoice ${_invoiceNo.text.trim()}');
      if (!mounted) return;
      if (r == null) {
        _toast(S.t('Queued — will sync. Confirm the sale once online.',
            'रांगेत — सिंक होईल. ऑनलाइन झाल्यावर विक्री निश्चित करा.'));
        _backToList();
        return;
      }
      setState(() {
        _invoice = r;
        _pendingRef = null;
      });
    } on ApiException catch (ex) {
      if (!mounted) return;
      if (ex.code == 'INVOICE_MISMATCH_REASON_REQUIRED') {
        await _mismatchDialog(ex);
      } else {
        _toast(ex.message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _mismatchDialog(ApiException ex) async {
    final reasonCtl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('Quantities differ from the dispatch',
            'प्रमाण डिस्पॅचपेक्षा वेगळे आहे')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ex.message, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: reasonCtl,
            maxLines: 2,
            decoration: InputDecoration(
                labelText: S.t('Mismatch reason *', 'फरकाचे कारण *')),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(S.t('Cancel', 'रद्द'))),
          FilledButton(
            onPressed: () {
              final reason = reasonCtl.text.trim();
              if (reason.isEmpty) return;
              Navigator.of(ctx).pop();
              _submit(mismatchReason: reason);
            },
            child: Text(S.t('Record with reason', 'कारणासह नोंदवा')),
          ),
        ],
      ),
    );
  }

  // --- confirm sale -------------------------------------------------------------

  Future<void> _confirm() async {
    setState(() => _submitting = true);
    try {
      await Api.dio.post('/invoices/${_invoice!['id']}/confirm');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: YColors.green, size: 36),
          title: Text(S.t('Sale confirmed', 'विक्री निश्चित')),
          content: Text(
              S.t('Sale confirmed · sales report updated live',
                  'विक्री निश्चित · विक्री अहवाल लगेच अद्ययावत'),
              textAlign: TextAlign.center),
          actions: [
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(S.t('OK', 'ठीक'))),
          ],
        ),
      );
      if (!mounted) return;
      _backToList();
    } on DioException catch (e) {
      if (mounted) _toast(ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // --- build ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final formMode = _dispatch != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(formMode
            ? S.t('Sale / billing · ${_dispatch!['doc_no']}',
                'विक्री / बिलिंग · ${_dispatch!['doc_no']}')
            : S.t('Sale / billing', 'विक्री / बिलिंग')),
        leading: formMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: _backToList)
            : null,
      ),
      body: formMode ? _form() : _list(),
    );
  }

  Widget _list() {
    if (_dispatches == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_dispatches == null) {
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
    final list = _dispatches!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (list.isEmpty)
            AlertBanner(
                kind: 'info',
                title: S.t('No open dispatches', 'खुले डिस्पॅच नाहीत'),
                body: S.t('Create a dispatch first; it appears here to bill.',
                    'आधी डिस्पॅच करा; बिलिंगसाठी तो येथे दिसेल.'))
          else
            AlertBanner(
                kind: 'purple',
                title: S.t('Pick a dispatch to bill',
                    'बिल करण्यासाठी डिस्पॅच निवडा'),
                body: S.t(
                    'The SAP invoice is keyed in here and matched against the dispatch.',
                    'SAP इनव्हॉइस येथे नोंदवले जाते आणि डिस्पॅचशी जुळवले जाते.')),
          for (final d in list)
            ListRow(
              title: '${d['doc_no']} · '
                  '${_customers[d['customer_id']] ?? '#${d['customer_id']}'}',
              subtitle: '${d['vehicle_no']} · ${d['total_pcs']} '
                  '${S.t('pcs', 'नग')}',
              trailing: const Icon(Icons.chevron_right, color: YColors.muted),
              onTap: () => _pick(d),
            ),
        ],
      ),
    );
  }

  Widget _form() {
    final d = _dispatch!;
    final recorded = _invoice != null;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AppCard(
          kind: 'info',
          title:
              '${d['doc_no']} · ${_customers[d['customer_id']] ?? '#${d['customer_id']}'}',
          meta: '${d['vehicle_no']} · ${d['total_pcs']} ${S.t('pcs', 'नग')} '
              '${S.t('dispatched', 'पाठवले')}',
        ),
        if (recorded) ...[
          AlertBanner(
            kind: _invoice!['match_status'] == 'matched' ? 'success' : 'warn',
            title: S.t('Invoice ${_invoice!['invoice_no']} recorded',
                'इनव्हॉइस ${_invoice!['invoice_no']} नोंदले'),
            body: _invoice!['match_status'] == 'matched'
                ? S.t('Matches dispatch ${d['doc_no']} — confirm the sale.',
                    'डिस्पॅच ${d['doc_no']} शी जुळते — विक्री निश्चित करा.')
                : S.t('Recorded with mismatch (reason logged) — confirm the sale.',
                    'फरकासह नोंदले (कारण नोंदवले) — विक्री निश्चित करा.'),
          ),
          ElevatedButton(
            onPressed: _submitting ? null : _confirm,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(S.t('Confirm sale', 'विक्री निश्चित करा')),
          ),
        ] else ...[
          AlertBanner(
              kind: 'info',
              title: S.t("SAP's invoice is truth", 'SAP इनव्हॉइसच प्रमाण'),
              body: S.t(
                  'Lines are prefilled from the dispatch — edit them to match the SAP invoice exactly.',
                  'ओळी डिस्पॅचमधून आधीच भरल्या आहेत — SAP इनव्हॉइसशी तंतोतंत जुळवा.')),
          TextField(
            controller: _invoiceNo,
            decoration: InputDecoration(
                labelText: S.t('SAP invoice no. *', 'SAP इनव्हॉइस क्र. *')),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _invoiceDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setState(() => _invoiceDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: S.t('Invoice date *', 'इनव्हॉइस तारीख *')),
                  child: Text(DateFormat('dd MMM yyyy').format(_invoiceDate),
                      style: const TextStyle(fontSize: 14)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _totalValue,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: S.t('Total value ₹ *', 'एकूण रक्कम ₹ *')),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _irn,
            decoration: InputDecoration(
                labelText: S.t('GST e-invoice IRN', 'GST ई-इनव्हॉइस IRN')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _eway,
            decoration: InputDecoration(
                labelText: S.t('e-Way bill no.', 'ई-वे बिल क्र.')),
          ),
          const SizedBox(height: 14),
          Text(S.t('INVOICE LINES', 'इनव्हॉइस ओळी'),
              style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: .4,
                  color: YColors.muted,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final l in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: Text(_materialNames[l.materialId] ?? '#${l.materialId}',
                      style: const TextStyle(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: l.qtyCtl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        InputDecoration(labelText: S.t('Qty', 'नग')),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: l.valueCtl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        InputDecoration(labelText: S.t('Value ₹', 'रक्कम ₹')),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _submitting ? null : () => _submit(),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(S.t('Record invoice', 'इनव्हॉइस नोंदवा')),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
