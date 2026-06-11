/// Schedules (scr-p-sched): period list → new draft (manual entry, provisional
/// until the Bajaj sample) → diff + sanity review → release (warnings need an
/// explicit confirm; SPLIT_MISSING deep-links to Config) → re-release rollback.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

String _currentPeriod() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  final _periodCtrl = TextEditingController(text: _currentPeriod());
  Future<List<dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _periodCtrl.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _fetch() async {
    try {
      final r = await Api.dio.get('/schedules', queryParameters: {
        if (_periodCtrl.text.trim().isNotEmpty)
          'period': _periodCtrl.text.trim(),
      });
      return r.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  void _reload() => setState(() => _future = _fetch());

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('Schedules', 'वेळापत्रके'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _periodCtrl,
                    decoration: InputDecoration(
                        labelText:
                            S.t('Period (YYYY-MM)', 'कालावधी (YYYY-MM)')),
                    onSubmitted: (_) => _reload(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: _reload,
                    child: Text(S.t('Load', 'लोड करा'))),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(S.t('New schedule', 'नवीन वेळापत्रक')),
                  onPressed: () async {
                    final created = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                            builder: (_) => _ScheduleEditorPage(
                                period: _periodCtrl.text.trim())));
                    if (created == true) _reload();
                  },
                ),
              ]),
              const SizedBox(height: 12),
              if (_future != null)
                AsyncBody<List<dynamic>>(
                  future: _future!,
                  onRetry: _reload,
                  builder: (context, rows) {
                    if (rows.isEmpty) {
                      return AlertBanner(
                          title: S.t('No schedules for this period',
                              'या कालावधीसाठी वेळापत्रके नाहीत'),
                          kind: 'info');
                    }
                    return Column(children: [
                      for (final s in rows)
                        _scheduleRow(s as Map<String, dynamic>),
                    ]);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scheduleRow(Map<String, dynamic> s) {
    final status = s['status'] as String? ?? 'draft';
    return ListRow(
      title: '${s['period']} · v${s['version']}',
      subtitle: '${S.t('customer', 'ग्राहक')} ${s['customer_id']}'
          '${s['released_at'] != null ? ' · ${S.t('released', 'प्रसिद्ध')} ${(s['released_at'] as String).substring(0, 10)}' : ''}',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StatusBadge(status, kind: status),
        if (status == 'released' || status == 'superseded') ...[
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => _reRelease(s),
            child: Text(S.t('Re-release', 'पुन्हा प्रसिद्ध')),
          ),
        ],
      ]),
      onTap: () async {
        final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => _ScheduleDetailPage(schedule: s)));
        if (changed == true) _reload();
      },
    );
  }

  Future<void> _reRelease(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('Re-release v${s['version']}?',
            'v${s['version']} पुन्हा प्रसिद्ध करायचे?')),
        content: Text(S.t(
            'Rollback by re-release: this version is cloned as a NEW version '
            'and released. Nothing is ever deleted.',
            'पुन्हा-प्रसिद्धीद्वारे रोलबॅक: ही आवृत्ती नवीन आवृत्ती म्हणून '
            'कॉपी होऊन प्रसिद्ध होते. काहीही हटवले जात नाही.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(S.t('Cancel', 'रद्द'))),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(S.t('Re-release', 'पुन्हा प्रसिद्ध'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await Api.dio.post('/schedules/${s['id']}/re-release');
      final data = Map<String, dynamic>.from(r.data as Map);
      if (!mounted) return;
      _snack(_releaseToast(data));
      _reload();
    } on DioException catch (e) {
      if (mounted) _snack(ApiException.from(e).message);
    }
  }
}

