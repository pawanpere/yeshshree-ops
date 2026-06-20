import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/polish2.dart';

/// Management — Anomaly Register (office). The open anomaly queue: rules the
/// engine raised on receipts, confirmations and issues — HARD ones (e.g. a
/// debit was raised) and SOFT ones (advisory spikes). Loaded from
/// [Data.anomalies]; clearly-marked DEMO fallback when the backend is
/// unreachable or the table is still empty. Each card can be marked reviewed
/// ([Data.resolveAnomaly] with note 'reviewed'), which removes it from the
/// open register. Renders inside the office shell — no responsive code of its
/// own, no StatusBar2.
class Ui2MgmtAnomaliesScreen extends StatefulWidget {
  const Ui2MgmtAnomaliesScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2MgmtAnomaliesScreen> createState() => _Ui2MgmtAnomaliesScreenState();
}

class _Ui2MgmtAnomaliesScreenState extends State<Ui2MgmtAnomaliesScreen> {
  Loaded<List<Json>>? _data;

  // Which anomaly id is mid-resolve (so only its button busies). Live rows
  // carry an int id; demo rows do too.
  int? _resolving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.anomalies();
    if (!mounted) return;
    setState(() => _data = res);
  }

  Future<void> _markReviewed(Json a) async {
    final id = a['id'];
    if (_resolving != null || id is! int) return;
    setState(() => _resolving = id);
    final res = await Data.resolveAnomaly(id, 'reviewed');
    if (!mounted) return;
    if (res.failed) {
      setState(() => _resolving = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.error?.message ??
            S.t('Could not mark reviewed', 'पुनरावलोकित म्हणून नोंदवता आले नाही')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(S.t('Marked reviewed', 'पुनरावलोकित म्हणून नोंदवले')),
      behavior: SnackBarBehavior.floating,
    ));
    // Optimistically drop the resolved card from the open register.
    final loaded = _data;
    if (loaded != null) {
      final next = [for (final r in loaded.data) if (r['id'] != id) r];
      setState(() {
        _resolving = null;
        _data = Loaded(next, demo: loaded.demo);
      });
    } else {
      setState(() => _resolving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('ANOMALY REGISTER', 'विसंगती नोंदवही'),
          demo: loaded?.demo ?? false,
          trailing: (loaded == null || rows.isEmpty)
              ? null
              : Text('${rows.length}', style: F.mono(12, color: Y2.muted)),
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: Icons.verified_outlined,
                      title: S.t('No open anomalies', 'खुल्या विसंगती नाहीत'),
                      subtitle: S.t(
                          'The rule engine has nothing flagged right now.',
                          'नियम इंजिनने सध्या काहीही चिन्हांकित केलेले नाही.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      itemCount: rows.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                                S.t('${rows.length} open anomalies',
                                    '${rows.length} खुल्या विसंगती'),
                                style: F.hind(12, color: Y2.muted)),
                          );
                        }
                        return _card(rows[i - 1]);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _card(Json a) {
    final severity = '${a['severity'] ?? 'soft'}'.toLowerCase();
    final isHard = severity == 'hard';
    final ruleCode = '${a['rule_code'] ?? '—'}';
    final message = S.t('${a['message_en'] ?? ''}', '${a['message_mr'] ?? ''}');
    final refType = '${a['ref_type'] ?? '—'}';
    final refId = a['ref_id'];
    final id = a['id'];
    final busy = id is int && _resolving == id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(Y2.rRow),
        border: Border.all(color: Y2.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill2(
                text: isHard
                    ? S.t('hard', 'कठोर')
                    : S.t('soft', 'मवाळ'),
                fg: isHard ? Y2.red : Y2.orange,
                bg: isHard ? Y2.redTint : Y2.orangeTint,
                borderColor: isHard ? Y2.redLine : Y2.orangeLine,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(ruleCode,
                    style: F.mono(12, w: FontWeight.w600, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(message,
              style: F.hind(13, w: FontWeight.w600, color: Y2.ink),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.link, size: 13, color: Y2.muted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                    refId == null ? refType : '$refType #$refId',
                    style: F.hind(12, color: Y2.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Pressable2(
              onTap: busy ? null : () => _markReviewed(a),
              child: Opacity(
                opacity: busy ? 0.5 : 1,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFCDD6E3)),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Y2.accent),
                        ),
                        const SizedBox(width: 7),
                      ] else ...[
                        const Icon(Icons.check, size: 15, color: Y2.ink),
                        const SizedBox(width: 6),
                      ],
                      Text(S.t('Mark reviewed', 'पुनरावलोकित करा'),
                          style:
                              F.hind(13, w: FontWeight.w600, color: Y2.ink)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
