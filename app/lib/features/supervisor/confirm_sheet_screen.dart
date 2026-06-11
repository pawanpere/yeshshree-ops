/// THE HERO (scr-s-confirm): good / rejected qty, reject reason (required when
/// rejected > 0), downtime, process-wise loss — posts via the retry queue so a
/// dead network means "queued", never lost (the 3-hour→minutes story).
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

double _num(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

String _qty(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

class ConfirmSheetScreen extends ConsumerStatefulWidget {
  const ConfirmSheetScreen({super.key, this.context_});

  /// line_id, line_name, shift, material_id, sap_code, description,
  /// planned, good, rejected — passed by the supervisor home part card.
  final Map<String, dynamic>? context_;

  @override
  ConsumerState<ConfirmSheetScreen> createState() => _ConfirmSheetScreenState();
}

class _ConfirmSheetScreenState extends ConsumerState<ConfirmSheetScreen> {
  final _good = TextEditingController();
  final _rej = TextEditingController();
  final _downMin = TextEditingController();
  final _blanking = TextEditingController();
  final _piercing = TextEditingController();
  final _forming = TextEditingController();

  List<dynamic> _rejectReasons = [];
  List<dynamic> _downtimeReasons = [];
  int? _rejectReasonId;
  int? _downtimeReasonId;
  bool _submitting = false;
  String? _errTitle;
  String? _errBody;

  Map<String, dynamic> get _ctx => widget.context_ ?? const {};

  @override
  void initState() {
    super.initState();
    _loadReasons();
  }

  @override
  void dispose() {
    for (final c in [_good, _rej, _downMin, _blanking, _piercing, _forming]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadReasons() async {
    try {
      final rej = await Api.dio
          .get('/config/reason-codes', queryParameters: {'kind': 'reject'});
      final down = await Api.dio
          .get('/config/reason-codes', queryParameters: {'kind': 'downtime'});
      if (!mounted) return;
      setState(() {
        _rejectReasons = rej.data as List<dynamic>;
        _downtimeReasons = down.data as List<dynamic>;
      });
    } on DioException catch (_) {
      // Dropdowns stay empty; submit validation will still guard rejects.
    }
  }

  String _label(dynamic r) {
    final mr = r['label_mr'] as String?;
    if (S.lang.value == 'mr' && mr != null && mr.isNotEmpty) return mr;
    return r['label_en'] as String? ?? r['code'] as String? ?? '—';
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit(String kind) async {
    final goodV = double.tryParse(_good.text.trim());
    final rejV = double.tryParse(
        _rej.text.trim().isEmpty ? '0' : _rej.text.trim());
    if (goodV == null || goodV < 0 || rejV == null || rejV < 0) {
      _snack(S.t('Enter a valid good quantity', 'योग्य संख्या भरा'));
      return;
    }
    if (rejV > 0 && _rejectReasonId == null) {
      _snack(S.t('Reject reason is required when rejected > 0',
          'नाकारलेले > 0 असल्यास कारण आवश्यक आहे'));
      return;
    }
    final downMin = int.tryParse(
            _downMin.text.trim().isEmpty ? '0' : _downMin.text.trim()) ??
        0;
    if (downMin > 0 && _downtimeReasonId == null) {
      _snack(S.t('Downtime reason is required when minutes > 0',
          'डाउनटाइम मिनिटे > 0 असल्यास कारण आवश्यक आहे'));
      return;
    }

    final body = <String, dynamic>{
      'client_ref': const Uuid().v4(),
      'line_id': _ctx['line_id'],
      'shift': _ctx['shift'],
      'material_id': _ctx['material_id'],
      'good_qty': _good.text.trim(),
      'rejected_qty': _rej.text.trim().isEmpty ? '0' : _rej.text.trim(),
      'reject_reason_id': rejV > 0 ? _rejectReasonId : null,
      'downtime_min': downMin,
      'downtime_reason_id': downMin > 0 ? _downtimeReasonId : null,
      'process_loss': {
        'blanking': _blanking.text.trim().isEmpty ? '0' : _blanking.text.trim(),
        'piercing': _piercing.text.trim().isEmpty ? '0' : _piercing.text.trim(),
        'forming': _forming.text.trim().isEmpty ? '0' : _forming.text.trim(),
      },
      'kind': kind,
      'shift_date': DateTime.now().toIso8601String().substring(0, 10),
    };
    final label =
        '${S.t('Confirmation', 'नोंद')} ${_good.text.trim()} ${_ctx['description'] ?? ''}';

    setState(() {
      _submitting = true;
      _errTitle = null;
      _errBody = null;
    });
    try {
      final res = await ref
          .read(retryQueueProvider.notifier)
          .post('/confirmations', body, label: label);
      if (!mounted) return;
      if (res == null) {
        // Offline — first-class path: nothing lost, drained automatically.
        _snack(S.t('Queued — will sync when network returns',
            'रांगेत — नेटवर्क आल्यावर सिंक होईल'));
      } else {
        _snack(S.t('Posted · SAP sync pending', 'नोंदले · SAP सिंक प्रलंबित'));
      }
      context.pop();
    } on ApiException catch (ex) {
      if (!mounted) return;
      if (ex.code == 'CONFIRMATION_NEEDS_ORDER') {
        await _offerHold(body, label);
      } else if (ex.code == 'CONFIRMATION_EXCEEDS_PLAN') {
        setState(() {
          _errTitle = ex.message;
          _errBody = ex.details.isEmpty ? null : ex.details.toString();
        });
      } else {
        _snack(ex.message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _offerHold(Map<String, dynamic> body, String label) async {
    final park = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('No production order', 'उत्पादन ऑर्डर नाही')),
        content: Text(S.t(
            'No production order — park it for PPC? Nothing is lost; '
            'PPC resolves the order and it posts.',
            'उत्पादन ऑर्डर नाही — PPC साठी होल्ड करायचे? काहीही गमावले जात '
            'नाही; PPC ऑर्डर ठरवेल आणि नोंद होईल.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(S.t('Cancel', 'रद्द'))),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(S.t('Park for PPC', 'PPC साठी होल्ड'))),
        ],
      ),
    );
    if (park != true || !mounted) return;
    try {
      final res = await ref
          .read(retryQueueProvider.notifier)
          .post('/confirmations/hold', body, label: '$label (hold)');
      if (!mounted) return;
      _snack(res == null
          ? S.t('Queued — will sync when network returns',
              'रांगेत — नेटवर्क आल्यावर सिंक होईल')
          : S.t('Parked for PPC', 'PPC साठी होल्ड केले'));
      context.pop();
    } on ApiException catch (ex) {
      if (mounted) _snack(ex.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final planned = _num(_ctx['planned']);
    final good = _num(_ctx['good']);
    final rejected = _num(_ctx['rejected']);
    final goodInput = double.tryParse(_good.text.trim()) ?? 0;

    return Scaffold(
      appBar: AppBar(
          title: Text(S.t('Production Confirmation', 'उत्पादन नोंद'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AppCard(
            title: _ctx['description'] as String? ?? '—',
            meta: '${_ctx['line_name'] ?? ''} · ${_ctx['shift'] ?? ''} · '
                '${_ctx['sap_code'] ?? ''}',
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProgressBar(fraction: planned > 0 ? good / planned : 0),
                  const SizedBox(height: 5),
                  Text(
                      '${S.t('Planned', 'नियोजित')} ${_qty(planned)} · '
                      '${S.t('Good', 'चांगले')} ${_qty(good)} · '
                      '${S.t('Rejected', 'नाकारले')} ${_qty(rejected)} · '
                      '${S.t('Remaining', 'शिल्लक')} '
                      '${_qty((planned - good).clamp(0, double.infinity).toDouble())}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF334155))),
                ]),
          ),
          const SizedBox(height: 8),
          if (_errTitle != null)
            AlertBanner(title: _errTitle!, body: _errBody, kind: 'danger'),
          Text(S.t('This posting', 'ही नोंद'),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
                child: _bigField(
                    _good, S.t('Good qty', 'चांगली संख्या'), YColors.green)),
            const SizedBox(width: 10),
            Expanded(
                child: _bigField(
                    _rej, S.t('Rejected qty', 'नाकारलेली संख्या'), YColors.red)),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _rejectReasonId,
            decoration: InputDecoration(
                labelText: S.t('Reject reason (required if reject > 0)',
                    'नाकारण्याचे कारण (नाकारले > 0 असल्यास आवश्यक)')),
            items: _rejectReasons
                .map((r) => DropdownMenuItem<int>(
                    value: r['id'] as int, child: Text(_label(r))))
                .toList(),
            onChanged: (v) => setState(() => _rejectReasonId = v),
          ),
          const SizedBox(height: 14),
          Text(S.t('Downtime (optional)', 'डाउनटाइम (ऐच्छिक)'),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          Row(children: [
            SizedBox(
              width: 110,
              child: TextField(
                controller: _downMin,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: S.t('Minutes', 'मिनिटे')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _downtimeReasonId,
                decoration:
                    InputDecoration(labelText: S.t('Reason', 'कारण')),
                items: _downtimeReasons
                    .map((r) => DropdownMenuItem<int>(
                        value: r['id'] as int, child: Text(_label(r))))
                    .toList(),
                onChanged: (v) => setState(() => _downtimeReasonId = v),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Text(S.t('Process-wise loss', 'प्रक्रियानिहाय तूट'),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
                child: _lossField(
                    _blanking, S.t('Blanking', 'ब्लँकिंग'))),
            const SizedBox(width: 8),
            Expanded(
                child: _lossField(
                    _piercing, S.t('Piercing', 'पियर्सिंग'))),
            const SizedBox(width: 8),
            Expanded(child: _lossField(_forming, S.t('Forming', 'फॉर्मिंग'))),
          ]),
          const SizedBox(height: 12),
          AlertBanner(
            title: S.t(
                'After this post: good ${_qty(good + goodInput)} of ${_qty(planned)}',
                'या नोंदीनंतर: चांगले ${_qty(good + goodInput)} / ${_qty(planned)}'),
            kind: 'info',
          ),
          ElevatedButton(
            onPressed: _submitting ? null : () => _submit('interim'),
            child: Text(S.t('Submit interim', 'अंतरिम नोंदवा')),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YColors.green),
            onPressed: _submitting ? null : () => _submit('shift_close'),
            child: Text(S.t('Close shift', 'पाळी बंद करा')),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _bigField(TextEditingController c, String label, Color color) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      style: TextStyle(
          fontSize: 28, fontWeight: FontWeight.w700, color: color),
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}), // live "after this post" preview
    );
  }

  Widget _lossField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }
}
