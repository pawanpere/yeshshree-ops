import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';
import '../widgets/sla.dart';

/// Gate — Goods Receipt (GRN) — prototype screen [16]. Posts a goods receipt
/// to SAP and adds stock; the final step of the gate inbound flow. The
/// put-away location is chosen via a Picker2; "Confirm & post" first creates the
/// gate entry, then the goods receipt referencing it (both transactional through
/// the retry queue), stashes the returned doc for the result screen, and routes
/// to the received confirmation.
class Ui2GateGrnScreen extends ConsumerStatefulWidget {
  const Ui2GateGrnScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2GateGrnScreen> createState() => _Ui2GateGrnScreenState();
}

class _Ui2GateGrnScreenState extends ConsumerState<Ui2GateGrnScreen> {
  // Numeric input that allows a decimal point (qty is NUMERIC(14,3)). Kept local
  // because the shared V.digitsOnly is integer-only and validators.dart is shared.
  static final List<TextInputFormatter> _decimalQty = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];
  static const _locations = ['Store A · Rack 12', 'Store B · Rack 4'];
  String _location = _locations.first;
  bool _posting = false;
  late final TextEditingController _received = TextEditingController(
      text: Ui2Flow.get<String>('gate.receivedQty') ?? '3980');

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the CTA + inline error on every keystroke in the qty field.
    _received.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _received.dispose();
    super.dispose();
  }

  String get _receivedQty => _received.text.replaceAll(',', '').trim();

  /// Rejected qty carried in from quality (defaults to 0). Accepted = received −
  /// rejected, so a receipt that does not exceed the rejected amount is invalid.
  double get _rejectedQty =>
      double.tryParse(
          (Ui2Flow.get<String>('gate.rejectedQty') ?? '0')
              .replaceAll(',', '')
              .trim()) ??
      0;

  /// Received must parse to a positive number AND be strictly greater than the
  /// rejected qty (otherwise nothing is actually accepted into stock).
  bool get _receivedValid {
    final v = double.tryParse(_receivedQty);
    return v != null && V.positive(v) && v > _rejectedQty;
  }

  // NOTE: over-PO receiving is deliberately NOT part of _canPost. Over-delivery is
  // a legitimate case the backend handles (the goods-receipt service posts a SOFT
  // `gr_qty_deviation` anomaly in the same transaction, and an extreme one a hard
  // `gr_qty_vs_po`), and stock checks never hard-block (invariant #11). We only
  // surface a non-blocking advisory warning so the operator can re-check the
  // weighbridge before posting.
  // The MAX STOCK limit (P-L) IS a hard block, though: you can't bring a material
  // past its configured maximum.
  bool get _canPost => _receivedValid && !_overMax;

  // ---- max stock limit (P-L) ----
  double get _onHand =>
      double.tryParse((Ui2Flow.get<String>('gate.onHand') ?? '').trim()) ?? 0;
  double get _stockMax =>
      double.tryParse((Ui2Flow.get<String>('gate.stockMax') ?? '').trim()) ?? 0;
  bool get _hasMax => _stockMax > 0;
  double get _cap {
    final c = _stockMax - _onHand;
    return c < 0 ? 0 : c;
  }
  bool get _overMax {
    final v = double.tryParse(_receivedQty);
    return _hasMax && v != null && v > _cap;
  }

  String _fmtQty(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(3);

  /// GRN 3-day deadline (P-T), from the arrival time carried in the flow.
  DateTime get _due {
    final h = Ui2Flow.raw('gate.arrivedHoursAgo');
    return grnDueFrom(_loadTime, h is num ? h : 6);
  }

  final DateTime _loadTime = DateTime.now();

  /// PO ordered qty carried in from the gate entry (gate.ordered). Null on paths
  /// that don't carry it (the quality-worklist hand-off, or a cold/demo open) —
  /// then there's nothing to compare against and no warning is shown.
  double? get _orderedQty {
    final n = double.tryParse((Ui2Flow.get<String>('gate.ordered') ?? '')
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.]'), ''));
    return (n == null || n == 0) ? null : n;
  }

  /// Advisory only: the (valid) received qty exceeds the PO ordered qty.
  bool get _overReceiving {
    final ordered = _orderedQty;
    final v = double.tryParse(_receivedQty);
    return ordered != null && v != null && _receivedValid && v > ordered;
  }

  /// PO ordered qty formatted for the warning (whole number when it is one).
  String get _orderedLabel {
    final o = _orderedQty;
    if (o == null) return '';
    return o == o.roundToDouble() ? '${o.round()}' : o.toStringAsFixed(3);
  }

  void _pickLocation() {
    nav.overlay(Picker2Sheet<String>(
      title: S.t('Put-away location', 'ठेवण्याचे ठिकाण'),
      options: [
        for (final loc in _locations) Picker2Option<String>(loc, loc),
      ],
      onPick: (v) {
        setState(() => _location = v);
        nav.hideOverlay();
      },
    ));
  }

  Future<void> _post() async {
    if (_posting || !_canPost) return;
    setState(() => _posting = true);

    // Step 1 — resolve the gate entry to receipt. Prefer the REAL entry the
    // quality operator picked from the worklist (gate.entryId); only self-create
    // one in the standalone/demo flow where no entry was carried.
    int? gateEntryId = Ui2Flow.get<int>('gate.entryId');
    if (gateEntryId == null) {
      final gateRes = await Data.submit(
        ref,
        '/gate-entries',
        <String, dynamic>{
          'doc_type': 'invoice',
          'vehicle_no': 'MH12 AB 4421',
          'driver_name': 'Ravi',
          // invoice gate entries require a vendor + invoice (GATE_INVOICE_REQUIRED)
          'vendor_id': 1,
          'invoice_no': 'INV-${Data.newRef().substring(0, 6).toUpperCase()}',
          'invoice_date': '2026-06-19',
          'invoice_value': '50000',
        },
        label: S.t('Gate entry', 'गेट नोंद'),
      );
      if (!mounted) return;
      if (gateRes.failed) {
        setState(() => _posting = false);
        _errorSnack(gateRes.error?.message ??
            S.t('Could not create gate entry', 'गेट नोंद करता आली नाही'));
        return;
      }
      gateEntryId = gateRes.data?['id'] as int?;
    }

    // Step 2 — post the goods receipt referencing the gate entry.
    final grnRes = await Data.submit(
      ref,
      '/goods-receipts',
      <String, dynamic>{
        'gate_entry_id': gateEntryId,
        'received_qty': _receivedQty,
        'rejected_qty': Ui2Flow.get<String>('gate.rejectedQty') ?? '0',
        'qc_result': Ui2Flow.get<String>('gate.qcResult') ?? 'pass',
      },
      label: '${S.t('Goods receipt', 'माल पावती')} $_receivedQty $_unit',
    );
    if (!mounted) return;

    if (grnRes.failed) {
      setState(() => _posting = false);
      _errorSnack(grnRes.error?.message ??
          S.t('Could not post goods receipt', 'माल पावती नोंदता आली नाही'));
      return;
    }

    // Capture the receipt unit (kg vs pcs) for the success screen BEFORE the
    // category is cleared below — otherwise the result screen can't tell a
    // counted component from a weighed coil and would mislabel the qty.
    Ui2Flow.set('gate.receivedUnit', _unit);
    // The entry has now been received — clear the carried context so it can't be
    // receipted again (the Quality tabs are independent roots; a stale entryId
    // would otherwise let a re-entry post a duplicate goods-receipt).
    Ui2Flow.set('gate.entryId', null);
    Ui2Flow.set('gate.vehicle', null);
    Ui2Flow.set('gate.category', null);
    Ui2Flow.set('gate.rejectedQty', null);
    // Stash for the result screen (real doc id when posted, queued marker else).
    Ui2Flow.set('gate.grnDoc',
        grnRes.data?['grn_no'] ?? grnRes.data?['doc_no'] ?? grnRes.data?['id']);
    Ui2Flow.set('gate.received', _receivedQty);
    Ui2Flow.set('gate.location', _location);
    Ui2Flow.set('gate.queued', grnRes.queued);
    HapticFeedback.mediumImpact();
    nav.replace(ScreenId.gateReceived);
  }

  void _errorSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Y2.red,
          content: Row(
            children: [
              const Icon(I2.error, size: 18, color: Colors.white),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(msg, style: F.hind(13, color: Colors.white))),
            ],
          ),
        ),
      );

  /// A value carried in from the quality worklist / gate-match hand-off, or a
  /// fallback when the receipt screen is reached cold (dev jump-nav / demo flow).
  String _ctx(String key, String fallback) {
    final v = Ui2Flow.get<String>(key);
    return (v != null && v.isNotEmpty) ? v : fallback;
  }

  /// Receipt unit follows the material category: components are counted (pcs),
  /// raw material is weighed (kg) — Phase 4.
  String get _unit =>
      Ui2Flow.get<String>('gate.category') == 'component'
          ? S.t('pcs', 'नग')
          : 'kg';

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- phone layout (unchanged device-chrome frame) ----

  Widget _phone() {
    return Column(
      children: [
        const StatusBar2(),
        _header(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _bodyChildren(),
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  // ---- desktop layout (no StatusBar2; centered reading-width form) ----

  Widget _desktop() {
    return Column(
      children: [
        _header(),
        Expanded(
          child: ResponsiveContent(
            maxWidth: 720,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _bodyChildren(),
              ),
            ),
          ),
        ),
        // Footer matched to the centered body width so the CTA lines up.
        ResponsiveContent(maxWidth: 720, child: _footer()),
      ],
    );
  }

  // Header: back chevron · title · step counter. Identical on both layouts.
  Widget _header() => ScreenHeader2(
        title: S.t('GOODS RECEIPT', 'माल पावती'),
        onBack: nav.pop,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SlaCountdown(_due, dense: true),
            const SizedBox(width: 8),
            Text('4/4', style: F.mono(12, color: Y2.muted)),
          ],
        ),
      );

  // Shared body — receipt summary card · put-away picker · info note.
  List<Widget> _bodyChildren() => [
        // Receipt summary card.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: Y2.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Y2.line),
          ),
          child: Column(
            children: [
              _summaryRow(
                  S.t('PO', 'PO'),
                  Text(Ui2Flow.get<String>('gate.po') ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.mono(13, w: FontWeight.w700, color: Y2.ink))),
              const SizedBox(height: 6),
              _summaryRow(
                  S.t('Supplier', 'पुरवठादार'),
                  Text(_ctx('gate.supplier', '—'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.hind(13, w: FontWeight.w700, color: Y2.ink))),
              const SizedBox(height: 6),
              _summaryRow(
                  S.t('Material', 'माल'),
                  Text(_ctx('gate.material', 'CR coil 2.5mm'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.hind(13, w: FontWeight.w700, color: Y2.ink))),
              if (_hasMax) ...[
                const SizedBox(height: 6),
                // Max stock limit (P-L): current on-hand vs the configured max.
                _summaryRow(
                    S.t('In stock / max', 'स्टॉक / कमाल'),
                    Text('${_fmtQty(_onHand)} / ${_fmtQty(_stockMax)} $_unit',
                        maxLines: 1,
                        style: F.mono(13,
                            w: FontWeight.w700,
                            color: _overMax ? Y2.red : Y2.ink))),
              ],
              const SizedBox(height: 6),
              // Received — editable gross received qty; the Rejected row
              // below is separate, so accepted = received − rejected.
              _summaryRow(
                  S.t('Received', 'मिळालेले'),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IntrinsicWidth(
                            child: TextField(
                              controller: _received,
                              textAlign: TextAlign.right,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: _decimalQty,
                              style: F.mono(13,
                                  w: FontWeight.w700,
                                  color: _receivedValid && !_overMax ? Y2.green : Y2.red),
                              cursorColor: Y2.accent,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          Text(' $_unit',
                              style: F.mono(13,
                                  w: FontWeight.w700,
                                  color: _receivedValid && !_overMax ? Y2.green : Y2.red)),
                        ],
                      ),
                      // Inline error when the qty is non-positive or does
                      // not exceed the rejected amount (nothing accepted).
                      FieldHint(
                        _rejectedQty > 0
                            ? S.t(
                                'Received must be more than rejected (${_ctx('gate.rejectedQty', '0')})',
                                'मिळालेले नाकारलेल्यापेक्षा जास्त हवे (${_ctx('gate.rejectedQty', '0')})')
                            : S.t('Enter a quantity greater than 0',
                                '० पेक्षा जास्त प्रमाण भरा'),
                        show: _receivedQty.isNotEmpty && !_receivedValid,
                      ),
                      // Advisory (non-blocking): over the PO ordered qty.
                      // Posting is still allowed — the backend records a
                      // soft anomaly — but flag it so the operator can
                      // re-check the weighbridge first.
                      FieldHint(
                        S.t('Over PO — ordered was $_orderedLabel $_unit',
                            'PO पेक्षा जास्त — ऑर्डर $_orderedLabel $_unit होती'),
                        tone: FieldHintTone.warning,
                        show: _overReceiving && !_overMax,
                      ),
                      // Max stock limit (P-L) — a HARD block: can't accept past max.
                      FieldHint(
                        _cap <= 0
                            ? S.t(
                                'At max stock (${_fmtQty(_stockMax)} $_unit) — cannot accept, return load',
                                'कमाल स्टॉक (${_fmtQty(_stockMax)} $_unit) — स्वीकारता येणार नाही, परत पाठवा')
                            : S.t(
                                'Over max — accept up to ${_fmtQty(_cap)} $_unit (${_fmtQty(_onHand)} in stock)',
                                'कमाल ओलांडले — फक्त ${_fmtQty(_cap)} $_unit स्वीकारा (${_fmtQty(_onHand)} स्टॉकमध्ये)'),
                        show: _overMax,
                      ),
                    ],
                  )),
              const SizedBox(height: 6),
              _summaryRow(
                  S.t('Rejected', 'नाकारले'),
                  Text('${_ctx('gate.rejectedQty', '0')} $_unit',
                      style: F.mono(13, w: FontWeight.w700, color: Y2.ink))),
            ],
          ),
        ),
        const SizedBox(height: 11),
        // Put-away location selector.
        Pressable2(
          onTap: _pickLocation,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: Y2.card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Y2.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.place_outlined, size: 18, color: Y2.muted),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.t('Put into location', 'ठिकाणी ठेवा'),
                          style: F.hind(11,
                              w: FontWeight.w400, color: Y2.muted)),
                      Text(_location,
                          style: F.hind(15,
                              w: FontWeight.w600, color: Y2.ink)),
                    ],
                  ),
                ),
                const Icon(I2.chevronDown, size: 20, color: Y2.muted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 11),
        // Info note.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x0D1D4ED8), // rgba(29,78,216,.05)
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBCD0F5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline, size: 16, color: Y2.accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  S.t(
                      'Posts a goods receipt to SAP and adds stock. Works offline — queues if no signal.',
                      'SAP मध्ये माल पावती नोंदते व स्टॉक वाढवते. ऑफलाइन चालते — सिग्नल नसल्यास रांगेत ठेवते.'),
                  style: F.hind(12, color: Y2.body),
                ),
              ),
            ],
          ),
        ),
      ];

  // Footer: confirm & post. Identical CTA + behavior on both layouts.
  Widget _footer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Color(0xFFF6F8FB),
          border: Border(top: BorderSide(color: Y2.line)),
        ),
        child: PrimaryButton2(
          label: _posting
              ? S.t('Posting…', 'नोंदवत आहे…')
              : S.t('Confirm & post', 'पुष्टी करा व नोंदवा'),
          busy: _posting,
          enabled: _canPost,
          onTap: _post,
        ),
      );

  Widget _summaryRow(String label, Widget value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: F.hind(13, color: Y2.ink)),
          ),
          const SizedBox(width: 8),
          Flexible(child: value),
        ],
      );
}
