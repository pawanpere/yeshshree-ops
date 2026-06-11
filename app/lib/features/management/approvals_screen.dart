/// Approvals inbox (app map scr-m-appr): pending approvals the caller can act
/// on (own role or active delegation), with approve / hold / decline, the §11.2
/// emergency override (management/admin, mandatory reason, post-facto review),
/// and a collapsed delegations manager. Field names mirror
/// backend/app/schemas/workflow.py exactly.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  List<dynamic>? _items;
  bool _loading = true;
  String? _error;

  List<dynamic>? _delegations;
  bool _delegationsLoading = false;

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
      final r = await Api.dio.get('/approvals/inbox');
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
    if (_delegations != null) await _loadDelegations(silent: true);
  }

  Future<void> _loadDelegations({bool silent = false}) async {
    if (!silent) setState(() => _delegationsLoading = true);
    try {
      final r = await Api.dio.get('/approvals/delegations');
      if (!mounted) return;
      setState(() {
        _delegations = r.data as List;
        _delegationsLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _delegationsLoading = false);
      _snack(ApiException.from(e).message);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- actions --------------------------------------------------------------

  Future<void> _decide(Map<String, dynamic> a, String decision) async {
    final titles = {
      'approve': S.t('Approve', 'मंजूर करा'),
      'hold': S.t('Put on hold', 'होल्डवर ठेवा'),
      'decline': S.t('Decline', 'नाकारा'),
    };
    final note = await _noteDialog(
        title: '${titles[decision]} · #${a['id']}', required: false);
    if (note == null) return; // cancelled
    try {
      await Api.dio.post('/approvals/${a['id']}/decide', data: {
        'decision': decision,
        if (note.isNotEmpty) 'note': note,
      });
      _snack(S.t('Decision recorded', 'निर्णय नोंदवला'));
      await _load();
    } on DioException catch (e) {
      _snack(ApiException.from(e).message);
    }
  }

  Future<void> _override(Map<String, dynamic> a) async {
    final reason = await _noteDialog(
      title: S.t('Emergency override · #${a['id']}',
          'आपत्कालीन ओव्हरराइड · #${a['id']}'),
      explain: S.t(
          'Executes now; creates a post-facto review for the original approvers.',
          'आत्ताच अंमलात येते; मूळ मंजुरीदारांसाठी पश्चात तपासणी तयार होते.'),
      required: true,
      submitLabel: S.t('Override', 'ओव्हरराइड'),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await Api.dio
          .post('/approvals/${a['id']}/override', data: {'reason': reason});
      _snack(S.t('Override executed — review created',
          'ओव्हरराइड झाले — तपासणी तयार'));
      await _load();
    } on DioException catch (e) {
      _snack(ApiException.from(e).message);
    }
  }

  /// Shared note/reason dialog. Returns null on cancel; trimmed text on submit.
  /// With [required], an empty value never submits.
  Future<String?> _noteDialog({
    required String title,
    String? explain,
    bool required = false,
    String? submitLabel,
  }) {
    final ctrl = TextEditingController();
    String? err;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (explain != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(explain,
                      style: const TextStyle(
                          fontSize: 12, color: YColors.muted)),
                ),
              TextField(
                controller: ctrl,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: required
                      ? S.t('Reason (required)', 'कारण (आवश्यक)')
                      : S.t('Note (optional)', 'टीप (ऐच्छिक)'),
                  errorText: err,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(S.t('Cancel', 'रद्द करा'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(110, 40)),
              onPressed: () {
                final v = ctrl.text.trim();
                if (required && v.isEmpty) {
                  setLocal(() =>
                      err = S.t('Reason is required', 'कारण आवश्यक आहे'));
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: Text(submitLabel ?? S.t('Submit', 'सबमिट')),
            ),
          ],
        ),
      ),
    );
  }

  // --- delegations ----------------------------------------------------------

  Future<void> _deactivateDelegation(int id) async {
    try {
      await Api.dio
          .patch('/approvals/delegations/$id', data: {'is_active': false});
      _snack(S.t('Delegation deactivated', 'प्रतिनिधित्व निष्क्रिय केले'));
      await _loadDelegations();
    } on DioException catch (e) {
      _snack(ApiException.from(e).message);
    }
  }

  Future<void> _addDelegationDialog() async {
    final principalCtrl = TextEditingController();
    final delegateCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    DateTime? from;
    DateTime? to;
    String? err;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> pick(bool isFrom) async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: ctx,
              initialDate: (isFrom ? from : to) ?? now,
              firstDate: now.subtract(const Duration(days: 365)),
              lastDate: now.add(const Duration(days: 730)),
            );
            if (d != null) setLocal(() => isFrom ? from = d : to = d);
          }

          return AlertDialog(
            title: Text(S.t('Add delegation', 'प्रतिनिधित्व जोडा'),
                style: const TextStyle(fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      S.t('While away, your approvals go to the delegate.',
                          'अनुपस्थितीत आपल्या मंजुरी प्रतिनिधीकडे जातात.'),
                      style: const TextStyle(
                          fontSize: 12, color: YColors.muted)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: principalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: S.t('Principal user ID (who is away)',
                            'मुख्य वापरकर्ता ID (कोण अनुपस्थित)')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: delegateCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: S.t('Delegate user ID',
                            'प्रतिनिधी वापरकर्ता ID')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: typeCtrl,
                    decoration: InputDecoration(
                        labelText: S.t('Approval type (blank = all)',
                            'मंजुरी प्रकार (रिक्त = सर्व)')),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pick(true),
                        child: Text(from == null
                            ? S.t('Valid from', 'पासून')
                            : _ymd(from!)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pick(false),
                        child: Text(
                            to == null ? S.t('Valid to', 'पर्यंत') : _ymd(to!)),
                      ),
                    ),
                  ]),
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(err!,
                          style: const TextStyle(
                              color: YColors.red, fontSize: 11.5)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(S.t('Cancel', 'रद्द करा'))),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(minimumSize: const Size(110, 40)),
                onPressed: () {
                  if (int.tryParse(principalCtrl.text.trim()) == null ||
                      int.tryParse(delegateCtrl.text.trim()) == null ||
                      from == null ||
                      to == null) {
                    setLocal(() => err = S.t(
                        'Both user IDs and both dates are required',
                        'दोन्ही वापरकर्ता ID व दोन्ही तारखा आवश्यक'));
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(S.t('Create', 'तयार करा')),
              ),
            ],
          );
        },
      ),
    );

    if (submitted != true) return;
    try {
      await Api.dio.post('/approvals/delegations', data: {
        'principal_user_id': int.parse(principalCtrl.text.trim()),
        'delegate_user_id': int.parse(delegateCtrl.text.trim()),
        if (typeCtrl.text.trim().isNotEmpty)
          'approval_type': typeCtrl.text.trim(),
        'valid_from': _ymd(from!),
        'valid_to': _ymd(to!),
      });
      _snack(S.t('Delegation created', 'प्रतिनिधित्व तयार झाले'));
      await _loadDelegations();
    } on DioException catch (e) {
      _snack(ApiException.from(e).message);
    }
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).role;
    final canOverride = role == 'management' || role == 'admin';

    return Scaffold(
      appBar: AppBar(title: Text(S.t('Approvals inbox', 'मंजुरी इनबॉक्स'))),
      body: RefreshIndicator(
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
                                title: S.t('Inbox clear', 'इनबॉक्स रिकामा'),
                                body: S.t('No approvals waiting on you.',
                                    'आपल्यावर प्रलंबित मंजुरी नाहीत.')),
                          ...?_items?.map((raw) => _approvalCard(
                              Map<String, dynamic>.from(raw as Map),
                              canOverride)),
                          const SizedBox(height: 8),
                          _delegationsSection(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _approvalCard(Map<String, dynamic> a, bool canOverride) {
    final type = (a['approval_type'] as String?) ?? '';
    final (String badgeLabel, String badgeKind) = switch (type) {
      'credit_waiver' => ('CREDIT WAIVER', 'warn'),
      'debit_note' => ('5× DEBIT', 'blue'),
      'issue_correction' => ('ISSUE CORRECTION', 'blue'),
      'confirmation_correction' => ('CONFIRM CORRECTION', 'blue'),
      'override_review' => ('OVERRIDE REVIEW', 'purple'),
      'credit_rebaseline' => ('CREDIT REBASELINE', 'blue'),
      _ => (type.replaceAll('_', ' ').toUpperCase(), 'blue'),
    };
    final payload = a['payload'] is Map
        ? Map<String, dynamic>.from(a['payload'] as Map)
        : <String, dynamic>{};
    final roles = (a['required_roles'] as List? ?? const [])
        .map((r) => r.toString())
        .toList();

    return AppCard(
      kind: type == 'override_review' ? 'info' : 'warn',
      title: '#${a['id']} · ${a['ref_type'] ?? ''} #${a['ref_id'] ?? ''}',
      meta: _age(a['created_at'] as String?),
      trailing: StatusBadge(badgeLabel, kind: badgeKind),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...payload.entries.take(8).map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(e.key.replaceAll('_', ' '),
                            style: const TextStyle(
                                fontSize: 10.5, color: YColors.muted)),
                      ),
                      Expanded(
                        child: Text('${e.value ?? '—'}',
                            style: const TextStyle(
                                fontSize: 11.5, color: YColors.ink)),
                      ),
                    ],
                  ),
                ),
              ),
          if (roles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 5, runSpacing: 4, children: [
                Text(S.t('Needs:', 'आवश्यक:'),
                    style: const TextStyle(
                        fontSize: 10.5, color: YColors.muted)),
                ...roles.map((r) => StatusBadge(r, kind: 'blue')),
              ]),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: YColors.green,
                    minimumSize: const Size.fromHeight(38)),
                onPressed: () => _decide(a, 'approve'),
                child: Text(S.t('Approve', 'मंजूर')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(38)),
                onPressed: () => _decide(a, 'hold'),
                child: Text(S.t('Hold', 'होल्ड')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: YColors.red,
                    minimumSize: const Size.fromHeight(38)),
                onPressed: () => _decide(a, 'decline'),
                child: Text(S.t('Decline', 'नाकारा')),
              ),
            ),
            if (canOverride)
              PopupMenuButton<String>(
                tooltip: S.t('More', 'अधिक'),
                onSelected: (_) => _override(a),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'override',
                    child: Text(
                        S.t('Emergency override', 'आपत्कालीन ओव्हरराइड'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
          ]),
        ],
      ),
    );
  }

  Widget _delegationsSection() {
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: Text(S.t('Delegations', 'प्रतिनिधित्व'),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: YColors.navy)),
        subtitle: Text(
            S.t('Route your approvals to someone while you are away',
                'अनुपस्थितीत आपल्या मंजुरी दुसऱ्याकडे वळवा'),
            style: const TextStyle(fontSize: 10.5, color: YColors.muted)),
        onExpansionChanged: (open) {
          if (open && _delegations == null && !_delegationsLoading) {
            _loadDelegations();
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_delegationsLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_delegations != null && _delegations!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                        S.t('No delegations yet.', 'अजून प्रतिनिधित्व नाही.'),
                        style: const TextStyle(
                            fontSize: 12, color: YColors.muted)),
                  )
                else
                  ...?_delegations?.map((raw) {
                    final dlg = Map<String, dynamic>.from(raw as Map);
                    final active = dlg['is_active'] == true;
                    return ListRow(
                      title: S.t(
                          'User ${dlg['principal_user_id']} → user ${dlg['delegate_user_id']}',
                          'वापरकर्ता ${dlg['principal_user_id']} → वापरकर्ता ${dlg['delegate_user_id']}'),
                      subtitle:
                          '${dlg['approval_type'] ?? S.t('all types', 'सर्व प्रकार')} · ${dlg['valid_from']} → ${dlg['valid_to']}',
                      trailing: active
                          ? TextButton(
                              onPressed: () => _deactivateDelegation(
                                  (dlg['id'] as num).toInt()),
                              child: Text(S.t('Deactivate', 'निष्क्रिय'),
                                  style: const TextStyle(
                                      fontSize: 11.5, color: YColors.red)),
                            )
                          : const StatusBadge('INACTIVE', kind: 'bad'),
                    );
                  }),
                OutlinedButton.icon(
                  onPressed: _addDelegationDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(S.t('Add delegation', 'प्रतिनिधित्व जोडा')),
                ),
              ],
            ),
          ),
        ],
      ),
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
