import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/polish2.dart';

/// Management — Anomaly Register (office). The open anomaly queue: rules the
/// engine raised on receipts, confirmations and issues — HARD ones (e.g. a
/// debit was raised) and SOFT ones (advisory spikes). Loaded from
/// [Data.anomalies]; clearly-marked DEMO fallback when the backend is
/// unreachable or the table is still empty. Each card can be marked reviewed
/// ([Data.resolveAnomaly] with note 'reviewed'), which removes it from the
/// open register. Renders inside the office shell — no StatusBar2. Phone: a
/// vertical list of anomaly cards. Desktop: the same register as a width-capped
/// data table with an inline review button on each row.
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
    return Responsive(
      phone: (_) => _phoneBody(),
      tablet: (_) => _desktopBody(),
      desktop: (_) => _desktopBody(),
    );
  }

  // Shared register header (no StatusBar2 — this screen lives in the office
  // shell). Used by both the phone list and the desktop table.
  Widget _header(Loaded<List<Json>>? loaded, List<Json> rows) => ScreenHeader2(
        title: S.t('ANOMALY REGISTER', 'विसंगती नोंदवही'),
        demo: loaded?.demo ?? false,
        trailing: (loaded == null || rows.isEmpty)
            ? null
            : Text('${rows.length}', style: F.mono(12, color: Y2.muted)),
      );

  EmptyState2 _empty() => EmptyState2(
        icon: Icons.verified_outlined,
        title: S.t('No open anomalies', 'खुल्या विसंगती नाहीत'),
        subtitle: S.t('The rule engine has nothing flagged right now.',
            'नियम इंजिनने सध्या काहीही चिन्हांकित केलेले नाही.'),
      );

  // ---- phone layout (unchanged vertical list of cards) ----

  Widget _phoneBody() {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        _header(loaded, rows),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? _empty()
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

  // ---- desktop layout (width-capped data table) ----

  // Column widths shared by the header row + body rows so cells line up. A
  // consistent gap (see _gap) is inserted between EVERY pair of adjacent
  // columns in both the header and the data rows, so right-aligned pills /
  // numbers never butt up against the next column's text. The Message column is
  // Expanded and absorbs the remaining width.
  //   fixed: 72 + 132 + 150 + 140 = 494
  //   gaps : 16 × 4 = 64  (Sev|Rule, Rule|Msg, Msg|Ref, Ref|Act)
  //   494 + 64 = 558 <= 900 — no overflow at the test's fixed-width font.
  static const _wSev = 72.0;
  static const _wRule = 132.0;
  static const _wRef = 150.0;
  static const _wAct = 140.0;
  // Shared inter-column gap, placed identically in header + rows so they align.
  static const _gap = SizedBox(width: 16);

  Widget _desktopBody() {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        _header(loaded, rows),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 5)
              : rows.isEmpty
                  ? _empty()
                  : ResponsiveContent(
                      maxWidth: 1200,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                  S.t('${rows.length} open anomalies',
                                      '${rows.length} खुल्या विसंगती'),
                                  style: F.hind(12, color: Y2.muted)),
                            ),
                            _table(rows),
                          ],
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _table(List<Json> rows) {
    return Card2(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header row.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8FB),
              border: Border(bottom: BorderSide(color: Y2.line)),
            ),
            child: Row(
              children: [
                SizedBox(width: _wSev, child: _thFitted(S.t('Severity', 'तीव्रता'))),
                _gap,
                SizedBox(width: _wRule, child: _thFitted(S.t('Rule', 'नियम'))),
                _gap,
                Expanded(child: _th(S.t('Message', 'संदेश'))),
                _gap,
                SizedBox(
                    width: _wRef,
                    child: _thFitted(S.t('Reference', 'संदर्भ'))),
                _gap,
                SizedBox(
                    width: _wAct,
                    child: _thFitted(S.t('Action', 'कृती'),
                        alignment: Alignment.centerRight)),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) _tableRow(rows[i], i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _th(String s) => Text(s,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));

  // Fixed-column header cell: shrinks to fit so it can never overflow its
  // SizedBox at the test's fixed-width font.
  Widget _thFitted(String s,
          {AlignmentGeometry alignment = Alignment.centerLeft}) =>
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: _th(s),
      );

  Widget _tableRow(Json a, bool last) {
    final severity = '${a['severity'] ?? 'soft'}'.toLowerCase();
    final isHard = severity == 'hard';
    final ruleCode = '${a['rule_code'] ?? '—'}';
    final message = S.t('${a['message_en'] ?? ''}', '${a['message_mr'] ?? ''}');
    final refType = '${a['ref_type'] ?? '—'}';
    final refId = a['ref_id'];
    final id = a['id'];
    final busy = id is int && _resolving == id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border:
            last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _wSev,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Pill2(
                text: isHard ? S.t('hard', 'कठोर') : S.t('soft', 'मवाळ'),
                fg: isHard ? Y2.red : Y2.orange,
                bg: isHard ? Y2.redTint : Y2.orangeTint,
                borderColor: isHard ? Y2.redLine : Y2.orangeLine,
              ),
            ),
          ),
          _gap,
          SizedBox(
            width: _wRule,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(ruleCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.mono(12, w: FontWeight.w600, color: Y2.ink)),
            ),
          ),
          _gap,
          Expanded(
            child: Text(message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.hind(13, w: FontWeight.w600, color: Y2.ink)),
          ),
          _gap,
          SizedBox(
            width: _wRef,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link, size: 13, color: Y2.muted),
                  const SizedBox(width: 5),
                  Text(refId == null ? refType : '$refType #$refId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.hind(12, color: Y2.muted)),
                ],
              ),
            ),
          ),
          _gap,
          SizedBox(
            width: _wAct,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: _reviewBtn(a, busy),
            ),
          ),
        ],
      ),
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
            child: _reviewBtn(a, busy),
          ),
        ],
      ),
    );
  }

  /// The "Mark reviewed" action — shared by the phone card and the desktop
  /// table row so both behave identically.
  Widget _reviewBtn(Json a, bool busy) => Pressable2(
        onTap: busy ? null : () => _markReviewed(a),
        child: Opacity(
          opacity: busy ? 0.5 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    style: F.hind(13, w: FontWeight.w600, color: Y2.ink)),
              ],
            ),
          ),
        ),
      );
}
