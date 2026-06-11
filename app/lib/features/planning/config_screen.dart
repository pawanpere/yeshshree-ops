/// Admin & config (scr-p-config): config over code. Six tabs — splits, reason
/// codes, mills, tolerances, calendar, settings. Every edit is audited server-
/// side; the ops_mode flip is a guarded business decision.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

String _currentMonth() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

void _snackIn(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

class ConfigScreen extends ConsumerWidget {
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(S.t('Admin & config', 'अ‍ॅडमिन व कॉन्फिग')),
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: S.t('Splits', 'स्प्लिट्स')),
              Tab(text: S.t('Reason codes', 'कारण कोड')),
              Tab(text: S.t('Mills', 'मिल्स')),
              Tab(text: S.t('Tolerances', 'सहनशीलता')),
              Tab(text: S.t('Calendar', 'दिनदर्शिका')),
              Tab(text: S.t('Settings', 'सेटिंग्ज')),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: TabBarView(children: const [
              _SplitsTab(),
              _ReasonsTab(),
              _MillsTab(),
              _TolerancesTab(),
              _CalendarTab(),
              _SettingsTab(),
            ]),
          ),
        ),
      ),
    );
  }
}

Future<List<dynamic>> _getList(String path,
    [Map<String, dynamic>? params]) async {
  try {
    final r = await Api.dio.get(path, queryParameters: params);
    return r.data as List<dynamic>;
  } on DioException catch (e) {
    throw ApiException.from(e);
  }
}

// ---------------------------------------------------------------- splits

class _SplitsTab extends StatefulWidget {
  const _SplitsTab();

  @override
  State<_SplitsTab> createState() => _SplitsTabState();
}

