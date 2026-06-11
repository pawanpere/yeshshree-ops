/// Issue material — limit check (P24, app map scr-o-issue). Destination routes
/// in-house / vendor sale / job work. Vendor destinations show the live
/// exposure panel (§5.5a) BEFORE submitting; a breach posts as waiver_pending
/// and routes a credit-waiver approval to management. Submit via retry queue.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/retry_queue.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class IssueScreen extends ConsumerStatefulWidget {
  const IssueScreen({super.key});

  @override
  ConsumerState<IssueScreen> createState() => _IssueScreenState();
}

class _IssueScreenState extends ConsumerState<IssueScreen> {
  String _dest = 'inhouse';
  List<Map<String, dynamic>> _lines = const [];
  int? _lineId;
  Map<String, dynamic>? _vendor;
  Map<String, dynamic>? _exposure;
  Map<String, dynamic>? _material;
  final _qty = TextEditingController();
  bool _submitting = false;
  ({String kind, String title, String body})? _result;

  bool get _vendorDest => _dest == 'vendor_sale' || _dest == 'job_work';

  @override
  void initState() {
    super.initState();
    _loadLines();
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _loadLines() async {
    try {
      final r = await Api.dio.get('/master/lines');
      if (!mounted) return;
      setState(() => _lines = (r.data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((l) => l['is_active'] != false)
          .toList());
    } on DioException {
      // dropdown stays empty; submit still validates
    }
  }

  Future<void> _loadExposure() async {
    final id = _vendor?['id'];
    if (id == null) return;
    try {
      final r = await Api.dio.get('/vendors/$id/exposure');
      if (!mounted) return;
      setState(() => _exposure = Map<String, dynamic>.from(r.data as Map));
    } on DioException catch (e) {
      if (!mounted) return;
      _toast(ApiException.from(e).message);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _submit() async {
    if (_material == null) {
      _toast(S.t('Pick a material', 'सामग्री निवडा'));
      return;
    }
    final qty = _qty.text.trim();
    if ((double.tryParse(qty) ?? 0) <= 0) {
      _toast(S.t('Quantity must be greater than zero',
          'प्रमाण शून्यापेक्षा जास्त हवे'));
      return;
    }
    if (_dest == 'inhouse' && _lineId == null) {
      _toast(S.t('Pick the production line', 'उत्पादन लाईन निवडा'));
      return;
    }
    if (_vendorDest && _vendor == null) {
      _toast(S.t('Pick the vendor', 'विक्रेता निवडा'));
      return;
    }
    final body = <String, dynamic>{
      'destination': _dest,
      'material_id': _material!['id'],
      'qty': qty, // Decimal as String
      'uom': _material!['uom'],
      if (_dest == 'inhouse') 'line_id': _lineId,
      if (_vendorDest) 'vendor_id': _vendor!['id'],
      'client_ref': const Uuid().v4(),
    };
    setState(() => _submitting = true);
    try {
      final r = await ref.read(retryQueueProvider.notifier).post(
          '/issues', body,
          label: 'Issue $qty ${_material!['uom']} ${_material!['sap_code']}');
      if (!mounted) return;
      if (r == null) {
        _toast(S.t('Queued — will sync', 'रांगेत — नंतर सिंक होईल'));
      } else if (r['status'] == 'waiver_pending') {
        final limits = (r['limit_check'] as Map?)?['limits'] as Map?;
        final breaches =
            ((limits?['breaches'] as List?) ?? const []).join(', ');
        setState(() => _result = (
              kind: 'warn',
              title: S.t('Blocked by limit — waiver routed to management',
                  'मर्यादेमुळे अडवले — सवलत व्यवस्थापनाकडे पाठवली'),
              body: '${S.t('Breached', 'ओलांडले')}: $breaches · '
                  '${r['doc_no']} ${S.t('waits for the waiver decision',
                      'सवलत निर्णयाच्या प्रतीक्षेत')}',
            ));
      } else if (r['stock_warning'] == true) {
        setState(() => _result = (
              kind: 'warn',
              title: S.t('Posted with stock warning', 'साठा इशाऱ्यासह पोस्ट'),
              body: S.t(
                  '${r['doc_no']} posted, but app stock was insufficient (parallel run — warn only).',
                  '${r['doc_no']} पोस्ट झाले, पण अ‍ॅप साठा अपुरा होता (समांतर रन — फक्त इशारा).'),
            ));
      } else {
        setState(() => _result = (
              kind: 'success',
              title: S.t('Issue ${r['doc_no']} posted',
                  'इश्यू ${r['doc_no']} पोस्ट झाला'),
              body: '$qty ${_material!['uom']} · ${_material!['description']} → '
                  '${_destLabel(_dest)}',
            ));
      }
      _qty.clear();
      if (_vendorDest) await _loadExposure(); // refresh the panel post-issue
    } on ApiException catch (ex) {
      if (mounted) _toast(ex.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _destLabel(String d) => switch (d) {
        'inhouse' => S.t('In-house line', 'इन-हाऊस लाईन'),
        'vendor_sale' => S.t('Sale to vendor', 'विक्रेत्याला विक्री'),
        _ => S.t('Job work', 'जॉब वर्क'),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(S.t('Issue material', 'सामग्री इश्यू'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_result != null)
            AlertBanner(
                kind: _result!.kind,
                title: _result!.title,
                body: _result!.body),
          Text(S.t('DESTINATION', 'गंतव्य'),
              style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: .4,
                  color: YColors.muted,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: 'inhouse',
                  label: Text(S.t('In-house', 'इन-हाऊस'),
                      style: const TextStyle(fontSize: 12))),
              ButtonSegment(
                  value: 'vendor_sale',
                  label: Text(S.t('Vendor sale', 'विक्री'),
                      style: const TextStyle(fontSize: 12))),
              ButtonSegment(
                  value: 'job_work',
                  label: Text(S.t('Job work', 'जॉब वर्क'),
                      style: const TextStyle(fontSize: 12))),
            ],
            selected: {_dest},
            onSelectionChanged: (s) => setState(() {
              _dest = s.first;
              _result = null;
            }),
          ),
          const SizedBox(height: 12),
          if (_dest == 'inhouse')
            DropdownButtonFormField<int>(
              initialValue: _lineId,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: S.t('Production line', 'उत्पादन लाईन')),
              items: [
                for (final l in _lines)
                  DropdownMenuItem(
                      value: l['id'] as int, child: Text('${l['name']}')),
              ],
              onChanged: (v) => setState(() => _lineId = v),
            ),
          if (_vendorDest) ...[
            _RemoteAutocomplete(
              path: '/master/vendors',
              label: S.t('Vendor', 'विक्रेता'),
              initialText: _vendor == null ? '' : '${_vendor!['name']}',
              labelOf: (v) => '${v['name']} (${v['sap_code']})',
              onSelected: (v) {
                setState(() {
                  _vendor = v;
                  _exposure = null;
                });
                _loadExposure();
              },
            ),
            if (_exposure != null) _exposurePanel(),
          ],
          const SizedBox(height: 12),
          _RemoteAutocomplete(
            path: '/master/materials',
            label: S.t('Material', 'सामग्री'),
            initialText: _material == null
                ? ''
                : '${_material!['sap_code']} · ${_material!['description']}',
            labelOf: (m) => '${m['sap_code']} · ${m['description']}',
            onSelected: (m) => setState(() => _material = m),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _qty,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: S.t('Qty *', 'प्रमाण *')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(labelText: S.t('UoM', 'एकक')),
                child: Text('${_material?['uom'] ?? '—'}',
                    style: const TextStyle(fontSize: 14)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(S.t('Issue material', 'सामग्री इश्यू करा')),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// §5.5a vendor position panel: credit ₹ and qty MT against limits.
  Widget _exposurePanel() {
    final e = _exposure!;
    double? frac(dynamic used, dynamic limit) {
      final u = double.tryParse('$used');
      final l = double.tryParse('${limit ?? ''}');
      if (u == null || l == null || l <= 0) return null;
      return u / l;
    }

    Widget row(String label, String used, dynamic limit, double? f) {
      final near = f != null && f >= 0.8;
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 11.5, color: YColors.muted))),
            Text(
                limit == null
                    ? '$used · ${S.t('no limit set', 'मर्यादा नाही')}'
                    : '$used / $limit'
                        '${f != null && f > 1 ? ' · ${S.t('BREACH', 'ओलांडली')}' : ''}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: near ? YColors.red : YColors.navy)),
          ]),
          if (f != null) ...[
            const SizedBox(height: 4),
            ProgressBar(fraction: f),
          ],
        ]),
      );
    }

    return AppCard(
      kind: 'info',
      title: S.t('Vendor position after recent issues',
          'विक्रेत्याची सद्यस्थिती'),
      child: Column(children: [
        row(
            S.t('Credit limit', 'क्रेडिट मर्यादा'),
            '₹${e['credit_exposure']}',
            e['credit_limit'] == null ? null : '₹${e['credit_limit']}',
            frac(e['credit_exposure'], e['credit_limit'])),
        row(
            S.t('Quantity limit (MT)', 'प्रमाण मर्यादा (MT)'),
            '${e['qty_mt']} MT',
            e['qty_limit_mt'] == null ? null : '${e['qty_limit_mt']} MT',
            frac(e['qty_mt'], e['qty_limit_mt'])),
      ]),
    );
  }
}

/// Async master-data autocomplete over GET ?q=.
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
