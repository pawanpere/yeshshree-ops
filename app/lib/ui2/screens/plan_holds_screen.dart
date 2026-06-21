import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/bits.dart';
import '../widgets/polish2.dart';

/// Planning — Resolve Holds (office). Production confirmations land on HOLD when
/// PPC has not yet given the SAP order number; they wait here until planning
/// types that order number and resolves each one. Reads from [Data.holds];
/// clearly-marked DEMO fallback when the backend is unreachable or the table is
/// still empty. Each card has an inline resolve flow:
/// a TextField for the SAP order + [Data.resolveHold]. Renders inside the office
/// shell — no responsive code of its own.
class Ui2PlanHoldsScreen extends StatefulWidget {
  const Ui2PlanHoldsScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2PlanHoldsScreen> createState() => _Ui2PlanHoldsScreenState();
}

class _Ui2PlanHoldsScreenState extends State<Ui2PlanHoldsScreen> {
  Loaded<List<Json>>? _data;

  // Per-hold SAP-order input, keyed by hold id (so each card keeps its own text).
  final Map<int, TextEditingController> _orderCtl = {};
  // Which hold id is mid-resolve (so only its button busies).
  int? _resolving;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _orderCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await Data.holds();
    if (!mounted) return;
    setState(() => _data = res);
  }

  // A controller per hold id, created on demand and reused across rebuilds. The
  // listener re-evaluates the CTA + inline hint on every keystroke.
  TextEditingController _ctl(int id) => _orderCtl.putIfAbsent(
        id,
        () => TextEditingController()
          ..addListener(() {
            if (mounted) setState(() {});
          }),
      );

  // SAP order must be digits-only and at least 6 long before we let it resolve.
  bool _orderValid(int id) => V.sapOrder(_ctl(id).text);

  Future<void> _resolve(int id) async {
    if (_resolving != null) return;
    final order = _ctl(id).text.trim();
    // Hard-block: never resolve with a missing or malformed SAP order.
    if (!_orderValid(id)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(S.t('Enter a valid SAP order number first (6+ digits)',
            'आधी वैध SAP ऑर्डर क्रमांक टाका (६+ अंक)')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _resolving = id);
    final res = await Data.resolveHold(id, order);
    if (!mounted) return;
    if (res.failed) {
      setState(() => _resolving = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.error?.message ??
            S.t('Could not resolve hold', 'होल्ड सोडवता आला नाही')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(S.t('Hold resolved with order $order',
          'ऑर्डर $order ने होल्ड सोडवला')),
      behavior: SnackBarBehavior.floating,
    ));
    _orderCtl.remove(id)?.dispose();
    setState(() => _resolving = null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  ScreenHeader2 _header(Loaded<List<Json>>? loaded, List<Json> rows) =>
      ScreenHeader2(
        title: S.t('RESOLVE HOLDS', 'होल्ड सोडवा'),
        demo: loaded?.demo ?? false,
        trailing: rows.isEmpty
            ? null
            : Text('${rows.length}', style: F.mono(12, color: Y2.muted)),
      );

  Widget _emptyState() => EmptyState2(
        icon: Icons.task_alt_outlined,
        title: S.t('No holds waiting', 'कोणतेही होल्ड प्रतीक्षेत नाहीत'),
        subtitle: S.t('Confirmations on hold for a SAP order appear here.',
            'SAP ऑर्डरसाठी होल्डवरील पुष्ट्या इथे दिसतील.'),
      );

  String _countLabel(int n) =>
      S.t('$n waiting for a SAP order', '$n SAP ऑर्डरच्या प्रतीक्षेत');

  // ---- phone layout (unchanged from the original single-column list) ----

  Widget _phone() {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        _header(loaded, rows),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      itemCount: rows.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(_countLabel(rows.length),
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

  // ---- desktop layout (capped width; holds rendered as a data table) ----

  Widget _desktop() {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        _header(loaded, rows),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? _emptyState()
                  : ResponsiveContent(
                      maxWidth: 1200,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(_countLabel(rows.length),
                                style: F.hind(12, color: Y2.muted)),
                          ),
                          _table(rows),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  // Column widths shared by header + rows so the cells line up. A consistent gap
  // (see _gap) is inserted between every pair of adjacent columns — in both the
  // header and the data rows — so right-aligned numbers never butt up against the
  // next column's text. Total fixed widths + gaps stay well under 900px; the SAP
  // order column is Expanded and absorbs the slack.
  static const _wMaterial = 220.0;
  static const _wMeta = 140.0;
  static const _wGood = 84.0;
  static const _wRej = 84.0;
  static const _wAction = 160.0;
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
                SizedBox(width: _wMaterial, child: _th(S.t('Material', 'माल'))),
                _gap,
                SizedBox(width: _wMeta, child: _th(S.t('Line · Shift', 'लाइन · शिफ्ट'))),
                _gap,
                SizedBox(
                    width: _wGood, child: _th(S.t('Good', 'चांगले'), right: true)),
                _gap,
                SizedBox(
                    width: _wRej, child: _th(S.t('Rejected', 'नापास'), right: true)),
                _gap,
                Expanded(child: _th(S.t('SAP order no.', 'SAP ऑर्डर क्र.'))),
                _gap,
                SizedBox(width: _wAction, child: _th('')),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) _tableRow(rows[i], last: i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _th(String s, {bool right = false}) => Text(s,
      textAlign: right ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));

  Widget _tableRow(Json row, {required bool last}) {
    final id = row['id'];
    final payload = (row['payload'] as Json?) ?? const <String, dynamic>{};
    final line = payload['line_id'] ?? row['line_id'];
    final shift = payload['shift'];
    final material = payload['material'] ??
        (payload['material_id'] != null || row['material_id'] != null
            ? 'Material #${payload['material_id'] ?? row['material_id']}'
            : '—');
    final goodQty = double.tryParse('${payload['good_qty']}') ?? 0;
    final rejectedQty = double.tryParse('${payload['rejected_qty']}') ?? 0;
    final busy = id is int && _resolving == id;
    final resolvable = id is int;

    final metaBits = <String>[
      if (line != null) S.t('Line $line', 'लाइन $line'),
      if (shift != null) S.t('Shift $shift', 'शिफ्ट $shift'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Material + on-hold pill.
          SizedBox(
            width: _wMaterial,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$material',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(13, w: FontWeight.w600, color: Y2.ink)),
                const SizedBox(height: 5),
                Pill2(
                    text: S.t('on hold', 'होल्डवर'),
                    fg: Y2.orange,
                    bg: Y2.orangeTint,
                    borderColor: Y2.orangeLine),
              ],
            ),
          ),
          _gap,
          // Line · Shift.
          SizedBox(
            width: _wMeta,
            child: Text(metaBits.isEmpty ? '—' : metaBits.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: F.hind(12, color: Y2.muted)),
          ),
          _gap,
          // Good qty.
          SizedBox(
            width: _wGood,
            child: _fit(Text(_n(goodQty),
                maxLines: 1,
                style: F.mono(13, w: FontWeight.w600, color: Y2.body))),
          ),
          _gap,
          // Rejected qty.
          SizedBox(
            width: _wRej,
            child: _fit(Text(rejectedQty > 0 ? _n(rejectedQty) : '—',
                maxLines: 1,
                style: F.mono(13,
                    w: FontWeight.w600,
                    color: rejectedQty > 0 ? Y2.red : Y2.muted))),
          ),
          _gap,
          // SAP order field (or demo note).
          Expanded(
            child: resolvable
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(_ctl(id),
                          hint: '100482',
                          enabled: !busy,
                          onSubmit: () => _resolve(id)),
                      if (_ctl(id).text.trim().isNotEmpty && !_orderValid(id))
                        FieldHint(
                            S.t('6+ digit SAP order', '६+ अंकी SAP ऑर्डर')),
                    ],
                  )
                : Text(
                    S.t('Demo hold — connect to resolve',
                        'डेमो होल्ड — सोडवण्यासाठी कनेक्ट करा'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(12, color: Y2.muted)),
          ),
          _gap,
          // Resolve action.
          SizedBox(
            width: _wAction,
            child: resolvable
                ? PrimaryButton2(
                    label: S.t('Resolve', 'सोडवा'),
                    busy: busy,
                    enabled: !busy && _orderValid(id),
                    onTap: () => _resolve(id),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Scale-to-fit wrapper so numeric cells never overflow their fixed column,
  /// whatever the font metrics (matches the repo's big-number tiles).
  Widget _fit(Widget child) => FittedBox(
      fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: child);

  Widget _card(Json row) {
    final id = row['id'];
    final payload = (row['payload'] as Json?) ?? const <String, dynamic>{};
    final line = payload['line_id'] ?? row['line_id'];
    final shift = payload['shift'];
    final material = payload['material'] ??
        (payload['material_id'] != null || row['material_id'] != null
            ? 'Material #${payload['material_id'] ?? row['material_id']}'
            : '—');
    final goodQty = double.tryParse('${payload['good_qty']}') ?? 0;
    final rejectedQty = double.tryParse('${payload['rejected_qty']}') ?? 0;
    final busy = id is int && _resolving == id;
    // Only a real (live) row has an int id we can resolve against the backend.
    final resolvable = id is int;

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
              Expanded(
                child: Text(
                    '$material',
                    style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Pill2(
                  text: S.t('on hold', 'होल्डवर'),
                  fg: Y2.orange,
                  bg: Y2.orangeTint,
                  borderColor: Y2.orangeLine),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (line != null)
                Text(S.t('Line $line', 'लाइन $line'),
                    style: F.hind(12, color: Y2.muted)),
              if (shift != null)
                Text(S.t('Shift $shift', 'शिफ्ट $shift'),
                    style: F.hind(12, color: Y2.muted)),
              Text(
                  S.t('good ${_n(goodQty)}', 'चांगले ${_n(goodQty)}'),
                  style: F.hind(12, w: FontWeight.w600, color: Y2.body)),
              if (rejectedQty > 0)
                Text(S.t('rej ${_n(rejectedQty)}', 'नापास ${_n(rejectedQty)}'),
                    style: F.hind(12, color: Y2.red)),
            ],
          ),
          const SizedBox(height: 11),
          if (resolvable) ...[
            _label(S.t('SAP ORDER NO.', 'SAP ऑर्डर क्र.')),
            _field(_ctl(id),
                hint: '100482', enabled: !busy, onSubmit: () => _resolve(id)),
            // Inline hint only when they've typed something that isn't valid yet.
            if (_ctl(id).text.trim().isNotEmpty && !_orderValid(id))
              FieldHint(S.t('6+ digit SAP order', '६+ अंकी SAP ऑर्डर')),
            const SizedBox(height: 10),
            PrimaryButton2(
              label: S.t('Resolve with SAP order', 'SAP ऑर्डरने सोडवा'),
              busy: busy,
              enabled: !busy && _orderValid(id),
              onTap: () => _resolve(id),
            ),
          ] else
            Text(
                S.t('Demo hold — connect to resolve',
                    'डेमो होल्ड — सोडवण्यासाठी कनेक्ट करा'),
                style: F.hind(12, color: Y2.muted)),
        ],
      ),
    );
  }

  // qty strings arrive as NUMERIC(14,3): drop a trailing ".0" for whole numbers.
  String _n(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toString();

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: F.hind(10, w: FontWeight.w600, ls: 0.5, color: Y2.muted)),
      );

  Widget _field(TextEditingController c,
          {String? hint, bool enabled = true, VoidCallback? onSubmit}) =>
      Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Container(
          decoration: BoxDecoration(
            color: Y2.card,
            border: Border.all(color: Y2.line),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: TextField(
            controller: c,
            enabled: enabled,
            inputFormatters: V.digitsOnly,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => onSubmit?.call(),
            textInputAction: TextInputAction.done,
            style: F.mono(15, color: Y2.ink),
            cursorColor: Y2.accent,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: F.mono(15, color: Y2.muted2),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      );
}