class _SplitsTabState extends State<_SplitsTab> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _getList('/config/splits');
  }

  void _reload() => setState(() => _future = _getList('/config/splits'));

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.centerLeft,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(S.t('Add split', 'स्प्लिट जोडा')),
          onPressed: _addDialog,
        ),
      ),
      const SizedBox(height: 10),
      AsyncBody<List<dynamic>>(
        future: _future,
        onRetry: _reload,
        builder: (context, rows) => Column(children: [
          if (rows.isEmpty)
            AlertBanner(
                title: S.t('No splits configured', 'स्प्लिट्स नाहीत'),
                kind: 'warn'),
          for (final s in rows)
            ListRow(
              title:
                  '${s['family']} · ${S.t('Yesh', 'येश')} ${s['yesh_pct']}% / '
                  '${S.t('Laxmi', 'लक्ष्मी')} ${s['laxmi_pct']}%',
              subtitle:
                  '${S.t('effective from', 'पासून लागू')} ${s['effective_from']}',
            ),
        ]),
      ),
    ]);
  }

  Future<void> _addDialog() async {
    final family = TextEditingController();
    final yesh = TextEditingController();
    final laxmi = TextEditingController();
    DateTime effFrom = DateTime.now();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(S.t('New split (new effective-dated row)',
              'नवीन स्प्लिट (नवीन लागू-तारीख ओळ)')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: family,
                decoration: InputDecoration(
                    labelText: S.t('Model family', 'मॉडेल फॅमिली'))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: yesh,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: S.t('Yeshshree %', 'येशश्री %')))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: laxmi,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: S.t('Laxmi %', 'लक्ष्मी %')))),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(effFrom.toIso8601String().substring(0, 10)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: effFrom,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030));
                if (d != null) setLocal(() => effFrom = d);
              },
            ),
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(err!,
                    style:
                        const TextStyle(color: YColors.red, fontSize: 11)),
              ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(S.t('Cancel', 'रद्द'))),
            ElevatedButton(
              onPressed: () {
                final y = int.tryParse(yesh.text.trim());
                final l = int.tryParse(laxmi.text.trim());
                if (family.text.trim().isEmpty || y == null || l == null) {
                  setLocal(() => err =
                      S.t('All fields are required', 'सर्व फील्ड आवश्यक'));
                  return;
                }
                if (y + l != 100) {
                  // Client-side mirror of the server's SPLIT_NOT_100 rule.
                  setLocal(() => err = S.t(
                      'Yesh + Laxmi must total 100 (now ${y + l})',
                      'येश + लक्ष्मी 100 असले पाहिजे (आता ${y + l})'));
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(S.t('Save', 'जतन करा')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Api.dio.post('/config/splits', data: {
        'family': family.text.trim(),
        'yesh_pct': int.parse(yesh.text.trim()),
        'laxmi_pct': int.parse(laxmi.text.trim()),
        'effective_from': effFrom.toIso8601String().substring(0, 10),
      });
      if (!mounted) return;
      _snackIn(context, S.t('Split added', 'स्प्लिट जोडला'));
      _reload();
    } on DioException catch (e) {
      if (mounted) _snackIn(context, ApiException.from(e).message);
    }
  }
}

// ---------------------------------------------------------------- reasons

class _ReasonsTab extends StatefulWidget {
  const _ReasonsTab();

  @override
  State<_ReasonsTab> createState() => _ReasonsTabState();
}

class _ReasonsTabState extends State<_ReasonsTab> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _getList('/config/reason-codes');
  }

  void _reload() =>
      setState(() => _future = _getList('/config/reason-codes'));

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.centerLeft,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(S.t('Add reason code', 'कारण कोड जोडा')),
          onPressed: () => _dialog(null),
        ),
      ),
      const SizedBox(height: 10),
      AsyncBody<List<dynamic>>(
        future: _future,
        onRetry: _reload,
        builder: (context, rows) => Column(children: [
          for (final r in rows)
            ListRow(
              title: '${r['code']} · ${r['label_en']}',
              subtitle: '${r['kind']}'
                  '${(r['label_mr'] ?? '') != '' ? ' · ${r['label_mr']}' : ''}',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                StatusBadge(
                    r['is_active'] == true
                        ? S.t('active', 'सक्रिय')
                        : S.t('inactive', 'निष्क्रिय'),
                    kind: r['is_active'] == true ? 'green' : 'red'),
                IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _dialog(r as Map<String, dynamic>)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Future<void> _dialog(Map<String, dynamic>? existing) async {
    final code = TextEditingController(
        text: existing == null ? '' : existing['code'] as String? ?? '');
    final en = TextEditingController(
        text: existing == null ? '' : existing['label_en'] as String? ?? '');
    final mr = TextEditingController(
        text: existing == null ? '' : existing['label_mr'] as String? ?? '');
    var kind = existing == null
        ? 'reject'
        : existing['kind'] as String? ?? 'reject';
    var active = existing == null ? true : existing['is_active'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null
              ? S.t('New reason code', 'नवीन कारण कोड')
              : S.t('Edit reason code', 'कारण कोड बदला')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: kind,
              decoration:
                  InputDecoration(labelText: S.t('Kind', 'प्रकार')),
              items: const [
                DropdownMenuItem(value: 'reject', child: Text('reject')),
                DropdownMenuItem(value: 'downtime', child: Text('downtime')),
              ],
              onChanged:
                  existing != null ? null : (v) => kind = v ?? 'reject',
            ),
            const SizedBox(height: 8),
            TextField(
                controller: code,
                enabled: existing == null,
                decoration:
                    InputDecoration(labelText: S.t('Code', 'कोड'))),
            const SizedBox(height: 8),
            TextField(
                controller: en,
                decoration: InputDecoration(
                    labelText: S.t('Label (English)', 'लेबल (इंग्रजी)'))),
            const SizedBox(height: 8),
            TextField(
                controller: mr,
                decoration: InputDecoration(
                    labelText: S.t('Label (Marathi)', 'लेबल (मराठी)'))),
            if (existing != null)
              SwitchListTile(
                dense: true,
                title: Text(S.t('Active', 'सक्रिय')),
                value: active,
                onChanged: (v) => setLocal(() => active = v),
              ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(S.t('Cancel', 'रद्द'))),
            ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(S.t('Save', 'जतन करा'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (existing == null) {
        if (code.text.trim().isEmpty || en.text.trim().isEmpty) {
          _snackIn(context,
              S.t('Code and English label required', 'कोड व इंग्रजी लेबल आवश्यक'));
          return;
        }
        await Api.dio.post('/config/reason-codes', data: {
          'kind': kind,
          'code': code.text.trim(),
          'label_en': en.text.trim(),
          'label_mr': mr.text.trim().isEmpty ? null : mr.text.trim(),
        });
      } else {
        await Api.dio.patch('/config/reason-codes/${existing['id']}', data: {
          'label_en': en.text.trim(),
          'label_mr': mr.text.trim().isEmpty ? null : mr.text.trim(),
          'is_active': active,
        });
      }
      if (!mounted) return;
      _snackIn(context, S.t('Saved', 'जतन झाले'));
      _reload();
    } on DioException catch (e) {
      if (mounted) _snackIn(context, ApiException.from(e).message);
    }
  }
}

// ---------------------------------------------------------------- mills

class _MillsTab extends StatefulWidget {
  const _MillsTab();

  @override
  State<_MillsTab> createState() => _MillsTabState();
}

class _MillsTabState extends State<_MillsTab> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _getList('/config/mills');
  }

  void _reload() => setState(() => _future = _getList('/config/mills'));

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.centerLeft,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(S.t('Add mill', 'मिल जोडा')),
          onPressed: () => _dialog(null),
        ),
      ),
      const SizedBox(height: 10),
      AsyncBody<List<dynamic>>(
        future: _future,
        onRetry: _reload,
        builder: (context, rows) => Column(children: [
          for (final m in rows)
            ListRow(
              title: m['name'] as String? ?? '—',
              subtitle: '${S.t('lead', 'लीड')} ${m['lead_days'] ?? '—'}d · '
                  'MOQ ${m['moq_mt'] ?? '—'} MT · '
                  '${m['sourcing'] ?? '—'}',
              trailing: IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _dialog(m as Map<String, dynamic>)),
            ),
        ]),
      ),
    ]);
  }

  Future<void> _dialog(Map<String, dynamic>? existing) async {
    final name = TextEditingController(
        text: existing == null ? '' : existing['name'] as String? ?? '');
    final lead = TextEditingController(
        text: existing?['lead_days']?.toString() ?? '');
    final moq =
        TextEditingController(text: existing?['moq_mt']?.toString() ?? '');
    final sourcing = TextEditingController(
        text: existing == null ? '' : existing['sourcing'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null
            ? S.t('New mill', 'नवीन मिल')
            : S.t('Edit mill', 'मिल बदला')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: InputDecoration(labelText: S.t('Name', 'नाव'))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: lead,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: S.t('Lead days', 'लीड दिवस')))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: moq,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(labelText: 'MOQ (MT)'))),
          ]),
          const SizedBox(height: 8),
          TextField(
              controller: sourcing,
              decoration: InputDecoration(
                  labelText: S.t('Sourcing (single/multi)',
                      'सोर्सिंग (single/multi)'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(S.t('Cancel', 'रद्द'))),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(S.t('Save', 'जतन करा'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (name.text.trim().isEmpty) {
      _snackIn(context, S.t('Name is required', 'नाव आवश्यक'));
      return;
    }
    final body = {
      'name': name.text.trim(),
      'lead_days': int.tryParse(lead.text.trim()),
      'moq_mt': moq.text.trim().isEmpty ? null : moq.text.trim(),
      'sourcing': sourcing.text.trim().isEmpty ? null : sourcing.text.trim(),
    };
    try {
      if (existing == null) {
        await Api.dio.post('/config/mills', data: body);
      } else {
        await Api.dio.patch('/config/mills/${existing['id']}', data: body);
      }
      if (!mounted) return;
      _snackIn(context, S.t('Saved', 'जतन झाले'));
      _reload();
    } on DioException catch (e) {
      if (mounted) _snackIn(context, ApiException.from(e).message);
    }
  }
}

// ---------------------------------------------------------------- tolerances

class _TolerancesTab extends StatefulWidget {
  const _TolerancesTab();

  @override
  State<_TolerancesTab> createState() => _TolerancesTabState();
}

class _TolerancesTabState extends State<_TolerancesTab> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _getList('/config/tolerances');
  }

  void _reload() =>
      setState(() => _future = _getList('/config/tolerances'));

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.centerLeft,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(S.t('Add tolerance', 'सहनशीलता जोडा')),
          onPressed: () => _dialog(null),
        ),
      ),
      const SizedBox(height: 10),
      AsyncBody<List<dynamic>>(
        future: _future,
        onRetry: _reload,
        builder: (context, rows) => Column(children: [
          for (final t in rows)
            ListRow(
              title: '${t['mat_group']} · ${t['uom']}',
              subtitle: '± ${t['pct_tolerance']}%',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                StatusBadge(
                    t['is_active'] == true
                        ? S.t('active', 'सक्रिय')
                        : S.t('inactive', 'निष्क्रिय'),
                    kind: t['is_active'] == true ? 'green' : 'red'),
                IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _dialog(t as Map<String, dynamic>)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Future<void> _dialog(Map<String, dynamic>? existing) async {
    final matGroup = TextEditingController(
        text: existing == null ? '' : existing['mat_group'] as String? ?? '');
    final uom = TextEditingController(
        text: existing == null ? 'KG' : existing['uom'] as String? ?? '');
    final pct = TextEditingController(
        text: existing?['pct_tolerance']?.toString() ?? '');
    var active = existing == null ? true : existing['is_active'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null
              ? S.t('New tolerance', 'नवीन सहनशीलता')
              : S.t('Edit tolerance', 'सहनशीलता बदला')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: matGroup,
                enabled: existing == null,
                decoration: InputDecoration(
                    labelText: S.t('Material group', 'मटेरियल गट'))),
            const SizedBox(height: 8),
            TextField(
                controller: uom,
                enabled: existing == null,
                decoration: const InputDecoration(labelText: 'UoM')),
            const SizedBox(height: 8),
            TextField(
                controller: pct,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: S.t('Tolerance %', 'सहनशीलता %'))),
            if (existing != null)
              SwitchListTile(
                dense: true,
                title: Text(S.t('Active', 'सक्रिय')),
                value: active,
                onChanged: (v) => setLocal(() => active = v),
              ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(S.t('Cancel', 'रद्द'))),
            ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(S.t('Save', 'जतन करा'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (double.tryParse(pct.text.trim()) == null) {
      _snackIn(context,
          S.t('Tolerance % must be a number', 'सहनशीलता % संख्या असावी'));
      return;
    }
    try {
      if (existing == null) {
        if (matGroup.text.trim().isEmpty || uom.text.trim().isEmpty) {
          _snackIn(context,
              S.t('Material group and UoM required', 'मटेरियल गट व UoM आवश्यक'));
          return;
        }
        await Api.dio.post('/config/tolerances', data: {
          'mat_group': matGroup.text.trim(),
          'uom': uom.text.trim(),
          'pct_tolerance': pct.text.trim(),
        });
      } else {
        await Api.dio.patch('/config/tolerances/${existing['id']}', data: {
          'pct_tolerance': pct.text.trim(),
          'is_active': active,
        });
      }
      if (!mounted) return;
      _snackIn(context, S.t('Saved', 'जतन झाले'));
      _reload();
    } on DioException catch (e) {
      if (mounted) _snackIn(context, ApiException.from(e).message);
    }
  }
}

// ---------------------------------------------------------------- calendar

class _DayDraft {
  _DayDraft({required this.date, required this.working, String? shiftsJson})
      : shifts = TextEditingController(text: shiftsJson ?? '');
  final DateTime date;
  bool working;
  final TextEditingController shifts;
}

class _CalendarTab extends StatefulWidget {
  const _CalendarTab();

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
  final _month = TextEditingController(text: _currentMonth());
  List<_DayDraft>? _days;
  String? _error;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _month.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final m = _month.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(m)) {
      setState(() => _error =
          S.t('Month must be YYYY-MM', 'महिना YYYY-MM असावा'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.dio
          .get('/config/calendar', queryParameters: {'month': m});
      final existing = <String, Map<String, dynamic>>{};
      for (final d in r.data as List) {
        existing['${d['cal_date']}'] = Map<String, dynamic>.from(d as Map);
      }
      // Full month grid: missing days default to working (PUT upserts them).
      final y = int.parse(m.substring(0, 4));
      final mo = int.parse(m.substring(5, 7));
      final days = <_DayDraft>[];
      var cursor = DateTime(y, mo, 1);
      while (cursor.month == mo) {
        final iso = cursor.toIso8601String().substring(0, 10);
        final ex = existing[iso];
        days.add(_DayDraft(
          date: cursor,
          working: ex == null ? true : ex['is_working'] == true,
          shiftsJson: ex == null || ex['shifts'] == null
              ? ''
              : jsonEncode(ex['shifts']),
        ));
        cursor = cursor.add(const Duration(days: 1));
      }
      if (mounted) setState(() => _days = days);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final days = _days;
    if (days == null) return;
    final body = <Map<String, dynamic>>[];
    for (final d in days) {
      dynamic shifts;
      final raw = d.shifts.text.trim();
      if (raw.isNotEmpty) {
        try {
          shifts = jsonDecode(raw);
        } catch (_) {
          _snackIn(
              context,
              S.t('Invalid shifts JSON on ${d.date.toIso8601String().substring(0, 10)}',
                  '${d.date.toIso8601String().substring(0, 10)} वर शिफ्ट JSON चुकीचे'));
          return;
        }
      }
      body.add({
        'cal_date': d.date.toIso8601String().substring(0, 10),
        'is_working': d.working,
        'shifts': shifts,
      });
    }
    setState(() => _saving = true);
    try {
      await Api.dio.put('/config/calendar', data: body);
      if (!mounted) return;
      _snackIn(context, S.t('Calendar saved', 'दिनदर्शिका जतन झाली'));
    } on DioException catch (e) {
      if (mounted) _snackIn(context, ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        SizedBox(
          width: 140,
          child: TextField(
            controller: _month,
            decoration: InputDecoration(
                labelText: S.t('Month (YYYY-MM)', 'महिना (YYYY-MM)')),
            onSubmitted: (_) => _load(),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
            onPressed: _loading ? null : _load,
            child: Text(S.t('Load', 'लोड करा'))),
        const Spacer(),
        ElevatedButton(
            onPressed: _saving || _days == null ? null : _save,
            child: Text(S.t('Save month', 'महिना जतन करा'))),
      ]),
      const SizedBox(height: 10),
      if (_error != null)
        AlertBanner(title: _error!, kind: 'danger'),
      if (_loading)
        const Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator())),
      if (_days != null)
        for (final d in _days!)
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(children: [
                SizedBox(
                  width: 110,
                  child: Text(d.date.toIso8601String().substring(0, 10),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: YColors.navy)),
                ),
                Switch(
                  value: d.working,
                  onChanged: (v) => setState(() => d.working = v),
                ),
                Text(
                    d.working
                        ? S.t('working', 'कामकाज')
                        : S.t('off', 'सुट्टी'),
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF64748B))),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: d.shifts,
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                        hintText: S.t('shifts JSON e.g. {"A":true,"B":true}',
                            'शिफ्ट JSON उदा. {"A":true,"B":true}'),
                        isDense: true),
                  ),
                ),
              ]),
            ),
          ),
    ]);
  }
}

