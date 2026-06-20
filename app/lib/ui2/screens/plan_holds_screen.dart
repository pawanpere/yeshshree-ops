import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
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

  // A controller per hold id, created on demand and reused across rebuilds.
  TextEditingController _ctl(int id) =>
      _orderCtl.putIfAbsent(id, () => TextEditingController());

  Future<void> _resolve(int id) async {
    if (_resolving != null) return;
    final order = _ctl(id).text.trim();
    if (order.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(S.t('Enter the SAP order number first',
            'आधी SAP ऑर्डर क्रमांक टाका')),
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
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('RESOLVE HOLDS', 'होल्ड सोडवा'),
          demo: loaded?.demo ?? false,
          trailing: rows.isEmpty
              ? null
              : Text('${rows.length}', style: F.mono(12, color: Y2.muted)),
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: Icons.task_alt_outlined,
                      title: S.t('No holds waiting', 'कोणतेही होल्ड प्रतीक्षेत नाहीत'),
                      subtitle: S.t(
                          'Confirmations on hold for a SAP order appear here.',
                          'SAP ऑर्डरसाठी होल्डवरील पुष्ट्या इथे दिसतील.'),
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
                                S.t('${rows.length} waiting for a SAP order',
                                    '${rows.length} SAP ऑर्डरच्या प्रतीक्षेत'),
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
            const SizedBox(height: 10),
            PrimaryButton2(
              label: S.t('Resolve with SAP order', 'SAP ऑर्डरने सोडवा'),
              busy: busy,
              enabled: !busy,
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
            onChanged: (_) => setState(() {}),
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