String _releaseToast(Map<String, dynamic> report) {
  final unmapped = report['unmapped'] as List? ?? const [];
  var msg = S.t(
      'Released — ${report['plans_created']} plans, '
          '${report['calloffs_created']} call-offs',
      'प्रसिद्ध — ${report['plans_created']} प्लॅन्स, '
          '${report['calloffs_created']} कॉल-ऑफ');
  if (unmapped.isNotEmpty) {
    msg += S.t(' · ${unmapped.length} unmapped lines!',
        ' · ${unmapped.length} ओळी मॅप नाहीत!');
  }
  return msg;
}

// ---------------------------------------------------------------- editor

class _LineDraft {
  String sapCode = '';
  final family = TextEditingController();
  final qty = TextEditingController();
  DateTime? date;

  void dispose() {
    family.dispose();
    qty.dispose();
  }
}

class _ScheduleEditorPage extends StatefulWidget {
  const _ScheduleEditorPage({required this.period});
  final String period;

  @override
  State<_ScheduleEditorPage> createState() => _ScheduleEditorPageState();
}

class _ScheduleEditorPageState extends State<_ScheduleEditorPage> {
  late final TextEditingController _period;
  List<dynamic> _customers = [];
  int? _customerId;
  final List<_LineDraft> _rows = [_LineDraft()];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _period = TextEditingController(
        text: widget.period.isEmpty ? _currentPeriod() : widget.period);
    _loadCustomers();
  }

  @override
  void dispose() {
    _period.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final r = await Api.dio.get('/master/customers');
      if (mounted) setState(() => _customers = r.data as List<dynamic>);
    } on DioException catch (_) {}
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    if (_customerId == null) {
      _snack(S.t('Pick a customer', 'ग्राहक निवडा'));
      return;
    }
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(_period.text.trim())) {
      _snack(S.t('Period must be YYYY-MM', 'कालावधी YYYY-MM असावा'));
      return;
    }
    final lines = <Map<String, dynamic>>[];
    for (final r in _rows) {
      final qty = double.tryParse(r.qty.text.trim());
      if (r.sapCode.isEmpty &&
          r.family.text.trim().isEmpty &&
          r.qty.text.trim().isEmpty) {
        continue; // skip fully empty rows
      }
      if (r.sapCode.isEmpty ||
          r.family.text.trim().isEmpty ||
          r.date == null ||
          qty == null ||
          qty <= 0) {
        _snack(S.t('Every row needs SAP code, family, date and qty > 0',
            'प्रत्येक ओळीत SAP कोड, फॅमिली, तारीख व संख्या > 0 हवी'));
        return;
      }
      lines.add({
        'sap_code': r.sapCode,
        'model_family': r.family.text.trim(),
        'bucket_date': r.date!.toIso8601String().substring(0, 10),
        'qty': r.qty.text.trim(),
      });
    }
    if (lines.isEmpty) {
      _snack(S.t('Add at least one line', 'किमान एक ओळ जोडा'));
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.dio.post('/schedules', data: {
        'customer_id': _customerId,
        'period': _period.text.trim(),
        'lines': lines,
      });
      if (!mounted) return;
      _snack(S.t('Draft schedule created', 'मसुदा वेळापत्रक तयार झाले'));
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (mounted) _snack(ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(S.t('New schedule', 'नवीन वेळापत्रक'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _customerId,
                    hint: Text(S.t('Customer', 'ग्राहक')),
                    items: _customers
                        .map((c) => DropdownMenuItem<int>(
                            value: c['id'] as int,
                            child: Text(c['name'] as String? ?? '—')))
                        .toList(),
                    onChanged: (v) => setState(() => _customerId = v),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _period,
                    decoration: InputDecoration(
                        labelText: S.t('Period', 'कालावधी')),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              for (var i = 0; i < _rows.length; i++) _rowEditor(i),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(S.t('Add row', 'ओळ जोडा')),
                onPressed: () => setState(() => _rows.add(_LineDraft())),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Text(S.t('Create draft', 'मसुदा तयार करा')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowEditor(int i) {
    final row = _rows[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            Expanded(
              flex: 3,
              child: Autocomplete<String>(
                optionsBuilder: (t) async {
                  if (t.text.trim().length < 2) {
                    return const Iterable<String>.empty();
                  }
                  try {
                    final r = await Api.dio.get('/master/materials',
                        queryParameters: {'q': t.text.trim(), 'limit': 10});
                    return (r.data as List).map((m) =>
                        '${m['sap_code']} — ${m['description']}');
                  } on DioException catch (_) {
                    return const Iterable<String>.empty();
                  }
                },
                onSelected: (v) => row.sapCode = v.split(' — ').first.trim(),
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                        labelText: S.t('SAP code', 'SAP कोड')),
                    onChanged: (v) =>
                        row.sapCode = v.split(' — ').first.trim(),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: row.family,
                decoration: InputDecoration(
                    labelText: S.t('Model family', 'मॉडेल फॅमिली')),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(row.date == null
                  ? S.t('Bucket date', 'तारीख')
                  : row.date!.toIso8601String().substring(0, 10)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: row.date ?? DateTime.now(),
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030));
                if (d != null) setState(() => row.date = d);
              },
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextField(
                controller: row.qty,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: S.t('Qty', 'संख्या')),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: _rows.length == 1
                  ? null
                  : () => setState(() => _rows.removeAt(i)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- detail

class _ScheduleDetailPage extends StatefulWidget {
  const _ScheduleDetailPage({required this.schedule});
  final Map<String, dynamic> schedule;

  @override
  State<_ScheduleDetailPage> createState() => _ScheduleDetailPageState();
}

class _ScheduleDetailPageState extends State<_ScheduleDetailPage> {
  late Future<Map<String, dynamic>> _diffFuture;
  late Future<Map<String, dynamic>> _sanityFuture;
  bool _releasing = false;
  String? _splitMissingMsg;

  int get _id => widget.schedule['id'] as int;
  String get _status => widget.schedule['status'] as String? ?? 'draft';

  @override
  void initState() {
    super.initState();
    _diffFuture = _fetchMap('/schedules/$_id/diff');
    _sanityFuture = _fetchMap('/schedules/$_id/sanity');
  }

  Future<Map<String, dynamic>> _fetchMap(String path) async {
    try {
      final r = await Api.dio.get(path);
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _release({required bool confirmWarnings}) async {
    setState(() {
      _releasing = true;
      _splitMissingMsg = null;
    });
    try {
      final r = await Api.dio.post('/schedules/$_id/release',
          data: {'confirm_warnings': confirmWarnings});
      final report = Map<String, dynamic>.from(r.data as Map);
      if (!mounted) return;
      _snack(_releaseToast(report));
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final ex = ApiException.from(e);
      if (!mounted) return;
      if (ex.code == 'RELEASE_WARNINGS') {
        await _warningsDialog(ex);
      } else if (ex.code == 'SPLIT_MISSING') {
        setState(() => _splitMissingMsg = ex.message);
      } else {
        _snack(ex.message);
      }
    } finally {
      if (mounted) setState(() => _releasing = false);
    }
  }

  Future<void> _warningsDialog(ApiException ex) async {
    final checks = (ex.details['checks'] as List?) ?? const [];
    final anyway = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('Release has warnings', 'प्रसिद्धीसाठी चेतावण्या')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in checks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                      '• ${S.lang.value == 'mr' ? (c['message_mr'] ?? c['message_en']) : c['message_en']}',
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(S.t('Cancel', 'रद्द'))),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: YColors.amber),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(S.t('Release anyway', 'तरीही प्रसिद्ध करा'))),
        ],
      ),
    );
    if (anyway == true && mounted) {
      await _release(confirmWarnings: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.schedule;
    return Scaffold(
      appBar: AppBar(
          title: Text('${s['period']} · v${s['version']} · $_status')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_splitMissingMsg != null) ...[
                AlertBanner(
                    title: S.t('Split missing — hard stop',
                        'विभागणी नाही — प्रसिद्धी थांबली'),
                    body: _splitMissingMsg,
                    kind: 'danger'),
                OutlinedButton(
                  onPressed: () => context.push('/planning/config'),
                  child: Text(
                      S.t('Open Config → Splits', 'कॉन्फिग → स्प्लिट्स उघडा')),
                ),
                const SizedBox(height: 12),
              ],
              Text(S.t('Changes from last version', 'मागील आवृत्तीपासूनचे बदल'),
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              AsyncBody<Map<String, dynamic>>(
                future: _diffFuture,
                builder: (context, d) => _diffTable(
                    Map<String, dynamic>.from(d['diff'] as Map? ?? const {})),
              ),
              const SizedBox(height: 14),
              Text(S.t('Sanity checks', 'तपासण्या'),
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              AsyncBody<Map<String, dynamic>>(
                future: _sanityFuture,
                builder: (context, d) {
                  final sanity = Map<String, dynamic>.from(
                      d['sanity'] as Map? ?? const {});
                  final checks = (sanity['checks'] as List?) ?? const [];
                  if (checks.isEmpty) {
                    return AlertBanner(
                        title: S.t('All checks passed',
                            'सर्व तपासण्या उत्तीर्ण'),
                        kind: 'success');
                  }
                  return Column(children: [
                    for (final c in checks)
                      AlertBanner(
                        title: '${c['code']}',
                        body: S.lang.value == 'mr'
                            ? (c['message_mr'] as String? ??
                                c['message_en'] as String?)
                            : c['message_en'] as String?,
                        kind: c['severity'] == 'hard' ? 'danger' : 'warn',
                      ),
                  ]);
                },
              ),
              const SizedBox(height: 14),
              if (_status == 'draft')
                ElevatedButton(
                  onPressed: _releasing
                      ? null
                      : () => _release(confirmWarnings: false),
                  child: Text(S.t('Release', 'प्रसिद्ध करा')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _diffTable(Map<String, dynamic> diff) {
    final entries = (diff['entries'] as List?) ?? const [];
    if (entries.isEmpty) {
      return AlertBanner(
          title: S.t('No prior released version — everything is new',
              'मागील प्रसिद्ध आवृत्ती नाही — सर्व नवीन'),
          kind: 'info');
    }
    const hStyle = TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF64748B));
    const cStyle = TextStyle(fontSize: 11.5, color: Color(0xFF334155));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            Expanded(
                flex: 3,
                child: Text(S.t('FAMILY', 'फॅमिली'), style: hStyle)),
            Expanded(
                flex: 2,
                child: Text(S.t('MATERIAL', 'मटेरियल'), style: hStyle)),
            Expanded(
                flex: 2, child: Text(S.t('DATE', 'तारीख'), style: hStyle)),
            Expanded(child: Text(S.t('OLD', 'जुने'), style: hStyle)),
            Expanded(child: Text(S.t('NEW', 'नवीन'), style: hStyle)),
            Expanded(child: Text('Δ', style: hStyle)),
          ]),
          const Divider(height: 12),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                    flex: 3,
                    child: Text('${e['model_family'] ?? '—'}', style: cStyle)),
                Expanded(
                    flex: 2,
                    child: Text('${e['material_id'] ?? '—'}', style: cStyle)),
                Expanded(
                    flex: 2,
                    child: Text('${e['bucket_date'] ?? '—'}', style: cStyle)),
                Expanded(child: Text('${e['old'] ?? '0'}', style: cStyle)),
                Expanded(child: Text('${e['new'] ?? '0'}', style: cStyle)),
                Expanded(
                    child: Text('${e['delta'] ?? ''}',
                        style: cStyle.copyWith(
                            fontWeight: FontWeight.w700,
                            color: '${e['delta']}'.startsWith('-')
                                ? YColors.red
                                : YColors.green))),
              ]),
            ),
        ]),
      ),
    );
  }
}