// ---------------------------------------------------------------- settings

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _getList('/config/settings');
  }

  void _reload() => setState(() => _future = _getList('/config/settings'));

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      AsyncBody<List<dynamic>>(
        future: _future,
        onRetry: _reload,
        builder: (context, rows) => Column(children: [
          for (final s in rows)
            if (s['key'] == 'ops_mode')
              _opsModeCard(Map<String, dynamic>.from(s as Map))
            else
              ListRow(
                title: '${s['key']}',
                subtitle:
                    '${jsonEncode(s['value'])}${(s['description'] ?? '') != '' ? ' · ${s['description']}' : ''}',
              ),
        ]),
      ),
    ]);
  }

  Widget _opsModeCard(Map<String, dynamic> s) {
    final value = Map<String, dynamic>.from(s['value'] as Map? ?? const {});
    final mode = value['mode'] as String? ?? 'parallel_run';
    final authoritative = mode == 'authoritative';
    return AppCard(
      title: 'ops_mode',
      meta: s['description'] as String?,
      kind: authoritative ? 'urgent' : 'warn',
      trailing: StatusBadge(mode, kind: authoritative ? 'red' : 'amber'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            authoritative
                ? S.t('Stock checks BLOCK operations when short.',
                    'स्टॉक कमी असल्यास ऑपरेशन्स ब्लॉक होतात.')
                : S.t('Parallel run: stock checks warn, never block.',
                    'समांतर चालू: स्टॉक तपासणी फक्त चेतावणी देते.'),
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    authoritative ? YColors.amber : YColors.red),
            onPressed: () => _flip(value, authoritative),
            child: Text(authoritative
                ? S.t('Switch to parallel_run', 'parallel_run वर जा')
                : S.t('Switch to authoritative', 'authoritative वर जा')),
          ),
        ),
      ]),
    );
  }

  Future<void> _flip(Map<String, dynamic> value, bool authoritative) async {
    final next = authoritative ? 'parallel_run' : 'authoritative';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('Switch ops_mode to $next?',
            'ops_mode $next करायचे?')),
        content: Text(authoritative
            ? S.t(
                'Switching back to parallel_run makes stock checks warn-only '
                'again. Continue?',
                'parallel_run वर परत गेल्यास स्टॉक तपासणी फक्त चेतावणी देईल. '
                'पुढे जायचे?')
            : S.t(
                'Business decision — switching to authoritative makes stock '
                'checks BLOCK. Continue?',
                'व्यावसायिक निर्णय — authoritative केल्यास स्टॉक तपासणी '
                'ऑपरेशन्स ब्लॉक करेल. पुढे जायचे?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(S.t('Cancel', 'रद्द'))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: YColors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(S.t('Continue', 'पुढे जा'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Api.dio.put('/config/settings/ops_mode', data: {
        'value': {...value, 'mode': next},
      });
      if (!mounted) return;
      _snackIn(context, S.t('ops_mode is now $next', 'ops_mode आता $next'));
      _reload();
    } on DioException catch (e) {
      if (mounted) _snackIn(context, ApiException.from(e).message);
    }
  }
}
