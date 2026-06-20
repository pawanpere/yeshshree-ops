import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';

/// Scrap Sale & Billing form — prototype screen [22]. Customer/material summary,
/// rate × qty → GST → invoice total, then confirm + raise invoice. The customer
/// row opens a Picker2 from Data.customers(); the material+qty row opens a
/// Picker2 from Data.materials(); rate is an editable numeric field and the
/// amount / GST / invoice total recompute live. 'Confirm sale & raise invoice'
/// POSTs /sales-invoices through the retry queue, stashes the flow values, and
/// advances to the sale-done screen.
class Ui2SaleFormScreen extends ConsumerStatefulWidget {
  const Ui2SaleFormScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2SaleFormScreen> createState() => _Ui2SaleFormScreenState();
}

class _Ui2SaleFormScreenState extends ConsumerState<Ui2SaleFormScreen> {
  PhoneNav get nav => widget.nav;

  // Selected customer — null until the operator actually picks one (the picker
  // returns a real customer name; no silent default carries through to billing).
  String? _customer;
  // Selected material + quantity — null until picked.
  String? _material;
  double _qty = 0;
  // Editable rate (₹ / kg).
  final _rateCtl = TextEditingController();
  final _rateFocus = FocusNode();

  bool _submitting = false;

  // Live-parsed rate. Empty / non-numeric reads as 0 so a cleared box can never
  // bill at a stale rate — _rateValid then gates the CTA.
  double get _rate => double.tryParse(_rateCtl.text.trim()) ?? 0;

  double get _amount => _rate * _qty;
  double get _gst => _amount * 0.18;
  double get _total => _amount + _gst;

