import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';
import '../widgets/sla.dart';

/// Gate — Receive Invoice (multi-item) — P-G.
///
/// One invoice/challan can carry several different items, and those items can sit
/// against DIFFERENT purchase orders. Instead of walking each item through the
/// single-item match → QC → GRN flow, this screen puts ALL items of one invoice on
/// a single screen so the operator can enter received/rejected qty for every line
/// and post one multi-line goods receipt.
///
/// Phone: a horizontal item selector + a per-item editor card (one item at a time,
/// progress shown across the top). Desktop: every line as an editable table row.
/// Both layouts share the same per-item controllers, so values survive a resize.
class Ui2GateReceiveItemsScreen extends ConsumerStatefulWidget {
  const Ui2GateReceiveItemsScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2GateReceiveItemsScreen> createState() =>
      _Ui2GateReceiveItemsScreenState();
}

/// One editable line on the invoice. The parent owns the controllers (created
/// once) so the value typed on phone is the same value shown on desktop.
class _ItemEntry {
  _ItemEntry({
    required this.material,
    required this.category,
    required this.po,
    required this.ordered,
    required this.challan,
    this.onHand = 0,
    this.stockMax = 0,
    this.stockMin = 0,
  })  : received = TextEditingController(text: _initial(challan)),
        rejected = TextEditingController(text: '0');

  String material;
  final String category;
  String po;
  final double ordered;
  final double challan;
  final double onHand; // current stock on hand
  final double stockMax; // 0 = no max limit configured
  final double stockMin;
  final TextEditingController received;
  final TextEditingController rejected;
  bool qcPass = true;

  static String _initial(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';

  bool get isComponent => category == 'component';

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;
  double get receivedQty => _parse(received);
  double get rejectedQty => _parse(rejected);
  double get acceptedQty => receivedQty - rejectedQty;

  // ---- max stock limit (P-L) ----
  bool get hasMax => stockMax > 0;
  /// How much can still be accepted before the material hits its max stock.
  double get cap {
    final c = stockMax - onHand;
    return c < 0 ? 0 : c;
  }
  /// Received would push stock past the max → hard-blocked at the gate.
  bool get overMax => hasMax && receivedQty > cap;
  /// Already at the max — nothing can be accepted (return the load).
  bool get atMax => hasMax && cap <= 0;
  bool get belowMin => stockMin > 0 && onHand < stockMin;

  /// A line is ready to post when something was received, the rejected amount
  /// doesn't exceed it, and it doesn't breach the material's max stock limit.
  bool get valid =>
      receivedQty > 0 &&
      rejectedQty >= 0 &&
      rejectedQty <= receivedQty &&
      !overMax;

  /// Advisory: received exceeds the PO ordered qty (still allowed — the backend
  /// records a soft anomaly; invariant #11 never hard-blocks stock).
  bool get overPo => ordered > 0 && receivedQty > ordered;

  void dispose() {
    received.dispose();
    rejected.dispose();
  }
}

class _Ui2GateReceiveItemsScreenState
    extends ConsumerState<Ui2GateReceiveItemsScreen> {
  static final _decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

  late String _invoice;
  late String _supplier;
  late String _vehicle;
  late final List<_ItemEntry> _items;
  late final DateTime _due; // GRN 3-day deadline (P-T)
  int _selected = 0;
  bool _posting = false;
  bool _posted = false;
  bool _queued = false;
  String _grnDoc = 'GR-5572';

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _invoice = Ui2Flow.get<String>('gate.invoice') ?? 'INV-0000';
    _supplier = Ui2Flow.get<String>('gate.supplier') ?? '—';
    _vehicle = Ui2Flow.get<String>('gate.vehicle') ?? '—';
    final raw = (Ui2Flow.raw('gate.items') as List?) ?? const [];
    _items = [
      for (final e in raw)
        if (e is Map)
          _ItemEntry(
            material: '${e['material'] ?? '—'}',
            category: '${e['category'] ?? 'rm'}',
            po: '${e['po'] ?? '—'}',
            ordered: _num(e['ordered']),
            challan: _num(e['challan']),
            onHand: _num(e['on_hand']),
            stockMax: _num(e['stock_max']),
            stockMin: _num(e['stock_min']),
          ),
    ];
    if (_items.isEmpty) {
      // Cold open (dev jump-nav / no invoice in the flow) — seed a representative
      // multi-PO invoice so the screen is never blank and previews look real.
      // CR coil + Fasteners sit near their max so their full challan can't be taken.
      _invoice = _invoice == 'INV-0000' ? 'INV-9931002' : _invoice;
      _supplier = _supplier == '—' ? 'Sandhar Steel' : _supplier;
      _vehicle = _vehicle == '—' ? 'MH40 PQ 8833' : _vehicle;
      _items.addAll([
        _ItemEntry(material: 'CR coil 2.5mm', category: 'rm', po: '77-2291', ordered: 4000, challan: 4000, onHand: 2800, stockMax: 3000, stockMin: 500),
        _ItemEntry(material: 'HR coil 3.0mm', category: 'rm', po: '77-2304', ordered: 6000, challan: 5860, onHand: 1000, stockMax: 12000, stockMin: 800),
        _ItemEntry(material: 'Mounting bracket 7782', category: 'component', po: '88-4419', ordered: 1500, challan: 1500, onHand: 200, stockMax: 5000, stockMin: 300),
        _ItemEntry(material: 'Fasteners M8 hex', category: 'component', po: '88-4631', ordered: 8000, challan: 8000, onHand: 7950, stockMax: 8000, stockMin: 1000),
      ]);
    }
    final h = Ui2Flow.raw('gate.arrivedHoursAgo');
    _due = grnDueFrom(DateTime.now(), h is num ? h : 6);
    for (final it in _items) {
      it.received.addListener(_onEdit);
      it.rejected.addListener(_onEdit);
    }
  }

