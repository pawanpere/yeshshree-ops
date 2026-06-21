import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';

/// Gate — match order — prototype screen [14]. Confirms the matching purchase
/// order for an inbound challan, then sends it on to quality. The auto-matched
/// PO is shown; "Wrong order? Search manually" opens a Picker2 of live POs from
/// [Data.purchaseOrders], and either path advances to inward QC.
class Ui2GateMatchScreen extends StatefulWidget {
  const Ui2GateMatchScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2GateMatchScreen> createState() => _Ui2GateMatchScreenState();
}

class _Ui2GateMatchScreenState extends State<Ui2GateMatchScreen> {
  late String _poNo;
  late String _poSupplier;
  late String _poMaterial;
  late String _poOrdered;
  late String _onChallan;
  late String _unit; // 'kg' for raw material, 'pcs' for purchased components
  bool _exact = true;
  bool _manual = false; // true once the operator overrides via manual search

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    // Seed the matched order from the gate entry the operator tapped, so this
    // screen shows *that* vehicle's supplier / material / PO / qty (RM weighed in
    // kg vs components counted in pcs). Falls back to a sample RM order when the
    // screen is opened cold (dev jump-nav) with no entry in the flow.
    final isComp = Ui2Flow.get<String>('gate.category') == 'component';
    _unit = isComp ? S.t('pcs', 'नग') : 'kg';
    _poNo = _flowOr('gate.po', '77-2291');
    _poSupplier = _flowOr('gate.supplier', 'Sandhar Steel');
    _poMaterial = _flowOr('gate.material', 'CR coil 2.5mm');
    _poOrdered = _qtyOr('gate.ordered', '4,000');
    _onChallan = _qtyOr('gate.challan', '4,000');
    // Auto-exact only when the challan equals the ordered qty.
    final o = _kg(_poOrdered), c = _kg(_onChallan);
    _exact = o != null && c != null && (o - c).abs() < 0.5;
  }

  String _flowOr(String key, String fallback) {
    final v = Ui2Flow.get<String>(key);
    return (v == null || v.isEmpty) ? fallback : v;
  }

  /// A quantity flow value ("5860") formatted with thousands + the entry's unit
  /// ("5,860 kg"); the [fallback] is already a bare grouped number.
  String _qtyOr(String key, String fallback) {
    final v = Ui2Flow.get<String>(key);
    final base = (v == null || v.isEmpty) ? fallback : _fmtNum(v);
    return '$base $_unit';
  }

  /// Group thousands in a bare number string ("5860" → "5,860"); passes through
  /// anything that isn't a plain integer.
  String _fmtNum(String raw) {
    final n = int.tryParse(raw.trim());
    if (n == null) return raw.trim();
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$b';
  }

  /// Parse "4,000 kg" / "1,500 pcs" → number for the ordered-vs-challan delta chip.
  double? _kg(String v) =>
      double.tryParse(v.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.]'), ''));

  Future<void> _searchManually() async {
    final res = await Data.purchaseOrders();
    final rows = res.data;
    nav.overlay(Picker2Sheet<int>(
      title: S.t('Search purchase order', 'खरेदी ऑर्डर शोधा'),
      options: [
        for (var i = 0; i < rows.length; i++)
          Picker2Option<int>(
            'PO ${rows[i]['sap_po_no'] ?? rows[i]['po_no'] ?? '—'}',
            i,
            sub:
                '${rows[i]['vendor'] ?? rows[i]['supplier'] ?? '—'} · ${rows[i]['material'] ?? '—'}',
          ),
      ],
      onPick: (i) {
        final r = rows[i];
        setState(() {
          _poNo = '${r['sap_po_no'] ?? r['po_no'] ?? '—'}';
          _poSupplier = '${r['vendor'] ?? r['supplier'] ?? '—'}';
          _poMaterial = '${r['material'] ?? '—'}';
          final qty = r['open_qty'] ?? r['ordered_qty'];
          _poOrdered = qty == null ? _poOrdered : '$qty $_unit';
          _manual = true; // a manually-chosen order, not the auto match
        });
        nav.hideOverlay();
      },
    ));
  }

  void _sendToQuality() {
    Ui2Flow.set('gate.po', _poNo);
    Ui2Flow.set('gate.supplier', _poSupplier);
    Ui2Flow.set('gate.material', _poMaterial);
    // Keep the entry's category + vehicle + challan (set when the row was tapped)
    // so inward QC weighs raw material vs counts components and shows this
    // vehicle's context. This is a fresh-challan match (not a worklist receipt),
    // so the GRN self-creates — clear only the worklist entry id.
    Ui2Flow.set('gate.entryId', null);
    nav.replace(ScreenId.gateQc);
  }

  /// Status pill on the matched order: EXACT (auto match, qty agrees), MATCHED
  /// (auto match but challan differs from the PO — the delta chip shows by how
  /// much), or SELECTED (operator overrode via manual search).
  Widget _matchPill() {
    final green = _exact || _manual;
    final label = _manual
        ? S.t('SELECTED', 'निवडले')
        : _exact
            ? S.t('EXACT', 'अचूक')
            : S.t('MATCHED', 'जुळले');
    return Pill2(
      text: label,
      fg: green ? Y2.green : Y2.accent,
      bg: green ? Y2.greenTint : Y2.accent.withValues(alpha: 0.10),
      borderColor: green ? Y2.greenLine : Y2.accent.withValues(alpha: 0.30),
      dot: false,
    );
  }

  /// Computed delta chip comparing ordered qty against the challan qty.
  Widget _deltaChip() {
    final ordered = _kg(_poOrdered);
    final challan = _kg(_onChallan);
    if (ordered == null || challan == null) return const SizedBox.shrink();
    final diff = challan - ordered;
    final exact = diff.abs() < 0.5;
    final pct = ordered == 0 ? 0.0 : (diff.abs() / ordered) * 100;
    final label = exact
        ? S.t('0 $_unit · exact', '0 $_unit · अचूक')
        : '${diff > 0 ? '+' : '−'}${diff.abs().round()} $_unit (${pct.toStringAsFixed(1)}%)';
    final fg = exact ? Y2.green : Y2.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: exact ? Y2.greenTint : Y2.orangeTint,
        border: Border.all(color: exact ? Y2.greenLine : Y2.orangeLine),
        borderRadius: BorderRadius.circular(Y2.rPill),
      ),
      child: Text(label,
          style: F.hind(11, w: FontWeight.w600, color: fg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- header (shared title / back / step counter) ----

  Widget _header() => ScreenHeader2(
        title: S.t('MATCH ORDER', 'ऑर्डर जुळवा'),
        onBack: nav.pop,
        trailing: Text('2/4', style: F.mono(12, color: Y2.muted)),
      );

  // ---- footer (shared send-to-quality action) ----

  Widget _footer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Color(0xFFF6F8FB),
          border: Border(top: BorderSide(color: Y2.line)),
        ),
        child: PrimaryButton2(
          label: S.t('Send to quality', 'गुणवत्तेकडे पाठवा'),
          onTap: _sendToQuality,
        ),
      );

  // ---- shared body pieces ----

  // Success banner: matching order found.
  Widget _matchBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Y2.greenTint,
          border: Border.all(color: const Color(0xFFA8DEC4)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Y2.green, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  S.t('1 matching order found', '1 जुळणारी ऑर्डर सापडली'),
                  style: F.hind(13, w: FontWeight.w600, color: Y2.green)),
            ),
          ],
        ),
      );

  // Matched order card (accent-bordered). Tappable to confirm.
  Widget _matchedOrderCard() => Pressable2(
        onTap: _sendToQuality,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Y2.card,
            border: Border.all(color: Y2.accent, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text('PO $_poNo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.mono(15, color: Y2.ink)),
                  ),
                  const SizedBox(width: 8),
                  _matchPill(),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 5, 0, 10),
                child: Text('$_poSupplier · $_poMaterial',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(12, color: Y2.muted)),
              ),
              _specRow(S.t('Ordered', 'ऑर्डर केले'), _poOrdered),
              const SizedBox(height: 6),
              _specRow(S.t('On challan', 'चलनावर'), _onChallan),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: _deltaChip()),
            ],
          ),
        ),
      );

  Widget _manualSearchButton() => OutlineButton2(
        label:
            S.t('Wrong order? Search manually', 'चुकीची ऑर्डर? स्वतः शोधा'),
        onTap: _searchManually,
      );

  // ---- phone layout (unchanged) ----

  Widget _phone() {
    return Column(
      children: [
        const StatusBar2(),
        // Header: back chevron + title + step counter.
        _header(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _matchBanner(),
                const SizedBox(height: 11),
                _matchedOrderCard(),
                const SizedBox(height: 11),
                _manualSearchButton(),
              ],
            ),
          ),
        ),
        // Footer: send to quality.
        _footer(),
      ],
    );
  }

  // ---- desktop layout (centered reading column, no phone chrome) ----

  Widget _desktop() {
    return Column(
      children: [
        _header(),
        Expanded(
          child: ResponsiveContent(
            maxWidth: 720,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _matchBanner(),
                  const SizedBox(height: 14),
                  _matchedOrderCard(),
                  const SizedBox(height: 14),
                  _manualSearchButton(),
                ],
              ),
            ),
          ),
        ),
        // Footer keeps its action centered to the same reading width.
        ResponsiveContent(
          maxWidth: 720,
          child: _footer(),
        ),
      ],
    );
  }

  Widget _specRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: F.hind(13, color: Y2.ink)),
          Text(value, style: F.mono(13, w: FontWeight.w600, color: Y2.ink)),
        ],
      );
}
