import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';

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
  static const _locations = ['Store A · Rack 12', 'Store B · Rack 4'];
  String _location = _locations.first;
  bool _posting = false;
  late final TextEditingController _received = TextEditingController(
      text: Ui2Flow.get<String>('gate.receivedQty') ?? '3980');

  PhoneNav get nav => widget.nav;

  @override
  void dispose() {
    _received.dispose();
    super.dispose();
  }

  String get _receivedQty => _received.text.replaceAll(',', '').trim();

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
    if (_posting) return;
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
        'rejected_qty': '0',
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

    // The entry has now been received — clear the carried context so it can't be
    // receipted again (the Quality tabs are independent roots; a stale entryId
    // would otherwise let a re-entry post a duplicate goods-receipt).
    Ui2Flow.set('gate.entryId', null);
    Ui2Flow.set('gate.vehicle', null);
    Ui2Flow.set('gate.category', null);
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
    return Column(
      children: [
        const StatusBar2(),
        // Header: back chevron · title · step counter.
        ScreenHeader2(
          title: S.t('GOODS RECEIPT', 'माल पावती'),
          onBack: nav.pop,
          trailing: Text('4/4', style: F.mono(12, color: Y2.muted)),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                              style: F.mono(13,
                                  w: FontWeight.w700, color: Y2.ink))),
                      const SizedBox(height: 6),
                      _summaryRow(
                          S.t('Supplier', 'पुरवठादार'),
                          Text(_ctx('gate.supplier', '—'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: F.hind(13,
                                  w: FontWeight.w700, color: Y2.ink))),
                      const SizedBox(height: 6),
                      _summaryRow(
                          S.t('Material', 'माल'),
                          Text(_ctx('gate.material', 'CR coil 2.5mm'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: F.hind(13,
                                  w: FontWeight.w700, color: Y2.ink))),
                      const SizedBox(height: 6),
                      // Accepted — editable received qty (kg).
                      _summaryRow(
                          S.t('Accepted', 'स्वीकारले'),
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
                                  style: F.mono(13,
                                      w: FontWeight.w700, color: Y2.green),
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
                                      w: FontWeight.w700, color: Y2.green)),
                            ],
                          )),
                      const SizedBox(height: 6),
                      _summaryRow(
                          S.t('Rejected', 'नाकारले'),
                          Text('0 $_unit',
                              style: F.mono(13,
                                  w: FontWeight.w700, color: Y2.ink))),
                    ],
                  ),
                ),
                const SizedBox(height: 11),
                // Put-away location selector.
                Pressable2(
                  onTap: _pickLocation,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                      color: Y2.card,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Y2.line),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 18, color: Y2.muted),
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
                        child:
                            Icon(Icons.info_outline, size: 16, color: Y2.accent),
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
              ],
            ),
          ),
        ),
        // Footer: confirm & post.
        Container(
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
            onTap: _post,
          ),
        ),
      ],
    );
  }

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
