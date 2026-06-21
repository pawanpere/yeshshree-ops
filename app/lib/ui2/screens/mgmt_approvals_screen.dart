import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/polish2.dart';

/// Management — Approvals office screen. The decision inbox: open approval rows
/// (override reviews, credit waivers, etc.) wait here for a manager to Approve
/// or Decline. Reads from [Data.approvalsInbox]; clearly-marked DEMO fallback
/// when the backend is unreachable or the inbox table is still empty. Each card
/// carries a per-card busy guard so only the pressed button spins, posts the
/// decision through [Data.mutate], and on success optimistically drops out of
/// the list. Renders inside the office shell — no responsive code of its own.
class Ui2MgmtApprovalsScreen extends StatefulWidget {
  const Ui2MgmtApprovalsScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2MgmtApprovalsScreen> createState() => _Ui2MgmtApprovalsScreenState();
}

class _Ui2MgmtApprovalsScreenState extends State<Ui2MgmtApprovalsScreen> {
  Loaded<List<Json>>? _data;

  // Decisions already taken locally, keyed by approval id → 'approve'|'decline'.
  // Drives optimistic removal so the card collapses out without a reload.
  final Map<Object, String> _decided = <Object, String>{};

  // Which approval id is mid-flight, and which button on it, so only the
  // pressed button on that one card shows a spinner.
  Object? _busyId;
  String? _pendingDecision;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.approvalsInbox();
    if (!mounted) return;
    setState(() => _data = res);
  }

  Future<void> _decide(Json row, String decision) async {
    final id = row['id'];
    if (id == null || _busyId != null || _decided.containsKey(id)) return;
    setState(() {
      _busyId = id;
      _pendingDecision = decision;
    });
    final res = await Data.mutate('/approvals/$id/decide', {'decision': decision});
    if (!mounted) return;
    if (res.failed) {
      setState(() {
        _busyId = null;
        _pendingDecision = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.error?.message ??
            S.t('Could not record decision', 'निर्णय नोंदवता आला नाही')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    // Success: light haptic + a receipt toast for the consequential decision.
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(decision == 'approve'
          ? S.t('Approved', 'मंजूर केले')
          : S.t('Declined the request', 'विनंती नाकारली')),
      behavior: SnackBarBehavior.floating,
    ));
    // Optimistically drop the resolved card out of the inbox.
    setState(() {
      _busyId = null;
      _pendingDecision = null;
      _decided[id] = decision;
    });
  }

  // The still-actionable rows: open inbox minus anything resolved locally.
  List<Json> get _pending {
    final rows = _data?.data ?? const <Json>[];
    return [for (final r in rows) if (!_decided.containsKey(r['id'])) r];
  }

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // Shared header trailing count chip, identical on both form factors.
  Widget? _countTrailing(List<Json> rows) => rows.isEmpty
      ? null
      : Text('${rows.length}', style: F.mono(12, color: Y2.muted));

  // ---- phone layout (unchanged) ----

  Widget _phone() {
    final loaded = _data;
    final rows = loaded == null ? const <Json>[] : _pending;
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('APPROVALS', 'मंजुरी'),
          demo: loaded?.demo ?? false,
          trailing: _countTrailing(rows),
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 3)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: Icons.task_alt_outlined,
                      title: S.t("You're all caught up", 'सर्व पूर्ण'),
                      subtitle: S.t('No approvals are waiting for a decision.',
                          'निर्णयाच्या प्रतीक्षेत कोणतीही मंजुरी नाही.'),
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
                                S.t('${rows.length} waiting for a decision',
                                    '${rows.length} निर्णयाच्या प्रतीक्षेत'),
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

  // ---- desktop layout (data table) ----

  Widget _desktop() {
    final loaded = _data;
    final rows = loaded == null ? const <Json>[] : _pending;
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('APPROVALS', 'मंजुरी'),
          demo: loaded?.demo ?? false,
          trailing: _countTrailing(rows),
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 3)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: Icons.task_alt_outlined,
                      title: S.t("You're all caught up", 'सर्व पूर्ण'),
                      subtitle: S.t('No approvals are waiting for a decision.',
                          'निर्णयाच्या प्रतीक्षेत कोणतीही मंजुरी नाही.'),
                    )
                  : ResponsiveContent(
                      maxWidth: 1200,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10, left: 2),
                              child: Text(
                                  S.t('${rows.length} waiting for a decision',
                                      '${rows.length} निर्णयाच्या प्रतीक्षेत'),
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

  // Column widths shared by header + rows so the cells line up. A gap is
  // inserted between every adjacent column (see _gap) so right-aligned
  // references and the action buttons never butt up against the next column's
  // text. Exactly one column (Approval) is Expanded and absorbs the slack;
  // the rest are fixed. Fixed total + gaps stays well under 900px:
  // 280 + 130 + 200 + 3×16 = 658, leaving the Expanded title room from 820px up.
  static const _wDetail = 280.0;
  static const _wRef = 130.0;
  static const _wActions = 200.0;
  static const _gap = SizedBox(width: 16);

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
                Expanded(child: _th(S.t('Approval', 'मंजुरी'))),
                _gap,
                SizedBox(width: _wDetail, child: _th(S.t('Details', 'तपशील'))),
                _gap,
                SizedBox(width: _wRef, child: _th(S.t('Reference', 'संदर्भ'))),
                _gap,
                SizedBox(width: _wActions, child: _th(S.t('Decision', 'निर्णय'))),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) _tableRow(rows[i], i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _th(String label, {bool right = false}) => Text(label,
      textAlign: right ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));

  Widget _tableRow(Json row, bool last) {
    final v = _RowView.from(row);
    final busyHere = _busyId == v.id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Approval type (the primary text column — absorbs the slack).
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Glyph(GlyphShape.diamond, Y2.accent, size: 10),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(v.title,
                      style: F.hind(14, w: FontWeight.w700, color: Y2.ink),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          _gap,
          // Details (who · summary).
          SizedBox(
            width: _wDetail,
            child: Text(
                v.detail.isEmpty ? '—' : v.detail,
                style: F.hind(12,
                    color: v.detail.isEmpty ? Y2.muted2 : Y2.body, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          _gap,
          // Reference.
          SizedBox(
            width: _wRef,
            child: v.ref.isEmpty
                ? Text('—', style: F.mono(11, color: Y2.muted2))
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(v.ref,
                        maxLines: 1, style: F.mono(11, color: Y2.muted)),
                  ),
          ),
          _gap,
          // Decision actions.
          SizedBox(
            width: _wActions,
            child: Row(
              children: [
                Expanded(
                  child: _action(
                    label: S.t('Approve', 'मंजूर'),
                    bg: Y2.accent,
                    fg: Colors.white,
                    borderColor: null,
                    onTap: () => _decide(row, 'approve'),
                    spinning: busyHere && _pendingDecision == 'approve',
                    disabled: _busyId != null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _action(
                    label: S.t('Decline', 'नाकारा'),
                    bg: Colors.white,
                    fg: Y2.ink,
                    borderColor: const Color(0xFFCDD6E3),
                    onTap: () => _decide(row, 'decline'),
                    spinning: busyHere && _pendingDecision == 'decline',
                    disabled: _busyId != null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Json row) {
    final v = _RowView.from(row);
    final id = v.id;
    final title = v.title;
    final ref = v.ref;
    final detail = v.detail;

    final busyHere = _busyId == id;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Glyph(GlyphShape.diamond, Y2.accent, size: 11),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(title,
                    style: F.hind(14, w: FontWeight.w700, color: Y2.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              if (ref.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(ref,
                      style: F.mono(11, color: Y2.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(detail,
                  style: F.hind(12, color: Y2.body, height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Row(children: [
              Expanded(
                child: _action(
                  label: S.t('Approve', 'मंजूर'),
                  bg: Y2.accent,
                  fg: Colors.white,
                  borderColor: null,
                  onTap: () => _decide(row, 'approve'),
                  spinning: busyHere && _pendingDecision == 'approve',
                  disabled: _busyId != null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                  label: S.t('Decline', 'नाकारा'),
                  bg: Colors.white,
                  fg: Y2.ink,
                  borderColor: const Color(0xFFCDD6E3),
                  onTap: () => _decide(row, 'decline'),
                  spinning: busyHere && _pendingDecision == 'decline',
                  disabled: _busyId != null,
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required String label,
    required Color bg,
    required Color fg,
    required Color? borderColor,
    required VoidCallback onTap,
    required bool spinning,
    required bool disabled,
  }) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : onTap,
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: borderColor == null ? null : Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (spinning) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  ),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(label,
                      style: F.hind(13, w: FontWeight.w600, color: fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false),
                ),
              ],
            ),
          ),
        ),
      );
}

/// The three display fields derived from one approval row, computed once and
/// shared verbatim by the phone card and the desktop table so both layouts
/// always read the same data.
class _RowView {
  const _RowView({
    required this.id,
    required this.title,
    required this.ref,
    required this.detail,
  });

  final Object? id;
  final String title;
  final String ref;
  final String detail;

  factory _RowView.from(Json row) {
    final refType = '${row['ref_type'] ?? ''}';
    final refId = row['ref_id'];
    final ref = (refType.isEmpty && refId == null)
        ? ''
        : '${refType.isEmpty ? S.t('ref', 'संदर्भ') : refType}'
            '${refId == null ? '' : ' #$refId'}';

    final payload = (row['payload'] is Map)
        ? Json.from(row['payload'] as Map)
        : const <String, dynamic>{};
    final who = '${payload['who'] ?? ''}'.trim();
    final summary =
        S.t('${payload['summary_en'] ?? ''}', '${payload['summary_mr'] ?? ''}')
            .trim();
    // who · summary — collapse to whichever parts are present.
    final detail = [who, summary].where((s) => s.isNotEmpty).join(' · ');

    return _RowView(
      id: row['id'],
      title: _humanize('${row['approval_type'] ?? ''}'),
      ref: ref,
      detail: detail,
    );
  }

  // 'override_review' → 'Override Review'.
  static String _humanize(String type) {
    if (type.isEmpty) return S.t('Approval', 'मंजुरी');
    return type
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