  // ----- validation -----
  // Rate must be a real /kg price: > 0 and within a realistic ceiling (≤ 1000).
  bool get _rateValid => V.positive(_rate) && _rate <= 1000;
  bool get _qtyValid => V.positive(_qty);
  bool get _customerValid => _customer != null;
  bool get _materialValid => _material != null;
  bool get _canInvoice =>
      _rateValid && _qtyValid && _customerValid && _materialValid;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the amount/GST/total, the CTA and the rate hint on every
    // keystroke (the rate is derived live from the controller text).
    _rateCtl.addListener(() => setState(() {}));
    _rateFocus.addListener(() {
      if (_rateFocus.hasFocus) {
        // Select-all on focus for fast re-typing of the rate.
        _rateCtl.selection = TextSelection(
            baseOffset: 0, extentOffset: _rateCtl.text.length);
      }
      setState(() {}); // repaint the focus affordance
    });
  }

  @override
  void dispose() {
    _rateCtl.dispose();
    _rateFocus.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------- pickers ---

  Future<void> _pickCustomer() async {
    nav.overlay(const _PickerLoading2());
    final res = await Data.customers();
    if (!mounted) return;
    final options = [
      for (final c in res.data)
        Picker2Option<String>(
          '${c['name'] ?? c['sap_code']}',
          '${c['name'] ?? c['sap_code']}',
          sub: c['gstin'] as String? ?? c['sap_code'] as String?,
        ),
    ];
    nav.overlay(Picker2Sheet<String>(
      title: S.t('Customer', 'ग्राहक'),
      options: options,
      onPick: (name) {
        setState(() => _customer = name);
        nav.hideOverlay();
      },
    ));
  }

  Future<void> _pickMaterial() async {
    nav.overlay(const _PickerLoading2());
    final res = await Data.materials();
    if (!mounted) return;
    final options = [
      for (final m in res.data)
        Picker2Option<String>(
          '${m['description'] ?? m['sap_code']}',
          '${m['description'] ?? m['sap_code']}',
          sub: m['sap_code'] as String?,
        ),
    ];
    nav.overlay(Picker2Sheet<String>(
      title: S.t('Material', 'माल'),
      options: options,
      onPick: (desc) {
        setState(() {
          _material = desc;
          // The picker carries only the description; seed a real, positive
          // demo quantity so the line is billable once a material is chosen.
          if (!_qtyValid) _qty = 1250;
        });
        nav.hideOverlay();
      },
    ));
  }

  // ------------------------------------------------------------ submit ---

  Future<void> _submit() async {
    if (_submitting || !_canInvoice) return;
    setState(() => _submitting = true);
    final res = await Data.submit(
      ref,
      '/sales-invoices',
      <String, dynamic>{
        'invoice_no': 'INV-AUTO',
        'invoice_date': '2026-06-19',
        'dispatch_id': 1,
        'total_value': _total.toStringAsFixed(2),
        'lines': <dynamic>[],
      },
      label: '${S.t('Invoice', 'बीजक')} ${_customer!}',
    );
    if (!mounted) return;
    // On failure still proceed for the demo, but surface the error.
    if (res.failed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.error?.message ??
            S.t('Could not raise invoice', 'बीजक काढता आले नाही')),
        behavior: SnackBarBehavior.floating,
      ));
    }
    // Stash the submitted values for the result screen. _canInvoice guarantees
    // customer/material are non-null here.
    Ui2Flow.set('sale.customer', _customer!);
    Ui2Flow.set('sale.material', _material!);
    Ui2Flow.set('sale.qty', _qty);
    Ui2Flow.set('sale.rate', _rate.toStringAsFixed(2));
    Ui2Flow.set('sale.amount', _total.toStringAsFixed(2));
    Ui2Flow.set('sale.doc',
        res.data?['invoice_no'] ?? res.data?['id'] ?? 'INV-2326');
    setState(() => _submitting = false);
    nav.replace(ScreenId.saleDone);
  }

  String _money(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      if (i > 0 && fromEnd % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '₹${buf.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        // Header: shared back affordance + title.
        ScreenHeader2(
          title: S.t('SCRAP SALE & BILLING', 'स्क्रॅप विक्री व बिलिंग'),
          onBack: nav.pop,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Customer selector.
                Pressable2(
                  onTap: _pickCustomer,
                  child: _field(
                    S.t('Customer', 'ग्राहक'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                              _customer ??
                                  S.t('Select customer…', 'ग्राहक निवडा…'),
                              style: F.hind(15,
                                  w: FontWeight.w600,
                                  color: _customer == null
                                      ? Y2.muted
                                      : Y2.ink)),
                        ),
                        const Icon(I2.chevronDown, size: 20, color: Y2.muted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                // Material + quantity.
                Pressable2(
                  onTap: _pickMaterial,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                    decoration: BoxDecoration(
                      color: Y2.card,
                      border: Border.all(color: Y2.line),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(S.t('Material', 'माल'),
                                style: F.hind(11,
                                    w: FontWeight.w400, color: Y2.muted)),
                            const Icon(I2.chevronDown,
                                size: 20, color: Y2.muted),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                  _material ??
                                      S.t('Select material…', 'माल निवडा…'),
                                  style: F.hind(15,
                                      w: FontWeight.w600,
                                      color: _material == null
                                          ? Y2.muted
                                          : Y2.ink)),
                            ),
                            // Quantity only reads once a material (with its qty)
                            // is actually picked.
                            if (_material != null) ...[
                              const SizedBox(width: 7),
                              Text(_qty.toStringAsFixed(0),
                                  style: F.mono(16, color: Y2.ink)),
                              const SizedBox(width: 7),
                              Text('kg',
                                  style: F.hind(12,
                                      w: FontWeight.w400, color: Y2.muted)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                // Rate (editable) / Amount (computed).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _rateField()),
                    const SizedBox(width: 11),
                    Expanded(
                        child:
                            _stat(S.t('Amount', 'रक्कम'), _money(_amount))),
                  ],
                ),
                const SizedBox(height: 11),
                // Tax summary.
                Container(
                  padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    border: Border.all(color: Y2.line),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    children: [
                      _taxRow(S.t('Taxable', 'करपात्र'), _money(_amount),
                          Y2.ink),
                      const SizedBox(height: 6),
                      _taxRow(S.t('GST 18%', 'GST 18%'), _money(_gst), Y2.ink),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                            border:
                                Border(top: BorderSide(color: Y2.line))),
                        child: _taxRow(S.t('Invoice total', 'बीजक एकूण'),
                            _money(_total), Y2.accent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Footer CTA.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: PrimaryButton2(
            label: _submitting
                ? S.t('Raising invoice…', 'बीजक काढत आहे…')
                : S.t('Confirm sale & raise invoice',
                    'विक्री निश्चित करा व बीजक काढा'),
            busy: _submitting,
            enabled: _canInvoice,
            onTap: _submit,
          ),
        ),
      ],
    );
  }

  Widget _field(String label, Widget value) => Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        decoration: BoxDecoration(
          color: Y2.card,
          border: Border.all(color: Y2.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
            const SizedBox(height: 2),
            value,
          ],
        ),
      );

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
        decoration: BoxDecoration(
          color: Y2.lineSoft, // read-only tiles read distinct from the editable rate
          border: Border.all(color: Y2.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
            const SizedBox(height: 1),
            Text(value, style: F.mono(18, color: Y2.ink)),
          ],
        ),
      );

  // Editable rate field — visibly distinct from read-only tiles: white fill,
  // an edit pencil + accent border/underline on focus, select-all on focus.
  Widget _rateField() {
    final focused = _rateFocus.hasFocus;
    // Hint when the rate is missing/zero, or above the realistic ₹1000/kg cap.
    final empty = _rateCtl.text.trim().isEmpty;
    final hint = !_rateValid
        ? (empty || _rate <= 0
            ? S.t('Enter a rate above ₹0', '₹0 पेक्षा जास्त दर भरा')
            : S.t('Rate looks too high (max ₹1000/kg)',
                'दर खूप जास्त वाटतो (कमाल ₹1000/kg)'))
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      decoration: BoxDecoration(
        color: Y2.card,
        // Red hairline when the rate is invalid, matching the gate form's signal.
        border: Border.all(
            color: hint != null
                ? Y2.red
                : (focused ? Y2.accent : Y2.line),
            width: focused ? 1.5 : 1),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(S.t('Rate / kg', 'दर / kg'),
                  style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
              Icon(I2.edit, size: 13, color: focused ? Y2.accent : Y2.muted),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('₹', style: F.mono(18, color: Y2.ink)),
              Expanded(
                child: TextField(
                  controller: _rateCtl,
                  focusNode: _rateFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    _TwoDecimalFormatter(),
                  ],
                  cursorColor: Y2.accent,
                  style: F.mono(18, color: Y2.ink),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          if (hint != null) FieldHint(hint),
        ],
      ),
    );
  }

  Widget _taxRow(String label, String value, Color valueColor) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: F.hind(13, w: FontWeight.w500, color: Y2.ink)),
          Text(value,
              style: F.mono(13, w: FontWeight.w700, color: valueColor)),
        ],
      );
}

/// Sheet shown while a picker's `Data.*` read is still resolving.
class _PickerLoading2 extends StatelessWidget {
  const _PickerLoading2();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Y2.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Y2.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: Y2.accent),
            ),
          ),
          const SizedBox(height: 14),
          Text(S.t('Loading…', 'लोड होत आहे…'),
              textAlign: TextAlign.center,
              style: F.hind(12, color: Y2.muted)),
        ],
      ),
    );
  }
}

/// Keeps the rate field to a money shape: at most one dot and ≤2 decimals.
/// Pairs with the `allow([0-9.])` filter — that strips other characters; this
/// rejects a second dot and any third decimal digit, so "32.005" can't be typed.
class _TwoDecimalFormatter extends TextInputFormatter {
  static final _ok = RegExp(r'^\d*\.?\d{0,2}$');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue prev, TextEditingValue next) {
    final t = next.text;
    if (t.isEmpty || _ok.hasMatch(t)) return next;
    return prev; // reject the keystroke, keep the prior valid value
  }
}
