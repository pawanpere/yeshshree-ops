/// Notifications inbox (P38; §11.14). Blockers (tier=blocker, not yet acted)
/// render as urgent cards with an "Act" button — acting stops the repeat chain
/// server-side. Everything else gets "Mark read". All / Unread filter chips and
/// pull-to-refresh.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _unreadOnly = false;
  ApiException? _error;
  final Set<int> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.dio.get(
        '/notifications',
        queryParameters: _unreadOnly ? {'unread': true} : null,
      );
      if (!mounted) return;
      setState(() {
        _items = (r.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _error = null;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.from(e);
        _loading = false;
      });
    }
  }

  void _setFilter(bool unreadOnly) {
    if (_unreadOnly == unreadOnly) return;
    setState(() {
      _unreadOnly = unreadOnly;
      _loading = true;
    });
    _load();
  }

  Future<void> _post(int id, String verb) async {
    if (_busyIds.contains(id)) return;
    setState(() => _busyIds.add(id));
    try {
      await Api.dio.post('/notifications/$id/$verb');
      await _load();
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e));
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Widget _card(Map<String, dynamic> n) {
    final id = n['id'] as int;
    final tier = (n['tier'] as String?) ?? 'normal';
    final unread = n['read_at'] == null;
    final isBlocker = tier == 'blocker' && n['acted_at'] == null;
    final kind = (n['kind'] as String?) ?? '';
    final created = DateTime.tryParse((n['created_at'] as String?) ?? '');
    final when = created == null
        ? ''
        : DateFormat('d MMM · HH:mm').format(created.toLocal());
    final meta = [if (kind.isNotEmpty) kind, if (when.isNotEmpty) when]
        .join(' · ');
    final busy = _busyIds.contains(id);

    Widget? action;
    if (isBlocker) {
      action = Align(
        alignment: Alignment.centerRight,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: YColors.red,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: busy ? null : () => _post(id, 'act'),
          child: Text(S.t('Act', 'कारवाई करा')),
        ),
      );
    } else if (unread) {
      action = Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: busy ? null : () => _post(id, 'read'),
          child: Text(S.t('Mark read', 'वाचले म्हणून नोंदवा')),
        ),
      );
    }

    return AppCard(
      title: (n['title'] as String?) ?? '',
      meta: meta.isEmpty ? null : meta,
      body: n['body'] as String?,
      kind: isBlocker ? 'urgent' : (unread ? 'info' : null),
      trailing: isBlocker
          ? StatusBadge(S.t('Blocker', 'ब्लॉकर'), kind: 'bad')
          : (unread ? StatusBadge(S.t('New', 'नवीन'), kind: 'blue') : null),
      child: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text(S.t('Notifications', 'सूचना'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(S.t('All', 'सर्व')),
                      selected: !_unreadOnly,
                      onSelected: (_) => _setFilter(false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(S.t('Unread', 'न वाचलेल्या')),
                      selected: _unreadOnly,
                      onSelected: (_) => _setFilter(true),
                    ),
                  ],
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: AlertBanner(
                    kind: 'danger',
                    title: S.t('Could not load notifications',
                        'सूचना लोड करता आल्या नाहीत'),
                    body: error.message,
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          children: _items.isEmpty
                              ? [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 48),
                                    child: Text(
                                      _unreadOnly
                                          ? S.t('No unread notifications.',
                                              'न वाचलेल्या सूचना नाहीत.')
                                          : S.t('No notifications yet.',
                                              'अजून सूचना नाहीत.'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: YColors.muted, fontSize: 12),
                                    ),
                                  ),
                                ]
                              : _items.map(_card).toList(),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