  void _setReceived(_ItemEntry it, double v) {
    it.received.text = v == v.roundToDouble() ? '${v.round()}' : '$v';
  }

  void _onEdit() => setState(() {});

  static double _num(dynamic v) =>
      double.tryParse('$v'.replaceAll(',', '').trim()) ?? 0;

  @override
  void dispose() {
    for (final it in _items) {
      it.received.removeListener(_onEdit);
      it.rejected.removeListener(_onEdit);
      it.dispose();
    }
    super.dispose();
  }

  int get _doneCount => _items.where((i) => i.valid).length;
  bool get _allValid => _items.isNotEmpty && _items.every((i) => i.valid);
  double get _totalAccepted =>
      _items.fold(0, (s, i) => s + (i.valid ? i.acceptedQty : 0));

  String _unitOf(_ItemEntry it) =>
      it.isComponent ? S.t('pcs', 'नग') : 'kg';

  /// Group thousands in an integer; pass decimals through with 3 places.
  String _fmt(double v) {
    if (v != v.roundToDouble()) return v.toStringAsFixed(3);
    final s = v.round().abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${v < 0 ? '−' : ''}$b';
  }

  Future<void> _changePo(_ItemEntry it) async {
    final res = await Data.purchaseOrders();
    final rows = res.data;
    if (!mounted) return;
    nav.overlay(Picker2Sheet<int>(
      title: S.t('Change purchase order', 'खरेदी ऑर्डर बदला'),
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
        setState(() =>
            it.po = '${rows[i]['sap_po_no'] ?? rows[i]['po_no'] ?? it.po}');
        nav.hideOverlay();
      },
    ));
  }

  Future<void> _post() async {
    if (_posting || !_allValid) return;
    setState(() => _posting = true);
    final res = await Data.submit(
      ref,
      '/goods-receipts/multi',
      <String, dynamic>{
        'doc_type': 'invoice',
        'vehicle_no': _vehicle,
        'invoice_no': _invoice,
        'vendor_id': 1,
        'items': [
          for (final it in _items)
            {
              'material': it.material,
              'po': it.po,
              'received_qty': '${it.receivedQty}',
              'rejected_qty': '${it.rejectedQty}',
              'qc_result': it.qcPass ? 'pass' : 'fail',
            }
        ],
      },
      label: '${S.t('Goods receipt', 'माल पावती')} · ${_items.length} ${S.t('items', 'वस्तू')}',
    );
    if (!mounted) return;
    if (res.failed) {
      setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Y2.red,
        content: Text(
            res.error?.message ??
                S.t('Could not post receipt', 'पावती नोंदता आली नाही'),
            style: F.hind(13, color: Colors.white)),
      ));
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() {
      _posting = false;
      _posted = true;
      _queued = res.queued;
      _grnDoc = '${res.data?['grn_no'] ?? res.data?['doc_no'] ?? res.data?['id'] ?? _grnDoc}';
    });
  }

  // ---------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    if (_posted) return _success();
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- shared header pieces ----

  Widget _invoiceStrip({required bool wide}) {
    final frac = _items.isEmpty ? 0.0 : _doneCount / _items.length;
    return Card2(
      padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 13, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(I2.invoice, size: 18, color: Y2.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_invoice,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.mono(14, w: FontWeight.w700, color: Y2.ink)),
              ),
              Pill2(
                text: S.t('${_items.length} ITEMS', '${_items.length} वस्तू'),
                fg: Y2.accent,
                bg: Y2.accent.withValues(alpha: 0.10),
                borderColor: Y2.accent.withValues(alpha: 0.30),
                dot: false,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text('$_supplier · $_vehicle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(12, color: Y2.muted)),
              ),
              const SizedBox(width: 8),
              // GRN must be completed within 3 days of arrival (P-T).
              SlaCountdown(_due),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: AnimatedBar2(fraction: frac)),
              const SizedBox(width: 10),
              Text(
                  S.t('$_doneCount of ${_items.length} entered',
                      '${_items.length} पैकी $_doneCount भरले'),
                  style: F.hind(11, w: FontWeight.w600, color: Y2.body)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Color(0xFFF6F8FB),
          border: Border(top: BorderSide(color: Y2.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _allValid
                    ? S.t('All items ready · accepting ${_fmt(_totalAccepted)}',
                        'सर्व वस्तू तयार · ${_fmt(_totalAccepted)} स्वीकारत')
                    : S.t('Enter qty for every item to post',
                        'नोंदवण्यासाठी प्रत्येक वस्तूचे प्रमाण भरा'),
                style: F.hind(11, color: Y2.muted),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 200,
              child: PrimaryButton2(
                label: _posting
                    ? S.t('Posting…', 'नोंदवत आहे…')
                    : S.t('Post GRN · ${_items.length} items',
                        '${_items.length} वस्तू नोंदवा'),
                busy: _posting,
                enabled: _allValid,
                onTap: _post,
              ),
            ),
          ],
        ),
      );

  // ---- phone layout ----

  Widget _phone() {
    final it = _items[_selected.clamp(0, _items.length - 1)];
    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('RECEIVE INVOICE', 'चलन स्वीकारा'),
          subtitle: _invoice,
          onBack: nav.pop,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _invoiceStrip(wide: false),
                const SizedBox(height: 11),
                _selectorChips(),
                const SizedBox(height: 11),
                _editorCard(it),
              ],
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  Widget _selectorChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final it = _items[i];
          final active = i == _selected;
          final done = it.valid;
          return Pressable2(
            scale: 0.96,
            onTap: () => setState(() => _selected = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? Y2.accent.withValues(alpha: 0.10) : Y2.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: active ? Y2.accent : Y2.line,
                    width: active ? 1.5 : 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: done ? Y2.green : Y2.muted2,
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Text('${i + 1}',
                      style: F.mono(13,
                          w: FontWeight.w700,
                          color: active ? Y2.accent : Y2.body)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _editorCard(_ItemEntry it) {
    final unit = _unitOf(it);
    return Card2(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(it.material,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(15, w: FontWeight.w700, color: Y2.ink)),
              ),
              const SizedBox(width: 8),
              _categoryPill(it),
            ],
          ),
          const SizedBox(height: 10),
          // PO row — tappable to reassign (items can span multiple POs).
          Pressable2(
            onTap: () => _changePo(it),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              decoration: BoxDecoration(
                color: Y2.screen,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Y2.line),
              ),
              child: Row(
                children: [
                  Text(S.t('PO', 'PO'), style: F.hind(12, color: Y2.muted)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(it.po,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.mono(13, w: FontWeight.w700, color: Y2.ink)),
                  ),
                  Text(S.t('change', 'बदला'),
                      style: F.hind(11, w: FontWeight.w600, color: Y2.accent)),
                  const Icon(I2.chevronDown, size: 18, color: Y2.accent),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _specRow(S.t('Ordered', 'ऑर्डर'), '${_fmt(it.ordered)} $unit'),
          const SizedBox(height: 6),
          _specRow(S.t('On challan', 'चलनावर'), '${_fmt(it.challan)} $unit'),
          const Divider(height: 22, color: Y2.line),
          _fieldRow(
            label: S.t('Received', 'मिळाले'),
            controller: it.received,
            unit: unit,
            valid: it.valid,
          ),
          if (it.overPo && !it.overMax)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  S.t('Over PO — ordered was ${_fmt(it.ordered)} $unit',
                      'PO पेक्षा जास्त — ऑर्डर ${_fmt(it.ordered)} $unit'),
                  style: F.hind(11, w: FontWeight.w600, color: Y2.orange)),
            ),
          if (it.hasMax) ...[
            const SizedBox(height: 8),
            _stockBlock(it, unit),
          ],
          const SizedBox(height: 10),
          _fieldRow(
            label: S.t('Rejected', 'नाकारले'),
            controller: it.rejected,
            unit: unit,
            valid: true,
          ),
          const SizedBox(height: 12),
          // Quality check — own row so the toggle never squeezes the accepted box.
          Row(
            children: [
              Expanded(
                child: Text(S.t('Quality check', 'गुणवत्ता तपासणी'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(13, color: Y2.ink)),
              ),
              const SizedBox(width: 8),
              _qcToggle(it),
            ],
          ),
          const SizedBox(height: 10),
          // Accepted = received − rejected, full width.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: Y2.greenTint,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Y2.greenLine),
            ),
            child: Row(
              children: [
                Text(S.t('Accepted', 'स्वीकारले'),
                    style: F.hind(12, w: FontWeight.w600, color: Y2.green)),
                const Spacer(),
                Flexible(
                  child: Text('${_fmt(it.acceptedQty)} $unit',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: F.mono(14, w: FontWeight.w700, color: Y2.green)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow({
    required String label,
    required TextEditingController controller,
    required String unit,
    required bool valid,
  }) {
    return Row(
      children: [
        Expanded(
            child: Text(label, style: F.hind(13, color: Y2.ink))),
        SizedBox(
          width: 110,
          child: TextField(
            controller: controller,
            textAlign: TextAlign.right,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _decimal,
            style: F.mono(15, w: FontWeight.w700, color: valid ? Y2.ink : Y2.red),
            cursorColor: Y2.accent,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              filled: true,
              fillColor: Y2.screen,
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: valid ? Y2.line : Y2.redLine)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Y2.accent, width: 1.4)),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
            width: 26,
            child: Text(unit, style: F.mono(12, color: Y2.muted))),
      ],
    );
  }

  /// Stock-limit (P-L) block: current on-hand vs the material's max, a gauge, and
  /// — when the received qty would push past the max — a hard-block message with a
  /// one-tap "accept up to the cap".
  Widget _stockBlock(_ItemEntry it, String unit) {
    final frac =
        it.stockMax <= 0 ? 0.0 : (it.onHand / it.stockMax).clamp(0.0, 1.0);
    final over = it.overMax;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: over ? Y2.redTint : Y2.screen,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: over ? Y2.redLine : Y2.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 14, color: over ? Y2.red : Y2.muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                    S.t('In stock ${_fmt(it.onHand)} / max ${_fmt(it.stockMax)} $unit',
                        'स्टॉक ${_fmt(it.onHand)} / कमाल ${_fmt(it.stockMax)} $unit'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(11,
                        w: FontWeight.w600, color: over ? Y2.red : Y2.body)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(children: [
                const Positioned.fill(child: ColoredBox(color: Y2.lineSoft)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: frac,
                  child: ColoredBox(color: over ? Y2.red : Y2.accent),
                ),
              ]),
            ),
          ),
          if (over) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                      it.atMax
                          ? S.t('At maximum — cannot accept, return load',
                              'कमाल — स्वीकारता येणार नाही, परत पाठवा')
                          : S.t('Over max — accept up to ${_fmt(it.cap)} $unit',
                              'कमाल ओलांडले — फक्त ${_fmt(it.cap)} $unit स्वीकारा'),
                      style: F.hind(11, w: FontWeight.w700, color: Y2.red)),
                ),
                if (!it.atMax) ...[
                  const SizedBox(width: 8),
                  Pressable2(
                    scale: 0.95,
                    onTap: () => _setReceived(it, it.cap),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: Y2.accent,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(
                          S.t('Accept ${_fmt(it.cap)}', '${_fmt(it.cap)} घ्या'),
                          style: F.hind(11,
                              w: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ],
            ),
          ] else if (it.belowMin) ...[
            const SizedBox(height: 6),
            Text(
                S.t('Below min ${_fmt(it.stockMin)} — low stock',
                    'किमान ${_fmt(it.stockMin)} खाली — कमी स्टॉक'),
                style: F.hind(10, w: FontWeight.w600, color: Y2.orange)),
          ],
        ],
      ),
    );
  }

  // ---- desktop layout ----

  Widget _desktop() {
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('RECEIVE INVOICE', 'चलन स्वीकारा'),
          subtitle: '$_invoice · $_supplier · $_vehicle',
          onBack: nav.pop,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _invoiceStrip(wide: true),
                const SizedBox(height: 14),
                _table(),
              ],
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  // Column widths shared by header + rows so the cells line up.
  static const _wNum = 30.0;
  static const _wPo = 104.0;
  static const _wOrd = 104.0;
  static const _wStock = 120.0;
  static const _wRecv = 116.0;
  static const _wRej = 104.0;
  static const _wQc = 128.0;

  /// Scale-to-fit wrapper so numeric cells / the QC toggle never overflow their
  /// fixed column, whatever the font metrics (matches the repo's big-number tiles).
  Widget _fit(Widget child, {Alignment align = Alignment.centerRight}) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: align, child: child);

  Widget _table() {
    return Card2(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header row.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8FB),
              border: Border(bottom: BorderSide(color: Y2.line)),
            ),
            child: Row(
              children: [
                _h(_wNum, '#'),
                Expanded(child: _h(null, S.t('Material', 'माल'))),
                _h(_wPo, S.t('PO', 'PO')),
                _h(_wOrd, S.t('Ordered', 'ऑर्डर'), right: true),
                _h(_wStock, S.t('Stock / max', 'स्टॉक / कमाल'), right: true),
                _h(_wRecv, S.t('Received', 'मिळाले'), right: true),
                _h(_wRej, S.t('Rejected', 'नाकारले'), right: true),
                const SizedBox(width: 14),
                _h(_wQc, S.t('QC', 'QC')),
              ],
            ),
          ),
          for (var i = 0; i < _items.length; i++) _tableRow(i),
        ],
      ),
    );
  }

  Widget _h(double? w, String label, {bool right = false}) {
    final t = Text(label,
        textAlign: right ? TextAlign.right : TextAlign.left,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));
    return w == null ? t : SizedBox(width: w, child: t);
  }

  Widget _tableRow(int i) {
    final it = _items[i];
    final unit = _unitOf(it);
    final last = i == _items.length - 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // # + status dot.
          SizedBox(
            width: _wNum,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: it.valid ? Y2.green : Y2.muted2,
                      shape: BoxShape.circle),
                ),
              ],
            ),
          ),
          // Material + category.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.material,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(13, w: FontWeight.w600, color: Y2.ink)),
                Text(
                    it.isComponent
                        ? S.t('component', 'घटक')
                        : S.t('raw material', 'कच्चा माल'),
                    style: F.hind(10, color: Y2.muted)),
              ],
            ),
          ),
          // PO (tappable).
          SizedBox(
            width: _wPo,
            child: Pressable2(
              scale: 0.97,
              onTap: () => _changePo(it),
              child: Row(
                children: [
                  Flexible(
                    child: Text(it.po,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.mono(12, w: FontWeight.w700, color: Y2.accent)),
                  ),
                  const Icon(I2.chevronDown, size: 15, color: Y2.accent),
                ],
              ),
            ),
          ),
          // Ordered / challan.
          SizedBox(
            width: _wOrd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _fit(Text('${_fmt(it.ordered)} $unit',
                    maxLines: 1,
                    style: F.mono(12, w: FontWeight.w600, color: Y2.ink))),
                _fit(Text(
                    S.t('chln ${_fmt(it.challan)}', 'चलन ${_fmt(it.challan)}'),
                    maxLines: 1,
                    style: F.hind(10, color: Y2.muted))),
              ],
            ),
          ),
          // In stock / max (P-L).
          SizedBox(
            width: _wStock,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _fit(Text(
                    it.hasMax ? '${_fmt(it.onHand)}/${_fmt(it.stockMax)}' : '—',
                    maxLines: 1,
                    style: F.mono(12,
                        w: FontWeight.w600,
                        color: it.overMax ? Y2.red : Y2.body))),
                if (it.hasMax)
                  _fit(Text(
                      it.atMax
                          ? S.t('at max', 'कमाल')
                          : S.t('cap ${_fmt(it.cap)}', 'मर्यादा ${_fmt(it.cap)}'),
                      maxLines: 1,
                      style: F.hind(10,
                          w: FontWeight.w600,
                          color: it.overMax ? Y2.red : Y2.muted))),
              ],
            ),
          ),
          // Received (field) + accepted.
          SizedBox(
            width: _wRecv,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _cellField(it.received, valid: it.valid),
                _fit(Text(
                    it.overMax
                        ? S.t('≤ ${_fmt(it.cap)} max', '≤ ${_fmt(it.cap)} कमाल')
                        : it.overPo
                            ? S.t('over PO', 'PO जास्त')
                            : S.t('acc ${_fmt(it.acceptedQty)}',
                                'स्वी ${_fmt(it.acceptedQty)}'),
                    maxLines: 1,
                    style: F.hind(10,
                        w: FontWeight.w600,
                        color: it.overMax
                            ? Y2.red
                            : it.overPo
                                ? Y2.orange
                                : Y2.green))),
              ],
            ),
          ),
          // Rejected (field).
          SizedBox(
            width: _wRej,
            child: _cellField(it.rejected, valid: true),
          ),
          const SizedBox(width: 14),
          // QC toggle.
          SizedBox(
              width: _wQc,
              child: _fit(_qcToggle(it), align: Alignment.centerLeft)),
        ],
      ),
    );
  }

  Widget _cellField(TextEditingController c, {required bool valid}) => SizedBox(
        width: 92,
        child: TextField(
          controller: c,
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _decimal,
          style: F.mono(13, w: FontWeight.w700, color: valid ? Y2.ink : Y2.red),
          cursorColor: Y2.accent,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            filled: true,
            fillColor: Y2.screen,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: valid ? Y2.line : Y2.redLine)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Y2.accent, width: 1.4)),
          ),
        ),
      );

  // ---- shared small bits ----

  Widget _categoryPill(_ItemEntry it) => Pill2(
        text: it.isComponent
            ? S.t('COMPONENT', 'घटक')
            : S.t('RAW MATERIAL', 'कच्चा माल'),
        fg: it.isComponent ? Y2.accent : Y2.body,
        bg: it.isComponent ? Y2.accent.withValues(alpha: 0.10) : Y2.lineSoft,
        borderColor: it.isComponent ? Y2.accent.withValues(alpha: 0.30) : Y2.line,
        dot: false,
      );

  Widget _specRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: F.hind(13, color: Y2.ink)),
          Text(value, style: F.mono(13, w: FontWeight.w600, color: Y2.ink)),
        ],
      );

  Widget _qcToggle(_ItemEntry it) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _qcSeg(S.t('Pass', 'पास'), it.qcPass, Y2.green,
              () => setState(() => it.qcPass = true)),
          const SizedBox(width: 6),
          _qcSeg(S.t('Fail', 'फेल'), !it.qcPass, Y2.red,
              () => setState(() => it.qcPass = false)),
        ],
      );

  Widget _qcSeg(String label, bool on, Color tone, VoidCallback onTap) =>
      Pressable2(
        scale: 0.96,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: on ? tone.withValues(alpha: 0.12) : Y2.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? tone : Y2.line),
          ),
          child: Text(label,
              style: F.hind(12,
                  w: FontWeight.w700, color: on ? tone : Y2.muted)),
        ),
      );

  // ---- success state ----

  Widget _success() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 74,
                  height: 74,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Y2.green, width: 3),
                  ),
                  child: const Icon(I2.check, color: Y2.green, size: 38),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _queued
                    ? S.t('SAVED · WILL SYNC', 'जतन केले · सिंक होईल')
                    : S.t('RECEIVED & IN STOCK', 'मिळाले आणि स्टॉकमध्ये'),
                textAlign: TextAlign.center,
                style: F.khand(22, ls: 0.4, color: Y2.ink),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: F.hind(13, color: Y2.body, height: 1.5),
                  children: [
                    TextSpan(text: S.t('GRN ', 'GRN ')),
                    TextSpan(
                        text: _grnDoc,
                        style: F.mono(13, color: Y2.ink, height: 1.5)),
                    TextSpan(
                        text: _queued
                            ? S.t(
                                ' queued · ${_items.length} items on invoice $_invoice.',
                                ' रांगेत · चलन $_invoice वर ${_items.length} वस्तू.')
                            : S.t(
                                ' posted · ${_items.length} items on invoice $_invoice.',
                                ' पोस्ट केले · चलन $_invoice वर ${_items.length} वस्तू.')),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              // Per-line summary.
              Card2(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: Y2.lineSoft),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(_items[i].material,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: F.hind(13, color: Y2.ink)),
                            ),
                            Text(
                                '${_fmt(_items[i].acceptedQty)} ${_unitOf(_items[i])}',
                                style: F.mono(13,
                                    w: FontWeight.w700, color: Y2.green)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton2(
                label: S.t('Next vehicle', 'पुढील वाहन'),
                onTap: () => nav.replace(ScreenId.gateArrivals),
              ),
              const SizedBox(height: 10),
              OutlineButton2(
                label: S.t('Back to home', 'मुख्यपृष्ठावर परत'),
                onTap: () => nav.home(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
