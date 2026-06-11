/// Dispatch note (P34, app map scr-o-dispatch). Customer + vehicle + dynamic
/// line rows (material + qty); total pcs computed live. Submit via retry queue
/// POST /dispatches; success offers the jump to Sale / billing.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/retry_queue.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class DispatchScreen extends ConsumerStatefulWidget {
  const DispatchScreen({super.key});

  @override
  ConsumerState<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchLine {
  _DispatchLine() : key = UniqueKey();
  final Key key;
  int? materialId;
  String label = '';
  final qty = TextEditingController();
}

class _DispatchScreenState extends ConsumerState<DispatchScreen> {
  List<Map<String, dynamic>> _customers = const [];
  int? _customerId;
  final _vehicle = TextEditingController();
  final List<_DispatchLine> _lines = [_DispatchLine()];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _vehicle.dispose();
    for (final l in _lines) {
      l.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final r = await Api.dio.get('/master/customers');
      if (!mounted) return;
      setState(() => _customers = (r.data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } on DioException catch (e) {
      if (!mounted) return;
      _toast(ApiException.from(e).message);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  int get _totalPcs {
    var total = 0;
    for (final l in _lines) {
      total += int.tryParse(l.qty.text.trim()) ??
          (double.tryParse(l.qty.text.trim())?.round() ?? 0);
    }
    return total;
  }

  Future<void> _submit() async {
    if (_customerId == null) {
      _toast(S.t('Pick the customer', 'ग्राहक निवडा'));
      return;
    }
    if (_vehicle.text.trim().isEmpty) {
      _toast(S.t('Vehicle number is required', 'वाहन क्रमांक आवश्यक'));
      return;
    }
    final lines = <Map<String, dynamic>>[];
    for (final l in _lines) {
      final qty = l.qty.text.trim();
      if (l.materialId == null || (double.tryParse(qty) ?? 0) <= 0) {
        _toast(S.t('Every line needs a material and a qty > 0',
            'प्रत्येक ओळीत सामग्री आणि ० पेक्षा जास्त प्रमाण हवे'));
        return;
      }
      lines.add({'material_id': l.materialId, 'qty': qty}); // Decimal as String
    }
    final body = {
      'customer_id': _customerId,
      'vehicle_no': _vehicle.text.trim(),
      'lines': lines,
      'client_ref': const Uuid().v4(),
    };
    setState(() => _submitting = true);
    try {
      final r = await ref.read(retryQueueProvider.notifier).post(
          '/dispatches', body,
          label: 'Dispatch $_totalPcs pcs ${_vehicle.text.trim()}');
      if (!mounted) return;
      if (r == null) {
        _toast(S.t('Queued — will sync', 'रांगेत — नंतर सिंक होईल'));
        _reset();
        return;
      }
      await _successDialog(r);
    } on ApiException catch (ex) {
      if (mounted) _toast(ex.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _reset() {
    final old = List<_DispatchLine>.from(_lines);
    setState(() {
      _vehicle.clear();
      _lines
        ..clear()
        ..add(_DispatchLine());
    });
    // dispose after the rebuild detaches the old fields
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final l in old) {
        l.qty.dispose();
      }
    });
  }

  Future<void> _successDialog(Map<String, dynamic> r) async {
    var body = S.t('DN ${r['doc_no']} created — ready to bill',
        'DN ${r['doc_no']} तयार — बिलिंगसाठी सज्ज');
    if (r['stock_warning'] == true) {
      body += '\n${S.t('Note: app stock was insufficient (parallel run warning).',
          'टीप: अ‍ॅप साठा अपुरा होता (समांतर रन इशारा).')}';
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: YColors.green, size: 36),
        title: Text(S.t('Dispatch created', 'डिस्पॅच तयार')),
        content: Text(body, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _reset();
            },
            child: Text(S.t('Close', 'बंद करा')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _reset();
              context.push('/store/billing');
            },
            child: Text(S.t('Bill now', 'आता बिल करा')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(S.t('Dispatch · new', 'डिस्पॅच · नवीन'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          DropdownButtonFormField<int>(
            initialValue: _customerId,
            isExpanded: true,
            decoration:
                InputDecoration(labelText: S.t('Customer', 'ग्राहक')),
            items: [
              for (final c in _customers)
                DropdownMenuItem(
                    value: c['id'] as int,
                    child: Text(
                        '${c['name']}${c['sap_code'] != null ? ' (${c['sap_code']})' : ''}',
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _customerId = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _vehicle,
            textCapitalization: TextCapitalization.characters,
            decoration:
                InputDecoration(labelText: S.t('Vehicle no. *', 'वाहन क्र. *')),
          ),
          const SizedBox(height: 14),
          Text(S.t('FINISHED ASSEMBLIES', 'तयार भाग'),
              style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: .4,
                  color: YColors.muted,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (var i = 0; i < _lines.length; i++) _lineRow(i),
          OutlinedButton.icon(
            onPressed: () => setState(() => _lines.add(_DispatchLine())),
            icon: const Icon(Icons.add),
            label: Text(S.t('Add line', 'ओळ जोडा')),
          ),
          const SizedBox(height: 10),
          AppCard(
            kind: 'info',
            title: S.t('Total pcs', 'एकूण नग'),
            trailing: Text('$_totalPcs',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: YColors.navy)),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(S.t('Generate dispatch note', 'डिस्पॅच नोट तयार करा')),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _lineRow(int i) {
    final line = _lines[i];
    return Padding(
      key: line.key,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: _MaterialAutocomplete(
            initialText: line.label,
            onSelected: (m) => setState(() {
              line.materialId = m['id'] as int;
              line.label = '${m['sap_code']} · ${m['description']}';
            }),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 88,
          child: TextField(
            controller: line.qty,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: S.t('Qty', 'नग')),
          ),
        ),
        IconButton(
          onPressed: _lines.length == 1
              ? null
              : () {
                  final removed = _lines[i];
                  setState(() => _lines.removeAt(i));
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => removed.qty.dispose());
                },
          icon: const Icon(Icons.remove_circle_outline, color: YColors.red),
        ),
      ]),
    );
  }
}

/// Async material autocomplete over GET /master/materials?q=.
class _MaterialAutocomplete extends StatelessWidget {
  const _MaterialAutocomplete({required this.onSelected, this.initialText});

  final void Function(Map<String, dynamic>) onSelected;
  final String? initialText;

  Future<Iterable<Map<String, dynamic>>> _search(String q) async {
    if (q.trim().length < 2) return const [];
    try {
      final r = await Api.dio.get('/master/materials',
          queryParameters: {'q': q.trim(), 'limit': 20});
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
      displayStringForOption: (m) => '${m['sap_code']} · ${m['description']}',
      optionsBuilder: (v) => _search(v.text),
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
          TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(labelText: S.t('Material', 'सामग्री')),
        onSubmitted: (_) => onFieldSubmitted(),
      ),
    );
  }
}
