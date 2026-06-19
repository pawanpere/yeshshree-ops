import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
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
  String _poNo = '77-2291';
  String _poSupplier = 'Sandhar Steel';
  String _poMaterial = 'CR coil 2.5mm';
  String _poOrdered = '4,000 kg';
  static const String _onChallan = '4,000 kg';
  bool _exact = true;

  PhoneNav get nav => widget.nav;

  /// Parse "4,000 kg" → 4000.0 for the ordered-vs-challan delta chip.
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
          _poOrdered = qty == null ? _poOrdered : '$qty kg';
          _exact = false; // a manually-chosen order is not an auto-exact match
        });
        nav.hideOverlay();
      },
    ));
  }

  void _sendToQuality() {
    Ui2Flow.set('gate.po', _poNo);
    Ui2Flow.set('gate.supplier', _poSupplier);
    Ui2Flow.set('gate.material', _poMaterial);
    nav.replace(ScreenId.gateQc);
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
        ? S.t('0 kg · exact', '0 kg · अचूक')
        : '${diff > 0 ? '+' : '−'}${diff.abs().round()} kg (${pct.toStringAsFixed(1)}%)';
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
    return Column(
      children: [
        const StatusBar2(),
        // Header: back chevron + title + step counter.
        ScreenHeader2(
          title: S.t('MATCH ORDER', 'ऑर्डर जुळवा'),
          onBack: nav.pop,
          trailing: Text('4/6', style: F.mono(12, color: Y2.muted)),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Success banner: matching order found.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                            S.t('1 matching order found',
                                '1 जुळणारी ऑर्डर सापडली'),
                            style: F.hind(13,
                                w: FontWeight.w600, color: Y2.green)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 11),
                // Matched order card (accent-bordered). Tappable to confirm.
                Pressable2(
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
                            Text('PO $_poNo',
                                style: F.mono(15, color: Y2.ink)),
                            Pill2(
                              text: _exact
                                  ? S.t('EXACT', 'अचूक')
                                  : S.t('SELECTED', 'निवडले'),
                              fg: Y2.green,
                              bg: Y2.greenTint,
                              borderColor: Y2.greenLine,
                              dot: false,
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 5, 0, 10),
                          child: Text('$_poSupplier · $_poMaterial',
                              style: F.hind(12, color: Y2.muted)),
                        ),
                        _specRow(S.t('Ordered', 'ऑर्डर केले'), _poOrdered),
                        const SizedBox(height: 6),
                        _specRow(S.t('On challan', 'चलनावर'), _onChallan),
                        const SizedBox(height: 8),
                        Align(
                            alignment: Alignment.centerRight,
                            child: _deltaChip()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                // Wrong order? Search manually.
                OutlineButton2(
                  label: S.t('Wrong order? Search manually',
                      'चुकीची ऑर्डर? स्वतः शोधा'),
                  onTap: _searchManually,
                ),
              ],
            ),
          ),
        ),
        // Footer: send to quality.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: PrimaryButton2(
            label: S.t('Send to quality', 'गुणवत्तेकडे पाठवा'),
            onTap: _sendToQuality,
          ),
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
